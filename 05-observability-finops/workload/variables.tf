variable "state_bucket_name" {
  description = "Terraform state bucket"
  type        = string
  default     = "bernard-tfstate-40b007"
}

variable "name" {
  description = "Name prefix the Project 02 pipeline was deployed with"
  type        = string
  default     = "inventory-pipeline"
}

# Personal: set in a gitignored terraform.tfvars (see example.tfvars).
variable "alert_email" {
  description = "Who gets paged by the composite alarm (AWS sends a confirmation link)"
  type        = string
  sensitive   = true
}

variable "runbook_base_url" {
  description = "Alarm descriptions link here"
  type        = string
  default     = "https://github.com/Bernard-Baah/aws-architect-portfolio/blob/main/docs/runbooks"
}

# ---------- SLO targets ----------
variable "slo_api_availability_pct" {
  description = "API: share of requests without a 5xx, over 30 days"
  type        = number
  default     = 99.9
}

variable "slo_api_p95_ms" {
  description = "API: p95 latency target in milliseconds"
  type        = number
  default     = 1000
}

variable "slo_pipeline_p95_seconds" {
  description = "Pipeline freshness: p95 time from upload event to result stored"
  type        = number
  default     = 60
}
