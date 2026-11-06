output "upload_bucket" {
  value = aws_s3_bucket.uploads.id
}

output "upload_example" {
  description = "Try it"
  value       = "aws s3 cp samples/rack-inventory-issues.csv s3://${aws_s3_bucket.uploads.id}/incoming/"
}

output "table_name" {
  value = aws_dynamodb_table.documents.name
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "topic_arn" {
  value = aws_sns_topic.events.arn
}

output "api_url" {
  description = "IAM-authorized; see scripts/query-api.sh"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}documents"
}
