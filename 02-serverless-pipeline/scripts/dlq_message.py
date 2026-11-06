#!/usr/bin/env python3
"""Decide what to do with one dead-letter queue message (stdlib only).

Reads the SQS message body on stdin and prints one JSON line:
    {"action": "retry", "input": {...original S3 event...}, "key": "...", "reason": "..."}
    {"action": "skip",  "key": "...", "reason": "..."}

Two kinds of message land in the DLQ:
  1. From the workflow (SendToDLQ): the full state, i.e. the original event
     fields plus "doc" and "error".
  2. From EventBridge, when it couldn't start the workflow at all: the bare event.

Errors caused by the file itself (bad type, size or columns) are skipped:
replaying them would fail the same way. Fix the file and upload it again.
"""

import json
import sys

NON_RETRYABLE = {"ValidationError", "SchemaError"}
EVENT_FIELDS = ("version", "id", "detail-type", "source", "account", "time", "region", "resources", "detail")


def decide(body):
    msg = json.loads(body)
    event = {k: msg[k] for k in EVENT_FIELDS if k in msg}
    key = (msg.get("detail") or {}).get("object", {}).get("key", "?")

    if msg.get("source") != "aws.s3" or "detail" not in msg:
        return {"action": "skip", "key": key, "reason": "not an S3 event"}

    error = (msg.get("error") or {}).get("Error")
    if error in NON_RETRYABLE:
        return {"action": "skip", "key": key,
                "reason": f"{error}: the file itself is invalid; fix it and upload again"}
    return {"action": "retry", "key": key, "input": event,
            "reason": f"retryable ({error or 'workflow never started'})"}


if __name__ == "__main__":
    print(json.dumps(decide(sys.stdin.read())))
