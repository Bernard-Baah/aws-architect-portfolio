# 04 · Secure multi-account landing zone

> **Status:** 🚧 In progress (layer 1 deployed; layer 2 in progress)

## Problem
Projects 01–03 ran in one account where any admin could do anything, anywhere. Real companies split workloads, logs and security tooling across accounts so that one compromised or careless identity can't erase the evidence or switch off detection. This project turns the portfolio account into the management account of an AWS Organization with guardrails, central logging and central security findings, all in Terraform.

**Brownfield start:** the account already managed an organization from an earlier project. Terraform adopts it with an `import` block and brings it under code, instead of creating a fresh one, and reuses its two idle member accounts as dev and prod. That's the more common situation at real companies.

## Structure
```
Management account (the existing portfolio account: Organizations, billing, Terraform state)
├── Security OU      → lz-log-archive, lz-audit
├── Workloads OU     → dev, prod (adopted from the earlier org)
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
| 1 | `organization/` | Organization (imported), 3 OUs, 2 new + 2 adopted member accounts, centralized root access, 2 SCPs |
| 2 | `security/` | Org CloudTrail → Log Archive (Object Lock, KMS), then GuardDuty + Security Hub delegated to Audit and EventBridge auto-response |
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

## Deploy layer 2a: organization CloudTrail
One trail in the management account logs every API call in every account and region into `org-cloudtrail-<log-archive-id>` in Log Archive:
- **SSE-KMS** with a customer managed key owned by Log Archive. Only CloudTrail can encrypt with it; Audit can decrypt for investigations.
- **Object Lock** (governance mode, 7 days in this lab) and **log file validation**, so deleting or editing a log is blocked or detectable.
- **Bucket policy** lets CloudTrail write only when the request comes from this trail (`aws:SourceArn`), and denies non-TLS access.

```bash
cd 04-landing-zone/security
terraform init -backend-config="bucket=bernard-tfstate-40b007"
terraform plan
terraform apply
```

Terraform reaches Log Archive by assuming `OrganizationAccountAccessRole` from the management account. CI validates this stack but doesn't plan it: the CI role is read-only in the management account and deliberately can't assume admin roles in member accounts.

## Deploy layer 2b: GuardDuty
The management account makes Audit the GuardDuty **delegated administrator** in us-east-1 and us-west-2. From Audit, GuardDuty is auto-enabled for every existing and future account, so findings from all 5 accounts land in one place. Members can't switch it off: they aren't the admin, and the guardrails SCP denies the delete and disassociate calls.

```bash
cd 04-landing-zone/security
terraform init
terraform apply
```

## Deploy layer 2c: AWS Config
Security Hub scores accounts from AWS Config, so every account records its resources first:
- **Every account, both regions:** `modules/account-config` (recorder role + daily recorder + delivery channel), one call per account.
- **Delivery:** one bucket in Log Archive. Only principals in this organization named `config-recorder*` can write, and only under their own account's prefix.
- **Daily** recording instead of continuous keeps cost to cents for quiet lab accounts. Global resources (IAM) are recorded in us-east-1 only.

**Lesson learned: why not a StackSet?** The first version used a service-managed CloudFormation StackSet so new accounts would get Config automatically. Every stack failed with "AWS::Config::ConfigurationRecorder ... did not stabilize". CloudFormation's recorder resource starts recording as soon as it's created, which needs a delivery channel, but a delivery channel can't be created without a recorder, so the two deadlock. Terraform creates the recorder stopped, adds the channel, then starts recording. Trade-off: a new account needs one more module call (Control Tower or a StackSet with a custom resource would automate it).

**Second lesson: the guardrails stopped our own cleanup.** Deleting the failed stacks also failed in the accounts where a recorder had been created. StackSet stacks in member accounts run as a normal IAM execution role, not a service-linked role, so the guardrails SCP's deny on `config:DeleteConfigurationRecorder` applied to CloudFormation too. Fix: detach those stack instances with `--retain-stacks`, then delete the stacks directly as `OrganizationAccountAccessRole`, the one role the SCP exempts. The guardrail worked exactly as designed; the cleanup path just has to go through the exempt role.

## Cost
Layer 1 is free: Organizations, OUs, SCPs and idle accounts cost nothing. AWS Config (daily recording) costs cents per account-region for quiet accounts. GuardDuty has a 30-day free trial per account and region, then is usage-based (small for idle lab accounts). Layer 2a: the first copy of management events is free; expect about $1/month for the KMS key plus cents of S3. Later layers add CloudTrail data storage, GuardDuty and Security Hub (both have 30-day free trials per account), noted in each layer.

## Teardown (read before deploying)
- `terraform destroy` **closes** the member accounts (`close_on_deletion = true`) rather than removing them, because a removed account would need its own payment method and root login.
- AWS lets an organization close at most **10 member accounts per rolling 30 days**; this build has 4.
- Destroying the stack would also delete the imported organization once it has no member accounts.
- A closed account stays in a **90-day post-closure period**: it can be reopened through Support, still counts toward the organization's account quota, and its email address can never be used for another AWS account.
- The organization itself deletes once it has no member accounts. Closed accounts drop out after the 90 days.

## Build checklist
- [x] Hand-built Organizations + Terraform (no Control Tower)
- [x] SCPs: deny leave-org, deny disabling CloudTrail/GuardDuty/Config/Security Hub, region allow-list, deny root
- [x] Centralized root access for member accounts
- [x] Org CloudTrail → Log Archive (Object Lock, KMS)
- [x] GuardDuty delegated to Audit (both regions, auto-enable all members)
- [x] AWS Config in every account and both regions (Terraform module per account)
- [ ] Security Hub delegated to Audit (central configuration, FSBP)
- [ ] EventBridge → Lambda auto-response for high-severity findings
- [ ] IAM Identity Center permission sets (Admin break-glass, PowerUser Dev, ReadOnly Prod)
- [ ] Redeploy Project 01 into Dev via GitHub Actions + a per-account OIDC role

## Results
| Metric | Before | After |
|--------|--------|-------|
| Security Hub FSBP score | _% | _% |

| Layer 1 deploy | Result |
|----------------|--------|
| Existing organization adopted | 3 imported, 10 added, 3 changed, **0 destroyed** |
| New accounts (log-archive, audit) | Created in 12–13 s each |
| Adopted accounts (dev, prod) | Moved into Workloads OU, names and emails unchanged |
| CI plan after apply | No changes (code matches the org) |

| SCP test (dev account, as `OrganizationAccountAccessRole`, an admin) | Result |
|-----------------------------|--------|
| `sts get-caller-identity` | ✅ Allowed: management account can administer dev |
| `ec2 describe-vpcs` in us-east-1 | ✅ Allowed (allow-listed region) |
| `ec2 describe-vpcs` in eu-west-1 | ⛔ **Denied**: "explicit deny in a service control policy" naming the `region-allowlist` policy |
| _Disable CloudTrail in dev as a non-exempt admin_ | _Pending (layer 3 Identity Center user)_ |

| Org CloudTrail test (layer 2a) | Result |
|--------------------------------|--------|
| Trail status from management | `IsLogging: true` |
| Dev account activity in Log Archive | ✅ Delivered to `AWSLogs/<org-id>/<dev-id>/CloudTrail/` about 4 minutes after the calls |
| SCP-denied eu-west-1 call | ✅ **Still recorded**: a log file appeared under `eu-west-1/` even though the call was blocked |
| Delete a log file version as a Log Archive admin | ⛔ **AccessDenied**: "object protected by object lock" |

| GuardDuty test (layer 2b) | Result |
|---------------------------|--------|
| Audit is delegated admin in us-east-1 and us-west-2 | ✅ Org auto-enable = `ALL` |
| Members listed in Audit right after apply | 0: auto-enable enrolls *existing* accounts in the background, so members are now added explicitly in code |
| Members after explicit enrollment | ✅ 4/4 **Enabled** (management, log-archive, dev, prod) |

| AWS Config test (layer 2c) | Result |
|----------------------------|--------|
| Recorders across 5 accounts × 2 regions | ✅ **10/10 recording**, daily mode |
| Delivery to the central Log Archive bucket | ✅ 10/10 `lastStatus: SUCCESS` (cross-account bucket policy works) |
| Final apply | 36 added, 1 changed, **0 destroyed** |

**Lesson learned:** enrolling the management account failed twice under Terraform with "Provider produced inconsistent result: Root object was present, but now absent". The same `create-members` call succeeded by hand minutes later, so it was eventual consistency right after its detector was created. Fix: enroll by hand, then adopt with `import` blocks so the code still describes reality.
