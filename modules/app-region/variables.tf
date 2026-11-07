variable "name" {
  description = "Name prefix, unique per region (IAM role names are global)"
  type        = string
}

variable "vpc_cidr" {
  description = "Use non-overlapping ranges per region so the VPCs could be peered later"
  type        = string
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "instance_type" {
  type    = string
  default = "t4g.micro"
}

variable "min_size" {
  description = "Primary: 2 (one per AZ). Warm standby: 1."
  type        = number
}

variable "max_size" {
  type    = number
  default = 4
}

variable "db_host" {
  description = "Database this region's app connects to (primary, or the local read replica)"
  type        = string
}

variable "db_name" {
  type    = string
  default = "app"
}

variable "db_secret_arn" {
  description = "Secret in this region holding the DB credentials"
  type        = string
}
