variable "name" {
  description = "Name prefix for every resource (e.g. ha-web-app)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Subnets are carved out as /24s."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR of /20 or larger."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 for high availability."
  }
}

variable "enable_nat_gateway" {
  description = "Give app subnets outbound internet through NAT. NAT Gateways bill hourly (~$0.045/hr each in us-east-1)."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (cheap, single-AZ dependency). false = one NAT per AZ (production HA)."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "How long VPC Flow Logs stay in CloudWatch Logs"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Extra tags added to every resource"
  type        = map(string)
  default     = {}
}
