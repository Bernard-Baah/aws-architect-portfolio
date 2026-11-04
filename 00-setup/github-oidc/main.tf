# Deploys the GitHub Actions OIDC provider + plan role into the portfolio account.
#
#   cd 00-setup/github-oidc
#   terraform init -backend-config="bucket=<your-state-bucket>"
#   terraform apply -var="state_bucket_name=<your-state-bucket>"
#
# Then copy the role_arn output into GitHub:
#   Settings → Secrets and variables → Actions → Variables → New: AWS_ROLE_ARN

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial config: the bucket name is passed at init time so it isn't hard-coded.
  backend "s3" {
    key          = "00-setup/github-oidc/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

variable "state_bucket_name" {
  description = "Name of the bucket created by 00-setup/bootstrap-backend"
  type        = string
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "portfolio-setup"
      Owner     = "bernard"
      ManagedBy = "terraform"
    }
  }
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  github_repo       = "Bernard-Baah/aws-architect-portfolio"
  state_bucket_name = var.state_bucket_name

  # Repo created 2026-11-04, so GitHub uses the immutable sub format:
  # repo:Bernard-Baah@78100467/aws-architect-portfolio@1445806520:...
  github_owner_id = 78100467
  github_repo_id  = 1445806520
}

output "role_arn" {
  description = "Paste into the AWS_ROLE_ARN repository variable"
  value       = module.github_oidc.role_arn
}

output "allowed_subjects" {
  value = module.github_oidc.allowed_subjects
}
