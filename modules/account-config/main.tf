# AWS Config baseline for one account: a recorder role plus a daily recorder
# and delivery channel in its home and secondary region.
#
# Built in Terraform rather than a CloudFormation StackSet on purpose: CFN's
# AWS::Config::ConfigurationRecorder starts recording as soon as it's created,
# which needs a delivery channel, and a delivery channel needs a recorder. The
# stack deadlocks ("did not stabilize"). Terraform creates the recorder
# stopped, adds the channel, then starts it (see modules/config-recorder).

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.home, aws.secondary]
    }
  }
}

variable "delivery_bucket" {
  description = "Central Config bucket (in Log Archive)"
  type        = string
}

variable "role_name" {
  description = "Recorder role name; must start with config-recorder to match the bucket policy"
  type        = string
  default     = "config-recorder"
}

data "aws_caller_identity" "this" {
  provider = aws.home
}

resource "aws_iam_role" "this" {
  provider = aws.home

  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.this.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "this" {
  provider = aws.home

  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "delivery" {
  provider = aws.home

  name = "deliver-to-log-archive"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${var.delivery_bucket}/AWSLogs/${data.aws_caller_identity.this.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${var.delivery_bucket}"
      },
    ]
  })
}

# Global resources (IAM) are recorded in the home region only.
module "home" {
  source = "../config-recorder"

  providers = {
    aws = aws.home
  }

  role_arn        = aws_iam_role.this.arn
  delivery_bucket = var.delivery_bucket
  include_global  = true

  depends_on = [aws_iam_role_policy.delivery, aws_iam_role_policy_attachment.this]
}

module "secondary" {
  source = "../config-recorder"

  providers = {
    aws = aws.secondary
  }

  role_arn        = aws_iam_role.this.arn
  delivery_bucket = var.delivery_bucket
  include_global  = false

  depends_on = [aws_iam_role_policy.delivery, aws_iam_role_policy_attachment.this]
}
