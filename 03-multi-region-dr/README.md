# 03 · Multi-region disaster recovery

> **Status:** ✅ Game day passed (2026-11-07): 100% availability through a primary-region outage, writable in us-west-2 9 min 15 s after the incident

## Problem
_The app from Project 01 must survive the loss of an entire AWS Region._
**Targets: RTO < 15 min, RPO < 5 min.**

## Architecture: warm standby
![Architecture: users reach one CloudFront + WAF URL whose origin group prefers the internal ALB in us-east-1 (2 instances, primary RDS, Secrets Manager) and fails over per request to the internal ALB in us-west-2 (1 warm instance, cross-region read replica, replicated secret); results card shows 100% availability and 9 min 15 s to writable](../docs/diagrams/03-multi-region-dr.svg)
Each region is a full copy of the Project 01 app tier (`modules/app-region` = network + security group
chain + internal ALB + Auto Scaling group), deployed from one Terraform stack with two providers.

## How failover works
| Layer | Automatic? | How |
|---|---|---|
| Traffic | ✅ automatic, per request | CloudFront **origin failover**: if the primary answers 500/502/503/504 or doesn't connect within 2 s (1 attempt), CloudFront retries the same request on the standby. No DNS TTL to wait out. |
| Reads | ✅ immediate | The standby app reads from its local replica, so `/` and `/db` work the moment traffic arrives. |
| Writes | 👤 human decision | `scripts/promote-standby.sh` promotes the replica to a standalone primary and scales the standby to 2 instances, timing each step. Promotion is a one-way door, so it stays a deliberate call. |

## Build checklist
- [x] Region module (`modules/app-region`) reused for both regions
- [x] Primary (2 instances) + warm standby (1 instance), non-overlapping CIDRs (10.0/16, 10.1/16)
- [x] RDS cross-region read replica, encrypted with the standby region's KMS key
- [x] DB secret replicated to the standby region
- [x] CloudFront origin group with fast primary timeouts + WAF
- [x] Promotion script with timings
- [x] Game day: break the primary, measure RTO (RPO under write load: see Known gaps)
- [x] Fail-back runbook documented (not yet executed)

## Design decisions & trade-offs
- **CloudFront origin failover instead of Route 53 failover.** No domain needed, and failover happens
  per request instead of after health-check intervals plus DNS TTL. Trade-off: origin groups only
  fail over `GET`/`HEAD`/`OPTIONS`, so the distribution allows only those methods (fine for this
  read-mostly app). A write-heavy app would use Route 53 failover records or ARC.
- **Self-managed DB password, never in Terraform state.** RDS doesn't allow read replicas of a DB
  whose master password it manages in Secrets Manager (Project 01's approach). Here Terraform
  generates the password as an **ephemeral** value and writes it through **write-only attributes**
  (`password_wo`, `secret_string_wo`, Terraform 1.11+), so it never touches state. The secret is
  replicated to us-west-2 so the standby can read it while us-east-1 is down. Trade-off: no
  automatic rotation; bump `db_password_version` to rotate.
- **`ignore_changes = [replicate_source_db]` on the replica.** After promotion the replica has no
  source. Without this, the next `terraform plan` would try to make the new primary a replica again,
  or replace it.
- **Warm standby, not pilot light or active-active.** One instance and a replica keep the standby
  ready to serve within seconds at about a third of the primary's cost. Pilot light (no running
  instances) would add minutes of boot time to the RTO; active-active needs multi-writer data.
- **Primary DB single-AZ in this lab** (`primary_db_multi_az = false`). Project 01 already measured
  Multi-AZ failover (40 s). Here the regional replica is the point, and two Multi-AZ setups would
  double the DB bill.

## DR strategy comparison
| Strategy | Relative cost | Typical RTO | Chosen? |
|----------|---------------|-------------|---------|
| Backup & restore | $ | Hours | |
| Pilot light | $$ | 10s of minutes | |
| Warm standby | $$$ | Minutes | ✅ |
| Active-active | $$$$ | Near zero | |

## Deploy
```bash
cd 03-multi-region-dr
terraform init -backend-config="bucket=bernard-tfstate-40b007"
terraform apply
terraform output -raw app_url
```
The first apply takes **35–50 minutes**: the primary DB, then the cross-region replica (it copies a
snapshot across regions), then the standby app tier, then two CloudFront VPC origins.

**Cost while running: about $5–6/day** (2 NAT Gateways, 2 ALBs, 2 DBs, 3 instances, WAF).
Run game days in one sitting, then `terraform destroy`.

Requires Terraform **1.11+** (write-only attributes).

## Game day · 2026-11-07
**Scenario:** the primary region's app tier is lost (us-east-1 Auto Scaling group set to 0). A probe
hit the single CloudFront URL twice a second for 10 minutes the whole time.

| Time (UTC) | Event |
|---|---|
| before 17:14:31 | us-east-1a and us-east-1b serve traffic (36 requests each) |
| **17:14:31** | **Incident:** us-east-1 app tier scaled to 0 |
| 17:14:31 → | CloudFront origin group sends traffic to us-west-2, **with no failed requests** |
| 17:19:00 | Disaster declared: `promote-standby.sh` starts (4 min 29 s of human decision time) |
| 17:18:56 | Standby Auto Scaling group raised to 2 |
| 17:23:46 | Replica promoted, **writable** (290 s); replication source = None |
| 17:23:54 | 2 healthy instances in us-west-2 |

| Measure | Target | Result |
|---|---|---|
| Availability during the outage (808 requests) | | **100.00%**, 0 s failure window |
| RTO for reads (users see the app working) | < 15 min | **0 s** (per-request origin failover) |
| RTO for writes (incident → writable DB) | < 15 min | **9 min 15 s** ✅ (4 min 29 s decision + 4 min 50 s automation) |
| Promotion alone | | 290 s |
| RPO | < 5 min | **Not measured under write load** (see below) |

Instances that served the probe: `us-east-1a` 36 · `us-east-1b` 36 · `us-west-2b` 590 · `us-west-2a` 146
(the second standby instance, launched by the promotion script).

### Known gaps (and how to close them)
- **RPO wasn't measured under writes.** CloudWatch `ReplicaLag` read 125–347 s on average (peaks
  257–302 s, and 647 s right after the replica was created). That's an artifact of an **idle** source:
  per [AWS](https://repost.aws/knowledge-center/rds-postgresql-replication-lag), with no transactions
  RDS PostgreSQL replicas report lag of up to 5 minutes, because the metric is *time since the last
  committed transaction* and resets when the WAL segment switches (every 5 minutes by default). With
  zero writes, no data was at risk. **Next game day:** run a write heartbeat (one timestamped row per
  second) on the primary, then compare the newest row on the promoted replica to the incident time.
- **The outage was graceful.** Scaling to 0 drains targets, so the primary returned clean 503s. A
  harder test is to block the primary ALB's security group (connection timeouts), which exercises
  the 1-attempt / 2-second origin timeout.
- **The 4.5-minute decision time dominates RTO.** It's deliberate, because promotion is a one-way door.
  To cut it: a CloudWatch alarm on primary 5xx/health that pages on-call with the promote command ready.

## Fail back to us-east-1 (runbook, not yet executed)
After promotion, us-west-2 is the only writable copy. Getting back without data loss:
1. Restore the us-east-1 app tier (Auto Scaling group back to 2). CloudFront still prefers it, so
   **first** keep it out of service: leave it at 0, or swap the origin group order.
2. Create a new cross-region replica **in us-east-1 from the promoted us-west-2 DB** and wait for it to
   catch up.
3. In a short maintenance window: stop writes, confirm replication is caught up, promote the us-east-1
   replica, point the us-east-1 app at it, and bring the us-east-1 app tier back.
4. Rebuild a fresh us-west-2 replica from the new primary, back to the original layout.
In Terraform terms: after step 3, re-import the promoted DBs, or run `terraform destroy` and `terraform apply`
for a lab. Automating this is a good follow-up project.
