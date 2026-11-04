variable "github_repo" {
  description = "Repository allowed to assume the role, as owner/name (e.g. Bernard-Baah/aws-architect-portfolio)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo must look like owner/name."
  }
}

variable "github_owner_id" {
  description = <<-EOT
    Numeric ID of the repo owner. Repos created (or renamed/transferred) after
    2026-07-15, or opted in, use GitHub's immutable subject format
    repo:<owner>@<owner_id>/<repo>@<repo_id>:... and need both IDs set.
    Find them with: gh api repos/<owner>/<repo> --jq '{owner_id: .owner.id, repo_id: .id}'
  EOT
  type        = number
  default     = null
}

variable "github_repo_id" {
  description = "Numeric ID of the repository (see github_owner_id). Set both or neither."
  type        = number
  default     = null
}

variable "role_name" {
  description = "Name of the IAM role GitHub Actions assumes"
  type        = string
  default     = "github-actions-terraform-plan"
}

variable "state_bucket_name" {
  description = "Terraform remote-state bucket the role may read and lock"
  type        = string
}

variable "allowed_subjects" {
  description = "OIDC 'sub' patterns (relative to repo:<github_repo>:) allowed to assume the role"
  type        = list(string)
  default = [
    "ref:refs/heads/main", # pushes to main
    "pull_request",        # any pull request in this repo
  ]
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one."
  type        = bool
  default     = true
}

variable "max_session_duration" {
  description = "Maximum role session length in seconds"
  type        = number
  default     = 3600
}
