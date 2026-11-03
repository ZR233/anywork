#!/usr/bin/env python3
"""ci-gate accepts only plan-allowed skips and fails closed otherwise."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pr_quality_gate import KNOWN_JOBS, evaluate  # noqa: E402
from pr_quality_changes import plan_from_paths  # noqa: E402


def _results(**overrides: str) -> dict[str, str]:
    results = {
        "changes": "success",
        "docs-policy": "skipped",
        "pr-title": "skipped",
        "release-configuration": "skipped",
        "rust-checks": "skipped",
        "linux-environment": "skipped",
        "flutter-checks": "skipped",
        "gui-generated": "skipped",
        "linux-tools": "skipped",
        "remote-helpers": "skipped",
        "linux-integration": "skipped",
        "windows-build": "skipped",
        "macos-build": "skipped",
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
            _results(**{"docs-policy": "success", "macos-build": "cancelled"}),
        )
        self.assertTrue(any("macos-build" in item for item in errors))

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
            **{"flutter-checks": "success", "linux-integration": "skipped"}
        ))
        self.assertEqual(errors, [])

    def test_rust_plan_cannot_skip_either_native_platform(self):
        plan = plan_from_paths(["code/pl-core/src/lib.rs"], event_name="push")
        results = _results(**{job: "success" for job in plan["required_jobs"]})
        self.assertEqual(evaluate(plan["required_jobs"], results), [])
        for job in ("windows-build", "macos-build"):
            with self.subTest(job=job):
                errors = evaluate(plan["required_jobs"], {**results, job: "skipped"})
                self.assertTrue(any(job in error for error in errors))

    def test_retired_jobs_are_not_known(self):
        self.assertFalse({
            "rust-quality", "rust-deterministic", "flutter-quality", "flutter-ui",
            "linux-desktop", "windows-desktop", "macos-desktop", "linux-native",
            "windows-native",
            "studio-server-linux",
        } & set(KNOWN_JOBS))


if __name__ == "__main__":
    unittest.main()
