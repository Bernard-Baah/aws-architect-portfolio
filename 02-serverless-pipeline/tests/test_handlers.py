"""Unit tests for the Lambda handlers. Run from the repo root:

    python3 -m unittest discover -s 02-serverless-pipeline/tests -v
"""

import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "src" / name / "handler.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


validate = load("validate")
analyze = load("analyze")


class ValidateTests(unittest.TestCase):
    def test_accepts_csv(self):
        self.assertTrue(validate.validate({"key": "incoming/a.csv", "size": 10})["ok"])

    def test_case_insensitive_suffix(self):
        self.assertTrue(validate.validate({"key": "incoming/A.CSV", "size": 10})["ok"])

    def test_rejects_other_types(self):
        with self.assertRaises(validate.ValidationError):
            validate.validate({"key": "incoming/a.txt", "size": 10})

    def test_rejects_empty(self):
        with self.assertRaises(validate.ValidationError):
            validate.validate({"key": "incoming/a.csv", "size": 0})

    def test_rejects_too_large(self):
        with self.assertRaises(validate.ValidationError):
            validate.validate({"key": "incoming/a.csv", "size": validate.MAX_BYTES + 1})

    def test_error_name_is_what_step_functions_matches(self):
        # The workflow's Retry/Catch match on this exact name.
        self.assertEqual(validate.ValidationError.__name__, "ValidationError")


class AnalyzeTests(unittest.TestCase):
    def sample(self, name):
        return (ROOT / "samples" / name).read_text(encoding="utf-8")

    def test_clean_file(self):
        r = analyze.analyze_csv(self.sample("rack-inventory-clean.csv"))
        self.assertEqual(r["row_count"], 10)
        self.assertEqual(r["rack_count"], 2)
        self.assertEqual(r["issue_count"], 0)
        self.assertEqual(r["result"], "clean")
        self.assertEqual(r["status_counts"], {"in_service": 8, "spare": 1, "staged": 1})

    def test_issues_file_finds_every_problem(self):
        r = analyze.analyze_csv(self.sample("rack-inventory-issues.csv"))
        joined = "\n".join(r["issues_sample"])
        self.assertEqual(r["row_count"], 8)
        self.assertEqual(r["result"], "needs_review")
        self.assertIn("DC1-00302 has no serial_number", joined)
        self.assertIn("both in R03 U2", joined)              # two devices in one U
        self.assertIn("invalid rack_unit '52'", joined)        # beyond U48
        self.assertIn("unknown status 'broken'", joined)
        self.assertIn("asset_tag DC1-00301 appears 2 times", joined)
        self.assertEqual(r["issue_count"], 5)

    def test_decommissioned_devices_do_not_occupy_a_unit(self):
        text = "asset_tag,serial_number,rack,rack_unit,model,status\n" \
               "A1,S1,R1,5,M,decommissioned\nA2,S2,R1,5,M,in_service\n"
        self.assertEqual(analyze.analyze_csv(text)["issue_count"], 0)

    def test_header_is_case_and_space_insensitive(self):
        text = " Asset_Tag ,Serial_Number,RACK,rack_unit,model,Status\nA1,S1,R1,1,M,spare\n"
        self.assertEqual(analyze.analyze_csv(text)["issue_count"], 0)

    def test_missing_columns_raise_schema_error(self):
        with self.assertRaises(analyze.SchemaError) as ctx:
            analyze.analyze_csv("asset_tag,rack\nA1,R1\n")
        self.assertIn("serial_number", str(ctx.exception))

    def test_empty_file_raises_schema_error(self):
        with self.assertRaises(analyze.SchemaError):
            analyze.analyze_csv("")

    def test_issue_sample_is_capped(self):
        rows = "\n".join(f"A{i},,R1,{i % 48 + 1},M,spare" for i in range(30))
        r = analyze.analyze_csv("asset_tag,serial_number,rack,rack_unit,model,status\n" + rows)
        self.assertEqual(len(r["issues_sample"]), analyze.ISSUE_SAMPLE_SIZE)
        self.assertGreater(r["issue_count"], analyze.ISSUE_SAMPLE_SIZE)


if __name__ == "__main__":
    unittest.main()
