# One-time bootstrap: creates the S3 bucket that stores Terraform state for every
# other project. Run this once with local state, then never destroy it.
#
#   cd 00-setup/bootstrap-backend
#   terraform init
#   terraform apply -var="state_bucket_name=<globally-unique-name>"

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  description = "Region for the state bucket"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the Terraform state bucket"
  type        = string
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "portfolio-setup"
      Owner     = "bernard"
      ManagedBy = "terraform"
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "backend_block" {
  description = "Paste into each project's backend.tf (change the key per project)"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.state.bucket}"
        key          = "<project-folder>/terraform.tfstate"
        region       = "${var.region}"
        use_lockfile = true
      }
    }
  EOT
}
