# Layer 3b: IAM Identity Center. People sign in once at the access portal
# and pick an account + role; no IAM users or long-lived keys in member
# accounts. Each permission set becomes a role named AWSReservedSSO_<name>_*
# in the accounts it's assigned to. Those roles are NOT exempt from the
# guardrails SCP, so even an Identity Center admin can't switch off
# CloudTrail, GuardDuty, Config or Security Hub.
#
# The Identity Center instance already existed (enabled for an earlier
# project), so it's read with a data source rather than created. New names
# are prefixed LZ- to avoid colliding with anything from that project.

data "aws_ssoadmin_instances" "this" {}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  accounts          = data.terraform_remote_state.org.outputs.account_ids

  # name => AWS managed policy + session length (ISO 8601)
  permission_sets = {
    LZ-Admin = {
      policy   = "arn:aws:iam::aws:policy/AdministratorAccess"
      duration = "PT1H" # short sessions for the most powerful access
      desc     = "Full admin in member accounts (still bound by the guardrails SCP)"
    }
    LZ-PowerUser = {
      policy   = "arn:aws:iam::aws:policy/PowerUserAccess"
      duration = "PT4H"
      desc     = "Build and run workloads; no IAM or Organizations changes"
    }
    LZ-ReadOnly = {
      policy   = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      duration = "PT4H"
      desc     = "Look, don't touch"
    }
  }

  # Who gets what, where: least privilege per environment.
  assignments = {
    "LZ-Admin/log-archive" = { set = "LZ-Admin", account = "log-archive" }
    "LZ-Admin/audit"       = { set = "LZ-Admin", account = "audit" }
    "LZ-Admin/dev"         = { set = "LZ-Admin", account = "dev" }
    "LZ-Admin/prod"        = { set = "LZ-Admin", account = "prod" }
    "LZ-PowerUser/dev"     = { set = "LZ-PowerUser", account = "dev" }
    "LZ-ReadOnly/prod"     = { set = "LZ-ReadOnly", account = "prod" }
    "LZ-ReadOnly/audit"    = { set = "LZ-ReadOnly", account = "audit" }
  }
}

# ---------- People ----------

resource "aws_identitystore_user" "admin" {
  identity_store_id = local.identity_store_id

  user_name    = var.admin_user.user_name
  display_name = "${var.admin_user.given_name} ${var.admin_user.family_name}"

  name {
    given_name  = var.admin_user.given_name
    family_name = var.admin_user.family_name
  }

  emails {
    value   = var.admin_user.email
    primary = true
  }
}

# Access is granted to groups, never directly to users, so adding a teammate
# is one membership instead of seven assignments.
resource "aws_identitystore_group" "platform" {
  identity_store_id = local.identity_store_id

  display_name = "lz-platform-team"
  description  = "Landing zone platform team"
}

resource "aws_identitystore_group_membership" "admin" {
  identity_store_id = local.identity_store_id

  group_id  = aws_identitystore_group.platform.group_id
  member_id = aws_identitystore_user.admin.user_id
}

# ---------- Permission sets ----------

resource "aws_ssoadmin_permission_set" "this" {
  for_each = local.permission_sets

  instance_arn     = local.instance_arn
  name             = each.key
  description      = each.value.desc
  session_duration = each.value.duration
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.permission_sets

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  managed_policy_arn = each.value.policy
}

# ---------- Assignments ----------

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.assignments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.set].arn
  principal_type     = "GROUP"
  principal_id       = aws_identitystore_group.platform.group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = local.accounts[each.value.account]

  depends_on = [aws_ssoadmin_managed_policy_attachment.this]
}
