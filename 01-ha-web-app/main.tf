# Project 01: highly available multi-tier web app.
# Built up in layers, one pull request each:
#   1. network    VPC, subnets, NAT, routing, flow logs     (done)
#   2. security groups + RDS Multi-AZ                     (done)
#   3. compute    launch template + Auto Scaling group      (done)
#   4. internal ALB                                         (done)
#   5. CloudFront (VPC origin) + WAF                        (this PR)

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

module "web_tier" {
  source = "../modules/web-tier"

  name               = var.name
  subnet_ids         = module.network.app_subnet_ids
  security_group_ids = [aws_security_group.app.id]
  app_port           = var.app_port
  instance_type      = var.instance_type

  vpc_id                 = module.network.vpc_id
  alb_subnet_ids         = module.network.app_subnet_ids
  alb_security_group_ids = [aws_security_group.alb.id]

  db_host       = module.database.address
  db_name       = module.database.db_name
  db_secret_arn = module.database.master_user_secret_arn
}

module "edge" {
  source = "../modules/edge"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name         = var.name
  alb_arn      = module.web_tier.alb_arn
  alb_dns_name = module.web_tier.alb_dns_name
}
