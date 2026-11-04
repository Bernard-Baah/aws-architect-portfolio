output "role_arn" {
  description = "Set this as the AWS_ROLE_ARN repository variable in GitHub"
  value       = aws_iam_role.plan.arn
}

output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}
