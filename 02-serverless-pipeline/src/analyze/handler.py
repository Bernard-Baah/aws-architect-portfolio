"""Step 2: read a rack-inventory CSV from S3 and report data-quality issues.

Expected columns (header row, any order, extra columns ignored):
    asset_tag, serial_number, rack, rack_unit, model, status

Checks the kinds of problems that cause real trouble on a data center floor:
  - duplicate asset tags
  - missing serial numbers
  - rack_unit that isn't a whole number from 1 to 48
  - two devices claiming the same rack + rack unit
  - unknown status values

Returns a JSON-serializable summary that the workflow stores in DynamoDB.
"""

import csv
import io
from collections import Counter

REQUIRED_COLUMNS = ("asset_tag", "serial_number", "rack", "rack_unit", "model", "status")
KNOWN_STATUSES = {"in_service", "spare", "rma", "staged", "decommissioned"}
MAX_RACK_UNIT = 48
ISSUE_SAMPLE_SIZE = 10


class SchemaError(Exception):
    """The CSV is missing required columns or has no header."""


def analyze_csv(text):
    reader = csv.DictReader(io.StringIO(text))
    header = [h.strip().lower() for h in (reader.fieldnames or [])]
    missing = [c for c in REQUIRED_COLUMNS if c not in header]
    if missing:
        raise SchemaError(f"missing required columns: {', '.join(missing)}")
    reader.fieldnames = header  # normalized names for row access

    issues = []
    tags = Counter()
    positions = {}
    racks = set()
    statuses = Counter()
    rows = 0

    for line_no, row in enumerate(reader, start=2):  # line 1 is the header
        rows += 1
        tag = (row.get("asset_tag") or "").strip()
        serial = (row.get("serial_number") or "").strip()
        rack = (row.get("rack") or "").strip()
        unit_raw = (row.get("rack_unit") or "").strip()
        status = (row.get("status") or "").strip().lower()

        if tag:
            tags[tag] += 1
        else:
            issues.append(f"line {line_no}: missing asset_tag")
        if not serial:
            issues.append(f"line {line_no}: {tag or '?'} has no serial_number")
        if rack:
            racks.add(rack)

        if not unit_raw.isdigit() or not 1 <= int(unit_raw) <= MAX_RACK_UNIT:
            issues.append(f"line {line_no}: {tag or '?'} has invalid rack_unit {unit_raw!r}")
        elif rack and status != "decommissioned":
            pos = (rack, int(unit_raw))
            if pos in positions:
                issues.append(f"line {line_no}: {tag or '?'} and {positions[pos]} both in {rack} U{unit_raw}")
            else:
                positions[pos] = tag or "?"

        statuses[status or "(blank)"] += 1
        if status not in KNOWN_STATUSES:
            issues.append(f"line {line_no}: {tag or '?'} has unknown status {status!r}")

    for tag, count in sorted(tags.items()):
        if count > 1:
            issues.append(f"asset_tag {tag} appears {count} times")

    return {
        "row_count": rows,
        "rack_count": len(racks),
        "status_counts": dict(sorted(statuses.items())),
        "issue_count": len(issues),
        "issues_sample": issues[:ISSUE_SAMPLE_SIZE],
        "result": "clean" if not issues else "needs_review",
    }


def handler(event, _context):
    import boto3  # lazy import keeps unit tests free of AWS dependencies

    obj = boto3.client("s3").get_object(Bucket=event["bucket"], Key=event["key"])
    text = obj["Body"].read().decode("utf-8-sig")  # tolerate Excel's BOM
    return analyze_csv(text)
