# Organization trail: one trail in the management account records every API
# call in every account and region, and writes it to a bucket in Log Archive.
# Nobody in a workload account can stop it (it isn't theirs, and the SCP
# blocks cloudtrail:StopLogging anyway) or rewrite history (Object Lock + log
# file validation).

data "aws_caller_identity" "management" {}

locals {
  management_id   = data.aws_caller_identity.management.account_id
  log_archive_id  = local.accounts["log-archive"]
  trail_arn       = "arn:aws:cloudtrail:us-east-1:${local.management_id}:trail/${var.trail_name}"
  trail_bucket    = "org-cloudtrail-${local.log_archive_id}"
  trail_bucket_id = aws_s3_bucket.trail.id
}

# ---------- KMS key (Log Archive) ----------

resource "aws_kms_key" "trail" {
  provider = aws.log_archive

  description             = "Encrypts organization CloudTrail logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "LogArchiveAdmins"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.log_archive_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudTrailEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:GenerateDataKey*"
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
          StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${local.management_id}:trail/*" }
        }
      },
      {
        Sid       = "CloudTrailDescribeKey"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:DescribeKey"
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
        }
      },
      {
        # The security team (Audit account) can read the logs during an
        # investigation, but only CloudTrail-encrypted data.
        Sid       = "AuditDecrypt"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.accounts["audit"]}:root" }
        Action    = ["kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          StringLike = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${local.management_id}:trail/*" }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "trail" {
  provider = aws.log_archive

  name          = "alias/org-cloudtrail"
  target_key_id = aws_kms_key.trail.key_id
}

# ---------- Bucket (Log Archive) ----------

resource "aws_s3_bucket" "trail" {
  provider = aws.log_archive

  bucket              = local.trail_bucket
  object_lock_enabled = true

  # Lets terraform destroy empty the bucket; governance-mode locks can be
  # bypassed by an admin with s3:BypassGovernanceRetention (compliance mode
  # could not, which is right for production and wrong for a lab).
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "trail" {
  provider = aws.log_archive

  bucket = local.trail_bucket_id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "trail" {
  provider = aws.log_archive

  bucket = local.trail_bucket_id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.log_lock_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  provider = aws.log_archive

  bucket = local.trail_bucket_id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.trail.arn
    }
    bucket_key_enabled = true # far fewer KMS calls, so far lower KMS cost
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  provider = aws.log_archive

  bucket                  = local.trail_bucket_id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "trail" {
  provider = aws.log_archive

  bucket = local.trail_bucket_id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  provider = aws.log_archive

  bucket = local.trail_bucket_id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_expire_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}

resource "aws_s3_bucket_policy" "trail" {
  provider = aws.log_archive

  bucket = local.trail_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
        }
      },
      {
        # Org trails write the management account's own events under its ID
        # and every member account's events under the organization ID.
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource = [
          "${aws_s3_bucket.trail.arn}/AWSLogs/${local.management_id}/*",
          "${aws_s3_bucket.trail.arn}/AWSLogs/${local.org.organization_id}/*",
        ]
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.trail]
}

# ---------- CloudWatch Logs delivery (management account) ----------
# Security Hub CloudTrail.5: the trail also streams to CloudWatch Logs, so
# events are searchable in seconds (Logs Insights) and can drive metric
# filters and alarms, instead of only landing as files in S3. Org trails
# deliver every account's events to this one log group.

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${var.trail_name}"
  retention_in_days = var.trail_log_retention_days
}

resource "aws_iam_role" "trail_cwlogs" {
  name = "cloudtrail-to-cloudwatch-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceArn" = local.trail_arn }
      }
    }]
  })
}

resource "aws_iam_role_policy" "trail_cwlogs" {
  name = "write-trail-log-group"
  role = aws_iam_role.trail_cwlogs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:log-stream:*"
    }]
  })
}

# ---------- Trail (management account) ----------

resource "aws_cloudtrail" "org" {
  name                          = var.trail_name
  s3_bucket_name                = local.trail_bucket
  kms_key_id                    = aws_kms_key.trail.arn
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_cwlogs.arn

  # CloudTrail checks bucket and key access at creation time.
  depends_on = [
    aws_s3_bucket_policy.trail,
    aws_s3_bucket_server_side_encryption_configuration.trail,
    aws_kms_alias.trail,
    aws_iam_role_policy.trail_cwlogs,
  ]
}
