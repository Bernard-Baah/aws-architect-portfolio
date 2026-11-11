# 05 · Observability & FinOps

> **Status:** 🚧 In progress (5a deployed; 5b observability)

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

## Deploy 5b: the workload and its observability
Project 02's pipeline runs in the landing zone's **dev** account, from the same code (`assume_role_arn` + a `dev` workspace; see Project 02's README). `workload/` builds the observability next to it, in dev:

| SLI | SLO | Alarm (5-min windows) |
|---|---|---|
| API availability (non-5xx share) | 99.9% over 30 days | 5xx rate > 1% in 2 of 3 windows |
| API latency | p95 < 1,000 ms | p95 above target for 15 min |
| Pipeline freshness (upload → result stored) | p95 < 60 s | p95 above target for 15 min |
| System errors | none | analyze/API Lambda errors, timeouts/aborts, DLQ not empty |

- **Bad input is not an incident.** A rejected file ends its execution as `FAILED` by design, so `ExecutionsFailed` and the validate function's errors are not paged on; the dashboard still shows them.
- **One page per incident.** Child alarms have no actions; a composite alarm ORs them and is the only thing that emails. Every alarm description links to its section of [`docs/runbooks/pipeline-unhealthy.md`](../docs/runbooks/pipeline-unhealthy.md).
- **Dashboard** `inventory-pipeline-slo`: SLO numbers, latency percentiles against the targets, executions split into succeeded / rejected / stuck, errors and throttles, a live Lambda-errors log table.
- **Saved Logs Insights queries**: lambda-errors, slowest-invocations, cold-starts, api-non-2xx, failed-executions. X-Ray tracing was already on in Project 02.

```bash
cd 05-observability-finops/workload
cp example.tfvars terraform.tfvars
nano terraform.tfvars
terraform init -backend-config="bucket=bernard-tfstate-40b007"
terraform apply
```

## Observability checklist
- [x] CloudWatch dashboard for the pipeline (API, Step Functions, Lambda, SQS DLQ)
- [x] SLOs defined (API 99.9% non-5xx, API p95 < 1 s, upload→result p95 < 60 s)
- [x] Composite alarm → SNS, every alarm linked to a runbook section in `docs/runbooks/`
- [x] X-Ray tracing + Logs Insights saved queries
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
