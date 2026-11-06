variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "subnet_ids" {
  description = "Private app-tier subnets (one per AZ) the Auto Scaling group spreads across"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for the instances"
  type        = list(string)
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "instance_type" {
  description = "Graviton (arm64) instance type"
  type        = string
  default     = "t4g.micro"
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "cpu_target_percent" {
  description = "Target tracking: add instances when average CPU goes above this"
  type        = number
  default     = 60
}

variable "vpc_id" {
  type = string
}

variable "alb_subnet_ids" {
  description = "Subnets (one per AZ) for the internal load balancer"
  type        = list(string)
}

variable "alb_security_group_ids" {
  description = "Security groups for the load balancer"
  type        = list(string)
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_secret_arn" {
  description = "Secrets Manager secret with DB credentials. The instance role can read only this secret."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
