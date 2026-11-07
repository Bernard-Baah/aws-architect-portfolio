# Layer 1 of the landing zone: the organization itself, its OUs, the member
# accounts and the guardrail SCPs. Later layers (security/, identity/) read
# this stack's outputs, so their provider roles never depend on account IDs
# that don't exist yet.
#
#   Management account (this one)
#   ├── Security OU   → log-archive, audit
#   ├── Workloads OU  → dev, prod
#   └── Sandbox OU    → (empty; for experiments with looser rules later)

# The portfolio account was already the management account of an organization
# from an earlier project, so Terraform adopts it instead of creating one.
# After the first apply this block is a no-op and can be deleted.
import {
  to = aws_organizations_organization.this
  id = "o-aq2mzfaelk"
}

resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  # Trusted access for the org-wide services the later layers turn on.
  aws_service_access_principals = [
    "account.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "guardduty.amazonaws.com",
    "iam.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com",
  ]

  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
}

locals {
  root_id = aws_organizations_organization.this.roots[0].id

  ous = ["Security", "Workloads", "Sandbox"]

  accounts = {
    log-archive = "Security"
    audit       = "Security"
    dev         = "Workloads"
    prod        = "Workloads"
  }

  # you@gmail.com -> you+lz-dev@gmail.com (same inbox, unique per account).
  # A closed account's email can never be reused, so the tags stay distinct.
  email_user   = split("@", var.email_base)[0]
  email_domain = split("@", var.email_base)[1]
}

resource "aws_organizations_organizational_unit" "this" {
  for_each = toset(local.ous)

  name      = each.key
  parent_id = local.root_id
}

resource "aws_organizations_account" "this" {
  for_each = local.accounts

  name      = "${var.account_prefix}-${each.key}"
  email     = "${local.email_user}+${var.account_prefix}-${each.key}@${local.email_domain}"
  parent_id = aws_organizations_organizational_unit.this[each.value].id

  # Created in every new account; the management account assumes it to
  # deploy the later layers. Exempt from the baseline-protection SCP.
  role_name = var.scp_exempt_role

  # terraform destroy closes the account instead of only removing it from the
  # org (a removed account would need its own payment method and root login).
  # AWS allows at most 10 closures per rolling 30 days for an org this size.
  close_on_deletion = true

  lifecycle {
    # The Organizations API never returns role_name, so it would always diff.
    ignore_changes = [role_name]
  }
}

# Centralized root access: removes long-lived root credentials from every
# member account. The management account can still run the few root-only
# tasks through short-lived sts:AssumeRoot sessions.
resource "aws_iam_organizations_features" "root_access" {
  enabled_features = [
    "RootCredentialsManagement",
    "RootSessions",
  ]

  depends_on = [aws_organizations_organization.this]
}
