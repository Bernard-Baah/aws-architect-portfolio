variable "name" {
  description = "Name prefix / DB identifier"
  type        = string
}

variable "subnet_ids" {
  description = "Private data-tier subnets, one per AZ"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS needs subnets in at least 2 AZs."
  }
}

variable "security_group_ids" {
  description = "Security groups attached to the DB instance"
  type        = list(string)
}

variable "engine_version" {
  description = "PostgreSQL major version; RDS picks the current default minor"
  type        = string
  default     = "17"
}

variable "instance_class" {
  description = "db.t4g.micro is the cheapest class that supports Multi-AZ"
  type        = string
  default     = "db.t4g.micro"
}

variable "multi_az" {
  description = "Synchronous standby in a second AZ with automatic failover. Doubles instance cost."
  type        = bool
  default     = true
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling"
  type        = number
  default     = 50
}

variable "db_name" {
  type    = string
  default = "app"
}

variable "master_username" {
  type    = string
  default = "appadmin"
}

variable "backup_retention_days" {
  description = "Automated backup retention. Some free-plan accounts only allow 1."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Keep false in the lab so terraform destroy works"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
