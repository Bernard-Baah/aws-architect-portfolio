# Shared Terraform modules

Reusable modules consumed by the project folders. Planned:

- `network/` ✅: VPC, tiered subnets across AZs, NAT, Flow Logs (Project 01, reused in 03)
- `web-tier/` ✅: ALB + target group, launch template, Auto Scaling group, instance role, app (Project 01, reused in 03)
- `database/` ✅: RDS PostgreSQL Multi-AZ, encrypted gp3, Secrets Manager-managed credentials (Project 01, replica in 03)
- `github-oidc/` ✅: GitHub Actions OIDC provider + read-only plan role (Project 00, per account in 04)
- `edge/` ✅: CloudFront VPC origin to an internal ALB (optional second-region origin group for failover), distribution with managed cache/security-header policies, AWS WAF (rate limit + 3 AWS managed rule groups) in us-east-1 (Project 01, reused in 03)
- `app-region/` ✅: one region's app tier (network + security group chain + web tier), instantiated per region by Project 03
- `org-guardduty/` ✅: GuardDuty for a whole organization in one region, delegated to a security account with auto-enable for every member (Project 04, once per allowed region)
- `config-recorder/` ✅: AWS Config recorder (daily) + delivery channel for one account and region (used by `account-config`)
- `account-config/` ✅: Config baseline for one account: recorder role + recorders in home and secondary region (Project 04, once per account)
