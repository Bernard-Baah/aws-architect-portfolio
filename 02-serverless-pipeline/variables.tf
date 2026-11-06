variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "inventory-pipeline"
}

variable "notification_email" {
  description = "Optional email for completion and DLQ alerts (AWS sends a confirmation link)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 14
}
