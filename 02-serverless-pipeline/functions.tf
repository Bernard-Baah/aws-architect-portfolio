# Small Python functions, each with its own least-privilege role.
# Storing results, notifying and dead-lettering are done by Step Functions'
# direct service integrations, so there's no Lambda "glue" code for them.

locals {
  functions = {
    validate = {
      description = "Rejects files the pipeline doesn't accept (type, size)"
      timeout     = 10
      memory      = 128
    }
    analyze = {
      description = "Parses a rack-inventory CSV and reports data-quality issues"
      timeout     = 30
      memory      = 256
    }
    api = {
      description = "Read-only query API over the results table"
      timeout     = 10
      memory      = 256
    }
  }
}

data "archive_file" "fn" {
  for_each = local.functions

  type        = "zip"
  source_dir  = "${path.module}/src/${each.key}"
  output_path = "${path.module}/build/${each.key}.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fn" {
  for_each = local.functions

  name               = "${var.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Logs only to its own log group (no AWSLambdaBasicExecutionRole wildcard)
data "aws_iam_policy_document" "fn_logs" {
  for_each = local.functions

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.fn[each.key].arn}:*"]
  }
}

resource "aws_iam_role_policy" "fn_logs" {
  for_each = local.functions

  name   = "logs"
  role   = aws_iam_role.fn[each.key].id
  policy = data.aws_iam_policy_document.fn_logs[each.key].json
}

resource "aws_iam_role_policy_attachment" "fn_xray" {
  for_each = local.functions

  role       = aws_iam_role.fn[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Only analyze reads files, and only from incoming/
data "aws_iam_policy_document" "analyze_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/incoming/*"]
  }
}

resource "aws_iam_role_policy" "analyze_read" {
  name   = "read-uploads"
  role   = aws_iam_role.fn["analyze"].id
  policy = data.aws_iam_policy_document.analyze_read.json
}

# The API can only query this table's indexes and read single items
data "aws_iam_policy_document" "api_read" {
  statement {
    actions = ["dynamodb:Query", "dynamodb:GetItem"]

    resources = [
      aws_dynamodb_table.documents.arn,
      "${aws_dynamodb_table.documents.arn}/index/*",
    ]
  }
}

resource "aws_iam_role_policy" "api_read" {
  name   = "read-results"
  role   = aws_iam_role.fn["api"].id
  policy = data.aws_iam_policy_document.api_read.json
}

resource "aws_cloudwatch_log_group" "fn" {
  for_each = local.functions

  name              = "/aws/lambda/${var.name}-${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "fn" {
  for_each = local.functions

  function_name    = "${var.name}-${each.key}"
  description      = each.value.description
  role             = aws_iam_role.fn[each.key].arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "handler.handler"
  filename         = data.archive_file.fn[each.key].output_path
  source_code_hash = data.archive_file.fn[each.key].output_base64sha256
  timeout          = each.value.timeout
  memory_size      = each.value.memory

  dynamic "environment" {
    for_each = each.key == "api" ? [1] : []

    content {
      variables = { TABLE_NAME = aws_dynamodb_table.documents.name }
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.fn[each.key].name
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_iam_role_policy.fn_logs]
}
