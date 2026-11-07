# GuardDuty for a whole organization in one region, administered from a
# delegated admin (security tooling) account instead of the management account.
# GuardDuty is regional, so the root stack calls this once per region.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.management, aws.audit]
    }
  }
}

variable "audit_account_id" {
  description = "Account that becomes the GuardDuty delegated administrator"
  type        = string
}

# Enable GuardDuty in the admin account first. Designating an admin that has no
# detector makes GuardDuty create one itself, which Terraform then can't adopt.
resource "aws_guardduty_detector" "audit" {
  provider = aws.audit

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_organization_admin_account" "this" {
  provider = aws.management

  admin_account_id = var.audit_account_id

  depends_on = [aws_guardduty_detector.audit]
}

# From the admin account: turn GuardDuty on in every existing and future
# member account. Members can't turn it off (they aren't the admin, and the
# guardrails SCP denies guardduty:DeleteDetector and disassociation).
resource "aws_guardduty_organization_configuration" "this" {
  provider = aws.audit

  detector_id                      = aws_guardduty_detector.audit.id
  auto_enable_organization_members = "ALL"

  depends_on = [aws_guardduty_organization_admin_account.this]
}

output "audit_detector_id" {
  value = aws_guardduty_detector.audit.id
}
