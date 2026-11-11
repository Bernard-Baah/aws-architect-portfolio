terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }

  # Partial config: pass the bucket at init time.
  #   terraform init -backend-config="bucket=bernard-tfstate-40b007"
  backend "s3" {
    key          = "05-observability-finops/finops/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

# Account IDs from the landing zone (Project 04, layer 1).
data "terraform_remote_state" "org" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = "04-landing-zone/organization/terraform.tfstate"
    region = "us-east-1"
  }
}

# Billing, Budgets and Cost Explorer for the whole organization live in the
# management account (consolidated billing).
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "observability-finops"
      Owner     = "bernard"
      ManagedBy = "terraform"
    }
  }
}
