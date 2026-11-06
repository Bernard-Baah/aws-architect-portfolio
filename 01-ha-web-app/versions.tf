terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial config: pass the bucket at init time.
  #   terraform init -backend-config="bucket=bernard-tfstate-40b007"
  backend "s3" {
    key          = "01-ha-web-app/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "ha-web-app"
      Owner     = "bernard"
      ManagedBy = "terraform"
    }
  }
}

# CloudFront-scoped WAF resources must be created in us-east-1, even when this
# stack is deployed to another region (Project 03).
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "ha-web-app"
      Owner     = "bernard"
      ManagedBy = "terraform"
    }
  }
}
