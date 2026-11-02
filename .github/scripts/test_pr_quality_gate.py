#!/usr/bin/env python3
"""ci-gate accepts only plan-allowed skips and fails closed otherwise."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pr_quality_gate import evaluate  # noqa: E402


def _results(**overrides: str) -> dict[str, str]:
    results = {
        "changes": "success",
        "docs-policy": "skipped",
        "pr-title": "skipped",
        "release-configuration": "skipped",
        "rust-quality": "skipped",
        "rust-deterministic": "skipped",
        "linux-environment": "skipped",
        "studio-server-linux": "skipped",
        "flutter-quality": "skipped",
        "macos-desktop": "skipped",
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
            ["changes", "rust-quality", "rust-deterministic", "linux-environment", "studio-server-linux"],
            _results(
                **{
                    "rust-quality": "failure",
                    "rust-deterministic": "skipped",
                    "linux-environment": "skipped",
                    "studio-server-linux": "skipped",
                }
            ),
        )
        self.assertTrue(any("linux-environment" in item for item in errors))
        self.assertTrue(any("studio-server-linux" in item for item in errors))
        self.assertTrue(any("rust-quality" in item for item in errors))

    def test_cancelled_required_job_fails(self):
        errors = evaluate(
            ["changes", "flutter-quality"],
            _results(**{"flutter-quality": "cancelled"}),
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
            _results(**{"docs-policy": "success", "macos-desktop": "cancelled"}),
        )
        self.assertTrue(any("macos-desktop" in item for item in errors))

    def test_empty_required_jobs_fails(self):
        errors = evaluate([], _results())
        self.assertTrue(any("required_jobs" in item for item in errors))

    def test_missing_result_string_is_not_success(self):
        errors = evaluate(
            ["changes", "docs-policy"],
            _results(**{"docs-policy": ""}),
        )
        self.assertTrue(any("docs-policy" in item for item in errors))


if __name__ == "__main__":
    unittest.main()
