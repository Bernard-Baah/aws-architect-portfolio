output "vpc_id" {
  value = module.network.vpc_id
}

output "data_subnet_ids" {
  value = module.network.data_subnet_ids
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}

output "alb_arn" {
  value = module.web_tier.alb_arn
}

output "alb_dns_name" {
  value = module.web_tier.alb_dns_name
}

output "asg_name" {
  value = module.web_tier.asg_name
}

output "target_group_arn_suffix" {
  value = module.web_tier.target_group_arn_suffix
}

output "alb_arn_suffix" {
  value = module.web_tier.alb_arn_suffix
}
