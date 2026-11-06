"""Unit tests for the query API handler, with a fake DynamoDB table.

boto3 isn't needed: a minimal stand-in for boto3.dynamodb.conditions.Key is
installed before the handler imports it.
"""

import importlib.util
import json
import pathlib
import sys
import types
import unittest
from decimal import Decimal

ROOT = pathlib.Path(__file__).resolve().parents[1]


class FakeCondition:
    def __init__(self, name, value):
        self.name, self.value = name, value

    def __eq__(self, other):
        return isinstance(other, FakeCondition) and (self.name, self.value) == (other.name, other.value)


class FakeKey:
    def __init__(self, name):
        self.name = name

    def eq(self, value):
        return FakeCondition(self.name, value)


if "boto3" not in sys.modules:
    conditions = types.ModuleType("boto3.dynamodb.conditions")
    conditions.Key = FakeKey
    sys.modules.update({
        "boto3": types.ModuleType("boto3"),
        "boto3.dynamodb": types.ModuleType("boto3.dynamodb"),
        "boto3.dynamodb.conditions": conditions,
    })

spec = importlib.util.spec_from_file_location("api", ROOT / "src" / "api" / "handler.py")
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


class FakeTable:
    def __init__(self, items, last_key=None):
        self.items, self.last_key, self.calls = items, last_key, []

    def query(self, **kwargs):
        self.calls.append(kwargs)
        page = {"Items": self.items}
        if self.last_key:
            page["LastEvaluatedKey"] = self.last_key
        return page


def event(params=None, route="GET /documents"):
    return {"routeKey": route, "queryStringParameters": params}


ITEM = {
    "doc_id": "incoming/a.csv#abc",
    "object_key": "incoming/a.csv",
    "status": "COMPLETE",
    "created_at": "2026-11-06T22:39:30Z",
    "row_count": Decimal("8"),
    "issue_count": Decimal("5"),
    "analysis": json.dumps({"issues_sample": ["x"]}),
    "execution_arn": "arn:aws:states:...:execution:...",  # internal, must not leak
    "bucket": "internal-bucket-name",
}


class ApiTests(unittest.TestCase):
    def call(self, params, table=None):
        table = table or FakeTable([ITEM])
        res = api.handle(event(params), table)
        return res["statusCode"], json.loads(res["body"]), table

    def test_query_by_key_uses_key_index_newest_first(self):
        status, body, table = self.call({"key": "incoming/a.csv"})
        self.assertEqual(status, 200)
        q = table.calls[0]
        self.assertEqual(q["IndexName"], "by-key")
        self.assertEqual(q["KeyConditionExpression"], FakeKey("object_key").eq("incoming/a.csv"))
        self.assertFalse(q["ScanIndexForward"])

    def test_query_by_status_is_case_insensitive(self):
        status, _, table = self.call({"status": "failed"})
        self.assertEqual(status, 200)
        self.assertEqual(table.calls[0]["IndexName"], "by-status")
        self.assertEqual(table.calls[0]["KeyConditionExpression"], FakeKey("status").eq("FAILED"))

    def test_numbers_and_analysis_are_returned_as_json(self):
        _, body, _ = self.call({"status": "COMPLETE"})
        item = body["items"][0]
        self.assertEqual(item["row_count"], 8)
        self.assertEqual(item["analysis"], {"issues_sample": ["x"]})

    def test_internal_fields_are_not_exposed(self):
        _, body, _ = self.call({"status": "COMPLETE"})
        self.assertNotIn("execution_arn", body["items"][0])
        self.assertNotIn("bucket", body["items"][0])

    def test_pagination_round_trip(self):
        last = {"doc_id": "d", "status": "FAILED", "created_at": "t"}
        _, body, _ = self.call({"status": "FAILED"}, FakeTable([ITEM], last_key=last))
        _, _, table = self.call({"status": "FAILED", "next": body["next"]})
        self.assertEqual(table.calls[0]["ExclusiveStartKey"], last)

    def test_limit_default_and_bounds(self):
        _, _, table = self.call({"status": "FAILED"})
        self.assertEqual(table.calls[0]["Limit"], api.DEFAULT_LIMIT)
        _, _, table = self.call({"status": "FAILED", "limit": "100"})
        self.assertEqual(table.calls[0]["Limit"], 100)
        for bad in ("0", "101", "-1", "ten"):
            self.assertEqual(self.call({"status": "FAILED", "limit": bad})[0], 400, bad)

    def test_bad_requests(self):
        for params in (None, {}, {"key": "a", "status": "FAILED"}, {"status": "DONE"},
                       {"status": "FAILED", "next": "%%%not-base64%%%"}):
            self.assertEqual(self.call(params)[0], 400, params)

    def test_unknown_route_is_404(self):
        res = api.handle(event({"status": "FAILED"}, route="POST /documents"), FakeTable([]))
        self.assertEqual(res["statusCode"], 404)


if __name__ == "__main__":
    unittest.main()
