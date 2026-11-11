# Layer 5a: FinOps guardrails for the whole organization.
#
#   1. Cost allocation tags  -> Cost Explorer can split cost by Project/Owner
#   2. Budgets               -> forecast and actual alerts, org total + workloads
#   3. Anomaly detection     -> one monitor per member account, daily email
#
# Nothing here costs money to run.

locals {
  accounts      = data.terraform_remote_state.org.outputs.account_ids
  workload_ids  = [local.accounts["dev"], local.accounts["prod"]]
  member_ids    = values(local.accounts)
  budget_alerts = [50, 80, 100]
}

data "aws_caller_identity" "management" {}

# ---------- 1. Cost allocation tags ----------
# Every stack in this repo tags resources through provider default_tags.
# Activation only affects cost data from now on (not retroactive), and a tag
# key must already have appeared in billing data to be activated.

resource "aws_ce_cost_allocation_tag" "this" {
  for_each = toset(var.cost_allocation_tags)

  tag_key = each.key
  status  = "Active"
}

# ---------- 2. Budgets ----------

resource "aws_budgets_budget" "org_total" {
  name         = "org-monthly-total"
  budget_type  = "COST"
  limit_amount = format("%.2f", var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Forecast alerts give warning before the money is spent; the 100% actual
  # alert confirms it was.
  dynamic "notification" {
    for_each = local.budget_alerts
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = [var.alert_email]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

resource "aws_budgets_budget" "workloads" {
  name         = "workloads-dev-prod-monthly"
  budget_type  = "COST"
  limit_amount = format("%.2f", var.workloads_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "LinkedAccount"
    values = local.workload_ids
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ---------- 3. Cost Anomaly Detection ----------
# A custom monitor over linked accounts: AWS learns each account's normal
# spend and flags spikes per account. (Accounts can only have one AWS-services
# monitor and many already have a default one, so this avoids colliding.)

resource "aws_ce_anomaly_monitor" "accounts" {
  name         = "member-accounts"
  monitor_type = "CUSTOM"

  monitor_specification = jsonencode({
    Dimensions = {
      Key          = "LINKED_ACCOUNT"
      Values       = concat(local.member_ids, [data.aws_caller_identity.management.account_id])
      MatchOptions = null
    }
    And            = null
    Or             = null
    Not            = null
    Tags           = null
    CostCategories = null
  })
}

resource "aws_ce_anomaly_subscription" "daily" {
  name      = "daily-anomaly-email"
  frequency = "DAILY"

  monitor_arn_list = [aws_ce_anomaly_monitor.accounts.arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }
}
