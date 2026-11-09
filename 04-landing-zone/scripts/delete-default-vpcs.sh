#!/usr/bin/env bash
# Deletes the unused default VPC in every landing-zone account and allowed
# region. Default VPCs come with public subnets, an internet gateway and an
# open default security group, and fail ~9 FSBP controls each (EC2.2, EC2.6,
# EC2.10, EC2.15, EC2.55-58, EC2.60). Workloads here build their own VPCs.
#
# Safety: a VPC that still has any network interface (an instance, Lambda,
# endpoint, load balancer...) is skipped, never force-deleted.
#
# Usage:
#   ./delete-default-vpcs.sh            # dry run: shows what it would delete
#   ./delete-default-vpcs.sh --apply    # deletes
#
# Profiles: tf (management) plus the lz-* profiles from the README.

set -uo pipefail

PROFILES=(tf lz-log-archive lz-audit lz-dev lz-prod)
REGIONS=(us-east-1 us-west-2)
APPLY=false
[ "${1:-}" = "--apply" ] && APPLY=true

run() {
  if $APPLY; then
    if "$@" --no-cli-pager >/dev/null; then echo "    ok: $3 $5"; else echo "    FAILED: $*"; fi
  else
    echo "    would run: $3 $5"
  fi
}

for p in "${PROFILES[@]}"; do
  for r in "${REGIONS[@]}"; do
    aws_() { aws --profile "$p" --region "$r" --no-cli-pager "$@"; }
    vpc=$(aws_ ec2 describe-vpcs --filters Name=is-default,Values=true \
      --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
    if [ -z "$vpc" ] || [ "$vpc" = "None" ]; then
      echo "== $p $r: no default VPC"
      continue
    fi

    enis=$(aws_ ec2 describe-network-interfaces --filters Name=vpc-id,Values="$vpc" \
      --query 'length(NetworkInterfaces)' --output text)
    if [ "$enis" != "0" ]; then
      echo "== $p $r: $vpc has $enis network interface(s) in use, SKIPPED"
      continue
    fi
    echo "== $p $r: $vpc"

    for igw in $(aws_ ec2 describe-internet-gateways \
      --filters Name=attachment.vpc-id,Values="$vpc" \
      --query 'InternetGateways[].InternetGatewayId' --output text); do
      run aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc" --profile "$p" --region "$r"
      run aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --profile "$p" --region "$r"
    done

    for subnet in $(aws_ ec2 describe-subnets --filters Name=vpc-id,Values="$vpc" \
      --query 'Subnets[].SubnetId' --output text); do
      run aws ec2 delete-subnet --subnet-id "$subnet" --profile "$p" --region "$r"
    done

    run aws ec2 delete-vpc --vpc-id "$vpc" --profile "$p" --region "$r"
  done
done

if ! $APPLY; then
  echo
  echo "Dry run only. Re-run with --apply to delete."
fi
