output "app_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "alb_arn_suffix" {
  description = "For CloudWatch metrics and alarms (Project 05)"
  value       = aws_lb.app.arn_suffix
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.app.arn_suffix
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "launch_template_id" {
  value = aws_launch_template.app.id
}

output "instance_role_name" {
  value = aws_iam_role.app.name
}

output "ami_id" {
  description = "AMI the current launch template version uses"
  value       = data.aws_ssm_parameter.al2023_arm64.insecure_value
}
