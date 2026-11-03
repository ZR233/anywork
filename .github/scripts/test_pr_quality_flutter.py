"""Exercise the CI wrapper's discovery, dependency boundary and failure routing."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("pr-quality-flutter.sh")


class FlutterEntryPointTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pr quality flutter-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        script = self.root / ".github/scripts/pr-quality-flutter.sh"
        script.parent.mkdir(parents=True)
        shutil.copyfile(SCRIPT, script)
        self.script = script
        for package, suite in [
            ("anywork_client", "test"),
            ("anywork", "test/ui"),
        ]:
            directory = self.root / "code" / package
            (directory / suite).mkdir(parents=True)
            (directory / "pubspec.lock").write_text("# fixture\n")
            (directory / suite / "example_test.dart").write_text("// fixture\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        fake_sdk = """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["SDK_CALLS"], "a") as log:
    log.write(json.dumps([tool, args, os.getcwd()]) + "\\n")
if f"{tool} {' '.join(args)}" == os.environ.get("FAIL_COMMAND"):
    sys.exit(23)
if args == ["pub", "deps", "--json"]:
    print(os.environ["DEPENDENCIES_JSON"])
"""
        for tool in ("dart", "flutter"):
            executable = self.bin / tool
            executable.write_text(fake_sdk)
            executable.chmod(0o755)
        self.calls = self.root / "calls.jsonl"
        self.environment = {
            **os.environ,
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "SDK_CALLS": str(self.calls),
            "FAIL_COMMAND": "",
        }

    def run_entry(self, data=None, *arguments):
        if data is None:
            data = {
                "root": "anywork_client",
                "packages": [{
                    "name": "anywork_client",
                    "kind": "root",
                    "directDependencies": [],
                    "dependencies": ["test"],
                    "devDependencies": ["test"],
                }],
            }
        self.environment["DEPENDENCIES_JSON"] = json.dumps(data)
        self.calls.unlink(missing_ok=True)
        return subprocess.run(
            ["bash", str(self.script), *arguments],
            cwd=self.bin,  # Root discovery must not depend on the caller's cwd.
            env=self.environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def sdk_calls(self):
        if not self.calls.exists():
            return []
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_package_cwds_and_single_locked_resolution(self):
        result = self.run_entry()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.sdk_calls()
        self.assertEqual(len(calls), 11)
        for tool, args, cwd in calls:
            package = "anywork_client" if tool == "dart" and (
                args[:2] in (["pub", "get"], ["pub", "deps"])
                or args[0] in ("analyze", "test")
                or args == ["format", "--output=none", "--set-exit-if-changed",
                            "lib", "test"]
            ) else "anywork"
            self.assertEqual(Path(cwd), self.root / "code" / package)
        self.assertEqual(
            [tool for tool, args, _ in calls
             if args == ["pub", "get", "--enforce-lockfile"]],
            ["dart", "flutter"],
        )
        self.assertEqual(calls[-1][0:2],
                         ["flutter", ["test", "--no-pub", "test/ui"]])
        boundary_calls = [args for _, args, _ in calls
                          if args[0].startswith("--packages=")]
        self.assertEqual(len(boundary_calls), 2)
        self.assertNotIn("--ui-closure", boundary_calls[0])
        self.assertIn("--ui-closure", boundary_calls[1])

    def test_invalid_runtime_dependency_shapes_stop_before_checks(self):
        root = {"name": "anywork_client", "kind": "root",
                "directDependencies": []}
        cases = [
            [],
            {"root": "anywork_client"},
            {"root": "anywork_client", "packages": {}},
            {"root": "anywork_client", "packages": ["invalid"]},
            {"root": "other", "packages": [root]},
            {"root": "anywork_client", "packages": []},
            {"root": "anywork_client", "packages": [root, root]},
            {"root": "anywork_client", "packages": [
                {**root, "name": "other"}]},
        ]
        for dependencies in (None, {}, "", ["flutter"]):
            package = dict(root)
            if dependencies is None:
                del package["directDependencies"]
            else:
                package["directDependencies"] = dependencies
            cases.append({"root": "anywork_client", "packages": [package]})
        for data in cases:
            with self.subTest(data=data):
                result = self.run_entry(data)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Client SDK-only boundary failed", result.stderr)
                self.assertEqual(len(self.sdk_calls()), 2)

    def test_missing_locks_directories_and_empty_suites_fail_before_sdk(self):
        for package, suite in [
            ("anywork_client", "test"),
            ("anywork", "test/ui"),
        ]:
            directory = self.root / "code" / package
            targets = [
                directory / "pubspec.lock",
                directory / suite / "example_test.dart",
                directory / suite,
            ]
            for target in targets:
                with self.subTest(target=target):
                    saved = target.with_name(target.name + ".saved")
                    target.rename(saved)
                    try:
                        result = self.run_entry()
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn("required", result.stderr)
                        self.assertEqual(self.sdk_calls(), [])
                    finally:
                        saved.rename(target)

    def test_sdk_failure_propagates_without_later_steps(self):
        self.environment["FAIL_COMMAND"] = "dart analyze --fatal-infos"
        result = self.run_entry()
        self.assertEqual(result.returncode, 23)
        self.assertEqual(self.sdk_calls()[-1][1], ["analyze", "--fatal-infos"])
        self.assertTrue(all(tool == "dart" for tool, _, _ in self.sdk_calls()))

    def test_dependency_command_failure_cannot_pass_the_pipeline(self):
        self.environment["FAIL_COMMAND"] = "dart pub deps --json"
        result = self.run_entry()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.sdk_calls()), 2)

    def test_arguments_are_rejected_before_sdk(self):
        result = self.run_entry(None, "--compat")
        self.assertEqual(result.returncode, 64)
        self.assertEqual(self.sdk_calls(), [])


if __name__ == "__main__":
    unittest.main()
