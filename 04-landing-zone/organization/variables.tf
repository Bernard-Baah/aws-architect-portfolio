# Mailbox for every member account. Each account gets a plus-address
# (you+lz-dev@gmail.com) that Gmail delivers to the same inbox. Kept out of the
# public repo: set it in a gitignored terraform.tfvars locally and in the
# LZ_EMAIL_BASE repository secret for CI (secrets are masked in logs).
variable "email_base" {
  description = "Plain mailbox address, e.g. you@gmail.com"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@+[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.email_base))
    error_message = "email_base must be a plain address like you@gmail.com (no + part)."
  }
}

variable "account_prefix" {
  description = "Prefix for member account names and email plus-tags"
  type        = string
  default     = "lz"
}

variable "allowed_regions" {
  description = "Regions member accounts may use (Projects 01-03 used these two)"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

# Terraform reaches member accounts through this role, so it may still change
# the security baseline (CloudTrail, GuardDuty, Config, Security Hub) and
# teardown keeps working. Every other principal is denied by the SCP.
variable "scp_exempt_role" {
  description = "Admin role created in each member account and exempt from the baseline-protection SCP"
  type        = string
  default     = "OrganizationAccountAccessRole"
}
