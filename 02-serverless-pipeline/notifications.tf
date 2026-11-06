# ---------------------------------------------------------------- SNS: completion + alarm notifications

# Not KMS-encrypted on purpose: CloudWatch alarms can't publish to a topic that
# uses the AWS-managed key (alias/aws/sns), because that key's policy can't be
# changed to allow the alarm service. Messages here are status summaries only.
# Production: a customer-managed KMS key whose policy allows cloudwatch.amazonaws.com.
resource "aws_sns_topic" "events" {
  name = "${var.name}-events"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.events.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ---------------------------------------------------------------- Dead-letter queue + alarm

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum
  sqs_managed_sse_enabled   = true
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name}-dlq-not-empty"
  alarm_description   = "A file failed processing and is waiting in the dead-letter queue"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.events.arn]
  ok_actions          = [aws_sns_topic.events.arn]
}
