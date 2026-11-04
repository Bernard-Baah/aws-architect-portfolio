# Lets GitHub Actions sign in to AWS with short-lived credentials (OIDC) instead of
# stored access keys. Only the listed repo + branches/events can assume the role.

locals {
  github_oidc_url = "token.actions.githubusercontent.com"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_url}"
  client_id_list = ["sts.amazonaws.com"]

  # AWS validates GitHub's certificate through its own trusted CA library, so these
  # values are not used for validation, but older provider versions require them.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.github_oidc_url}"
}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Pin to this repo only. Without this condition ANY GitHub repo could assume the role.
    condition {
      test     = "StringLike"
      variable = "${local.github_oidc_url}:sub"
      values   = [for s in var.allowed_subjects : "repo:${var.github_repo}:${s}"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = var.role_name
  description          = "Assumed by GitHub Actions in ${var.github_repo} to run terraform plan"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration
}

# Read-only view of the account, enough for terraform plan to refresh state.
resource "aws_iam_role_policy_attachment" "read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Plan also needs to read state and write/delete its S3 lock file.
data "aws_iam_policy_document" "state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}"]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}/*"]
  }

  statement {
    sid       = "ManageLockFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "state" {
  name   = "terraform-state-access"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state.json
}
