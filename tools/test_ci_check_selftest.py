"""Regression tests for the CI Godot log and process checker."""

import tempfile
import unittest
from pathlib import Path

from ci_check_selftest import check_log_file, check_log_text


def successful_log(*extra_lines: str) -> str:
    return "\n".join((
        "SELFTEST start",
        "SELFTEST suite start: equipmentintegration",
        "PASS: equipment fixture",
        "SELFTEST suite done: equipmentintegration",
        "SELFTEST done",
        *extra_lines,
        "",
    ))


class SelfTestLogCheckerTests(unittest.TestCase):
    def test_clean_successful_run(self):
        self.assertEqual(check_log_text(successful_log(), 0, "equipmentintegration"), [])

    def test_failed_assertion_before_completion(self):
        log = successful_log().replace("PASS: equipment fixture", "[FAIL] expected damage")
        self.assertTrue(any("[FAIL]" in failure for failure in check_log_text(log, 0, "equipmentintegration")))

    def test_failed_assertion_after_completion(self):
        failures = check_log_text(successful_log("[FAIL] late assertion"), 0, "equipmentintegration")
        self.assertTrue(any("[FAIL] late assertion" in failure for failure in failures))

    def test_error_after_completion(self):
        failures = check_log_text(successful_log("ERROR: synthetic fatal engine error after marker"), 0, "equipmentintegration")
        self.assertTrue(any("ERROR: synthetic fatal engine error after marker" in failure for failure in failures))

    def test_script_error_after_completion(self):
        failures = check_log_text(successful_log("SCRIPT ERROR: synthetic script failure after marker"), 0, "equipmentintegration")
        self.assertTrue(any("SCRIPT ERROR:" in failure for failure in failures))

    def test_missing_completion_marker(self):
        log = successful_log().replace("SELFTEST done\n", "")
        self.assertTrue(any("never printed" in failure for failure in check_log_text(log, 0, "equipmentintegration")))

    def test_recognized_benign_shutdown_leaks_after_completion(self):
        log = successful_log(
            "WARNING: ObjectDB instances leaked at exit (run with --verbose for details).",
            "ERROR: 3 resources still in use at exit (run with --verbose for details).",
            "ERROR: 2 RID allocations of type 'RendererDummy' were leaked at exit.",
        )
        self.assertEqual(check_log_text(log, 0, "equipmentintegration"), [])

    def test_unexpected_shutdown_error(self):
        failures = check_log_text(successful_log("ERROR: unexpected shutdown failure"), 0, "equipmentintegration")
        self.assertTrue(any("unexpected shutdown failure" in failure for failure in failures))

    def test_nonzero_process_exit_code(self):
        failures = check_log_text(successful_log(), 1, "equipmentintegration")
        self.assertTrue(any("nonzero process exit code 1" in failure for failure in failures))

    def test_timeout(self):
        failures = check_log_text(successful_log(), 124, "equipmentintegration")
        self.assertTrue(any("timed out" in failure for failure in failures))

    def test_missing_focused_suite_execution_marker(self):
        log = successful_log().replace("SELFTEST suite done: equipmentintegration\n", "")
        failures = check_log_text(log, 0, "equipmentintegration")
        self.assertTrue(any("did not report execution completion" in failure for failure in failures))

    def test_missing_focused_suite_log(self):
        with tempfile.TemporaryDirectory() as directory:
            missing_log = Path(directory) / "missing-suite.log"
            failures = check_log_file(str(missing_log), 0, "equipmentintegration")
            self.assertTrue(any("cannot read" in failure for failure in failures))

    def test_original_codex_synthetic_failing_log_is_rejected(self):
        original_log = (
            "SELFTEST done\n"
            "ERROR: synthetic fatal engine error after marker\n"
            "SCRIPT ERROR: synthetic failure after marker\n"
        )
        failures = check_log_text(original_log, 0)
        self.assertTrue(any("ERROR:" in failure for failure in failures))
        self.assertTrue(any("SCRIPT ERROR:" in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()
