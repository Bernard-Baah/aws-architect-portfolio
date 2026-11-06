#!/usr/bin/env bash
# Uploads the three sample files and shows what the pipeline did with each.
# Run from 02-serverless-pipeline/ after `terraform apply`. Works with bash 3.2 (macOS).
set -euo pipefail

BUCKET=$(terraform output -raw upload_bucket)
TABLE=$(terraform output -raw table_name)
DLQ=$(terraform output -raw dlq_url)
RUN=$(date +%Y%m%d-%H%M%S)

echo "Uploading samples to s3://$BUCKET/incoming/$RUN/"
for f in samples/rack-inventory-clean.csv samples/rack-inventory-issues.csv samples/not-a-csv.txt; do
  aws s3 cp "$f" "s3://$BUCKET/incoming/$RUN/$(basename "$f")" --only-show-errors
  echo "  $(basename "$f")"
done

echo "Waiting 20s for the workflows to finish..."
sleep 20

echo
echo "Results in DynamoDB ($TABLE):"
aws dynamodb scan --table-name "$TABLE" \
  --filter-expression "begins_with(object_key, :p)" \
  --expression-attribute-values "{\":p\":{\"S\":\"incoming/$RUN/\"}}" \
  --query 'Items[].[object_key.S, status.S, row_count.N, rack_count.N, issue_count.N, error_name.S]' \
  --output table

echo
echo "Issues found in rack-inventory-issues.csv:"
aws dynamodb scan --table-name "$TABLE" \
  --filter-expression "object_key = :k" \
  --expression-attribute-values "{\":k\":{\"S\":\"incoming/$RUN/rack-inventory-issues.csv\"}}" \
  --query 'Items[0].analysis.S' --output text \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); [print("  -", i) for i in d["issues_sample"]]' \
  || echo "  (not finished yet: rerun the scan in a few seconds)"

echo
echo -n "Messages in the dead-letter queue: "
aws sqs get-queue-attributes --queue-url "$DLQ" \
  --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text
