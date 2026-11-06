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
