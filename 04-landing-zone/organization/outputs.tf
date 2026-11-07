output "organization_id" {
  value = aws_organizations_organization.this.id
}

output "root_id" {
  value = local.root_id
}

output "ou_ids" {
  description = "OU name => OU id"
  value       = { for k, ou in aws_organizations_organizational_unit.this : k => ou.id }
}

output "account_ids" {
  description = "Account key (log-archive, audit, dev, prod) => account id. Read by the security/ and identity/ stacks."
  value       = { for k, a in aws_organizations_account.this : k => a.id }
}

output "admin_role_name" {
  description = "Role the management account assumes in each member account"
  value       = var.scp_exempt_role
}
