"""Read-only query API over the results table (API Gateway HTTP API, payload v2).

    GET /documents?key=incoming/run1/file.csv     every processed version of one file, newest first
    GET /documents?status=FAILED&limit=20         items by status, newest first, paginated
    GET /documents?status=FAILED&next=<token>     next page

Uses the table's GSIs (by-key, by-status), never a Scan.
"""

import base64
import json
import os
from decimal import Decimal

STATUSES = {"PROCESSING", "COMPLETE", "FAILED"}
DEFAULT_LIMIT = 20
MAX_LIMIT = 100

# Fields returned to callers (the table also holds internal ones like execution_arn)
PUBLIC_FIELDS = (
    "doc_id", "object_key", "status", "created_at", "completed_at", "failed_at",
    "row_count", "rack_count", "issue_count", "result", "analysis",
    "error_name", "error_cause",
)


class BadRequest(Exception):
    pass


def _json_default(value):
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    raise TypeError(f"not serializable: {type(value).__name__}")


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", "Cache-Control": "no-store"},
        "body": json.dumps(body, default=_json_default),
    }


def present(item):
    out = {k: item[k] for k in PUBLIC_FIELDS if k in item}
    if isinstance(out.get("analysis"), str):  # stored as a JSON string by the workflow
        try:
            out["analysis"] = json.loads(out["analysis"])
        except ValueError:
            pass
    return out


def encode_token(last_key):
    return base64.urlsafe_b64encode(json.dumps(last_key, default=_json_default).encode()).decode()


def decode_token(token):
    try:
        return json.loads(base64.urlsafe_b64decode(token.encode()))
    except (ValueError, TypeError) as exc:
        raise BadRequest("invalid 'next' token") from exc


def parse_limit(raw):
    if raw is None:
        return DEFAULT_LIMIT
    if not raw.isdigit() or not 1 <= int(raw) <= MAX_LIMIT:
        raise BadRequest(f"'limit' must be a whole number from 1 to {MAX_LIMIT}")
    return int(raw)


def build_query(params):
    """Turn query-string parameters into DynamoDB Query arguments."""
    key, status = params.get("key"), params.get("status")
    if bool(key) == bool(status):
        raise BadRequest("pass exactly one of 'key' or 'status'")

    from boto3.dynamodb.conditions import Key  # lazy: keeps unit tests AWS-free

    query = {"ScanIndexForward": False, "Limit": parse_limit(params.get("limit"))}
    if key:
        query.update(IndexName="by-key", KeyConditionExpression=Key("object_key").eq(key))
    else:
        status = status.upper()
        if status not in STATUSES:
            raise BadRequest(f"'status' must be one of {', '.join(sorted(STATUSES))}")
        query.update(IndexName="by-status", KeyConditionExpression=Key("status").eq(status))
    if params.get("next"):
        query["ExclusiveStartKey"] = decode_token(params["next"])
    return query


def handle(event, table):
    if event.get("routeKey") != "GET /documents":
        return respond(404, {"error": "not found"})
    try:
        query = build_query(event.get("queryStringParameters") or {})
    except BadRequest as exc:
        return respond(400, {"error": str(exc)})

    page = table.query(**query)
    body = {"items": [present(i) for i in page.get("Items", [])]}
    if "LastEvaluatedKey" in page:
        body["next"] = encode_token(page["LastEvaluatedKey"])
    return respond(200, body)


_table = None


def handler(event, _context):
    global _table
    if _table is None:
        import boto3

        _table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    return handle(event, _table)
