output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability Zones in use, in subnet order"
  value       = local.azs
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  value = aws_subnet.data[*].id
}

output "nat_public_ips" {
  description = "Outbound IPs for the app tier (useful for allow-lists)"
  value       = aws_eip.nat[*].public_ip
}

output "flow_log_group" {
  value = aws_cloudwatch_log_group.flow_logs.name
}
