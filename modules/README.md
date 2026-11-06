# Shared Terraform modules

Reusable modules consumed by the project folders. Planned:

- `network/` ✅: VPC, tiered subnets across AZs, NAT, Flow Logs (Project 01, reused in 03)
- `web-tier/` 🚧: launch template, Auto Scaling group, instance role, app (Project 01, reused in 03). ALB comes next.
- `database/` ✅: RDS PostgreSQL Multi-AZ, encrypted gp3, Secrets Manager-managed credentials (Project 01, replica in 03)
- `github-oidc/` ✅: GitHub Actions OIDC provider + read-only plan role (Project 00, per account in 04)
