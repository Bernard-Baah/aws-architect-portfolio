terraform {
  # Write-only attributes (password_wo, secret_string_wo) need Terraform 1.11+.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7" # ephemeral random_password
    }
  }

  # Partial config: pass the bucket at init time.
  #   terraform init -backend-config="bucket=bernard-tfstate-40b007"
  backend "s3" {
    key          = "03-multi-region-dr/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

locals {
  tags = {
    Project   = "multi-region-dr"
    Owner     = "bernard"
    ManagedBy = "terraform"
  }
}

# Primary region
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.tags
  }
}

# Warm standby region
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = local.tags
  }
}

# CloudFront-scoped WAF must be created in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}
