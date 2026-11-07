# One region's copy of the Project 01 app tier: network, security group chain,
# internal ALB and Auto Scaling group. The database is managed by the caller,
# because the primary and standby regions need different kinds (primary vs.
# cross-region read replica).
#
# Uses whatever aws provider the caller passes in, so the same module builds
# us-east-1 and us-west-2 (Project 03).

module "network" {
  source = "../network"

  name               = var.name
  vpc_cidr           = var.vpc_cidr
  az_count           = 2
  enable_nat_gateway = true
  single_nat_gateway = true
}

module "web_tier" {
  source = "../web-tier"

  name               = var.name
  subnet_ids         = module.network.app_subnet_ids
  security_group_ids = [aws_security_group.app.id]
  app_port           = var.app_port
  instance_type      = var.instance_type
  min_size           = var.min_size
  max_size           = var.max_size

  vpc_id                 = module.network.vpc_id
  alb_subnet_ids         = module.network.app_subnet_ids
  alb_security_group_ids = [aws_security_group.alb.id]

  db_host       = var.db_host
  db_name       = var.db_name
  db_secret_arn = var.db_secret_arn
}
