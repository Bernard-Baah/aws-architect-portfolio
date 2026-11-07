# Service control policies cap what any principal in a member account can do,
# admins included. They never apply to the management account, which is why
# nothing runs there except Organizations, billing and Terraform state.
#
# Both policies attach at the root, so every OU and account inherits them.
# AWS's default FullAWSAccess policy stays attached alongside; these only deny.

locals {
  exempt_role_arn = "arn:aws:iam::*:role/${var.scp_exempt_role}"
}

resource "aws_organizations_policy" "guardrails" {
  name        = "guardrails"
  description = "Stay in the org, keep the security baseline on, no root user"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyLeavingOrg"
        Effect   = "Deny"
        Action   = "organizations:LeaveOrganization"
        Resource = "*"
      },
      {
        Sid    = "ProtectSecurityBaseline"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder",
          "guardduty:DeleteDetector",
          "guardduty:DeleteMembers",
          "guardduty:DisassociateFromAdministratorAccount",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:DisassociateMembers",
          "guardduty:StopMonitoringMembers",
          "guardduty:UpdateDetector",
          "securityhub:DeleteMembers",
          "securityhub:DisableSecurityHub",
          "securityhub:DisassociateFromAdministratorAccount",
          "securityhub:DisassociateFromMasterAccount",
          "securityhub:DisassociateMembers",
        ]
        Resource = "*"
        Condition = {
          ArnNotLike = { "aws:PrincipalARN" = local.exempt_role_arn }
        }
      },
      {
        Sid      = "DenyRootUser"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringLike = { "aws:PrincipalArn" = "arn:aws:iam::*:root" }
        }
      },
    ]
  })
}

resource "aws_organizations_policy" "region_allowlist" {
  name        = "region-allowlist"
  description = "Deny regional services outside ${join(", ", var.allowed_regions)}"
  type        = "SERVICE_CONTROL_POLICY"

  # Global services are listed in NotAction because their API endpoints live
  # in us-east-1 regardless of where you call from (IAM, CloudFront, Route 53,
  # Organizations, billing, support). Based on AWS's published example.
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyOutsideAllowedRegions"
        Effect = "Deny"
        NotAction = [
          "account:*",
          "acm:*",
          "aws-marketplace:*",
          "aws-portal:*",
          "billing:*",
          "budgets:*",
          "ce:*",
          "cloudfront:*",
          "cur:*",
          "ec2:DescribeRegions",
          "globalaccelerator:*",
          "health:*",
          "iam:*",
          "kms:*",
          "networkmanager:*",
          "organizations:*",
          "pricing:*",
          "route53:*",
          "route53domains:*",
          "s3:GetAccountPublic*",
          "s3:ListAllMyBuckets",
          "s3:PutAccountPublic*",
          "shield:*",
          "sso:*",
          "sts:*",
          "support:*",
          "trustedadvisor:*",
          "waf:*",
          "wafv2:*",
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = { "aws:RequestedRegion" = var.allowed_regions }
        }
      },
    ]
  })
}

resource "aws_organizations_policy_attachment" "root" {
  for_each = {
    guardrails       = aws_organizations_policy.guardrails.id
    region_allowlist = aws_organizations_policy.region_allowlist.id
  }

  policy_id = each.value
  target_id = local.root_id
}
