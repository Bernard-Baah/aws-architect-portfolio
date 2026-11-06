# 02 · Serverless event-driven pipeline

> **Status:** 🚧 In progress: pipeline and query API built; burst test next

## Problem
_Data center teams export rack inventories as CSV files, and bad rows (duplicate asset tags, missing
serials, two devices in the same rack unit) cause real problems on the floor. Every upload should be
checked automatically, at any burst size, with failures captured instead of lost, and no servers to run._

## Architecture
```
S3 incoming/*.csv ──EventBridge──▶ Step Functions (Standard)
                                   │
                                   ├─ Prepare        Pass: doc_id = key#etag
                                   ├─ Validate       Lambda: type and size (bad files are not retried)
                                   ├─ RecordReceived DynamoDB PutItem, conditional (idempotent)
                                   ├─ Analyze        Lambda: parse CSV, find data-quality issues
                                   ├─ StoreResult    DynamoDB UpdateItem (direct integration)
                                   └─ Notify         SNS Publish (direct integration)
                     any failure ─▶ MarkFailed (DynamoDB) ─▶ SendToDLQ (SQS) ─▶ Fail
                     DLQ depth > 0 ─▶ CloudWatch alarm ─▶ SNS

caller ──SigV4──▶ API Gateway HTTP API (IAM auth, throttled) ──▶ Lambda ──Query──▶ DynamoDB GSIs
```

### What the Analyze step checks
| Check | Example from `samples/rack-inventory-issues.csv` |
|---|---|
| Missing serial number | `DC1-00302 has no serial_number` |
| Two devices in one rack unit | `DC1-00303 and DC1-00302 both in R03 U2` |
| Rack unit outside 1–48 | `DC1-00304 has invalid rack_unit '52'` |
| Unknown status | `DC1-00305 has unknown status 'broken'` |
| Duplicate asset tag | `asset_tag DC1-00301 appears 2 times` |

Decommissioned devices don't count as occupying a rack unit.

## Build checklist
- [x] S3 bucket with EventBridge notifications + rule that starts the workflow
- [x] Step Functions workflow, Lambda steps (Python 3.13, arm64), retries + Catch → DLQ
- [x] DynamoDB (on-demand, GSI on status + created_at, PITR)
- [x] SNS completion topic (optional email) + CloudWatch alarm when the DLQ isn't empty
- [x] Least-privilege role per function, idempotency, X-Ray tracing
- [x] Unit tests: handlers + workflow structure (run in CI)
- [x] API Gateway HTTP API to query results (IAM auth, throttling, access logs, GSI queries only)
- [ ] Burst test (500 files) and DLQ redrive

## Design decisions & trade-offs
- **Step Functions direct integrations instead of Lambda glue.** Writing to DynamoDB, publishing to SNS
  and sending to SQS are done by the state machine itself. Only two functions contain real logic, so
  there's less code, fewer cold starts, and one less IAM role per step.
- **Idempotency with a conditional write.** S3 → EventBridge delivery is at-least-once. `doc_id` is
  `key#etag`, and `RecordReceived` uses `attribute_not_exists(doc_id)`. A repeated event ends in the
  `Duplicate` state, while a *new version* of the same file name (new ETag) is processed again.
- **Retry only what can succeed on retry.** Lambda service errors and DynamoDB throttling are retried
  with exponential backoff and full jitter. `ValidationError` and `SchemaError` go straight to the DLQ,
  because a bad file stays bad.
- **Nothing is dropped.** Workflow failures go to the DLQ with full context (event, document, error),
  and the item is marked `FAILED`. EventBridge has its own retry policy and dead-letter config pointing
  at the same queue, in case it can't start the workflow at all.
- **Standard, not Express, workflows.** Standard gives exactly-once execution and a visual history of
  every run, which is useful for audits. Express is cheaper at very high volume (thousands per second)
  but at-least-once.
- **SNS topic not KMS-encrypted.** CloudWatch alarms can't publish to a topic using the AWS-managed
  `alias/aws/sns` key. Production would use a customer-managed key whose policy allows
  `cloudwatch.amazonaws.com`.
- **Query API with IAM (SigV4) auth.** It's an internal operations API, so only identities in this AWS
  account can call it. HTTP APIs don't support API keys, and an external audience would get a Cognito
  JWT authorizer. The route is throttled (10 requests/s, burst 20) and every call is access-logged
  with the caller's ARN.
- **Queries, never scans.** `GET /documents?key=` uses the `by-key` index and `?status=` uses
  `by-status`, both newest first with opaque `next` tokens for pagination. The API returns only
  public fields (no execution ARNs or bucket names) and can only `Query`/`GetItem` this table.
- **Least privilege:** `analyze` can read only `incoming/*`; `validate` reads nothing; the workflow can
  invoke only these two functions and write only to this table, topic and queue. Service roles carry
  `aws:SourceAccount` conditions (confused-deputy protection).

## Run it
```bash
cd 02-serverless-pipeline
terraform init -backend-config="bucket=bernard-tfstate-40b007"
terraform apply
./scripts/run-samples.sh
```
Optional email alerts: `terraform apply -var="notification_email=you@example.com"`, then click the
confirmation link AWS emails you.

Expected:
| File | Status | Why |
|---|---|---|
| `rack-inventory-clean.csv` | `COMPLETE` | 10 rows, 2 racks, 0 issues |
| `rack-inventory-issues.csv` | `COMPLETE` | 8 rows, 5 issues (listed by the script) |
| `not-a-csv.txt` | `FAILED` (`ValidationError`) | 1 message in the DLQ, DLQ alarm fires |

Query the results over the API (SigV4-signed with your current AWS sign-in):
```bash
./scripts/query-api.sh 'status=FAILED'
./scripts/query-api.sh 'status=COMPLETE&limit=5'
./scripts/query-api.sh 'key=incoming/<run>/rack-inventory-issues.csv'
./scripts/query-api.sh --unsigned 'status=FAILED'
```
The last one should return **403**: no credentials, no access.

Watch it run: **Step Functions → State machines → inventory-pipeline → Executions** shows each
run's path through the graph.

## Results
| Test | Measured |
|------|----------|
| Sample run (2026-11-06) | ✅ clean → `COMPLETE` (10 rows, 2 racks, 0 issues) · issues → `COMPLETE` (8 rows, **all 5 issues found**) · `.txt` → `FAILED` (`ValidationError`), 1 message in the DLQ |
| Duplicate upload (same key + same content → same ETag) | ✅ execution ended in the `Duplicate` state (`SucceedStateExited Duplicate`); stored result untouched |
| DLQ alarm | ✅ `ALARM` within about 1 minute of the bad file: "1 datapoint [1.0] was greater than the threshold (0.0)" |
| Query API: signed vs unsigned | _ |
| Burst: 500 files | _ |
| Cost per 1,000 documents | _ |

## Cost
At portfolio volume this is close to free: Lambda, Step Functions (4,000 free state transitions per
month), DynamoDB on-demand and S3 are all billed per request. About 7 transitions per file means
roughly 570 files per month inside the free tier. The DLQ alarm costs $0.10/month. Nothing bills while
idle, so `terraform destroy` is optional here.

## Tests
```bash
python3 -m unittest discover -s 02-serverless-pipeline/tests -v
```
31 tests: the validate and analyze handlers against the sample files; the query API with a fake table
(right index, newest first, internal fields hidden, pagination round-trip, input validation); and
structural checks on the Step Functions definition (every transition valid, every state reachable,
failures routed to the DLQ, validation errors never retried, DynamoDB reserved words aliased).
