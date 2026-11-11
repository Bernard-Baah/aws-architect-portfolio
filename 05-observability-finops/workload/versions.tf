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
    key          = "05-observability-finops/workload/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

data "terraform_remote_state" "org" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = "04-landing-zone/organization/terraform.tfstate"
    region = "us-east-1"
  }
}

# The Project 02 pipeline as deployed into dev (its "dev" workspace).
data "terraform_remote_state" "pipeline" {
  backend   = "s3"
  workspace = "dev"

  config = {
    bucket = var.state_bucket_name
    key    = "02-serverless-pipeline/terraform.tfstate"
    region = "us-east-1"
  }
}

# Everything here lives next to the workload, in the dev account.
provider "aws" {
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::${data.terraform_remote_state.org.outputs.account_ids["dev"]}:role/${data.terraform_remote_state.org.outputs.admin_role_name}"
    session_name = "terraform-observability"
  }

  default_tags {
    tags = {
      Project   = "observability-finops"
      Owner     = "bernard"
      ManagedBy = "terraform"
    }
  }
}
