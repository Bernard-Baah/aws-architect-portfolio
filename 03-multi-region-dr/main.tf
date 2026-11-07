# Project 03: warm-standby disaster recovery for the Project 01 app.
#
#   viewer -> CloudFront (+ WAF) -> origin group -> primary ALB  (us-east-1, 2 instances)
#                                              \-> standby ALB  (us-west-2, 1 instance)
#   primary RDS (us-east-1) --async replication--> read replica (us-west-2)
#   DB secret (us-east-1) --replicated--> us-west-2
#
# CloudFront fails each request over to the standby when the primary returns
# 5xx or can't be reached, so no DNS change or domain is needed. The standby
# app serves reads from its local replica straight away; promoting the replica
# (scripts/promote-standby.sh) makes it writable.

module "primary" {
  source = "../modules/app-region"

  # db_secret_arn comes from the secret *version* (same ARN as the secret), so
  # instances wait until the secret holds a value, without a module-wide depends_on.
  name          = "${var.name}-use1"
  vpc_cidr      = "10.0.0.0/16"
  min_size      = 2
  db_host       = aws_db_instance.primary.address
  db_secret_arn = aws_secretsmanager_secret_version.db.arn
}

module "secondary" {
  source = "../modules/app-region"

  providers = {
    aws = aws.secondary
  }

  name          = "${var.name}-usw2"
  vpc_cidr      = "10.1.0.0/16"
  min_size      = var.standby_min_size
  db_host       = aws_db_instance.replica.address
  db_secret_arn = local.db_secret_arn_secondary
}

module "edge" {
  source = "../modules/edge"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name                   = var.name
  alb_arn                = module.primary.alb_arn
  alb_dns_name           = module.primary.alb_dns_name
  secondary_alb_arn      = module.secondary.alb_arn
  secondary_alb_dns_name = module.secondary.alb_dns_name
}
