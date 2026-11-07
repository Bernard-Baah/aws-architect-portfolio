# AWS Config in every account and both regions, delivering to one bucket in
# Log Archive. Security Hub (next layer) evaluates its controls from Config,
# so this has to exist first.
#
# Member accounts: a service-managed CloudFormation StackSet targeted at the
# org root, with auto-deployment, so any account created later gets a recorder
# automatically. Its stacks run as a service-linked role, which SCPs don't
# restrict. StackSets never deploy to the management account, so management
# gets its recorder directly from Terraform below.

locals {
  config_bucket  = "org-config-${local.log_archive_id}"
  config_regions = ["us-east-1", "us-west-2"]
}

# ---------- Central bucket (Log Archive) ----------

resource "aws_s3_bucket" "config" {
  provider = aws.log_archive

  bucket        = local.config_bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "config" {
  provider = aws.log_archive

  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "config" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config.id

  rule {
    id     = "expire-snapshots"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_expire_days
    }
  }
}

# Writers must be in this organization AND be a Config recorder role (or the
# Config service itself), and each account may only write under its own prefix.
resource "aws_s3_bucket_policy" "config" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ConfigAclCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = aws_s3_bucket.config.arn
        Condition = {
          StringEquals = { "aws:SourceOrgID" = local.org.organization_id }
        }
      },
      {
        Sid       = "ConfigAclCheckRoles"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = aws_s3_bucket.config.arn
        Condition = {
          StringEquals = { "aws:PrincipalOrgID" = local.org.organization_id }
          ArnLike      = { "aws:PrincipalArn" = "arn:aws:iam::*:role/config-recorder-*" }
        }
      },
      {
        Sid       = "ConfigWriteService"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "aws:SourceOrgID" = local.org.organization_id
            "s3:x-amz-acl"    = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "ConfigWriteRoles"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config.arn}/AWSLogs/$${aws:PrincipalAccount}/*"
        Condition = {
          StringEquals = { "aws:PrincipalOrgID" = local.org.organization_id }
          ArnLike      = { "aws:PrincipalArn" = "arn:aws:iam::*:role/config-recorder-*" }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.config]
}

# ---------- Member accounts: StackSet ----------

resource "aws_cloudformation_stack_set" "config" {
  name             = "config-recorder"
  description      = "AWS Config recorder in every member account (landing zone baseline)"
  permission_model = "SERVICE_MANAGED"
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = file("${path.module}/templates/config-recorder.yaml")

  parameters = {
    DeliveryBucket = local.config_bucket
    HomeRegion     = "us-east-1"
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  # Stop at the first failure. CloudFormation requires max_concurrent_count
  # <= failure_tolerance_count + 1, so accounts go one at a time per region.
  operation_preferences {
    region_concurrency_type = "PARALLEL"
    max_concurrent_count    = 1
    failure_tolerance_count = 0
  }

  lifecycle {
    # Set by AWS for service-managed StackSets; would otherwise always diff.
    ignore_changes = [administration_role_arn]
  }

  depends_on = [aws_s3_bucket_policy.config]
}

resource "aws_cloudformation_stack_set_instance" "config" {
  for_each = toset(local.config_regions)

  stack_set_name = aws_cloudformation_stack_set.config.name
  region         = each.key

  deployment_targets {
    organizational_unit_ids = [local.org.root_id]
  }

  operation_preferences {
    max_concurrent_count    = 1
    failure_tolerance_count = 0
  }
}

# ---------- Management account: direct ----------

resource "aws_iam_role" "config_management" {
  name = "config-recorder-management"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.management_id }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_management" {
  role       = aws_iam_role.config_management.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# The bucket policy only trusts roles named config-recorder-*, so management
# gets an equivalent role name and an inline write permission for its prefix.
resource "aws_iam_role_policy" "config_management_delivery" {
  name = "deliver-to-log-archive"
  role = aws_iam_role.config_management.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config.arn}/AWSLogs/${local.management_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
      },
    ]
  })
}

module "config_management_use1" {
  source = "../../modules/config-recorder"

  providers = {
    aws = aws
  }

  role_arn        = aws_iam_role.config_management.arn
  delivery_bucket = aws_s3_bucket.config.id
  include_global  = true

  depends_on = [aws_s3_bucket_policy.config, aws_iam_role_policy.config_management_delivery]
}

module "config_management_usw2" {
  source = "../../modules/config-recorder"

  providers = {
    aws = aws.usw2
  }

  role_arn        = aws_iam_role.config_management.arn
  delivery_bucket = aws_s3_bucket.config.id
  include_global  = false

  depends_on = [aws_s3_bucket_policy.config, aws_iam_role_policy.config_management_delivery]
}
