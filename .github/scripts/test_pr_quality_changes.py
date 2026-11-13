#!/usr/bin/env python3
"""Behavioral classes for PR Quality Gate path classification."""

from __future__ import annotations

from io import StringIO
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pr_quality_changes import (  # noqa: E402
    OUTPUT_FLAGS,
    classify_path,
    parse_name_status,
    plan_from_paths,
    write_github_output,
)


class PlanFromPathsTest(unittest.TestCase):
    def plan(self, *paths, event="pull_request"):
        return plan_from_paths(paths, event_name=event)

    def enabled(self, plan):
        return {name for name in OUTPUT_FLAGS if plan[name]}

    def test_documentation_and_collaboration_do_not_build_products(self):
        for path in (
            "design/24-testing.md",
            "reports/pr-263/migration.md",
            "README.md",
            "AGENTS.md",
            "./.agents/skills/test-quality/SKILL.md",
            ".agents/skills/test-quality/agents/openai.yaml",
            ".claude/skills/slint/SKILL.md",
            "code/pl-core/README.md",
            "code/tools/filesystem/README.md",
            "code/anywork_client/README.md",
            "docker/linux/README.md",
        ):
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertEqual(self.enabled(plan), {"docs_policy"})
                self.assertEqual(
                    plan["required_jobs"],
                    ("changes", "docs-policy", "pr-title"),
                )

    def test_push_and_merge_queue_do_not_require_a_pr_title(self):
        for event in ("push", "merge_group"):
            self.assertEqual(
                self.plan("design/README.md", event=event)["required_jobs"],
                ("changes", "docs-policy"),
            )

    def test_release_metadata_and_scripts_do_not_build_products(self):
        for path in (
            "studio-version.txt",
            ".release-please-manifest.json",
            "release-please-config.json",
            ".github/workflows/studio-release.yml",
            ".github/scripts/studio-release-assets.ps1",
        ):
            with self.subTest(path=path):
                self.assertEqual(
                    self.enabled(self.plan(path)), {"release_configuration"}
                )
        plan = self.plan("studio-version.txt", "CHANGELOG.md")
        self.assertEqual(self.enabled(plan), {"release_configuration", "docs_policy"})

    def test_rust_production_keeps_platform_builds(self):
        for path in (
            "code/pl-core/src/lib.rs",
            "code/tools/filesystem/src/lib.rs",
            "code/pl-studio-runtime/assets/skills/office/SKILL.md",
            "code/pl-studio-runtime/assets/README.md",
        ):
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertEqual(self.enabled(plan), {
                    "rust_checks", "linux_environment", "linux_inputs",
                    "remote_helpers", "windows_build", "macos_build",
                    "windows_gui_build", "macos_gui_build",
                })
                self.assertIn("linux-inputs", plan["required_jobs"])

    def test_rust_tests_and_their_support_need_no_gui_or_bundled_helpers(self):
        for path in (
            "code/pl-core/tests/chat_page.rs",
            "code/pl-core/tests/support/mod.rs",
            "code/pl-core/tests/fixtures/history.json",
            "code/tools/filesystem/tests/mutation.rs",
            "code/tools/fixtures/downstream/tests/media_execution.rs",
            "code/anywork/rust/tests/chat.rs",
            "rustfmt.toml",
        ):
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertEqual(self.enabled(plan), {
                    "rust_checks", "linux_environment", "windows_build", "macos_build",
                })
                self.assertNotIn("linux-inputs", plan["required_jobs"])
        # Names alone do not prove that Rust excludes a module from production.
        for path in (
            "code/pl-core/Cargo.toml",
            "code/pl-core/src/chat/tests.rs",
            "code/pl-core/src/chat/tests/mod.rs",
            "code/pl-studio-runtime/src/session/mod.rs",
            "code/anywork/rust/src/api/studio/handlers/chat.rs",
        ):
            self.assertTrue(self.plan(path)["windows_gui_build"])

    def test_ui_tests_and_adapter_tests_only_need_the_app_suite(self):
        for path in (
            "code/anywork/test/ui/composer_button_matrix_test.dart",
            "code/anywork/test/unit/frb_adapter/frb_timeline_adapter_test.dart",
            "code/anywork/analysis_options.yaml",
            "code/anywork/dart_test.yaml",
            "code/anywork_previews/lib/src/features/shell/previews/sidebar_previews.dart",
        ):
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertEqual(self.enabled(plan), {"flutter_checks", "linux_environment"})
                self.assertIn("flutter-checks", plan["required_jobs"])

    def test_client_tests_are_independent_but_shared_inputs_check_the_app(self):
        for path in (
            "code/anywork_client/test/timeline_tail_test.dart",
            "code/anywork_client/analysis_options.yaml",
        ):
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertEqual(self.enabled(plan), {"client_checks", "linux_environment"})
                # Both frontend selections are consumed by one workflow job.
                self.assertEqual(plan["required_jobs"].count("flutter-checks"), 1)
        for path in (
            "code/anywork_client/lib/studio_client.dart",
            "code/anywork_client/test/support/accounts_test_runtime.dart",
            "code/anywork_client/test/support/directory_feed.dart",
            "code/anywork_client/pubspec.yaml",
            "code/anywork_client/pubspec.lock",
        ):
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertEqual(self.enabled(plan), {
                    "client_checks", "flutter_checks", "linux_environment",
                })
                self.assertEqual(plan["required_jobs"].count("flutter-checks"), 1)

    def test_generator_configuration_needs_tool_but_not_helpers(self):
        plan = self.plan("code/anywork/build.yaml")
        self.assertEqual(self.enabled(plan), {
            "flutter_checks", "gui_generated", "linux_inputs", "linux_environment",
        })
        self.assertIn("gui-generated", plan["required_jobs"])
        self.assertIn("linux-inputs", plan["required_jobs"])

    def test_app_dependencies_keep_native_compilation(self):
        for path in ("code/anywork/pubspec.yaml", "code/anywork/pubspec.lock"):
            plan = self.plan(path)
            self.assertTrue(plan["flutter_checks"])
            self.assertTrue(plan["gui_generated"])
            self.assertTrue(plan["linux_desktop"])
            self.assertTrue(plan["linux_native"])
            self.assertTrue(plan["windows_gui_build"])
            self.assertTrue(plan["macos_gui_build"])
            self.assertFalse(plan["client_checks"])
            self.assertFalse(plan["rust_checks"])

    def test_platform_directory_changes_stay_on_that_platform(self):
        for path, selected in (
            ("code/anywork/linux/CMakeLists.txt", {"linux_desktop", "linux_native"}),
            ("code/anywork/windows/runner/main.cpp", {"windows_build", "windows_gui_build"}),
            ("code/anywork/macos/Runner/AppDelegate.swift", {"macos_build", "macos_gui_build"}),
        ):
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertEqual(self.enabled(plan), selected | {
                    "flutter_checks", "linux_inputs", "remote_helpers", "linux_environment",
                })

    def test_shared_runner_and_bridge_include_their_integration_consumers(self):
        for path in (
            "code/anywork/runner_common/window.cpp",
            "code/anywork/lib/src/app/frb_startup_host.dart",
            "code/anywork/lib/src/infrastructure/frb/api.dart",
        ):
            with self.subTest(path=path):
                plan = self.plan(path)
                for name in (
                    "flutter_checks", "linux_desktop", "linux_native",
                    "windows_gui_build", "macos_gui_build", "remote_helpers",
                    "linux_inputs", "linux_environment",
                ):
                    self.assertTrue(plan[name], name)
                self.assertFalse(plan["client_checks"])
                self.assertFalse(plan["rust_checks"])
        rust_bridge = self.plan("code/anywork/rust/src/api.rs")
        self.assertTrue(rust_bridge["rust_checks"])
        self.assertTrue(rust_bridge["gui_generated"])

    def test_desktop_and_native_suites_keep_distinct_scope(self):
        desktop = self.plan("code/anywork/integration_test/message_submission_test.dart")
        self.assertTrue(desktop["linux_desktop"])
        self.assertFalse(desktop["linux_native"])
        self.assertFalse(desktop["gui_generated"])
        native = self.plan("code/anywork/lib/src/app/studio_host_lifecycle.dart")
        self.assertTrue(native["linux_native"])
        self.assertFalse(native["linux_desktop"])
        self.assertFalse(native["gui_generated"])
        self.assertTrue(native["windows_gui_build"])
        self.assertTrue(native["macos_gui_build"])

    def test_mixed_paths_union_responsibilities(self):
        paths = [
            "code/pl-core/tests/chat_page.rs",
            "code/pl-core/src/lib.rs",
            "code/anywork/test/ui/example_test.dart",
            "code/anywork_client/test/timeline_tail_test.dart",
            "design/24-testing.md",
            "studio-version.txt",
        ]
        expected = set().union(*(self.enabled(self.plan(path)) for path in paths))
        plan = self.plan(*paths)
        self.assertEqual(self.enabled(plan), expected)
        self.assertEqual(len(plan["required_jobs"]), len(set(plan["required_jobs"])))

    def test_shared_ci_fixtures_and_unknown_inputs_remain_full(self):
        for paths in (
            [],
            ["not-a-known-tree/file"],
            [".github/workflows/pr-quality.yml"],
            ["docker/linux/Dockerfile"],
            ["Cargo.lock"],
            ["code/anywork_previews/analysis_options.yaml"],
            ["code/anywork_previews/pubspec.lock"],
            ["code/anywork_previews/pubspec.yaml"],
            ["code/pl-provider-fixture/src/lib.rs"],
            ["code/pl-studio-acceptance/src/manual_gui/mod.rs"],
            ["xtask/src/test_project.rs", "design/24-testing.md"],
        ):
            with self.subTest(paths=paths):
                plan = self.plan(*paths)
                self.assertEqual(self.enabled(plan), set(OUTPUT_FLAGS))
                self.assertEqual(plan["required_jobs"].count("flutter-checks"), 1)

    def test_output_exposes_both_frontend_selections_to_workflow(self):
        stream = StringIO()
        write_github_output(self.plan("code/anywork_client/test/query_test.dart"), stream)
        output = dict(line.split("=", 1) for line in stream.getvalue().splitlines())
        self.assertEqual(output["client_checks"], "true")
        self.assertEqual(output["flutter_checks"], "false")
        self.assertEqual(output["remote_helpers"], "false")
        self.assertIn("flutter-checks", output["required_jobs"].split(","))


class ChangedPathsTest(unittest.TestCase):
    def test_moves_include_source_and_destination_responsibilities(self):
        paths = parse_name_status([
            "R100", "code/pl-core/tests/old.rs", "code/anywork/integration_test/new_test.dart",
            "M", "design/24-testing.md",
        ])
        self.assertEqual(paths, [
            "code/pl-core/tests/old.rs", "code/anywork/integration_test/new_test.dart",
            "design/24-testing.md",
        ])
        plan = plan_from_paths(paths, event_name="push")
        self.assertTrue(plan["rust_checks"])
        self.assertTrue(plan["linux_desktop"])
        self.assertTrue(plan["docs_policy"])
        self.assertFalse(plan["linux_native"])

    def test_documentation_renames_and_copies_stay_light(self):
        paths = parse_name_status([
            "R100", "design/a.md", "design/b.md",
            "C060", "README.md", "code/pl-core/README.md",
        ])
        plan = plan_from_paths(paths, event_name="push")
        self.assertEqual(plan["plan"], "docs-only")
        self.assertEqual(plan["required_jobs"], ("changes", "docs-policy"))

    def test_incomplete_or_unmerged_diff_is_not_a_safe_skip(self):
        for parts in (
            ["R100", "design/a.md"],
            ["M"],
            ["U", "README.md"],
            ["X", "README.md"],
            ["", "README.md"],
            ["C100", "README.md", ""],
        ):
            with self.subTest(parts=parts):
                self.assertIsNone(parse_name_status(parts))
        self.assertEqual(
            parse_name_status(["D", "design/old.md", "A", "design/new.md"]),
            ["design/old.md", "design/new.md"],
        )
        self.assertEqual(classify_path("mystery.bin"), frozenset({"unknown"}))


if __name__ == "__main__":
    unittest.main()
