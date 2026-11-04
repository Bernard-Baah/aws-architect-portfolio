variable "region" {
  description = "Region to deploy into (Project 03 deploys this same stack to a second region)"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "ha-web-app"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Set false to skip the NAT Gateway (~$1.08/day) when you only need the network"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "One shared NAT for the lab. Set false for one NAT per AZ (production pattern)."
  type        = bool
  default     = true
}
