# 04 · Secure multi-account landing zone

> **Status:** 🚧 In progress (layer 1 of 3: organization)

## Problem
Projects 01–03 ran in one account where any admin could do anything, anywhere. Real companies split workloads, logs and security tooling across accounts so that one compromised or careless identity can't erase the evidence or switch off detection. This project turns the portfolio account into the management account of an AWS Organization with guardrails, central logging and central security findings, all in Terraform.

**Brownfield start:** the account already managed an organization from an earlier project. Terraform adopts it with an `import` block and brings it under code, instead of creating a fresh one. That's the more common situation at real companies.

## Structure
```
Management account (the existing portfolio account: Organizations, billing, Terraform state)
├── Security OU      → lz-log-archive, lz-audit
├── Workloads OU     → lz-dev, lz-prod
└── Sandbox OU       → (empty)
```

## Why hand-built Terraform instead of Control Tower
| | Control Tower | This build |
|---|---|---|
| What you learn | Clicks through a wizard | Every Organizations, SCP, CloudTrail, GuardDuty and Identity Center resource |
| Change review | Console drift, landing-zone upgrades | Pull request + `terraform plan` in CI |
| Lab cost | Config recorders in every governed region from day one | Only what each layer turns on |
| Teardown | Unmanage accounts first, then decommission | `terraform destroy` per layer |

Control Tower is the right call for a real company that wants AWS to own the upgrades. Building the pieces by hand is how you understand what it does.

## Layers
Each layer is its own Terraform stack, so a later layer's provider can assume a role in an account that the earlier layer already created.

| Layer | Folder | What it creates |
|---|---|---|
| 1 | `organization/` | Organization (all features), 3 OUs, 4 member accounts, centralized root access, 2 SCPs |
| 2 | `security/` | Org CloudTrail → Log Archive (Object Lock, KMS); GuardDuty + Security Hub delegated to Audit; EventBridge auto-response |
| 3 | `identity/` | IAM Identity Center permission sets: Admin (break-glass), PowerUser → Dev, ReadOnly → Prod |

## Guardrails (layer 1)
| SCP | Denies | Exempt |
|---|---|---|
| `guardrails` | Leaving the org; stopping or deleting CloudTrail, GuardDuty, Config, Security Hub; any action by a member account's root user | `OrganizationAccountAccessRole` (baseline statement only, so Terraform can still manage and tear down) |
| `region-allowlist` | Regional APIs outside us-east-1 and us-west-2 (global services like IAM, CloudFront, Route 53 excepted) | Nobody |

SCPs never apply to the management account, which is why no workloads run there.

**Centralized root access** removes long-lived root passwords and keys from every member account. Root-only tasks (like unlocking a bucket policy that locks everyone out) go through short-lived `sts:AssumeRoot` sessions from the management account.

## Deploy layer 1
Account creation is real and slow to undo, so read the plan before typing `yes`.

```bash
cd 04-landing-zone/organization
cp example.tfvars terraform.tfvars
terraform init -backend-config="bucket=bernard-tfstate-40b007"
terraform plan
terraform apply
```

Expect around 5 to 10 minutes: each account takes a few minutes to provision.

## Cost
Layer 1 is free: Organizations, OUs, SCPs and idle accounts cost nothing. Later layers add CloudTrail data storage, GuardDuty and Security Hub (both have 30-day free trials per account), noted in each layer.

## Teardown (read before deploying)
- `terraform destroy` **closes** the member accounts (`close_on_deletion = true`) rather than removing them, because a removed account would need its own payment method and root login.
- AWS lets an organization close at most **10 member accounts per rolling 30 days**; this build has 4.
- A closed account stays in a **90-day post-closure period**: it can be reopened through Support, still counts toward the organization's account quota, and its email address can never be used for another AWS account.
- The organization itself deletes once it has no member accounts. Closed accounts drop out after the 90 days.

## Build checklist
- [x] Hand-built Organizations + Terraform (no Control Tower)
- [x] SCPs: deny leave-org, deny disabling CloudTrail/GuardDuty/Config/Security Hub, region allow-list, deny root
- [x] Centralized root access for member accounts
- [ ] Org CloudTrail → Log Archive (Object Lock, KMS)
- [ ] GuardDuty + Security Hub delegated to Audit
- [ ] EventBridge → Lambda auto-response for high-severity findings
- [ ] IAM Identity Center permission sets (Admin break-glass, PowerUser Dev, ReadOnly Prod)
- [ ] Redeploy Project 01 into Dev via GitHub Actions + a per-account OIDC role

## Results
| Metric | Before | After |
|--------|--------|-------|
| Security Hub FSBP score | _% | _% |

| SCP test (attempted action) | Result |
|-----------------------------|--------|
| _Disable CloudTrail in Dev_ | _Denied_ |
| _Launch EC2 in eu-west-1 from Dev_ | _Denied_ |
