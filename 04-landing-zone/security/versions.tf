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
    key          = "04-landing-zone/security/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

# Account IDs come from layer 1, which already ran, so they're known at plan
# time and the providers below can assume roles in those accounts.
data "terraform_remote_state" "org" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = "04-landing-zone/organization/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  org        = data.terraform_remote_state.org.outputs
  accounts   = local.org.account_ids
  admin_role = local.org.admin_role_name

  tags = {
    Project   = "landing-zone"
    Owner     = "bernard"
    ManagedBy = "terraform"
  }
}

# Management account: the organization trail lives here.
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

# Log Archive account: the bucket and KMS key the trail writes to.
provider "aws" {
  alias  = "log_archive"
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::${local.accounts["log-archive"]}:role/${local.admin_role}"
    session_name = "terraform-landing-zone"
  }

  default_tags {
    tags = local.tags
  }
}
