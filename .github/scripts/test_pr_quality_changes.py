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

    def test_bridge_and_native_paths_are_distinguished(self):
        self.assertIn("bridge", classify_path("code/pl-studio-bridge/src/lib.rs"))
        self.assertIn("native_exact", classify_path("code/anywork/tool/native_fault_main.dart"))


class PlanFromPathsTest(unittest.TestCase):
    def test_design_only_runs_docs_policy(self):
        plan = plan_from_paths(["design/24-testing.md"], event_name="pull_request")
        self.assertEqual(plan["plan"], "docs-only")
        self.assertTrue(plan["docs_policy"])
        self.assertFalse(any(plan[name] for name in (
            "rust_checks", "linux_environment", "flutter_checks", "gui_generated",
            "linux_tools", "remote_helpers", "linux_desktop", "linux_native",
            "windows_build", "macos_build",
        )))
        self.assertEqual(
            plan["required_jobs"],
            ("changes", "docs-policy", "pr-title"),
        )

    def test_push_design_only_omits_pr_title(self):
        plan = plan_from_paths(["design/README.md"], event_name="push")
        self.assertEqual(plan["required_jobs"], ("changes", "docs-policy"))

    def test_rust_only_requires_native_platform_checks_and_builds(self):
        plan = plan_from_paths(["code/pl-core/src/lib.rs"], event_name="pull_request")
        for flag in (
            "rust_checks", "linux_environment", "linux_tools",
            "remote_helpers", "windows_build", "macos_build",
        ):
            self.assertTrue(plan[flag], flag)
        self.assertFalse(plan["release_configuration"])
        self.assertFalse(plan["flutter_checks"])
        self.assertFalse(plan["gui_generated"])
        self.assertFalse(plan["linux_desktop"])
        self.assertFalse(plan["linux_native"])
        self.assertFalse(plan["docs_policy"])
        self.assertEqual(set(plan["required_jobs"]), {
            "changes", "pr-title", "rust-checks", "linux-environment",
            "linux-tools", "remote-helpers", "windows-build", "macos-build",
        })

    def test_ui_only_selects_flutter_and_its_container_without_rust_jobs(self):
        plan = plan_from_paths(
            ["code/anywork/test/ui/composer_button_matrix_test.dart"],
            event_name="pull_request",
        )
        self.assertTrue(plan["flutter_checks"])
        self.assertFalse(plan["rust_checks"])
        self.assertTrue(plan["linux_environment"])
        self.assertFalse(plan["linux_tools"])
        self.assertFalse(plan["remote_helpers"])
        self.assertFalse(plan["linux_desktop"])
        self.assertFalse(plan["linux_native"])
        self.assertFalse(plan["windows_build"])
        self.assertFalse(plan["macos_build"])
        self.assertEqual(
            plan["required_jobs"],
            ("changes", "pr-title", "linux-environment", "flutter-checks"),
        )

    def test_platform_directories_follow_platform_boundaries(self):
        expectations = {
            "code/anywork/linux/CMakeLists.txt": ("linux_desktop", "linux_native"),
            "code/anywork/windows/runner/main.cpp": ("windows_build",),
            "code/anywork/macos/Runner/AppDelegate.swift": ("macos_build",),
            "code/anywork/runner_common/window.cpp": (
                "linux_desktop", "linux_native", "windows_build", "macos_build",
            ),
            "code/anywork/integration_test/smoke_test.dart": ("linux_desktop",),
            "code/anywork/tool/inspect.dart": ("linux_desktop",),
        }
        heavy_flags = (
            "linux_desktop", "linux_native", "windows_build", "macos_build",
            "gui_generated", "rust_checks",
        )
        for path, selected in expectations.items():
            with self.subTest(path=path):
                plan = plan_from_paths([path], event_name="push")
                self.assertTrue(plan["flutter_checks"])
                self.assertEqual(
                    {name for name in heavy_flags if plan[name]},
                    set(selected),
                )
                self.assertFalse(plan["rust_checks"])

    def test_bridge_dependency_closure_and_native_exact(self):
        bridge = plan_from_paths(
            ["code/anywork/lib/src/infrastructure/frb/api.dart"],
            event_name="pull_request",
        )
        for name in (
            "flutter_checks", "gui_generated", "linux_desktop", "linux_native",
            "windows_build", "macos_build", "remote_helpers", "linux_tools",
            "linux_environment",
        ):
            self.assertTrue(bridge[name], name)
        self.assertEqual(
            set(bridge["required_jobs"]),
            {
                "changes", "pr-title", "flutter-checks", "gui-generated",
                "linux-environment", "linux-tools", "remote-helpers",
                "windows-build", "macos-build", "linux-environment",
                "linux-integration",
            },
        )
        rust_bridge = plan_from_paths(
            ["code/pl-studio-bridge/src/lib.rs"],
            event_name="push",
        )
        self.assertTrue(rust_bridge["rust_checks"])
        self.assertTrue(rust_bridge["linux_environment"])
        self.assertIn("rust-checks", rust_bridge["required_jobs"])
        rust_source = plan_from_paths(
            ["code/anywork/lib/src/rust/api.rs"],
            event_name="push",
        )
        self.assertTrue(rust_source["rust_checks"])
        self.assertTrue(rust_source["linux_environment"])
        native = plan_from_paths(
            ["code/anywork/lib/src/app/studio_host_lifecycle.dart"],
            event_name="push",
        )
        self.assertTrue(native["flutter_checks"])
        self.assertTrue(native["linux_native"])
        self.assertTrue(native["windows_build"])
        self.assertTrue(native["macos_build"])
        self.assertFalse(native["linux_desktop"])
        self.assertFalse(native["gui_generated"])

    def test_production_bridge_composition_uses_bridge_checks(self):
        for path in (
            "code/anywork/lib/src/app/frb_startup_host.dart",
            "code/anywork/lib/src/app/app_composition.dart",
        ):
            with self.subTest(path=path):
                plan = plan_from_paths([path], event_name="pull_request")
                for flag in (
                    "flutter_checks", "gui_generated", "linux_desktop",
                    "linux_native", "windows_build", "macos_build",
                    "linux_tools", "remote_helpers", "linux_environment",
                ):
                    self.assertTrue(plan[flag], flag)
                self.assertIn("linux-integration", plan["required_jobs"])
                self.assertIn("gui-generated", plan["required_jobs"])
                self.assertFalse(plan["rust_checks"])

    def test_mixed_changes_are_union_not_full(self):
        plan = plan_from_paths(
            ["code/pl-core/src/lib.rs", "code/anywork/test/ui/example_test.dart"],
            event_name="push",
        )
        self.assertTrue(plan["rust_checks"])
        self.assertTrue(plan["linux_environment"])
        self.assertTrue(plan["flutter_checks"])
        self.assertTrue(plan["windows_build"])
        self.assertTrue(plan["macos_build"])
        self.assertFalse(plan["gui_generated"])
        self.assertFalse(plan["linux_desktop"])

    def test_fixture_and_skills_force_full_suite(self):
        for path in (
            "code/pl-provider-fixture/src/lib.rs",
            ".agents/skills/test-quality/SKILL.md",
            "code/pl-studio-runtime/assets/skills/office/SKILL.md",
        ):
            plan = plan_from_paths([path], event_name="push")
            self.assertEqual(plan["plan"], "full", path)
            self.assertTrue(all(plan[name] for name in (
                "docs_policy", "release_configuration", "rust_checks",
                "linux_environment", "flutter_checks", "gui_generated",
                "linux_tools", "remote_helpers", "linux_desktop", "linux_native",
                "windows_build", "macos_build",
            )), path)

    def test_empty_or_unknown_runs_full_suite(self):
        empty = plan_from_paths([], event_name="pull_request")
        unknown = plan_from_paths(["not-a-known-tree/file"], event_name="pull_request")
        for plan in (empty, unknown):
            self.assertEqual(plan["plan"], "full")
            self.assertEqual(len(plan["required_jobs"]), len(set(plan["required_jobs"])))
            self.assertTrue(all(plan[name] for name in plan if name in {
                "docs_policy", "release_configuration", "rust_checks",
                "linux_environment", "flutter_checks", "gui_generated",
                "linux_tools", "remote_helpers", "linux_desktop", "linux_native",
                "windows_build", "macos_build",
            }))
            self.assertIn("pr-title", plan["required_jobs"])

    def test_mixed_docs_and_rust_keeps_docs_policy(self):
        plan = plan_from_paths(
            ["design/24-testing.md", "code/pl-patch/src/lib.rs"],
            event_name="push",
        )
        self.assertTrue(plan["docs_policy"])
        self.assertTrue(plan["rust_checks"])
        self.assertFalse(plan["flutter_checks"])
        self.assertFalse(plan["linux_desktop"])

    def test_github_output_uses_true_false(self):
        plan = plan_from_paths(["design/01-overview.md"], event_name="push")
        from io import StringIO

        buffer = StringIO()
        write_github_output(plan, buffer)
        text = buffer.getvalue()
        self.assertIn("docs_policy=true\n", text)
        self.assertIn("rust_checks=false\n", text)
        self.assertNotIn("flutter_ui=", text)
        self.assertNotIn("rust_quality=", text)
        self.assertIn("required_jobs=changes,docs-policy\n", text)

    def test_host_lifecycle_native_scope_excludes_desktop_and_generation(self):
        for path in (
            "code/anywork/lib/src/app/studio_host_lifecycle.dart",
            "code/anywork/tool/native_fault_main.dart",
        ):
            plan = plan_from_paths([path], event_name="push")
            self.assertTrue(plan["flutter_checks"], path)
            self.assertTrue(plan["linux_native"], path)
            self.assertTrue(plan["windows_build"], path)
            self.assertTrue(plan["macos_build"], path)
            self.assertFalse(plan["linux_desktop"], path)
            self.assertFalse(plan["gui_generated"], path)

    def test_retired_outputs_are_absent(self):
        plan = plan_from_paths(["code/anywork/lib/main.dart"], event_name="push")
        from io import StringIO

        buffer = StringIO()
        write_github_output(plan, buffer)
        for retired in ("flutter_ui", "flutter_quality", "rust_quality", "windows_native"):
            self.assertNotIn(f"{retired}=", buffer.getvalue())

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
