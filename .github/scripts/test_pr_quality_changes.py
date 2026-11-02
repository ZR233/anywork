#!/usr/bin/env python3
"""Behavioral classes for PR Quality Gate path classification."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pr_quality_changes import (  # noqa: E402
    classify_path,
    parse_name_status,
    plan_from_paths,
    write_github_output,
)


class ClassifyPathTest(unittest.TestCase):
    def test_design_and_readme_are_docs(self):
        self.assertEqual(classify_path("design/24-testing.md"), frozenset({"docs"}))
        self.assertEqual(classify_path("README.md"), frozenset({"docs"}))
        self.assertEqual(classify_path("reports/pr-263/migration.md"), frozenset({"docs"}))

    def test_agents_skills_fixture_and_workflows_are_policy(self):
        self.assertIn("policy", classify_path("AGENTS.md"))
        self.assertIn("policy", classify_path(".agents/skills/test-quality/SKILL.md"))
        self.assertIn("policy", classify_path("./.agents/skills/test-quality/SKILL.md"))
        self.assertIn("policy", classify_path("code/pl-provider-fixture/src/lib.rs"))
        self.assertIn("policy", classify_path(".github/workflows/pr-quality.yml"))
        self.assertIn("policy", classify_path("xtask/src/lib.rs"))
        self.assertIn("policy", classify_path("Cargo.lock"))

    def test_unknown_root_file_is_unknown(self):
        self.assertEqual(classify_path("mystery.bin"), frozenset({"unknown"}))


class PlanFromPathsTest(unittest.TestCase):
    def test_design_only_runs_docs_policy(self):
        plan = plan_from_paths(["design/24-testing.md"], event_name="pull_request")
        self.assertEqual(plan["plan"], "docs-only")
        self.assertTrue(plan["docs_policy"])
        self.assertFalse(plan["rust_quality"])
        self.assertFalse(plan["rust_deterministic"])
        self.assertFalse(plan["linux_environment"])
        self.assertFalse(plan["flutter_quality"])
        self.assertFalse(plan["flutter_ui"])
        self.assertFalse(plan["macos_desktop"])
        self.assertEqual(
            plan["required_jobs"],
            ("changes", "docs-policy", "pr-title"),
        )

    def test_push_design_only_omits_pr_title(self):
        plan = plan_from_paths(["design/README.md"], event_name="push")
        self.assertEqual(plan["required_jobs"], ("changes", "docs-policy"))

    def test_rust_only_selects_rust_and_linux(self):
        plan = plan_from_paths(["code/pl-core/src/lib.rs"], event_name="pull_request")
        self.assertTrue(plan["rust_quality"])
        self.assertTrue(plan["rust_deterministic"])
        self.assertTrue(plan["linux_environment"])
        self.assertFalse(plan["release_configuration"])
        self.assertFalse(plan["flutter_quality"])
        self.assertFalse(plan["flutter_ui"])
        self.assertFalse(plan["macos_desktop"])
        self.assertFalse(plan["docs_policy"])
        self.assertIn("rust-quality", plan["required_jobs"])
        self.assertIn("rust-deterministic", plan["required_jobs"])
        self.assertIn("studio-server-linux", plan["required_jobs"])

    def test_ui_only_selects_flutter(self):
        plan = plan_from_paths(
            ["code/anywork/test/ui/composer_button_matrix_test.dart"],
            event_name="pull_request",
        )
        self.assertTrue(plan["flutter_quality"])
        self.assertTrue(plan["flutter_ui"])
        self.assertFalse(plan["rust_quality"])
        self.assertFalse(plan["rust_deterministic"])
        self.assertFalse(plan["linux_environment"])
        self.assertFalse(plan["macos_desktop"])
        self.assertIn("flutter-ui", plan["required_jobs"])

    def test_platform_runner_selects_desktop_and_flutter(self):
        plan = plan_from_paths(
            ["code/anywork/linux/CMakeLists.txt"],
            event_name="pull_request",
        )
        self.assertTrue(plan["flutter_quality"])
        self.assertTrue(plan["flutter_ui"])
        self.assertTrue(plan["macos_desktop"])
        self.assertTrue(plan["linux_environment"])
        self.assertFalse(plan["docs_policy"])

    def test_fixture_and_skills_force_full_suite(self):
        for path in (
            "code/pl-provider-fixture/src/lib.rs",
            ".agents/skills/test-quality/SKILL.md",
            "code/pl-studio-runtime/assets/skills/office/SKILL.md",
        ):
            plan = plan_from_paths([path], event_name="push")
            self.assertEqual(plan["plan"], "full", path)
            self.assertTrue(plan["rust_quality"], path)
            self.assertTrue(plan["rust_deterministic"], path)
            self.assertTrue(plan["flutter_quality"], path)
            self.assertTrue(plan["flutter_ui"], path)
            self.assertTrue(plan["macos_desktop"], path)

    def test_empty_or_unknown_runs_full_suite(self):
        empty = plan_from_paths([], event_name="pull_request")
        unknown = plan_from_paths(["not-a-known-tree/file"], event_name="pull_request")
        for plan in (empty, unknown):
            self.assertEqual(plan["plan"], "full")
            self.assertTrue(plan["rust_quality"])
            self.assertTrue(plan["rust_deterministic"])
            self.assertTrue(plan["flutter_quality"])
            self.assertTrue(plan["flutter_ui"])
            self.assertTrue(plan["macos_desktop"])
            self.assertTrue(plan["docs_policy"])
            self.assertIn("pr-title", plan["required_jobs"])

    def test_mixed_docs_and_rust_keeps_docs_policy(self):
        plan = plan_from_paths(
            ["design/24-testing.md", "code/pl-patch/src/lib.rs"],
            event_name="push",
        )
        self.assertTrue(plan["docs_policy"])
        self.assertTrue(plan["rust_quality"])
        self.assertTrue(plan["rust_deterministic"])
        self.assertFalse(plan["flutter_quality"])
        self.assertFalse(plan["flutter_ui"])

    def test_github_output_uses_true_false(self):
        plan = plan_from_paths(["design/01-overview.md"], event_name="push")
        from io import StringIO

        buffer = StringIO()
        write_github_output(plan, buffer)
        text = buffer.getvalue()
        self.assertIn("docs_policy=true\n", text)
        self.assertIn("rust_quality=false\n", text)
        self.assertIn("required_jobs=changes,docs-policy\n", text)

    def test_rename_or_copy_forces_full_suite(self):
        self.assertIsNone(parse_name_status(["R100", "design/a.md", "design/b.md"]))
        self.assertIsNone(parse_name_status(["C060", "README.md", "docs/README.md"]))
        self.assertEqual(parse_name_status(["M", "design/24-testing.md"]), ["design/24-testing.md"])
        self.assertEqual(
            parse_name_status(["A", "code/pl-core/src/lib.rs", "M", "README.md"]),
            ["code/pl-core/src/lib.rs", "README.md"],
        )


if __name__ == "__main__":
    unittest.main()
