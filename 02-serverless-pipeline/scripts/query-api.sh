#!/usr/bin/env bash
# Calls the IAM-authorized query API with SigV4-signed curl (curl 7.75+, which
# macOS ships). Run from 02-serverless-pipeline/ after `terraform apply`.
#
#   ./scripts/query-api.sh 'status=FAILED'
#   ./scripts/query-api.sh 'status=COMPLETE&limit=5'
#   ./scripts/query-api.sh 'key=incoming/20261106-173929/rack-inventory-issues.csv'
#   ./scripts/query-api.sh --unsigned 'status=FAILED'    # expect 403: no credentials
set -euo pipefail

SIGN=1
if [ "${1:-}" = "--unsigned" ]; then SIGN=0; shift; fi
QUERY="${1:-status=COMPLETE}"
URL="$(terraform output -raw api_url)?$QUERY"
REGION=$(echo "$URL" | sed -n 's#^https://[^.]*\.execute-api\.\([^.]*\)\..*#\1#p')

if [ "$SIGN" = 0 ]; then
  curl -s -w '\nHTTP %{http_code}\n' "$URL"
  exit 0
fi

# Short-lived credentials from the current AWS CLI sign-in (works with `aws login`)
eval "$(aws configure export-credentials --format env)"

curl -s -w '\nHTTP %{http_code}\n' \
  --aws-sigv4 "aws:amz:${REGION}:execute-api" \
  --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
  ${AWS_SESSION_TOKEN:+-H "x-amz-security-token: ${AWS_SESSION_TOKEN}"} \
  "$URL" \
  | python3 -c '
import json, sys
raw = sys.stdin.read()
body, _, status = raw.rpartition("\nHTTP ")
try:
    print(json.dumps(json.loads(body), indent=2))
except ValueError:
    print(body)
print("HTTP", status.strip())
'
