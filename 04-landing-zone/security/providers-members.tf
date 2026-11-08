# One provider per member account and region, each assuming the org admin
# role from the management account. (Provider blocks can't use for_each.)

locals {
  member_role = { for k, id in local.accounts : k => "arn:aws:iam::${id}:role/${local.admin_role}" }
}

provider "aws" {
  alias  = "log_archive_usw2"
  region = "us-west-2"

  assume_role {
    role_arn     = local.member_role["log-archive"]
    session_name = "terraform-landing-zone"
  }

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "dev"
  region = "us-east-1"

  assume_role {
    role_arn     = local.member_role["dev"]
    session_name = "terraform-landing-zone"
  }

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "dev_usw2"
  region = "us-west-2"

  assume_role {
    role_arn     = local.member_role["dev"]
    session_name = "terraform-landing-zone"
  }

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "prod"
  region = "us-east-1"

  assume_role {
    role_arn     = local.member_role["prod"]
    session_name = "terraform-landing-zone"
  }

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "prod_usw2"
  region = "us-west-2"

  assume_role {
    role_arn     = local.member_role["prod"]
    session_name = "terraform-landing-zone"
  }

  default_tags {
    tags = local.tags
  }
}
