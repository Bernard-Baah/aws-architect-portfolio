variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "alb_arn" {
  description = "Internal ALB that CloudFront reaches through a VPC origin"
  type        = string
}

variable "alb_dns_name" {
  type = string
}

variable "enable_failover" {
  description = <<-EOT
    Add a standby origin (secondary_alb_*) and fail over to it on 5xx or timeouts.
    An explicit flag, not "is secondary_alb_arn set?": the ARN isn't known until
    apply, and count must be known at plan time.
  EOT
  type        = bool
  default     = false
}

variable "secondary_alb_arn" {
  description = "Standby ALB (another region); required when enable_failover = true"
  type        = string
  default     = null
}

variable "secondary_alb_dns_name" {
  type    = string
  default = null
}

variable "price_class" {
  description = "PriceClass_100 = North America + Europe edge locations (cheapest)"
  type        = string
  default     = "PriceClass_100"
}

variable "rate_limit_per_5min" {
  description = "Requests per client IP per 5 minutes before WAF blocks it"
  type        = number
  default     = 500
}

variable "tags" {
  type    = map(string)
  default = {}
}
