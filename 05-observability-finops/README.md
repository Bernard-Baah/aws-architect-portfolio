# 05 · Observability & FinOps

> **Status:** ⏳ Planned

## Problem
_Know when every workload is unhealthy before users do, and prove the environment runs at the lowest sensible cost._

## Observability checklist
- [ ] CloudWatch dashboard per workload (ALB, ASG, RDS, Lambda, SQS DLQ)
- [ ] SLOs defined (e.g. 99.9% success, p95 < 300 ms over 30 days)
- [ ] Composite alarms → SNS, each linked to a runbook in `docs/runbooks/`
- [ ] X-Ray tracing + Logs Insights saved queries
- [ ] Cross-account observability into the monitoring/Audit account

## FinOps checklist
- [ ] Cost allocation tags activated; one-week baseline per project
- [ ] Compute Optimizer / Trusted Advisor / rightsizing review
- [ ] Changes applied in Terraform (Graviton, VPC gateway endpoints, Spot, schedules, lifecycle rules)
- [ ] Budgets per account, Cost Anomaly Detection, required-tag policy
- [ ] Well-Architected Tool review of one workload

## Cost case study
| Change | Before ($/mo) | After ($/mo) | Saved | Trade-off |
|--------|---------------|--------------|-------|-----------|
| _EC2/RDS → Graviton_ | | | | |
| _S3/DynamoDB gateway endpoints_ | | | | |
| _Dev schedule off nights/weekends_ | | | | |
| **Total** | | | **_%** | |
