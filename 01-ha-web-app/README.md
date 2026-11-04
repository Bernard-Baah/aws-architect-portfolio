# 01 · Highly available multi-tier web app

> **Status:** 🚧 In progress: network layer done

## Problem
_A business-critical app must survive the loss of an Availability Zone with no manual intervention._

## Architecture
Route 53 → CloudFront (+ WAF) → ALB (public subnets, 2 AZs) → EC2 Auto Scaling group
(private app subnets) → RDS PostgreSQL Multi-AZ (private data subnets). Static assets in S3
via Origin Access Control. Secrets in Secrets Manager. No SSH; access through SSM Session Manager.

_Diagram: `docs/diagrams/01-ha-web-app.png`_

### Network layout (`10.0.0.0/16`, 2 AZs)

| Tier | AZ a | AZ b | Route to internet | What lives here |
|------|------|------|-------------------|-----------------|
| Public | 10.0.0.0/24 | 10.0.1.0/24 | Internet Gateway | ALB, NAT Gateway |
| App | 10.0.10.0/24 | 10.0.11.0/24 | NAT (outbound only) | EC2 Auto Scaling group |
| Data | 10.0.20.0/24 | 10.0.21.0/24 | None | RDS Multi-AZ |

Gaps between tiers (`.2`–`.9`, `.12`–`.19`) leave room for a third AZ without renumbering.
VPC Flow Logs (all traffic, 60s aggregation) go to CloudWatch Logs with 7-day retention.
The default security group has no rules.

## Build checklist
- [x] Network module: VPC, 6 subnets across 2 AZs, IGW, NAT, route tables, Flow Logs
- [ ] Security groups chained ALB → app → DB
- [ ] RDS Multi-AZ + Secrets Manager
- [ ] Launch template, instance profile, ASG (min 2 / max 4, target tracking 60% CPU)
- [ ] ALB + ACM cert + HTTP→HTTPS redirect, health checks on `/health`
- [ ] CloudFront + S3 origin + WAF managed rules
- [ ] Failure tests: terminate instances, force RDS failover, load test

## Design decisions & trade-offs
- **One NAT Gateway, not one per AZ.** Saves about $33/month in the lab. Trade-off: if AZ a fails, app
  instances in AZ b lose *outbound* internet, though inbound traffic through the ALB keeps working.
  Production would set `single_nat_gateway = false`. Each AZ already has its own app route table,
  so that switch needs no re-plumbing.
- **Data tier has no internet route at all**, not even through NAT. The database only needs to talk to the app tier.
- **No public IPs auto-assigned in public subnets.** Only the ALB and NAT live there.
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
cd 01-ha-web-app
terraform init -backend-config="bucket=bernard-tfstate-40b007"
terraform apply
terraform destroy   # at the end of every session; the NAT Gateway bills hourly
```

Network only, no NAT (nearly free, good for a quick look):
```bash
terraform apply -var="enable_nat_gateway=false"
```
