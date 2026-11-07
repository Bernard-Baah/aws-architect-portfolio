# 03 · Multi-region disaster recovery

> **Status:** 🚧 In progress: two-region stack built; game day next

## Problem
_The app from Project 01 must survive the loss of an entire AWS Region._
**Targets: RTO < 15 min, RPO < 5 min.**

## Architecture: warm standby
```
viewer ─HTTPS─▶ CloudFront + WAF ─▶ origin group ─┬─▶ primary ALB   us-east-1  (ASG: 2 instances)
                                                  └─▶ standby ALB   us-west-2  (ASG: 1 instance)
                                                       ▲ used when the primary returns 5xx or can't be reached

primary RDS PostgreSQL (us-east-1) ──async replication──▶ read replica (us-west-2)
DB secret (us-east-1) ──Secrets Manager replication──▶ us-west-2
```
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
- [ ] Game day: break the primary, measure RTO/RPO
- [ ] Fail back to `us-east-1`

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

## Results
| Test | Measured |
|------|----------|
| Traffic failover (primary app tier down) | _ |
| Replica lag (RPO estimate) | _ |
| Promotion time (RTO for writes) | _ |
| Fail back | _ |
