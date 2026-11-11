# 05 · Observability & FinOps

> **Status:** 🚧 In progress (5a and 5b deployed + game day; 5c/5d next)

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
| System errors | none | Lambda errors that aren't bad input (log metric filter excludes `ValidationError`), timeouts/aborts |

- **Bad input is not an incident.** A rejected file ends its execution as `FAILED` and goes to the DLQ by design, so `ExecutionsFailed`, DLQ depth and `ValidationError` are not paged on; the dashboard still shows them.
- **Found on day one:** the first version also paged on the DLQ alarm, and the sample run's `not-a-csv.txt` set the composite to ALARM. A log metric filter now counts only validate's *non*-validation errors, and the DLQ became information.
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

## Game day: a bad IAM change (2026-11-11)
Removed the `read-uploads` permission from the analyze function's role (simulating a bad manual change), then uploaded a **valid** file.

| Time (ET) | Event |
|---|---|
| 12:57:58 | Fault injected; valid file uploaded |
| 12:59:55 | `system-lambda-errors` → ALARM; composite `inventory-pipeline-unhealthy` emails (**~2 min to detect**) |
| ~13:10 | Runbook: saved Logs Insights query `lambda-errors` shows `AccessDenied` on `s3:GetObject` |
| **13:14:55** | Composite emails **OK**, while the permission was still missing |
| ~13:20 | `terraform plan` detects the drift (1 to add); `apply` restores the policy |
| ~13:23 | `redrive-dlq.sh` replays the failed upload (classified `retryable (AccessDenied)`) |
| 13:29 | File confirmed `COMPLETE` (10 rows, 2 racks): **no data lost** |

**What worked:** one page for one incident, sent in ~2 minutes; the email named the failing child alarm and linked the runbook; bad-input alarms stayed quiet; the DLQ held the failed upload until the fix; Terraform found and repaired the drift; replay finished the work.

**What the game day taught:**
- **"Alarm OK" ≠ recovered.** Error alarms count errors per 5-minute window. With no new traffic, the window went quiet and the composite cleared ~8 minutes **before** the fix. On a low-traffic system, recovery is proven by a successful run (replay + `COMPLETE` in DynamoDB), not by the alarm. The runbook now says so. A synthetic canary (a scheduled known-good upload) would close this gap.
- **The DLQ dry run over-reported.** With visibility 0, SQS returned one message 10 times in a batch and could miss others; fixed by de-duplicating on `MessageId` and sampling until nothing new appears.

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
