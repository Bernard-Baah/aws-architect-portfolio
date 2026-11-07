output "app_url" {
  description = "One URL for both regions (CloudFront origin failover)"
  value       = module.edge.url
}

output "primary" {
  value = {
    region      = var.primary_region
    asg_name    = module.primary.asg_name
    db_instance = aws_db_instance.primary.identifier
  }
}

output "secondary" {
  value = {
    region      = var.secondary_region
    asg_name    = module.secondary.asg_name
    db_instance = aws_db_instance.replica.identifier
  }
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db.name
}

output "cloudfront_distribution_id" {
  value = module.edge.distribution_id
}
