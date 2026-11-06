#!/usr/bin/env bash
# Upload N generated inventory files at once and measure how the pipeline copes.
# Run from 02-serverless-pipeline/ after `terraform apply`. Works with bash 3.2 (macOS).
#
#   ./scripts/burst-test.sh          # 500 files
#   ./scripts/burst-test.sh 100
#
# Reports: files lost (must be 0), status counts, whether every planted issue
# was found, end-to-end time, per-file latency (p50/p95/max), Lambda
# throttles/concurrency and Step Functions execution counts.
set -euo pipefail

N="${1:-500}"
BUCKET=$(terraform output -raw upload_bucket)
TABLE=$(terraform output -raw table_name)
DLQ=$(terraform output -raw dlq_url)
SM=$(terraform output -raw state_machine_arn)
NAME=${SM##*:}
RUN="burst-$(date +%Y%m%d-%H%M%S)"
WORK=$(mktemp -d -t burst.XXXXXX)

dlq_depth() {
  aws sqs get-queue-attributes --queue-url "$DLQ" --attribute-names ApproximateNumberOfMessages \
    --query 'Attributes.ApproximateNumberOfMessages' --output text | tr -d '\r\n'
}

echo "Lambda account concurrency limit: $(aws lambda get-account-settings --query 'AccountLimit.ConcurrentExecutions' --output text)"
echo "Generating $N files..."
MANIFEST=$(python3 scripts/generate_inventory.py "$WORK/files" "$N")
echo "  $MANIFEST"
DLQ_BEFORE=$(dlq_depth)

echo "Uploading to s3://$BUCKET/incoming/$RUN/ (parallel)..."
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
aws s3 cp "$WORK/files" "s3://$BUCKET/incoming/$RUN/" --recursive --only-show-errors
T1=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "  upload window: $T0 -> $T1"

echo "Waiting for results (up to 10 min)..."
deadline=$(( $(date +%s) + 600 ))
while :; do
  aws dynamodb scan --table-name "$TABLE" \
    --filter-expression "begins_with(object_key, :p)" \
    --expression-attribute-values "{\":p\":{\"S\":\"incoming/$RUN/\"}}" \
    --projection-expression "object_key, #s, created_at, completed_at, failed_at, issue_count, error_name" \
    --expression-attribute-names '{"#s":"status"}' \
    --output json > "$WORK/items.json"
  done_count=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for i in d["Items"] if i["status"]["S"] in ("COMPLETE","FAILED")))' "$WORK/items.json")
  printf '\r  finished: %s / %s ' "$done_count" "$N"
  [ "$done_count" -ge "$N" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then echo; echo "  timed out; reporting what finished"; break; fi
  sleep 5
done
echo

echo "Waiting 90s for CloudWatch metrics to land..."
sleep 90
T2=$(date -u +%Y-%m-%dT%H:%M:%SZ)

metric() { # namespace metric stat dimension-name dimension-value
  aws cloudwatch get-metric-statistics --namespace "$1" --metric-name "$2" --statistics "$3" \
    --dimensions "Name=$4,Value=$5" --start-time "$T0" --end-time "$T2" --period 60 --output json
}
for fn in validate analyze; do
  metric AWS/Lambda Throttles Sum FunctionName "inventory-pipeline-$fn" > "$WORK/throttles-$fn.json"
  metric AWS/Lambda ConcurrentExecutions Maximum FunctionName "inventory-pipeline-$fn" > "$WORK/conc-$fn.json"
  metric AWS/Lambda Duration Average FunctionName "inventory-pipeline-$fn" > "$WORK/dur-$fn.json"
done
metric AWS/States ExecutionsSucceeded Sum StateMachineArn "$SM" > "$WORK/sfn-ok.json"
metric AWS/States ExecutionsFailed Sum StateMachineArn "$SM" > "$WORK/sfn-failed.json"
DLQ_AFTER=$(dlq_depth)

python3 - "$WORK" "$N" "$T0" "$T1" "$DLQ_BEFORE" "$DLQ_AFTER" "$MANIFEST" <<'PY'
import json, sys, statistics
from datetime import datetime

work, n, t0, t1, dlq_before, dlq_after, manifest = sys.argv[1:8]
n = int(n); manifest = json.loads(manifest)
ts = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00"))
items = json.load(open(f"{work}/items.json"))["Items"]

status = {}
for i in items:
    status[i["status"]["S"]] = status.get(i["status"]["S"], 0) + 1
complete = [i for i in items if i["status"]["S"] == "COMPLETE"]
flagged = sum(1 for i in complete if int(i["issue_count"]["N"]) > 0)
lat = sorted((ts(i["completed_at"]["S"]) - ts(i["created_at"]["S"])).total_seconds() for i in complete)
last_done = max((ts(i["completed_at"]["S"]) for i in complete), default=None)

def total(name):
    pts = json.load(open(f"{work}/{name}.json"))["Datapoints"]
    return sum(p.get("Sum", 0) for p in pts), max((p.get("Maximum", 0) for p in pts), default=0), \
           (statistics.mean(p["Average"] for p in pts) if pts and "Average" in pts[0] else 0)

def pct(xs, p):
    return xs[min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1))))] if xs else 0

print("=" * 62)
print(f"Files uploaded            {n}")
print(f"Recorded in DynamoDB      {len(items)}   (lost: {n - len(items)})")
print(f"Status                    {status}")
print(f"Planted issues found      {flagged} of {manifest['files_with_planted_issues']} files"
      f"  {'(all found)' if flagged == manifest['files_with_planted_issues'] else '(MISMATCH)'}")
print(f"Rows analyzed             {manifest['rows']}")
if last_done:
    e2e = (last_done - ts(t0)).total_seconds()
    print(f"Upload start -> last done {e2e:.1f} s   ({len(complete) / e2e:.1f} files/s)")
print(f"Per-file latency          p50 {pct(lat, 50):.2f} s · p95 {pct(lat, 95):.2f} s · max {pct(lat, 100):.2f} s")
for fn in ("validate", "analyze"):
    thr, _, _ = total(f"throttles-{fn}")
    _, conc, _ = total(f"conc-{fn}")
    _, _, dur = total(f"dur-{fn}")
    print(f"Lambda {fn:<9}          max concurrency {conc:.0f} · throttles {thr:.0f} · avg duration {dur:.0f} ms")
ok, _, _ = total("sfn-ok"); bad, _, _ = total("sfn-failed")
print(f"Step Functions            succeeded {ok:.0f} · failed {bad:.0f}")
print(f"DLQ messages              before {dlq_before} · after {dlq_after}")
print("=" * 62)
PY
echo "Raw data kept in $WORK"
