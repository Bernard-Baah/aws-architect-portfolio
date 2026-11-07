# GuardDuty in every account, in both allowed regions, with findings
# centralized in the Audit account. The region allow-list SCP blocks every
# other region, so there's nothing to watch there.

provider "aws" {
  alias  = "usw2"
  region = "us-west-2"

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "audit"
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::${local.accounts["audit"]}:role/${local.admin_role}"
    session_name = "terraform-landing-zone"
  }

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "audit_usw2"
  region = "us-west-2"

  assume_role {
    role_arn     = "arn:aws:iam::${local.accounts["audit"]}:role/${local.admin_role}"
    session_name = "terraform-landing-zone"
  }

  default_tags {
    tags = local.tags
  }
}

module "guardduty_use1" {
  source = "../../modules/org-guardduty"

  providers = {
    aws.management = aws
    aws.audit      = aws.audit
  }

  audit_account_id = local.accounts["audit"]
}

module "guardduty_usw2" {
  source = "../../modules/org-guardduty"

  providers = {
    aws.management = aws.usw2
    aws.audit      = aws.audit_usw2
  }

  audit_account_id = local.accounts["audit"]
}
