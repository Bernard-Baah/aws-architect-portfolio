# 04 · Secure multi-account landing zone

> **Status:** ⏳ Planned

## Problem
_Move from one lab account to a governed, auditable multi-account organization, then run Projects 01–03 inside it._

## Structure
```
Management account
├── Security OU      → Log Archive, Audit
├── Workloads OU     → Dev, Prod
└── Sandbox OU
```

## Build checklist
- [ ] Control Tower (or hand-built Organizations + Terraform)
- [ ] IAM Identity Center permission sets (Admin break-glass, PowerUser Dev, ReadOnly Prod)
- [ ] SCPs: deny leave-org, deny disabling CloudTrail/GuardDuty/Config, region allow-list, deny root
- [ ] Org CloudTrail → Log Archive (Object Lock, KMS)
- [ ] Config aggregator, GuardDuty + Security Hub delegated to Audit
- [ ] EventBridge → Lambda auto-response for high-severity findings
- [ ] Redeploy Project 01 into Dev and Prod via GitHub Actions + per-account OIDC roles

## Results
| Metric | Before | After |
|--------|--------|-------|
| Security Hub FSBP score | _% | _% |

| SCP test (attempted action) | Result |
|-----------------------------|--------|
| _Disable CloudTrail in Dev_ | _Denied_ |
