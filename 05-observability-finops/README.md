# 05 · Observability & FinOps

> **Status:** 🚧 In progress (5a FinOps guardrails)

## Problem
_Know when every workload is unhealthy before users do, and prove the environment runs at the lowest sensible cost._

## Layers
| Layer | Folder | What |
|---|---|---|
| 5a | `finops/` | Cost allocation tags, budgets (org total + dev/prod), per-account Cost Anomaly Detection, all from the management account |
| 5b | `workload/` | Project 02's pipeline redeployed into **dev** through the landing zone, plus dashboard, SLOs, alarms with runbooks, X-Ray, Logs Insights queries |
| 5c | | Cross-account observability: dev's metrics, logs and traces visible from Audit |
| 5d | | Cost case study: one measured before → after change with its trade-off |

## Deploy 5a: FinOps guardrails
```bash
cd 05-observability-finops/finops
cp example.tfvars terraform.tfvars
nano terraform.tfvars
terraform init -backend-config="bucket=bernard-tfstate-40b007"
terraform apply
```
- **Cost allocation tags** `Project`, `Owner`, `ManagedBy`: every stack already sets them through provider `default_tags`; activating them lets Cost Explorer split spend by project. Not retroactive.
- **Budgets**: `org-monthly-total` ($25, forecast alerts at 50/80/100% + actual at 100%) and `workloads-dev-prod-monthly` ($10, scoped to the dev and prod accounts).
- **Cost Anomaly Detection**: a custom monitor over all 5 accounts (AWS models each account's normal spend), daily email when an anomaly's impact reaches $5.

## Observability checklist
- [ ] CloudWatch dashboard per workload (ALB, ASG, RDS, Lambda, SQS DLQ)
- [ ] SLOs defined (e.g. 99.9% success, p95 < 300 ms over 30 days)
- [ ] Composite alarms → SNS, each linked to a runbook in `docs/runbooks/`
- [ ] X-Ray tracing + Logs Insights saved queries
- [ ] Cross-account observability into the monitoring/Audit account

## FinOps checklist
- [x] Cost allocation tags activated
- [ ] One-week cost baseline per project
- [ ] Compute Optimizer / Trusted Advisor / rightsizing review
- [ ] Changes applied in Terraform (Graviton, VPC gateway endpoints, Spot, schedules, lifecycle rules)
- [x] Budgets (org + workloads), Cost Anomaly Detection per account
- [ ] Required-tag policy
- [ ] Well-Architected Tool review of one workload

## Cost case study
| Change | Before ($/mo) | After ($/mo) | Saved | Trade-off |
|--------|---------------|--------------|-------|-----------|
| _EC2/RDS → Graviton_ | | | | |
| _S3/DynamoDB gateway endpoints_ | | | | |
| _Dev schedule off nights/weekends_ | | | | |
| **Total** | | | **_%** | |
