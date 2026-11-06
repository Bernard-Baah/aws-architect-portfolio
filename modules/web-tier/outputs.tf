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
