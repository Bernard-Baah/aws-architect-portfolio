# Shared Terraform modules

Reusable modules consumed by the project folders. Planned:

- `network/` ✅: VPC, tiered subnets across AZs, NAT, Flow Logs (Project 01, reused in 03)
- `web-tier/` ✅: ALB + target group, launch template, Auto Scaling group, instance role, app (Project 01, reused in 03)
- `database/` ✅: RDS PostgreSQL Multi-AZ, encrypted gp3, Secrets Manager-managed credentials (Project 01, replica in 03)
- `github-oidc/` ✅: GitHub Actions OIDC provider + read-only plan role (Project 00, per account in 04)
- `edge/` ✅: CloudFront VPC origin to an internal ALB, distribution with managed cache/security-header policies, AWS WAF (rate limit + 3 AWS managed rule groups) in us-east-1 (Project 01, reused in 03)
