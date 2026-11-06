# ---------------------------------------------------------------- Step Functions state machine

resource "aws_cloudwatch_log_group" "workflow" {
  # The /aws/vendedlogs/ prefix avoids hitting the CloudWatch Logs resource-policy size limit.
  name              = "/aws/vendedlogs/states/${var.name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "states_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    # Confused-deputy protection: only state machines in this account
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "workflow" {
  name               = "${var.name}-workflow"
  assume_role_policy = data.aws_iam_policy_document.states_assume.json
}

data "aws_iam_policy_document" "workflow" {
  statement {
    sid     = "InvokeFunctions"
    actions = ["lambda:InvokeFunction"]

    resources = flatten([
      for fn in aws_lambda_function.fn : [fn.arn, "${fn.arn}:*"]
    ])
  }

  statement {
    sid       = "WriteResults"
    actions   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.documents.arn]
  }

  statement {
    sid       = "Notify"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.events.arn]
  }

  statement {
    sid       = "DeadLetter"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }

  statement {
    sid = "Tracing"

    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
    ]

    resources = ["*"]
  }

  # Log delivery APIs don't support resource-level permissions
  statement {
    sid = "ExecutionLogs"

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "workflow" {
  name   = "workflow"
  role   = aws_iam_role.workflow.id
  policy = data.aws_iam_policy_document.workflow.json
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = var.name
  type     = "STANDARD"
  role_arn = aws_iam_role.workflow.arn

  definition = templatefile("${path.module}/workflow.asl.json", {
    validate_function_arn = aws_lambda_function.fn["validate"].arn
    analyze_function_arn  = aws_lambda_function.fn["analyze"].arn
    table_name            = aws_dynamodb_table.documents.name
    topic_arn             = aws_sns_topic.events.arn
    dlq_url               = aws_sqs_queue.dlq.url
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.workflow.arn}:*"
    include_execution_data = false # executions carry file contents' summaries; keep them out of logs
    level                  = "ERROR"
  }

  tracing_configuration {
    enabled = true
  }

  depends_on = [aws_iam_role_policy.workflow]
}

# ---------------------------------------------------------------- EventBridge: S3 upload -> workflow

resource "aws_cloudwatch_event_rule" "upload" {
  name        = "${var.name}-upload"
  description = "New CSV under incoming/ starts the pipeline"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]

    detail = {
      bucket = { name = [aws_s3_bucket.uploads.id] }
      object = { key = [{ prefix = "incoming/" }] }
    }
  })
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "events" {
  name               = "${var.name}-events"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

data "aws_iam_policy_document" "events_start" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.pipeline.arn]
  }
}

resource "aws_iam_role_policy" "events" {
  name   = "start-pipeline"
  role   = aws_iam_role.events.id
  policy = data.aws_iam_policy_document.events_start.json
}

resource "aws_cloudwatch_event_target" "pipeline" {
  rule     = aws_cloudwatch_event_rule.upload.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.events.arn

  # If EventBridge can't start the workflow (throttling, permissions), keep the
  # event in the same DLQ instead of dropping it.
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}

# EventBridge needs permission to write undeliverable events to the DLQ
data "aws_iam_policy_document" "dlq" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.upload.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy    = data.aws_iam_policy_document.dlq.json
}
