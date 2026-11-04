# 01 · Highly available multi-tier web app

> **Status:** ⏳ Planned

## Problem
_A business-critical app must survive the loss of an Availability Zone with no manual intervention._

## Architecture
Route 53 → CloudFront (+ WAF) → ALB (public subnets, 2 AZs) → EC2 Auto Scaling group
(private app subnets) → RDS PostgreSQL Multi-AZ (private data subnets). Static assets in S3
via Origin Access Control. Secrets in Secrets Manager. No SSH; access through SSM Session Manager.

_Diagram: `docs/diagrams/01-ha-web-app.png`_

## Build checklist
- [ ] Network module: VPC, 6 subnets across 2 AZs, IGW, NAT, route tables, Flow Logs
- [ ] Security groups chained ALB → app → DB
- [ ] RDS Multi-AZ + Secrets Manager
- [ ] Launch template, instance profile, ASG (min 2 / max 4, target tracking 60% CPU)
- [ ] ALB + ACM cert + HTTP→HTTPS redirect, health checks on `/health`
- [ ] CloudFront + S3 origin + WAF managed rules
- [ ] Failure tests: terminate instances, force RDS failover, load test

## Design decisions & trade-offs
- _One vs. one-NAT-per-AZ_
- _EC2 vs. ECS Fargate_
- _RDS vs. Aurora_

## Results
| Test | Measured |
|------|----------|
| Instance termination → replaced | _ min |
| RDS forced failover downtime | _ s |
| Scale-out under load | _ → _ instances |

## Deploy / destroy
```bash
terraform -chdir=01-ha-web-app init
terraform -chdir=01-ha-web-app apply
terraform -chdir=01-ha-web-app destroy
```
