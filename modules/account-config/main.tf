# AWS Config baseline for one account: Config's service-linked role plus a
# daily recorder and delivery channel in its home and secondary region.
#
# Built in Terraform rather than a CloudFormation StackSet on purpose: CFN's
# AWS::Config::ConfigurationRecorder starts recording as soon as it's created,
# which needs a delivery channel, and a delivery channel needs a recorder. The
# stack deadlocks ("did not stabilize"). Terraform creates the recorder
# stopped, adds the channel, then starts it (see modules/config-recorder).

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.home, aws.secondary]
    }
  }
}

variable "delivery_bucket" {
  description = "Central Config bucket (in Log Archive)"
  type        = string
}

# Security Hub Config.1 (critical) requires the recorder to use AWS Config's
# service-linked role. Config then delivers to the central bucket as the
# config.amazonaws.com service principal, which the bucket policy trusts for
# this organization (aws:SourceOrgID).
resource "aws_iam_service_linked_role" "config" {
  provider = aws.home

  aws_service_name = "config.amazonaws.com"
}

# Global resources (IAM) are recorded in the home region only.
module "home" {
  source = "../config-recorder"

  providers = {
    aws = aws.home
  }

  role_arn        = aws_iam_service_linked_role.config.arn
  delivery_bucket = var.delivery_bucket
  include_global  = true
}

module "secondary" {
  source = "../config-recorder"

  providers = {
    aws = aws.secondary
  }

  role_arn        = aws_iam_service_linked_role.config.arn
  delivery_bucket = var.delivery_bucket
  include_global  = false
}
