# Account-wide hardening in every account and both regions
# (modules/account-hardening). Each setting clears an FSBP control that failed
# 10 times in the baseline: once per account per region.

module "hardening_management" {
  source = "../../modules/account-hardening"

  providers = {
    aws.home      = aws
    aws.secondary = aws.usw2
  }
}

module "hardening_log_archive" {
  source = "../../modules/account-hardening"

  providers = {
    aws.home      = aws.log_archive
    aws.secondary = aws.log_archive_usw2
  }
}

module "hardening_audit" {
  source = "../../modules/account-hardening"

  providers = {
    aws.home      = aws.audit
    aws.secondary = aws.audit_usw2
  }
}

module "hardening_dev" {
  source = "../../modules/account-hardening"

  providers = {
    aws.home      = aws.dev
    aws.secondary = aws.dev_usw2
  }
}

module "hardening_prod" {
  source = "../../modules/account-hardening"

  providers = {
    aws.home      = aws.prod
    aws.secondary = aws.prod_usw2
  }
}
