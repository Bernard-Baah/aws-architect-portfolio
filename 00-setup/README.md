# 00 · Shared setup

Foundation every other project uses: a dedicated AWS account, cost alerts, Terraform remote
state and CI.

## Checklist

- [ ] Dedicated AWS account for this portfolio; MFA on root, root locked away
- [ ] AWS Budget at $25/month with alerts at 50% / 80% / 100%
- [x] Terraform and AWS CLI installed locally (tflint optional)
- [ ] Sign-in through IAM Identity Center (or an admin IAM user with MFA)
- [x] Remote state bucket created with [`bootstrap-backend/`](bootstrap-backend/)
- [x] GitHub OIDC provider + plan role deployed with [`github-oidc/`](github-oidc/); `AWS_ROLE_ARN` repo variable set
- [x] `plan` job enabled in [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml)

## Remote state

`bootstrap-backend/` creates a versioned, encrypted, private S3 bucket. State locking uses
Terraform's native S3 lockfile (`use_lockfile = true`, Terraform 1.10+), so no DynamoDB
table is needed.

```bash
cd 00-setup/bootstrap-backend
terraform init
terraform apply -var="state_bucket_name=bernard-tfstate-<random-suffix>"
```

Copy the `backend_block` output into each project's `backend.tf`, changing `key` per project.

## GitHub Actions → AWS (OIDC)

`github-oidc/` deploys [`modules/github-oidc`](../modules/github-oidc/): an IAM OIDC provider
for GitHub and a role that **only this repo** can assume, and only from `main` or a pull
request. The role gets `ReadOnlyAccess` plus read access to the state bucket and permission to
manage its `.tflock` files. That's enough for `terraform plan` and nothing more. No access
keys are stored anywhere.

```bash
cd 00-setup/github-oidc
terraform init -backend-config="bucket=<your-state-bucket>"
terraform apply -var="state_bucket_name=<your-state-bucket>"
```

Copy the `role_arn` output into GitHub → **Settings → Secrets and variables → Actions →
Variables** as `AWS_ROLE_ARN`. The workflow's `plan` job runs automatically once that variable exists.

**Design notes**
- The `sub` condition is the critical control. Without it, *any* GitHub repository could assume the role.
- Plan and apply are separate privileges. A write-capable apply role, limited to `main` and gated by a
  GitHub environment approval, is a later step.
