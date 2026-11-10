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
