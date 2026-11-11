# Layer 5b: SLOs and alarms for the Project 02 pipeline running in dev.
#
# SLIs (what users feel), each with its own alarm:
#   API availability  : share of /documents requests without a 5xx
#   API latency       : p95 response time
#   Pipeline freshness: p95 time from upload to result stored
#   System errors     : timeouts/aborts, Lambda errors that aren't bad input
#
# Bad input is NOT an incident. A rejected file (wrong format, missing
# columns) ends its execution as FAILED by design and is recorded in
# DynamoDB (and the DLQ), so ExecutionsFailed, DLQ depth and validate's
# ValidationError are deliberately left out of paging.
#
# The child alarms have no actions. One composite alarm ORs them together
# and is the only thing that notifies, so one incident sends one email.

locals {
  pipeline = data.terraform_remote_state.pipeline.outputs

  state_machine_arn = local.pipeline.state_machine_arn
  api_id            = regex("^https://([^.]+)\\.execute-api\\.", local.pipeline.api_url)[0]
  api_stage         = "$default"
  dlq_name          = element(split("/", local.pipeline.dlq_url), length(split("/", local.pipeline.dlq_url)) - 1)
  fn                = { for k in ["validate", "analyze", "api"] : k => "${var.name}-${k}" }

  runbook = "${var.runbook_base_url}/pipeline-unhealthy.md"
}

# ---------- Where pages go ----------
# Unencrypted on purpose: CloudWatch alarms can't publish to a topic encrypted
# with the AWS managed aws/sns key (lesson from Project 02).
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------- Child alarms (no actions) ----------

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name}-api-5xx-rate"
  alarm_description   = "API error rate above the SLO burn threshold (1% of requests in 5 min). Runbook: ${local.runbook}#api-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "rate"
    expression  = "IF(requests > 0, 100 * errors / requests, 0)"
    label       = "5xx rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "5xx"
      period      = 300
      stat        = "Sum"
      dimensions  = { ApiId = local.api_id, Stage = local.api_stage }
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "Count"
      period      = 300
      stat        = "Sum"
      dimensions  = { ApiId = local.api_id, Stage = local.api_stage }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "${var.name}-api-latency-p95"
  alarm_description   = "API p95 latency above ${var.slo_api_p95_ms} ms for 15 min. Runbook: ${local.runbook}#api-latency-p95"
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiId = local.api_id, Stage = local.api_stage }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.slo_api_p95_ms
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "pipeline_latency" {
  alarm_name          = "${var.name}-pipeline-latency-p95"
  alarm_description   = "Upload-to-result p95 above ${var.slo_pipeline_p95_seconds} s for 15 min. Runbook: ${local.runbook}#pipeline-latency-p95"
  namespace           = "AWS/States"
  metric_name         = "ExecutionTime"
  dimensions          = { StateMachineArn = local.state_machine_arn }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.slo_pipeline_p95_seconds * 1000
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "pipeline_stuck" {
  alarm_name          = "${var.name}-pipeline-timeouts-aborts"
  alarm_description   = "Executions timed out or were aborted (never bad input). Runbook: ${local.runbook}#pipeline-timeouts-aborts"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "stuck"
    expression  = "timedout + aborted"
    label       = "Timed out + aborted"
    return_data = true
  }

  metric_query {
    id = "timedout"
    metric {
      namespace   = "AWS/States"
      metric_name = "ExecutionsTimedOut"
      period      = 300
      stat        = "Sum"
      dimensions  = { StateMachineArn = local.state_machine_arn }
    }
  }

  metric_query {
    id = "aborted"
    metric {
      namespace   = "AWS/States"
      metric_name = "ExecutionsAborted"
      period      = 300
      stat        = "Sum"
      dimensions  = { StateMachineArn = local.state_machine_arn }
    }
  }
}

# validate raises ValidationError for bad files (expected) and anything else
# for real faults (S3 access, bugs). The Lambda Errors metric can't tell them
# apart, so a log metric filter counts only the non-validation errors.
resource "aws_cloudwatch_log_metric_filter" "validate_system_errors" {
  name           = "${var.name}-validate-system-errors"
  log_group_name = "/aws/lambda/${local.fn["validate"]}"
  pattern        = "\"[ERROR]\" -ValidationError"

  metric_transformation {
    name          = "ValidateSystemErrors"
    namespace     = "InventoryPipeline"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name}-system-lambda-errors"
  alarm_description   = "System errors in analyze, API, or validate (validate's ValidationError for bad files is excluded). Runbook: ${local.runbook}#system-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "errs"
    expression  = "analyze + api + validate"
    label       = "system errors"
    return_data = true
  }

  metric_query {
    id = "analyze"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      period      = 300
      stat        = "Sum"
      dimensions  = { FunctionName = local.fn["analyze"] }
    }
  }

  metric_query {
    id = "api"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      period      = 300
      stat        = "Sum"
      dimensions  = { FunctionName = local.fn["api"] }
    }
  }

  metric_query {
    id = "validate"
    metric {
      namespace   = "InventoryPipeline"
      metric_name = aws_cloudwatch_log_metric_filter.validate_system_errors.metric_transformation[0].name
      period      = 300
      stat        = "Sum"
    }
  }
}

# ---------- The one alarm that pages ----------
# Project 02's DLQ alarm is deliberately NOT part of the composite: the
# workflow sends every failure to the DLQ, rejected files included, so DLQ
# depth alone can't say "system broken". (First version included it and
# paged on the sample run's not-a-csv.txt.) System failures that end in the
# DLQ are caught by the error and timeout alarms above; the DLQ stays on the
# dashboard as information, with its runbook section for triage.

locals {
  child_alarms = [
    aws_cloudwatch_metric_alarm.api_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.api_latency.alarm_name,
    aws_cloudwatch_metric_alarm.pipeline_latency.alarm_name,
    aws_cloudwatch_metric_alarm.pipeline_stuck.alarm_name,
    aws_cloudwatch_metric_alarm.lambda_errors.alarm_name,
  ]

  info_alarms = ["${var.name}-dlq-not-empty"]
}

resource "aws_cloudwatch_composite_alarm" "unhealthy" {
  alarm_name        = "${var.name}-unhealthy"
  alarm_description = "One or more pipeline SLO alarms is firing. Open the dashboard, find the red child alarm, follow its runbook section: ${local.runbook}"
  alarm_rule        = join(" OR ", [for a in local.child_alarms : "ALARM(\"${a}\")"])

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
