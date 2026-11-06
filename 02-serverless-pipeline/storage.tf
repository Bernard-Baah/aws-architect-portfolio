# ---------------------------------------------------------------- S3 upload bucket

resource "aws_s3_bucket" "uploads" {
  # Bucket names are global; account ID + region keeps this one unique.
  bucket        = "${var.name}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true # lab: terraform destroy also removes uploaded files
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Uploads are processed within seconds; nothing needs to stay for long.
resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "expire-uploads"
    status = "Enabled"

    filter {
      prefix = "incoming/"
    }

    expiration {
      days = 30
    }
  }
}

data "aws_iam_policy_document" "uploads_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.uploads.arn,
      "${aws_s3_bucket.uploads.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  policy = data.aws_iam_policy_document.uploads_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.uploads]
}

# Send every object event to EventBridge (rules decide what to act on).
resource "aws_s3_bucket_notification" "uploads" {
  bucket      = aws_s3_bucket.uploads.id
  eventbridge = true
}

# ---------------------------------------------------------------- DynamoDB results table

resource "aws_dynamodb_table" "documents" {
  name         = "${var.name}-documents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "doc_id"

  attribute {
    name = "doc_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  # "Show me everything that FAILED, newest first" without a table scan
  global_secondary_index {
    name            = "by-status"
    hash_key        = "status"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  # Encrypted at rest by default with an AWS-owned key (no KMS charges).
}
