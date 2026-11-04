output "endpoint" {
  description = "host:port"
  value       = aws_db_instance.this.endpoint
}

output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "identifier" {
  description = "Use with: aws rds reboot-db-instance --db-instance-identifier <this> --force-failover"
  value       = aws_db_instance.this.identifier
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the master username and password"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "multi_az" {
  value = aws_db_instance.this.multi_az
}
