# Security Hub CSPM with central configuration: Audit is the delegated admin,
# us-east-1 is the home (aggregation) region with us-west-2 linked, and one
# configuration policy turns on AWS Foundational Security Best Practices
# (FSBP) in every account. Controls are evaluated from the AWS Config data
# recorded by layer 2c.
#
# Order matters (AWS docs): Security Hub on in management -> delegate Audit in
# the home region -> finding aggregator -> CENTRAL organization configuration
# -> configuration policy -> associate it with the org root.

locals {
  fsbp_arn = "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# AWS requires Security Hub to be on in the management account (in at least
# one region) before delegating. After that the central policy manages it.
resource "aws_securityhub_account" "management" {
  enable_default_standards = false

  lifecycle {
    ignore_changes = all
  }
}

# Same pattern as GuardDuty: turn it on in Audit first, so the delegation
# finds an existing hub instead of creating one Terraform doesn't track.
resource "aws_securityhub_account" "audit" {
  provider = aws.audit

  enable_default_standards = false

  lifecycle {
    ignore_changes = all
  }
}

# Home region only: central configuration copies the admin to linked regions.
resource "aws_securityhub_organization_admin_account" "audit" {
  admin_account_id = local.accounts["audit"]

  depends_on = [aws_securityhub_account.management, aws_securityhub_account.audit]
}

resource "aws_securityhub_finding_aggregator" "this" {
  provider = aws.audit

  linking_mode      = "SPECIFIED_REGIONS"
  specified_regions = ["us-west-2"]

  depends_on = [aws_securityhub_organization_admin_account.audit]
}

resource "aws_securityhub_organization_configuration" "this" {
  provider = aws.audit

  auto_enable           = false
  auto_enable_standards = "NONE"

  organization_configuration {
    configuration_type = "CENTRAL"
  }

  depends_on = [aws_securityhub_finding_aggregator.this]
}

resource "aws_securityhub_configuration_policy" "fsbp" {
  provider = aws.audit

  # Switching security_hub_enabled to false doesn't delete anything: the same
  # policy, still associated with the org root, becomes "Security Hub
  # disabled", and central configuration turns it off in every account. No
  # hub means no security checks and no bill. Flip back to true to re-enable.
  name        = "fsbp-all-accounts"
  description = var.security_hub_enabled ? "Security Hub on with AWS Foundational Security Best Practices, all controls" : "Security Hub disabled org-wide to save cost, re-enable with security_hub_enabled"

  configuration_policy {
    service_enabled       = var.security_hub_enabled
    enabled_standard_arns = var.security_hub_enabled ? [local.fsbp_arn] : null

    dynamic "security_controls_configuration" {
      for_each = var.security_hub_enabled ? [1] : []
      content {
        disabled_control_identifiers = []
      }
    }
  }

  depends_on = [aws_securityhub_organization_configuration.this]
}

# Associating with the root applies the policy to every OU and account,
# including ones created later.
resource "aws_securityhub_configuration_policy_association" "root" {
  provider = aws.audit

  target_id = local.org.root_id
  policy_id = aws_securityhub_configuration_policy.fsbp.id
}
