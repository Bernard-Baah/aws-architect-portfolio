# Runbook: inventory pipeline unhealthy

**Pages from:** composite alarm `inventory-pipeline-unhealthy` (dev account, us-east-1).
**Dashboard:** CloudWatch → Dashboards → `inventory-pipeline-slo`.

## First five minutes
1. Open the dashboard. The **Alarm status** row shows which child alarm is red; jump to its section below.
2. Check whether it's one file or many: the **Executions** widget separates succeeded, failed (which includes rejected files), timed out and aborted.
3. Note the start time. Every section ends with "recovered when": write the end time and cause in the incident note.

> **Not an incident:** a user uploading a bad file. The pipeline rejects it on purpose, records `FAILED` with a `ValidationError` in DynamoDB, and does not page. If the only red thing is `dlq-not-empty` and the DLQ messages are all `ValidationError`, tell the uploader and purge or keep the messages as evidence.

---

## api-5xx-rate
The query API returned 5xx for more than 1% of requests in 5-minute windows (SLO: 99.9% non-5xx over 30 days).

1. Logs Insights → saved query **`inventory-pipeline/api-non-2xx`**: look at `status` and `integrationErr`.
2. Logs Insights → **`inventory-pipeline/lambda-errors`**, filtered to the API function: a Python traceback means a code bug; `AccessDenied` on DynamoDB means a permissions change.
3. Throttling? The dashboard's **throttles** line for `api`. The account's Lambda concurrency limit is low in a fresh account (10).

**Mitigate:** roll back the last change (`git revert` + `terraform apply` in `02-serverless-pipeline`, workspace `dev`).
**Recovered when:** the 5xx rate is under 1% for 15 minutes and the alarm returns to OK.

## api-latency-p95
p95 latency above 1,000 ms for 15 minutes.

1. Logs Insights → **`inventory-pipeline/slowest-invocations`**: is it `@initDuration` (cold starts) or the handler itself?
2. Logs Insights → **`inventory-pipeline/cold-starts`**: many cold starts after a quiet period are normal; sustained ones under load suggest concurrency churn.
3. X-Ray → Trace Map: the DynamoDB segment shows whether the table (scan/query pattern) is the slow part.

**Mitigate:** if DynamoDB is the bottleneck, query the `by-status` index instead of scanning; if it's Lambda, raise memory (CPU scales with it).

## pipeline-latency-p95
Upload-to-result p95 above 60 s for 15 minutes.

1. Dashboard **Lambda errors · throttles**: throttles mean Step Functions is backing off (it retries up to 10 times with jitter); results arrive late but arrive.
2. Step Functions console → a slow execution → the state with the longest duration.

**Mitigate:** a burst is self-healing; raise reserved concurrency only if this is the steady state.

## pipeline-timeouts-aborts
An execution timed out or was aborted. Bad input never causes this, so something is stuck or someone stopped executions.

1. Logs Insights → **`inventory-pipeline/failed-executions`**.
2. CloudTrail (org trail, Logs Insights on `/aws/cloudtrail/org-trail`): `eventName = "StopExecution"` shows who aborted.

**Mitigate:** re-run the affected uploads with `scripts/redrive-dlq.sh` once the cause is fixed.

## system-lambda-errors
The `analyze` or `api` function raised an error. (`validate` is excluded because rejecting files is its job.)

1. Logs Insights → **`inventory-pipeline/lambda-errors`**.
2. X-Ray trace for the failing request.

**Mitigate:** fix forward or revert; failed uploads land in the DLQ, so nothing is lost. Redrive afterwards: `TARGET_PROFILE=lz-dev ./scripts/redrive-dlq.sh`.

## dlq-not-empty
At least one upload ended in the dead-letter queue.

1. Dry run first (messages stay in the queue): `TARGET_PROFILE=lz-dev ./scripts/redrive-dlq.sh`
2. Each message carries `error_name`: `ValidationError` = bad input (see the note at the top); anything else = system failure, so fix it, then redrive with `--apply`.

**Recovered when:** the DLQ is empty and the alarm returns to OK.
