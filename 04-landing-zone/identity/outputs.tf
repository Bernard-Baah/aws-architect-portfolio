output "access_portal_url" {
  description = "Sign-in page for Identity Center (default URL format)"
  value       = "https://${local.identity_store_id}.awsapps.com/start"
}

output "permission_sets" {
  value = { for k, ps in aws_ssoadmin_permission_set.this : k => ps.arn }
}
