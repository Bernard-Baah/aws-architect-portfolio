variable "state_bucket_name" {
  description = "Terraform state bucket (holds the landing zone's outputs)"
  type        = string
  default     = "bernard-tfstate-40b007"
}

# Personal: set in a gitignored terraform.tfvars (see example.tfvars).
variable "alert_email" {
  description = "Where budget and anomaly alerts go"
  type        = string
  sensitive   = true
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget for the whole organization"
  type        = number
  default     = 25
}

variable "workloads_budget_usd" {
  description = "Monthly cost budget for the dev + prod accounts"
  type        = number
  default     = 10
}

variable "anomaly_threshold_usd" {
  description = "Alert when an anomaly's total cost impact reaches this many dollars"
  type        = number
  default     = 5
}

variable "cost_allocation_tags" {
  description = "Tag keys every project already sets; activating them makes Cost Explorer group by them"
  type        = list(string)
  default     = ["Project", "Owner", "ManagedBy"]
}
