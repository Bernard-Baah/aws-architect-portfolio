output "role_arn" {
  description = "Set this as the AWS_ROLE_ARN repository variable in GitHub"
  value       = aws_iam_role.plan.arn
}

output "allowed_subjects" {
  description = "Exact sub patterns the role trusts (useful when debugging AssumeRoleWithWebIdentity errors)"
  value       = [for s in var.allowed_subjects : "${local.sub_prefix}:${s}"]
}

output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}
