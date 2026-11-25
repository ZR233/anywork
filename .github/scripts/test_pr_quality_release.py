#!/usr/bin/env python3
"""Exercise release-only routing with real Git histories and GitHub event data."""

from __future__ import annotations

import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pr_quality_changes import OUTPUT_FLAGS, changed_paths, plan_for_event  # noqa: E402


class ReleaseRoutingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._class_temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls._class_temp.cleanup)
        cls._template = Path(cls._class_temp.name) / "repository"
        cls._template.mkdir()
        cls._git(cls._template, "init", "-q", "-b", "main")
        cls._git(cls._template, "config", "user.name", "Test Author")
        cls._git(cls._template, "config", "user.email", "test@example.invalid")
        cls._write(cls._template, "release-please-config.json", json.dumps({
            "changelog-path": "CHANGELOG.md",
            "packages": {".": {
                "component": "studio",
                "version-file": "studio-version.txt",
                "extra-files": [
                    {"type": "generic", "path": "code/anywork/pubspec.yaml"},
                    {
                        "type": "yaml", "path": "code/anywork_previews/pubspec.lock",
                        "jsonpath": "$.packages.anywork.version",
                    },
                ],
            }},
        }))
        cls._write(cls._template, "CHANGELOG.md", "# Changelog\n")
        cls._write_version(cls._template, "1.2.0")
        cls._base = cls._commit(cls._template, "initial")
        cls._write_version(cls._template, "1.3.0")
        cls._write(cls._template, "CHANGELOG.md", "# Changelog\n\n## 1.3.0\n")
        cls._head = cls._commit(cls._template, "release")

    @staticmethod
    def _git(cwd, *args):
        return subprocess.check_output(
            ["git", *args], cwd=cwd, stderr=subprocess.PIPE, text=True
        ).strip()

    @staticmethod
    def _write(root, name, content):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    @classmethod
    def _write_version(cls, root, version):
        cls._write(root, ".release-please-manifest.json", json.dumps({".": version}) + "\n")
        cls._write(root, "studio-version.txt", version + "\n")
        cls._write(
            root,
            "code/anywork/pubspec.yaml",
            f"name: anywork\nversion: {version} # x-release-please-version\ndependencies:\n  foo: 1.0.0\n",
        )
        cls._write(
            root,
            "code/anywork_previews/pubspec.lock",
            f"packages:\n  anywork:\n    source: path\n    version: {version}\n"
            "  foo:\n    source: hosted\n    version: 1.0.0\n",
        )

    @classmethod
    def _commit(cls, cwd, message):
        cls._git(cwd, "add", "-A")
        cls._git(cwd, "commit", "-qm", message)
        return cls._git(cwd, "rev-parse", "HEAD")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repository"
        shutil.copytree(self._template, self.root)
        self.base = self._base
        self.head = self._head
        self.pull = {
            "number": 42,
            "state": "closed",
            "merged_at": "2026-01-01T00:00:00Z",
            "merge_commit_sha": self.head,
            "user": {"login": "owner"},
            "base": {"ref": "main", "sha": self.base, "repo": {"full_name": "owner/repo"}},
            "head": {
                "ref": "release-please--branches--main--components--studio",
                "sha": self.head,
                "repo": {"full_name": "owner/repo"},
            },
        }
        self.event_path = Path(self.temporary.name) / "event.json"

    def git(self, *args):
        return self._git(self.root, *args)

    def write(self, name, content):
        self._write(self.root, name, content)

    def commit(self, message):
        return self._commit(self.root, message)

    def plan(self, *, event="pull_request", base=None, head=None, pull=None, ref=None):
        base = base or self.base
        head = head or self.head
        self.event_path.write_text(json.dumps({"pull_request": pull or self.pull}), encoding="utf-8")
        return plan_for_event(
            changed_paths(base, head, git_dir=str(self.root)) or [],
            event_name=event,
            base=base,
            head=head,
            repository="owner/repo",
            ref=ref or ("refs/heads/main" if event == "push" else "refs/pull/42/merge"),
            event_path=str(self.event_path),
            git_dir=str(self.root),
        )

    def assert_release_skipped(self, plan):
        self.assertTrue(plan["release_only"])
        self.assertEqual(plan["required_jobs"], ("changes",))
        self.assertFalse(any(plan[flag] for flag in OUTPUT_FLAGS))

    def test_release_pull_request_and_merged_push_skip_quality(self):
        self.assert_release_skipped(self.plan())
        with patch("pr_quality_release._associated_pull_requests", return_value=[self.pull]):
            self.assert_release_skipped(self.plan(event="push"))

    def test_pull_request_checks_identity_and_source_sha(self):
        for keys, value in (
            (("head", "ref"), "ordinary-branch"),
            (("head", "repo", "full_name"), "fork/repo"),
            (("base", "ref"), "other"),
            (("user", "login"), "other"),
            (("head", "sha"), "0" * 40),
        ):
            with self.subTest(keys=keys):
                pull = copy.deepcopy(self.pull)
                item = pull
                for key in keys[:-1]:
                    item = item[key]
                item[keys[-1]] = value
                self.assertFalse(self.plan(pull=pull)["release_only"])

    def test_pull_request_accepts_the_real_merge_test_commit(self):
        self.git("switch", "--detach", self.base)
        self.write("README.md", "new mainline commit\n")
        base = self.commit("mainline change")
        self.git("merge", "--no-ff", "--no-edit", self.head)
        merged = self.git("rev-parse", "HEAD")
        pull = copy.deepcopy(self.pull)
        pull["base"]["sha"] = base
        self.assert_release_skipped(self.plan(base=base, head=merged, pull=pull))

    def test_classifier_entrypoint_writes_release_outputs(self):
        self.event_path.write_text(json.dumps({"pull_request": self.pull}), encoding="utf-8")
        output_path = Path(self.temporary.name) / "output"
        environment = {
            **os.environ,
            "EVENT_NAME": "pull_request",
            "BASE_SHA": self.base,
            "HEAD_SHA": self.head,
            "GITHUB_REPOSITORY": "owner/repo",
            "GITHUB_REF": "refs/pull/42/merge",
            "GITHUB_EVENT_PATH": str(self.event_path),
            "GITHUB_OUTPUT": str(output_path),
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        script = Path(__file__).with_name("pr_quality_changes.py")
        subprocess.run([sys.executable, str(script)], cwd=self.root, env=environment, check=True, capture_output=True)
        output = dict(line.split("=", 1) for line in output_path.read_text().splitlines())
        self.assertEqual(output["release_only"], "true")
        self.assertEqual(output["required_jobs"], "changes")
        self.assertTrue(all(output[flag] == "false" for flag in OUTPUT_FLAGS))

    def test_non_version_changes_inside_release_files_keep_checks(self):
        for name, old, new in (
            ("code/anywork/pubspec.yaml", "foo: 1.0.0", "foo: 2.0.0"),
            ("code/anywork_previews/pubspec.lock", "version: 1.0.0", "version: 2.0.0"),
            ("studio-version.txt", "1.3.0", "1.4.0"),
        ):
            with self.subTest(name=name):
                path = self.root / name
                original = path.read_text(encoding="utf-8")
                path.write_text(original.replace(old, new), encoding="utf-8")
                changed_head = self.commit("additional change")
                pull = copy.deepcopy(self.pull)
                pull["head"]["sha"] = changed_head
                plan = self.plan(head=changed_head, pull=pull)
                self.assertFalse(plan["release_only"])
                self.assertTrue(plan["flutter_checks"])
                self.git("reset", "--hard", self.head)

    def test_other_files_and_mixed_pushes_keep_their_checks(self):
        self.write("code/pl-core/src/lib.rs", "pub fn changed() {}\n")
        changed_head = self.commit("product change")
        pull = copy.deepcopy(self.pull)
        pull["head"]["sha"] = changed_head
        for event in ("pull_request", "push", "merge_group"):
            with self.subTest(event=event):
                plan = self.plan(event=event, head=changed_head, pull=pull)
                self.assertFalse(plan["release_only"])
                self.assertTrue(plan["rust_checks"])

    def test_multiple_commits_must_all_belong_to_the_same_release(self):
        self.write("CHANGELOG.md", "# Changelog\n\n## 1.3.0\nMore notes.\n")
        final_head = self.commit("more release notes")
        release = copy.deepcopy(self.pull)
        release["merge_commit_sha"] = final_head
        other = copy.deepcopy(release)
        other["number"] = 43
        with patch("pr_quality_release._associated_pull_requests", return_value=[release]):
            self.assert_release_skipped(self.plan(event="push", head=final_head))
        with patch("pr_quality_release._associated_pull_requests", side_effect=[[release], [other]]):
            self.assertFalse(self.plan(event="push", head=final_head)["release_only"])

    def test_unknown_association_or_merge_group_keeps_checks(self):
        for association in ([], [dict(self.pull, merged_at=None)], [dict(self.pull, merge_commit_sha=self.base)]):
            with self.subTest(association=association):
                with patch("pr_quality_release._associated_pull_requests", return_value=association):
                    self.assertFalse(self.plan(event="push")["release_only"])
        with patch("pr_quality_release._associated_pull_requests", side_effect=OSError("unavailable")):
            self.assertFalse(self.plan(event="push")["release_only"])
        self.assertFalse(self.plan(event="merge_group")["release_only"])


if __name__ == "__main__":
    unittest.main()
