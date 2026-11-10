variable "state_bucket_name" {
  description = "Terraform state bucket (holds layer 1's outputs)"
  type        = string
  default     = "bernard-tfstate-40b007"
}

# Personal details: set in a gitignored terraform.tfvars (see example.tfvars).
variable "admin_user" {
  description = "The human who signs in through Identity Center"
  type = object({
    user_name   = string
    given_name  = string
    family_name = string
    email       = string
  })
  sensitive = true
}
