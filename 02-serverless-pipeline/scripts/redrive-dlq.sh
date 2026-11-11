#!/usr/bin/env bash
# Replay retryable dead-letter queue messages through the workflow.
# Run from 02-serverless-pipeline/ after the underlying problem is fixed.
#
#   ./scripts/redrive-dlq.sh            # replay retryable, remove invalid-file messages
#   ./scripts/redrive-dlq.sh --dry-run  # show what would happen, change nothing
#
# Retryable messages start a fresh execution with the original S3 event (the
# workflow allows FAILED items to be reprocessed). Messages for invalid files
# are removed after printing: their FAILED record stays in DynamoDB.
# Works with bash 3.2 (macOS).
set -euo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
DLQ=$(terraform output -raw dlq_url)
SM=$(terraform output -raw state_machine_arn)

# Terraform state lives in the management account, so outputs are read with
# your normal credentials. Set TARGET_PROFILE to run the AWS calls in another
# account, e.g. the landing zone dev deployment: TARGET_PROFILE=lz-dev ./scripts/...
if [ -n "${TARGET_PROFILE:-}" ]; then export AWS_PROFILE="$TARGET_PROFILE"; fi
TMP=$(mktemp -d -t redrive.XXXXXX)
retried=0; skipped=0; passes=0

# A dry run must not hide messages from the real run that usually follows it:
# with visibility 0, every message it reads is immediately visible again.
VISIBILITY=60
[ "$DRY" = 1 ] && VISIBILITY=0

while :; do
  aws sqs receive-message --queue-url "$DLQ" --max-number-of-messages 10 \
    --wait-time-seconds 2 --visibility-timeout "$VISIBILITY" --output json > "$TMP/batch.json"
  count=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("Messages", [])))' "$TMP/batch.json" 2>/dev/null || echo 0)
  [ "$count" = "0" ] && break

  new=0
  i=0
  while [ "$i" -lt "$count" ]; do
    python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["Messages"][int(sys.argv[2])]; open(sys.argv[3],"w").write(m["Body"]); print(m["ReceiptHandle"]); open(sys.argv[4],"w").write(m["MessageId"])' \
      "$TMP/batch.json" "$i" "$TMP/body.json" "$TMP/msgid" > "$TMP/receipt"
    # With visibility 0 (dry run) SQS can return the same message several
    # times in one batch; count each message once.
    if grep -qxF "$(cat "$TMP/msgid")" "$TMP/seen" 2>/dev/null; then i=$((i + 1)); continue; fi
    cat "$TMP/msgid" >> "$TMP/seen"; echo >> "$TMP/seen"
    new=$((new + 1))
    python3 scripts/dlq_message.py < "$TMP/body.json" > "$TMP/decision.json"
    action=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["action"])' "$TMP/decision.json")
    summary=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["key"], "|", d["reason"])' "$TMP/decision.json")

    if [ "$action" = "retry" ]; then
      echo "RETRY  $summary"
      if [ "$DRY" = 0 ]; then
        python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["input"]))' "$TMP/decision.json" > "$TMP/input.json"
        aws stepfunctions start-execution --state-machine-arn "$SM" --input "file://$TMP/input.json" \
          --query executionArn --output text | sed 's/^/       started /'
      fi
      retried=$((retried + 1))
    else
      echo "SKIP   $summary"
      skipped=$((skipped + 1))
    fi

    if [ "$DRY" = 0 ]; then
      aws sqs delete-message --queue-url "$DLQ" --receipt-handle "$(cat "$TMP/receipt")"
    fi
    i=$((i + 1))
  done
  # A dry run keeps seeing the same visible messages, and one batch can repeat
  # one message while missing others. Keep sampling until a few batches in a
  # row bring nothing new (bounded, so it always ends).
  if [ "$DRY" = 1 ]; then
    if [ "$new" = 0 ]; then passes=$((passes + 1)); else passes=0; fi
    [ "$passes" -ge 3 ] && break
  fi
done

echo
echo "Replayed: $retried   Removed as invalid input: $skipped   (dry run: $([ "$DRY" = 1 ] && echo yes || echo no))"
if [ "$DRY" = 0 ]; then
  echo "Replayed files that fail again return to the DLQ with a new message."
fi
