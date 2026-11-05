# 01 · Highly available multi-tier web app

> **Status:** 🚧 In progress: network, security groups and database done

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

![VPC resource map: 6 subnets across us-east-1a and us-east-1b, their route tables, the internet gateway and the NAT gateway](../docs/diagrams/01-network-resource-map.png)

*Deployed network, from the VPC console's resource map. The unnamed `rtb-…` is the VPC's main
route table. No subnet uses it, so anything accidentally left unassociated gets no internet route.*

Gaps between tiers (`.2`–`.9`, `.12`–`.19`) leave room for a third AZ without renumbering.
VPC Flow Logs (all traffic, 60s aggregation) go to CloudWatch Logs with 7-day retention.
The default security group has no rules.

## Build checklist
- [x] Network module: VPC, 6 subnets across 2 AZs, IGW, NAT, route tables, Flow Logs
- [x] Security groups chained ALB → app → DB
- [x] RDS Multi-AZ + Secrets Manager
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
- **Security groups reference each other, not IP ranges.** Only members of the ALB group can reach the
  app port, and only members of the app group can reach PostgreSQL. A new instance in the same subnet
  gets nothing by default. The database group has no outbound rules at all.
- **No database password in code or Terraform state.** `manage_master_user_password` has RDS generate the
  password and keep it in Secrets Manager with automatic rotation.
- **RDS Multi-AZ (instance), not Aurora.** `db.t4g.micro` Multi-AZ costs about $0.80/day; the smallest Aurora
  setup costs several times that. Aurora would win on failover time (usually under 30s vs. 1–2 min) and
  read replicas, which matters more in Project 03.
- _EC2 vs. ECS Fargate_

## Results
| Test | Measured |
|------|----------|
| Instance termination → replaced | _ min |
| RDS forced failover (2026-11-05) | **40 s** per RDS event log (failover started → completed); primary moved us-east-1b → us-east-1a. API status back to `available` after 83 s. |
| Scale-out under load | _ → _ instances |

## Deploy / destroy
```bash
cd 01-ha-web-app
terraform init -backend-config="bucket=bernard-tfstate-40b007"
terraform apply
terraform destroy   # at the end of every session; the NAT Gateway bills hourly
```

Approximate running cost with everything on: NAT Gateway about $1.20/day plus RDS Multi-AZ
about $0.90/day. Cheaper options while building:
```bash
terraform apply -var="db_multi_az=false"          # single-AZ DB, about half the DB cost
terraform apply -var="enable_nat_gateway=false"   # no NAT; fine until the app tier exists
```

### Failover test (RDS)
```bash
DB=$(terraform output -raw db_identifier)
aws rds describe-db-instances --db-instance-identifier $DB \
  --query 'DBInstances[0].[AvailabilityZone,SecondaryAvailabilityZone]'
aws rds reboot-db-instance --db-instance-identifier $DB --force-failover
# re-run describe-db-instances: the two AZs swap
aws rds describe-events --source-identifier $DB --source-type db-instance --duration 30 \
  --query 'Events[].[Date,Message]' --output text
```

The event log is the source of truth for timing. `AvailabilityZone` in `describe-db-instances` can
lag by a minute or two after the failover completes. In the first test it still showed the old AZ
when the status returned to `available`.

| Event (UTC, 2026-11-05) | Time |
|-------------------------|------|
| Multi-AZ instance failover started | 18:03:19 |
| DB instance restarted | 18:03:34 |
| Multi-AZ instance failover completed | 18:03:59 |

This measures the database side only. Real application downtime, including DNS TTL and connection
retries, gets measured once the app tier exists.

Network only, no NAT (nearly free, good for a quick look):
```bash
terraform apply -var="enable_nat_gateway=false"
```
