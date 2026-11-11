variable "state_bucket_name" {
  description = "Terraform state bucket (holds layer 1's outputs)"
  type        = string
  default     = "bernard-tfstate-40b007"
}

variable "trail_name" {
  description = "Name of the organization trail"
  type        = string
  default     = "org-trail"
}

variable "log_lock_days" {
  description = "Object Lock (governance mode) retention for trail logs. Kept short for a lab; real orgs use 1-7 years."
  type        = number
  default     = 7
}

variable "log_expire_days" {
  description = "Delete trail logs after this many days"
  type        = number
  default     = 365
}

variable "trail_log_retention_days" {
  description = "How long the CloudWatch Logs copy of trail events is kept (S3 keeps the long-term copy)"
  type        = number
  default     = 90
}

# Cost switches. Security Hub CSPM (billed per check) and AWS Config (billed
# per configuration item and per rule evaluation, and Security Hub's checks run
# as Config rules) together cost ~$30/month across 5 accounts x 2 regions after
# the trial. Measured scores are in the README; turn back on for a new reading.
variable "security_hub_enabled" {
  description = "Security Hub CSPM in every account (false = central policy disables it everywhere)"
  type        = bool
  default     = false
}

variable "config_enabled" {
  description = "AWS Config recorders in every account and both regions"
  type        = bool
  default     = false
}
