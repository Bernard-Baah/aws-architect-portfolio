# Free, account-wide security settings for one account in its home and
# secondary region. Each one clears a Security Hub FSBP control that fails
# once per account per region in a fresh account.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.home, aws.secondary]
    }
  }
}

data "aws_caller_identity" "this" {
  provider = aws.home
}

locals {
  account_id = data.aws_caller_identity.this.account_id
}

# ---------- Global (once per account) ----------

# S3.1: no bucket in the account can be made public, whatever its own policy says.
resource "aws_s3_account_public_access_block" "this" {
  provider = aws.home

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM.7: strong password rules for any IAM user with a console password.
# No forced expiry: NIST 800-63B advises against periodic rotation.
resource "aws_iam_account_password_policy" "this" {
  provider = aws.home

  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
}

# ---------- Regional (home) ----------

# EC2.7: every new EBS volume and snapshot copy is encrypted.
resource "aws_ebs_encryption_by_default" "home" {
  provider = aws.home

  enabled = true
}

# EC2.182: snapshots can't be shared publicly.
resource "aws_ebs_snapshot_block_public_access" "home" {
  provider = aws.home

  state = "block-all-sharing"
}

# SSM.7 (critical): SSM documents can't be shared publicly.
resource "aws_ssm_service_setting" "doc_sharing_home" {
  provider = aws.home

  setting_id    = "arn:aws:ssm:us-east-1:${local.account_id}:servicesetting/ssm/documents/console/public-sharing-permission"
  setting_value = "Disable"
}

# SSM.6: Automation runbook output is logged to CloudWatch.
resource "aws_ssm_service_setting" "automation_logs_home" {
  provider = aws.home

  setting_id    = "arn:aws:ssm:us-east-1:${local.account_id}:servicesetting/ssm/automation/customer-script-log-destination"
  setting_value = "CloudWatch"
}

# ---------- Regional (secondary) ----------

resource "aws_ebs_encryption_by_default" "secondary" {
  provider = aws.secondary

  enabled = true
}

resource "aws_ebs_snapshot_block_public_access" "secondary" {
  provider = aws.secondary

  state = "block-all-sharing"
}

resource "aws_ssm_service_setting" "doc_sharing_secondary" {
  provider = aws.secondary

  setting_id    = "arn:aws:ssm:us-west-2:${local.account_id}:servicesetting/ssm/documents/console/public-sharing-permission"
  setting_value = "Disable"
}

resource "aws_ssm_service_setting" "automation_logs_secondary" {
  provider = aws.secondary

  setting_id    = "arn:aws:ssm:us-west-2:${local.account_id}:servicesetting/ssm/automation/customer-script-log-destination"
  setting_value = "CloudWatch"
}
