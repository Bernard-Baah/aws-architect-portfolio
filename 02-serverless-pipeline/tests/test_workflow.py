"""Structural checks on the Step Functions definition, run before Terraform ever
sends it to AWS. Renders the template the way Terraform's templatefile() does.

    python3 -m unittest discover -s 02-serverless-pipeline/tests -v
"""

import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
TEMPLATE_VARS = {
    "validate_function_arn": "arn:aws:lambda:us-east-1:111111111111:function:validate",
    "analyze_function_arn": "arn:aws:lambda:us-east-1:111111111111:function:analyze",
    "table_name": "documents",
    "topic_arn": "arn:aws:sns:us-east-1:111111111111:topic",
    "dlq_url": "https://sqs.us-east-1.amazonaws.com/111111111111/dlq",
}


def render():
    raw = (ROOT / "workflow.asl.json").read_text()
    used = set(re.findall(r"(?<!\$)\$\{(\w+)\}", raw))
    missing = used - TEMPLATE_VARS.keys()
    assert not missing, f"template variables not supplied by Terraform: {missing}"
    rendered = re.sub(r"(?<!\$)\$\{(\w+)\}", lambda m: TEMPLATE_VARS[m.group(1)], raw)
    return json.loads(rendered), used


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.asl, cls.used_vars = render()
        cls.states = cls.asl["States"]

    def targets(self, state):
        out = []
        if "Next" in state:
            out.append(state["Next"])
        out += [c["Next"] for c in state.get("Catch", [])]
        return out

    def test_template_uses_exactly_the_terraform_variables(self):
        self.assertEqual(self.used_vars, set(TEMPLATE_VARS))

    def test_every_transition_points_to_a_real_state(self):
        for name, state in self.states.items():
            for t in self.targets(state):
                self.assertIn(t, self.states, f"{name} -> {t}")

    def test_every_state_is_reachable(self):
        seen, todo = set(), [self.asl["StartAt"]]
        while todo:
            s = todo.pop()
            if s not in seen:
                seen.add(s)
                todo += self.targets(self.states[s])
        self.assertEqual(seen, set(self.states))

    def test_non_terminal_states_have_a_next(self):
        for name, state in self.states.items():
            if state["Type"] not in ("Succeed", "Fail") and not state.get("End"):
                self.assertIn("Next", state, name)

    def test_every_risky_task_routes_failures_to_the_dlq_path(self):
        for name in ("Validate", "RecordReceived", "Analyze", "StoreResult"):
            catches = [c for c in self.states[name]["Catch"] if "States.ALL" in c["ErrorEquals"]]
            self.assertEqual(len(catches), 1, name)
            self.assertEqual(catches[0]["Next"], "MarkFailed", name)

    def test_validation_errors_are_not_retried(self):
        # A bad file stays bad: only Lambda service errors are retried.
        for retry in self.states["Validate"]["Retry"]:
            self.assertNotIn("ValidationError", retry["ErrorEquals"])
            self.assertNotIn("States.ALL", retry["ErrorEquals"])

    def test_duplicates_are_caught_before_the_generic_catch(self):
        catches = self.states["RecordReceived"]["Catch"]
        self.assertEqual(catches[0]["ErrorEquals"], ["DynamoDB.ConditionalCheckFailedException"])
        self.assertEqual(catches[0]["Next"], "Duplicate")

    def test_failure_path_ends_in_fail_state(self):
        self.assertEqual(self.states["MarkFailed"]["Next"], "SendToDLQ")
        self.assertEqual(self.states["SendToDLQ"]["Next"], "ProcessingFailed")
        self.assertEqual(self.states["ProcessingFailed"]["Type"], "Fail")

    def test_reserved_words_are_aliased_in_update_expressions(self):
        # 'status' and 'result' are DynamoDB reserved words.
        for name in ("StoreResult", "MarkFailed"):
            expr = self.states[name]["Parameters"]["UpdateExpression"]
            self.assertNotRegex(expr, r"\bstatus\s*=", name)
            self.assertNotRegex(expr, r"\bresult\s*=", name)

    def test_update_expression_placeholders_are_all_defined(self):
        for name in ("StoreResult", "MarkFailed"):
            p = self.states[name]["Parameters"]
            expr = p["UpdateExpression"]
            for ph in set(re.findall(r":\w+", expr)):
                self.assertIn(ph, p["ExpressionAttributeValues"], f"{name}: {ph}")
            for ph in set(re.findall(r"#\w+", expr)):
                self.assertIn(ph, p["ExpressionAttributeNames"], f"{name}: {ph}")


if __name__ == "__main__":
    unittest.main()
