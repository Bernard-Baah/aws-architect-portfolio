# AWS Config in every account and both regions, delivering to one bucket in
# Log Archive. Security Hub (next layer) evaluates its controls from Config,
# so this has to exist first. One modules/account-config call per account.
#
# First attempt used a service-managed CloudFormation StackSet (auto-deploys
# to new accounts), but CFN's Config recorder deadlocks with its delivery
# channel; see modules/account-config. Trade-off: a new account needs one
# more module call here.

locals {
  config_bucket = "org-config-${local.log_archive_id}"
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

# Writers must be in this organization AND be a config-recorder* role (or the
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
          ArnLike      = { "aws:PrincipalArn" = "arn:aws:iam::*:role/config-recorder*" }
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
          ArnLike      = { "aws:PrincipalArn" = "arn:aws:iam::*:role/config-recorder*" }
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

# ---------- Recorders: one module call per account ----------

module "config_management" {
  source = "../../modules/account-config"

  providers = {
    aws.home      = aws
    aws.secondary = aws.usw2
  }

  delivery_bucket = aws_s3_bucket.config.id
  role_name       = "config-recorder-management"

  depends_on = [aws_s3_bucket_policy.config]
}

module "config_log_archive" {
  source = "../../modules/account-config"

  providers = {
    aws.home      = aws.log_archive
    aws.secondary = aws.log_archive_usw2
  }

  delivery_bucket = aws_s3_bucket.config.id

  depends_on = [aws_s3_bucket_policy.config]
}

module "config_audit" {
  source = "../../modules/account-config"

  providers = {
    aws.home      = aws.audit
    aws.secondary = aws.audit_usw2
  }

  delivery_bucket = aws_s3_bucket.config.id

  depends_on = [aws_s3_bucket_policy.config]
}

module "config_dev" {
  source = "../../modules/account-config"

  providers = {
    aws.home      = aws.dev
    aws.secondary = aws.dev_usw2
  }

  delivery_bucket = aws_s3_bucket.config.id

  depends_on = [aws_s3_bucket_policy.config]
}

module "config_prod" {
  source = "../../modules/account-config"

  providers = {
    aws.home      = aws.prod
    aws.secondary = aws.prod_usw2
  }

  delivery_bucket = aws_s3_bucket.config.id

  depends_on = [aws_s3_bucket_policy.config]
}

# The management account's recorder was created by the first version of this
# file; move it into the module instead of destroying and recreating it.
moved {
  from = aws_iam_role.config_management
  to   = module.config_management.aws_iam_role.this
}

moved {
  from = aws_iam_role_policy_attachment.config_management
  to   = module.config_management.aws_iam_role_policy_attachment.this
}

moved {
  from = aws_iam_role_policy.config_management_delivery
  to   = module.config_management.aws_iam_role_policy.delivery
}

moved {
  from = module.config_management_use1
  to   = module.config_management.module.home
}

moved {
  from = module.config_management_usw2
  to   = module.config_management.module.secondary
}
