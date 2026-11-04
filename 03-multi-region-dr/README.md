# 03 · Multi-region disaster recovery

> **Status:** ⏳ Planned

## Problem
_The app from Project 01 must recover from the loss of an entire AWS Region._
**Targets: RTO < 15 min, RPO < 5 min.**

## Architecture
Warm standby. Primary in `us-east-1`, scaled-down copy in `us-west-2`. RDS cross-region read
replica, S3 Cross-Region Replication, replicated secrets, AWS Backup cross-region copies.
Route 53 failover routing with health checks (TTL 60s). Failover runbook as code
(SSM Automation / Step Functions).

_Diagram: `docs/diagrams/03-multi-region-dr.png`_

## Build checklist
- [ ] Refactor Project 01 into a module parameterized by `region` and `capacity`
- [ ] Deploy primary (full) + standby (ASG min 1)
- [ ] RDS cross-region replica, S3 CRR, secret replication
- [ ] AWS Backup plan with cross-region copy
- [ ] Route 53 failover records + health checks
- [ ] Automated failover runbook
- [ ] Game day: fail over, measure RTO/RPO
- [ ] Fail back to `us-east-1`

## DR strategy comparison
| Strategy | Relative cost | Typical RTO | Chosen? |
|----------|---------------|-------------|---------|
| Backup & restore | $ | Hours | |
| Pilot light | $$ | 10s of minutes | |
| Warm standby | $$$ | Minutes | ✅ |
| Active-active | $$$$ | Near zero | |

## Game-day results
| Metric | Target | Measured |
|--------|--------|----------|
| RTO | < 15 min | _ |
| RPO | < 5 min | _ |
