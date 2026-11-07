#!/usr/bin/env bash
# DR failover, part 2: make the standby region fully writable and scaled.
#
# CloudFront already routes reads to the standby automatically when the primary
# fails. This script finishes the job a human decides to do:
#   1. promote the us-west-2 read replica to a standalone, writable primary
#   2. scale the standby Auto Scaling group up to production size
# and times each step. Run from 03-multi-region-dr/. Works with bash 3.2 (macOS).
#
#   ./scripts/promote-standby.sh            # asks for confirmation
#   ./scripts/promote-standby.sh --yes
#
# One-way door: after promotion the old primary no longer replicates to it.
# Failing back means building a new replica in the original region.
set -euo pipefail

json() { terraform output -json "$1" | python3 -c "import json,sys; print(json.load(sys.stdin)['$2'])"; }
REGION=$(json secondary region)
DB=$(json secondary db_instance)
ASG=$(json secondary asg_name)
TARGET_SIZE="${TARGET_SIZE:-2}"

echo "Standby region:  $REGION"
echo "Replica:         $DB"
echo "Auto Scaling:    $ASG  -> desired $TARGET_SIZE"
if [ "${1:-}" != "--yes" ]; then
  printf 'Promote the replica? This cannot be undone. Type "promote": '
  read -r answer
  [ "$answer" = "promote" ] || { echo "Aborted."; exit 1; }
fi

T0=$(date +%s)
echo "[$(date -u +%H:%M:%S)] scaling standby app tier to $TARGET_SIZE"
aws autoscaling update-auto-scaling-group --region "$REGION" --auto-scaling-group-name "$ASG" \
  --min-size "$TARGET_SIZE" --desired-capacity "$TARGET_SIZE"

echo "[$(date -u +%H:%M:%S)] promoting $DB (backups on, 1 day)"
aws rds promote-read-replica --region "$REGION" --db-instance-identifier "$DB" \
  --backup-retention-period 1 > /dev/null

# The instance goes 'modifying' -> 'rebooting' -> 'available'; wait for the
# status change to start before waiting for 'available'.
sleep 30
aws rds wait db-instance-available --region "$REGION" --db-instance-identifier "$DB"
T1=$(date +%s)
echo "[$(date -u +%H:%M:%S)] promoted: $DB is writable ($((T1 - T0)) s)"

SOURCE=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB" \
  --query 'DBInstances[0].ReadReplicaSourceDBInstanceIdentifier' --output text)
echo "    replication source now: $SOURCE   (None = standalone primary)"

echo "[$(date -u +%H:%M:%S)] waiting for $TARGET_SIZE healthy instances in $ASG"
for _ in $(seq 1 60); do
  healthy=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" \
    --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy'])" --output text)
  [ "$healthy" -ge "$TARGET_SIZE" ] && break
  sleep 10
done
T2=$(date +%s)
echo "[$(date -u +%H:%M:%S)] app tier: $healthy healthy instance(s) ($((T2 - T0)) s total)"
echo
echo "Failover complete in $((T2 - T0)) s. Record this in the README game-day table."
