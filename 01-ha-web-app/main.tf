# Project 01: highly available multi-tier web app.
# Built up in layers, one pull request each:
#   1. network    VPC, subnets, NAT, routing, flow logs           (done)
#   2. security groups + RDS Multi-AZ                           (this PR)
#   3. compute    launch template + Auto Scaling group
#   4. ALB + HTTPS
#   5. CloudFront + WAF + S3 static assets

module "network" {
  source = "../modules/network"

  name               = var.name
  vpc_cidr           = var.vpc_cidr
  az_count           = 2
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway
}

module "database" {
  source = "../modules/database"

  name                  = var.name
  subnet_ids            = module.network.data_subnet_ids
  security_group_ids    = [aws_security_group.db.id]
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
}
