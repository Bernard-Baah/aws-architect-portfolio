# Project 01: highly available multi-tier web app.
# Built up in layers, one pull request each:
#   1. network   (this PR)  VPC, subnets, NAT, routing, flow logs
#   2. security groups + RDS Multi-AZ
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
