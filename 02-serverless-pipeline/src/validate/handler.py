"""Step 1: cheap checks on the uploaded object before any processing.

Input (from the workflow's Prepare state):
    {"bucket": "...", "key": "incoming/x.csv", "size": 1234, "etag": "...", "doc_id": "..."}

Raises ValidationError for files the pipeline should reject. Step Functions
sees the exception class name as the error name, so the workflow does not
retry these (a bad file stays bad) and routes them straight to the DLQ.
"""

MAX_BYTES = 5 * 1024 * 1024
ALLOWED_SUFFIXES = (".csv",)


class ValidationError(Exception):
    """The uploaded object is not something this pipeline accepts."""


def validate(doc):
    key = doc.get("key", "")
    size = int(doc.get("size", 0))

    if not key.lower().endswith(ALLOWED_SUFFIXES):
        raise ValidationError(f"unsupported file type: {key!r} (expected .csv)")
    if size == 0:
        raise ValidationError(f"empty file: {key!r}")
    if size > MAX_BYTES:
        raise ValidationError(f"file too large: {size} bytes (limit {MAX_BYTES})")

    return {"ok": True, "key": key, "size": size}


def handler(event, _context):
    return validate(event)
