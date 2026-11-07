variable "name" {
  description = "Base name; each region appends its own short code"
  type        = string
  default     = "ha-dr"
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "secondary_region" {
  type    = string
  default = "us-west-2"
}

variable "standby_min_size" {
  description = "Warm standby: instances kept running in the secondary region. Scale up during failover."
  type        = number
  default     = 1
}

variable "primary_db_multi_az" {
  description = "Multi-AZ on the primary DB (Project 01 tested this). Off by default here to keep the two-region lab cheaper."
  type        = bool
  default     = false
}

variable "db_password_version" {
  description = "Bump to rotate the DB password: Terraform generates a new one and writes it to RDS and Secrets Manager."
  type        = number
  default     = 1
}
