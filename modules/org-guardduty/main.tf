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

variable "members" {
  description = "Account ID => root email of every other org account to enroll now (auto-enable only reaches existing accounts eventually)"
  type        = map(string)
  default     = {}
}

# Enable GuardDuty in the admin account first. Designating an admin that has no
# detector makes GuardDuty create one itself, which Terraform then can't adopt.
resource "aws_guardduty_detector" "audit" {
  provider = aws.audit

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

# The management account can only be enrolled as a member once it has its
# own detector (otherwise CreateMembers silently rejects it). After enrollment
# the admin controls its settings, so Terraform only creates it.
resource "aws_guardduty_detector" "management" {
  provider = aws.management

  enable = true

  lifecycle {
    ignore_changes = all
  }
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

# auto_enable "ALL" covers new accounts immediately but enrolls existing ones
# in the background, which can take hours. Adding them explicitly enrolls
# them now (no invitation needed for accounts in the same organization).
resource "aws_guardduty_member" "this" {
  provider = aws.audit
  for_each = var.members

  detector_id = aws_guardduty_detector.audit.id
  account_id  = each.key
  email       = each.value

  lifecycle {
    ignore_changes = [email, invite]
  }

  depends_on = [
    aws_guardduty_organization_configuration.this,
    aws_guardduty_detector.management,
  ]
}

output "audit_detector_id" {
  value = aws_guardduty_detector.audit.id
}
