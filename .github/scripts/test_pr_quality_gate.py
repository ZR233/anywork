#!/usr/bin/env python3
"""ci-gate accepts only plan-allowed skips and fails closed otherwise."""

from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pr_quality_gate import evaluate  # noqa: E402
from pr_quality_changes import plan_from_paths  # noqa: E402


def _results(**overrides: str) -> dict[str, str]:
    results = {
        "changes": "success",
        "docs-policy": "skipped",
        "pr-title": "skipped",
        "release-configuration": "skipped",
        "rust-checks": "skipped",
        "platform-rust-checks": "skipped",
        "linux-environment": "skipped",
        "flutter-checks": "skipped",
        "gui-generated": "skipped",
        "linux-inputs": "skipped",
        "remote-helpers": "skipped",
        "linux-test-inputs": "skipped",
        "linux-desktop": "skipped",
        "linux-native": "skipped",
        "pages-preview": "skipped",
        "rust-scale": "skipped",
    }
    results.update(overrides)
    return results


class GateEvaluateTest(unittest.TestCase):
    def test_design_only_success(self):
        errors = evaluate(
            ["changes", "docs-policy", "pr-title"],
            _results(**{"docs-policy": "success", "pr-title": "success"}),
        )
        self.assertEqual(errors, [])

    def test_required_skip_from_upstream_fails(self):
        errors = evaluate(
            ["changes", "rust-checks", "linux-environment"],
            _results(
                **{
                    "rust-checks": "failure",
                    "linux-environment": "skipped",
                }
            ),
        )
        self.assertTrue(any("linux-environment" in item for item in errors))
        self.assertTrue(any("rust-checks" in item for item in errors))

    def test_cancelled_required_job_fails(self):
        errors = evaluate(
            ["changes", "flutter-checks"],
            _results(**{"flutter-checks": "cancelled"}),
        )
        self.assertTrue(any("cancelled" in item for item in errors))

    def test_missing_changes_fails(self):
        errors = evaluate(["docs-policy"], _results(changes="failure"))
        self.assertTrue(any("changes" in item for item in errors))

    def test_allowed_skip_is_accepted(self):
        errors = evaluate(
            ["changes", "docs-policy"],
            _results(**{"docs-policy": "success"}),
        )
        self.assertEqual(errors, [])

    def test_cancelled_optional_job_fails(self):
        errors = evaluate(
            ["changes", "docs-policy"],
            _results(**{"docs-policy": "success", "platform-rust-checks": "cancelled"}),
        )
        self.assertTrue(any("platform-rust-checks" in item for item in errors))

    def test_empty_required_jobs_fails(self):
        errors = evaluate([], _results())
        self.assertTrue(any("required_jobs" in item for item in errors))

    def test_missing_result_string_is_not_success(self):
        errors = evaluate(
            ["changes", "docs-policy"],
            _results(**{"docs-policy": ""}),
        )
        self.assertTrue(any("docs-policy" in item for item in errors))

    def test_optional_planned_job_skip_passes(self):
        errors = evaluate(["changes", "flutter-checks"], _results(
            **{"flutter-checks": "success", "linux-inputs": "skipped"}
        ))
        self.assertEqual(errors, [])

    def test_gui_generation_requires_helpers_only_for_application_suites(self):
        for path, needs_helpers in (
            ("code/anywork/lib/src/infrastructure/frb/api.dart", True),
            (
                "code/anywork/lib/src/features/settings/accounts/view_models/account_editor_view_model.dart",
                False,
            ),
            ("code/anywork/lib/l10n/app_zh.arb", False),
        ):
            with self.subTest(path=path):
                plan = plan_from_paths([path], event_name="pull_request")
                required = plan["required_jobs"]
                self.assertIn("gui-generated", required)
                self.assertIn("linux-inputs", required)
                self.assertEqual("remote-helpers" in required, needs_helpers)
                results = _results(**{job: "success" for job in required})
                self.assertEqual(evaluate(required, results), [])
                for status in ("skipped", "failure"):
                    errors = evaluate(required, {**results, "gui-generated": status})
                    self.assertTrue(any("gui-generated" in error for error in errors))

    def test_desktop_and_native_required_jobs_reject_skip_or_cancel(self):
        for path, job in (
            ("code/anywork/integration_test/smoke_test.dart", "linux-desktop"),
            ("code/pl-model/src/lib.rs", "linux-desktop"),
            ("code/anywork/lib/src/app/studio_host_lifecycle.dart", "linux-native"),
        ):
            plan = plan_from_paths([path], event_name="push")
            required = plan["required_jobs"]
            self.assertIn(job, required)
            self.assertIn("linux-test-inputs", required)
            results = _results(**{item: "success" for item in required})
            self.assertEqual(evaluate(required, results), [])
            for status in ("skipped", "cancelled"):
                with self.subTest(job=job, status=status):
                    errors = evaluate(required, {**results, job: status})
                    self.assertTrue(any(job in error for error in errors))
            for status in ("skipped", "cancelled", "failure", ""):
                with self.subTest(input_status=status):
                    errors = evaluate(required, {**results, "linux-test-inputs": status})
                    self.assertTrue(any("linux-test-inputs" in error for error in errors))

    def test_gate_requires_successful_remote_helpers_for_desktop_and_native(self):
        for path in (
            "code/anywork/integration_test/smoke_test.dart",
            "code/anywork/lib/src/app/studio_host_lifecycle.dart",
        ):
            required = plan_from_paths([path], event_name="push")["required_jobs"]
            results = _results(**{job: "success" for job in required})
            base_env = {
                f"{job.upper().replace('-', '_')}_RESULT": result
                for job, result in results.items()
                if job != "remote-helpers"
            }
            base_env["REQUIRED_JOBS"] = ",".join(required)
            for status in ("success", "failure", "skipped", "cancelled", None):
                with self.subTest(path=path, helper_status=status):
                    env = base_env.copy()
                    if status is not None:
                        env["REMOTE_HELPERS_RESULT"] = status
                    result = subprocess.run(
                        [sys.executable, Path(__file__).with_name("pr_quality_gate.py")],
                        env=env,
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    expected = 0 if status == "success" else 1
                    self.assertEqual(result.returncode, expected, result.stderr or result.stdout)
                    if expected:
                        self.assertIn("remote-helpers", result.stderr)

    def test_selected_platform_and_specialized_jobs_must_succeed(self):
        for path, job in (
            ("code/pl-core/src/lib.rs", "platform-rust-checks"),
            ("site/build.py", "pages-preview"),
            (".github/workflows/rust-scale.yml", "rust-scale"),
        ):
            required = plan_from_paths([path], event_name="pull_request")["required_jobs"]
            self.assertIn(job, required)
            results = _results(**{name: "success" for name in required})
            self.assertEqual(evaluate(required, results), [])
            for status in ("skipped", "failure"):
                with self.subTest(job=job, status=status):
                    errors = evaluate(required, {**results, job: status})
                    self.assertTrue(any(job in error for error in errors))

if __name__ == "__main__":
    unittest.main()
