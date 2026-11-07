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

# Every active account except Audit (the admin itself), management included.
data "aws_organizations_organization" "this" {}

locals {
  guardduty_members = {
    for a in data.aws_organizations_organization.this.accounts :
    a.id => a.email if a.status == "ACTIVE" && a.id != local.accounts["audit"]
  }
}

module "guardduty_use1" {
  source = "../../modules/org-guardduty"

  providers = {
    aws.management = aws
    aws.audit      = aws.audit
  }

  audit_account_id = local.accounts["audit"]
  members          = local.guardduty_members
}

module "guardduty_usw2" {
  source = "../../modules/org-guardduty"

  providers = {
    aws.management = aws.usw2
    aws.audit      = aws.audit_usw2
  }

  audit_account_id = local.accounts["audit"]
  members          = local.guardduty_members
}

# The management account's enrollment failed under Terraform: CreateMembers
# ran about a second after its detector was created and AWS hadn't caught up
# ("Root object was present, but now absent"). Enrolled by hand with the CLI a
# few minutes later, then adopted here. Import id = <admin detector>:<account>.
import {
  to = module.guardduty_use1.aws_guardduty_member.this["923931894420"]
  id = "4bd7d8b61f8c425daf08fbd0785ba1cb:923931894420"
}

import {
  to = module.guardduty_usw2.aws_guardduty_member.this["923931894420"]
  id = "539ad781f4db45d5a7d65fbe2f09e3b4:923931894420"
}
