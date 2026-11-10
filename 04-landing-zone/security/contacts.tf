# Security Hub Account.1: every account needs a security alternate contact,
# the person AWS contacts about security issues in that account. Set from the
# management account through Organizations (trusted access for
# account.amazonaws.com was enabled in layer 1).
#
# The contact details are personal, so they live in a gitignored
# terraform.tfvars (see example.tfvars), never in the repo.

variable "security_contact" {
  description = "Security contact for every account: name, title, email, phone (E.164, e.g. +15555550100)"
  type = object({
    name  = string
    title = string
    email = string
    phone = string
  })
  sensitive = true
}

# Member accounts: set from management by account ID.
resource "aws_account_alternate_contact" "security" {
  for_each = local.accounts

  account_id             = each.value
  alternate_contact_type = "SECURITY"
  name                   = var.security_contact.name
  title                  = var.security_contact.title
  email_address          = var.security_contact.email
  phone_number           = var.security_contact.phone
}

# Management account: the API takes no account ID for the caller's own account.
resource "aws_account_alternate_contact" "security_management" {
  alternate_contact_type = "SECURITY"
  name                   = var.security_contact.name
  title                  = var.security_contact.title
  email_address          = var.security_contact.email
  phone_number           = var.security_contact.phone
}
