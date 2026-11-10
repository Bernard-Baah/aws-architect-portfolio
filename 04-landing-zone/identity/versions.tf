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
    key          = "04-landing-zone/identity/terraform.tfstate"
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

# Identity Center lives in the management account, in its home region.
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "landing-zone"
      Owner     = "bernard"
      ManagedBy = "terraform"
    }
  }
}
