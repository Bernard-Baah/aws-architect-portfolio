# 02 · Serverless event-driven pipeline

> **Status:** ⏳ Planned

## Problem
_Process uploaded documents (incident reports, rack inventory CSVs) reliably and at any burst size, with no servers to manage._

## Architecture
S3 upload → EventBridge → Step Functions (validate → extract → enrich → store) → DynamoDB → SNS.
API Gateway HTTP API + Lambda for queries. SQS dead-letter queue for failures. X-Ray tracing throughout.

_Diagram: `docs/diagrams/02-serverless-pipeline.png`_

## Build checklist
- [ ] S3 bucket with EventBridge notifications + rule that starts the workflow
- [ ] Step Functions workflow, Lambda steps (Python), retries + Catch → DLQ
- [ ] DynamoDB (on-demand, GSI on status + created_at, PITR)
- [ ] API Gateway HTTP API with Cognito or API-key auth
- [ ] SNS completion topic with email + SQS fan-out
- [ ] Least-privilege role per Lambda, idempotency, Powertools logging
- [ ] Burst test (500 files) and DLQ redrive demo

## Design decisions & trade-offs
- _Step Functions vs. Lambda chaining_
- _DynamoDB vs. RDS_
- _Standard vs. Express workflows_

## Results
| Metric | Measured |
|--------|----------|
| Files processed in burst | _ |
| Lost events | _ |
| Cost per 1,000 documents | $_ |
