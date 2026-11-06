# ---------------------------------------------------------------- Query API (API Gateway HTTP API)
#
# Internal, read-only API. IAM (SigV4) authorization: only principals in this
# account with execute-api:Invoke can call it. HTTP APIs don't support API keys;
# an external audience would get a Cognito JWT authorizer instead.

resource "aws_apigatewayv2_api" "query" {
  name          = "${var.name}-api"
  description   = "Query rack-inventory processing results"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "query" {
  api_id                 = aws_apigatewayv2_api.query.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.fn["api"].invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_route" "documents" {
  api_id             = aws_apigatewayv2_api.query.id
  route_key          = "GET /documents"
  target             = "integrations/${aws_apigatewayv2_integration.query.id}"
  authorization_type = "AWS_IAM"
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${var.name}-api"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.query.id
  name        = "$default"
  auto_deploy = true

  # Protects the table (and the bill) from a runaway client
  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn

    format = jsonencode({
      requestId      = "$context.requestId"
      requestTime    = "$context.requestTime"
      caller         = "$context.identity.userArn"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      latencyMs      = "$context.responseLatency"
      integrationErr = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowQueryApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn["api"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.query.execution_arn}/*/GET/documents"
}
