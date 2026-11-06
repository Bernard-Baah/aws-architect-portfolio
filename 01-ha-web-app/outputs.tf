output "vpc_id" {
  value = module.network.vpc_id
}

output "azs" {
  value = module.network.azs
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "app_subnet_ids" {
  value = module.network.app_subnet_ids
}

output "data_subnet_ids" {
  value = module.network.data_subnet_ids
}

output "nat_public_ips" {
  value = module.network.nat_public_ips
}

output "flow_log_group" {
  value = module.network.flow_log_group
}

output "security_group_ids" {
  value = {
    alb = aws_security_group.alb.id
    app = aws_security_group.app.id
    db  = aws_security_group.db.id
  }
}

output "db_endpoint" {
  value = module.database.endpoint
}

output "db_identifier" {
  value = module.database.identifier
}

output "db_secret_arn" {
  description = "Secrets Manager secret with the DB master credentials"
  value       = module.database.master_user_secret_arn
}

output "db_multi_az" {
  value = module.database.multi_az
}

output "asg_name" {
  value = module.web_tier.asg_name
}

output "app_ami_id" {
  value = module.web_tier.ami_id
}
