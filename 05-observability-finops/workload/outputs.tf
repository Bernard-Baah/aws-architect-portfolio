output "dashboard_url" {
  value = "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards/dashboard/${aws_cloudwatch_dashboard.pipeline.dashboard_name}"
}

output "composite_alarm" {
  value = aws_cloudwatch_composite_alarm.unhealthy.alarm_name
}

output "child_alarms" {
  value = local.child_alarms
}
