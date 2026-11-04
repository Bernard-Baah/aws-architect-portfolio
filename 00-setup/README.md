# 00 · Shared setup

Foundation every other project uses: a dedicated AWS account, cost alerts, Terraform remote
state and CI.

## Checklist

- [ ] Dedicated AWS account for this portfolio; MFA on root, root locked away
- [ ] AWS Budget at $25/month with alerts at 50% / 80% / 100%
- [ ] Terraform, AWS CLI and tflint installed locally
- [ ] Sign-in through IAM Identity Center (or an admin IAM user with MFA)
- [ ] Remote state bucket created with [`bootstrap-backend/`](bootstrap-backend/)
- [ ] GitHub OIDC provider + deploy role in AWS; `AWS_ROLE_ARN` repo variable set
- [ ] `plan` job enabled in [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml)

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
