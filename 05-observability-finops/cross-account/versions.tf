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
    key          = "05-observability-finops/cross-account/terraform.tfstate"
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

locals {
  org      = data.terraform_remote_state.org.outputs
  accounts = local.org.account_ids

  tags = {
    Project   = "observability-finops"
    Owner     = "bernard"
    ManagedBy = "terraform"
  }
}

# Monitoring account: Audit already holds GuardDuty and Security Hub, so it
# becomes the one place to look at telemetry too.
provider "aws" {
  alias  = "audit"
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::${local.accounts["audit"]}:role/${local.org.admin_role_name}"
    session_name = "terraform-observability"
  }

  default_tags {
    tags = local.tags
  }
}

# Source account: where the workload runs.
provider "aws" {
  alias  = "dev"
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::${local.accounts["dev"]}:role/${local.org.admin_role_name}"
    session_name = "terraform-observability"
  }

  default_tags {
    tags = local.tags
  }
}
