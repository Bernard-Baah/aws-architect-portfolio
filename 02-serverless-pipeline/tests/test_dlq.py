"""Unit tests for the DLQ redrive decision logic (scripts/dlq_message.py)."""

import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("dlq_message", ROOT / "scripts" / "dlq_message.py")
dlq = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dlq)

EVENT = {
    "version": "0",
    "id": "e1",
    "detail-type": "Object Created",
    "source": "aws.s3",
    "account": "111111111111",
    "time": "2026-11-06T23:00:00Z",
    "region": "us-east-1",
    "resources": ["arn:aws:s3:::bucket"],
    "detail": {"bucket": {"name": "bucket"}, "object": {"key": "incoming/r/a.csv", "size": 10, "etag": "abc"}},
}


def workflow_message(error_name):
    # What SendToDLQ writes: the whole state = event + doc + error
    return json.dumps(dict(EVENT, doc={"doc_id": "incoming/r/a.csv#abc"},
                           error={"Error": error_name, "Cause": "..."}))


class DlqDecisionTests(unittest.TestCase):
    def test_throttled_file_is_replayed_with_only_the_original_event(self):
        d = dlq.decide(workflow_message("Lambda.TooManyRequestsException"))
        self.assertEqual(d["action"], "retry")
        self.assertEqual(d["input"], EVENT)  # no doc/error fields leak into the new execution
        self.assertEqual(d["key"], "incoming/r/a.csv")

    def test_invalid_files_are_not_replayed(self):
        for err in ("ValidationError", "SchemaError"):
            d = dlq.decide(workflow_message(err))
            self.assertEqual(d["action"], "skip", err)
            self.assertIn("fix it and upload again", d["reason"])

    def test_event_that_never_started_a_workflow_is_replayed(self):
        # EventBridge's own DLQ delivery: the bare event, no "error"
        d = dlq.decide(json.dumps(EVENT))
        self.assertEqual(d["action"], "retry")
        self.assertIn("workflow never started", d["reason"])

    def test_non_s3_messages_are_skipped(self):
        d = dlq.decide(json.dumps({"source": "something.else"}))
        self.assertEqual(d["action"], "skip")


if __name__ == "__main__":
    unittest.main()
