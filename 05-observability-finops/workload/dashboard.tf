# One dashboard for the pipeline, top to bottom in the order you debug:
# are we inside the SLOs? -> where is time or errors going? -> show me logs.
# Plus saved Logs Insights queries for the common investigations.

locals {
  region = "us-east-1"

  api_dims = ["ApiId", local.api_id, "Stage", local.api_stage]
  sfn_dims = ["StateMachineArn", local.state_machine_arn]

  log_groups = {
    validate = "/aws/lambda/${local.fn["validate"]}"
    analyze  = "/aws/lambda/${local.fn["analyze"]}"
    api      = "/aws/lambda/${local.fn["api"]}"
    workflow = "/aws/vendedlogs/states/${var.name}"
    access   = "/aws/apigateway/${var.name}-api"
  }
}

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${var.name}-slo"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = join("", [
            "## ${var.name} (dev) · SLOs\n",
            "API ≥ ${var.slo_api_availability_pct}% non-5xx · API p95 < ${var.slo_api_p95_ms} ms · upload→result p95 < ${var.slo_pipeline_p95_seconds} s · ",
            "rejected files are expected, not incidents · [runbook](${local.runbook})",
          ])
        }
      },
      {
        type = "alarm", x = 0, y = 2, width = 24, height = 3
        properties = {
          title  = "Alarm status (only the composite pages; DLQ is information)"
          alarms = concat([aws_cloudwatch_composite_alarm.unhealthy.arn], [for a in concat(local.child_alarms, local.info_alarms) : "arn:aws:cloudwatch:${local.region}:${data.terraform_remote_state.org.outputs.account_ids["dev"]}:alarm:${a}"])
        }
      },
      {
        type = "metric", x = 0, y = 5, width = 8, height = 6
        properties = {
          title                = "API availability (% non-5xx, whole range)"
          view                 = "singleValue"
          region               = local.region
          setPeriodToTimeRange = true
          metrics = [
            [{ expression = "IF(requests > 0, 100 * (1 - errors / requests), 100)", label = "Availability %", id = "avail" }],
            concat(["AWS/ApiGateway", "5xx"], local.api_dims, [{ id = "errors", stat = "Sum", visible = false }]),
            concat(["AWS/ApiGateway", "Count"], local.api_dims, [{ id = "requests", stat = "Sum", visible = false }]),
          ]
        }
      },
      {
        type = "metric", x = 8, y = 5, width = 8, height = 6
        properties = {
          title  = "API latency (ms)"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = [
            concat(["AWS/ApiGateway", "Latency"], local.api_dims, [{ stat = "p50", label = "p50" }]),
            concat(["AWS/ApiGateway", "Latency"], local.api_dims, [{ stat = "p95", label = "p95" }]),
            concat(["AWS/ApiGateway", "Latency"], local.api_dims, [{ stat = "p99", label = "p99" }]),
          ]
          annotations = { horizontal = [{ label = "SLO p95", value = var.slo_api_p95_ms }] }
        }
      },
      {
        type = "metric", x = 16, y = 5, width = 8, height = 6
        properties = {
          title  = "Upload → result time (s)"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = [
            [{ expression = "p50 / 1000", label = "p50", id = "s50" }],
            [{ expression = "p95 / 1000", label = "p95", id = "s95" }],
            concat(["AWS/States", "ExecutionTime"], local.sfn_dims, [{ stat = "p50", id = "p50", visible = false }]),
            concat(["AWS/States", "ExecutionTime"], local.sfn_dims, [{ stat = "p95", id = "p95", visible = false }]),
          ]
          annotations = { horizontal = [{ label = "SLO p95", value = var.slo_pipeline_p95_seconds }] }
        }
      },
      {
        type = "metric", x = 0, y = 11, width = 12, height = 6
        properties = {
          title   = "Executions: succeeded vs rejected vs stuck"
          view    = "timeSeries"
          stacked = true
          region  = local.region
          period  = 300
          stat    = "Sum"
          metrics = [
            concat(["AWS/States", "ExecutionsSucceeded"], local.sfn_dims, [{ label = "succeeded" }]),
            concat(["AWS/States", "ExecutionsFailed"], local.sfn_dims, [{ label = "failed (incl. rejected files)" }]),
            concat(["AWS/States", "ExecutionsTimedOut"], local.sfn_dims, [{ label = "timed out" }]),
            concat(["AWS/States", "ExecutionsAborted"], local.sfn_dims, [{ label = "aborted" }]),
          ]
        }
      },
      {
        type = "metric", x = 12, y = 11, width = 12, height = 6
        properties = {
          title  = "Lambda errors · throttles · DLQ depth"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = concat(
            [for k, f in local.fn : ["AWS/Lambda", "Errors", "FunctionName", f, { stat = "Sum", label = "${k} errors" }]],
            [for k, f in local.fn : ["AWS/Lambda", "Throttles", "FunctionName", f, { stat = "Sum", label = "${k} throttles" }]],
            [["InventoryPipeline", "ValidateSystemErrors", { stat = "Sum", label = "validate system errors" }]],
            [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.dlq_name, { stat = "Maximum", label = "DLQ depth", yAxis = "right" }]],
          )
        }
      },
      {
        type = "metric", x = 0, y = 17, width = 12, height = 6
        properties = {
          title  = "Lambda duration p95 (ms) · cost driver"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = [
            for k, f in local.fn : ["AWS/Lambda", "Duration", "FunctionName", f, { stat = "p95", label = k }]
          ]
        }
      },
      {
        type = "log", x = 12, y = 17, width = 12, height = 6
        properties = {
          title  = "Latest Lambda errors"
          region = local.region
          view   = "table"
          query  = "SOURCE '${local.log_groups.analyze}' | SOURCE '${local.log_groups.api}' | fields @timestamp, @log, @message | filter @message like /ERROR|Traceback|Task timed out/ | sort @timestamp desc | limit 20"
        }
      },
    ]
  })
}

# ---------- Saved Logs Insights queries ----------

resource "aws_cloudwatch_query_definition" "lambda_errors" {
  name            = "${var.name}/lambda-errors"
  log_group_names = [local.log_groups.validate, local.log_groups.analyze, local.log_groups.api]

  query_string = <<-EOT
    fields @timestamp, @log, @message
    | filter @message like /ERROR|Traceback|Task timed out/
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "slowest_invocations" {
  name            = "${var.name}/slowest-invocations"
  log_group_names = [local.log_groups.validate, local.log_groups.analyze, local.log_groups.api]

  query_string = <<-EOT
    filter @type = "REPORT"
    | fields @timestamp, @log, @duration, @billedDuration, @maxMemoryUsed / 1000000 as memMB, @initDuration
    | sort @duration desc
    | limit 20
  EOT
}

resource "aws_cloudwatch_query_definition" "cold_starts" {
  name            = "${var.name}/cold-starts"
  log_group_names = [local.log_groups.validate, local.log_groups.analyze, local.log_groups.api]

  query_string = <<-EOT
    filter @type = "REPORT"
    | stats count(*) as invocations, count(@initDuration) as coldStarts, avg(@initDuration) as avgInitMs by @log
  EOT
}

resource "aws_cloudwatch_query_definition" "api_errors" {
  name            = "${var.name}/api-non-2xx"
  log_group_names = [local.log_groups.access]

  query_string = <<-EOT
    fields @timestamp, status, routeKey, latencyMs, caller, integrationErr
    | filter status >= 400
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "failed_executions" {
  name            = "${var.name}/failed-executions"
  log_group_names = [local.log_groups.workflow]

  query_string = <<-EOT
    fields @timestamp, type, execution_arn, details.error, details.cause
    | filter type like /Failed|TimedOut|Aborted/
    | sort @timestamp desc
    | limit 50
  EOT
}
