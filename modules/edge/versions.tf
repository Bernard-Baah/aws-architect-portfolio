terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"

      # WAF web ACLs for CloudFront must live in us-east-1, whatever region the
      # rest of the stack is in (Project 03 deploys a second copy in us-west-2).
      configuration_aliases = [aws.us_east_1]
    }
  }
}
