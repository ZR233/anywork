"""Exercise cache mounts and command routing through the actual container entry."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class LinuxContainerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="container cache-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "checkout"
        self.script = self.workspace / "docker/linux/scripts/run.sh"
        self.script.parent.mkdir(parents=True)
        source = Path(__file__).resolve().parents[2] / "docker/linux/scripts/run.sh"
        shutil.copyfile(source, self.script)
        binary = self.root / "bin"
        binary.mkdir()
        docker = binary / "docker"
        docker.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "print(json.dumps(sys.argv[1:]))\n"
            "sys.exit(int(os.environ.get('DOCKER_EXIT', '0')))\n"
        )
        docker.chmod(0o755)
        self.environment = dict(os.environ, PATH=f"{binary}{os.pathsep}{os.environ['PATH']}")
        self.environment.pop("CARGO_HOME", None)
        self.environment.pop("PURE_REMOTE_HELPER_PREBUILT_DIR", None)
        self.environment.pop("ANYWORK_CONTAINER_TMPFS", None)

    def run_container(self):
        return subprocess.run(
            ["bash", str(self.script), "build-image", "cargo", "test", "a b"],
            cwd=self.root,
            env=self.environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_external_cache_is_created_and_shared_at_the_same_path(self):
        cache = self.root / "external cache"
        self.environment["CARGO_HOME"] = str(cache)
        result = self.run_container()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = json.loads(result.stdout)
        self.assertTrue(cache.is_dir())
        self.assertFalse(cache.is_relative_to(self.workspace))
        self.assertIn(f"type=bind,src={cache},dst={cache}", arguments)
        self.assertIn(f"CARGO_HOME={cache}", arguments)
        self.assertIn(f"type=bind,src={self.workspace},dst={self.workspace}", arguments)
        self.assertEqual(arguments[-4:], ["build-image", "cargo", "test", "a b"])
        self.environment["DOCKER_EXIT"] = "23"
        self.assertEqual(self.run_container().returncode, 23)

    def test_default_invocation_keeps_the_image_cache_and_only_mounts_source(self):
        result = self.run_container()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = json.loads(result.stdout)
        self.assertEqual(arguments.count("--mount"), 1)
        self.assertFalse(any(value.startswith("CARGO_HOME=") for value in arguments))
        self.assertNotIn("--tmpfs", arguments)

    def test_tmpfs_is_mounted_when_requested(self):
        self.environment["ANYWORK_CONTAINER_TMPFS"] = "1"
        result = self.run_container()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = json.loads(result.stdout)
        index = arguments.index("--tmpfs")
        self.assertEqual(arguments[index + 1], "/tmp:rw,exec,nosuid,size=2g")


class LinuxBuildHandoffTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix="image handoff-", dir=os.environ.get("PR_HANDOFF_TEST_SCRATCH")
        )
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.workspace = Path(__file__).resolve().parents[2]
        self.calls = self.root / "docker.jsonl"
        self.output = self.root / "github-env"
        binary = self.root / "bin"
        binary.mkdir()
        docker = binary / "docker"
        docker.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "calls = Path(os.environ['DOCKER_CALLS'])\n"
            "with calls.open('a') as log:\n"
            "    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "if sys.argv[1] == 'pull':\n"
            "    attempts = sum(json.loads(line)[0] == 'pull' for line in calls.read_text().splitlines())\n"
            "    if attempts <= int(os.environ['DOCKER_PULL_FAILURES']):\n"
            "        print('read: connection reset by peer', file=sys.stderr)\n"
            "        sys.exit(23)\n"
            "elif sys.argv[1:3] == ['image', 'inspect']:\n"
            "    print(os.environ['IMAGE_KEY'])\n"
            "else:\n"
            "    sys.exit(97)\n"
        )
        docker.chmod(0o755)
        sleep = binary / "sleep"
        sleep.write_text("#!/usr/bin/env bash\nexit 0\n")
        sleep.chmod(0o755)
        key = subprocess.check_output(
            ["python3", "docker/linux/scripts/image-key.py"],
            cwd=self.workspace, text=True,
        ).strip()
        self.image = "ghcr.io/zr233/anywork-linux-build@sha256:" + "a" * 64
        self.environment = dict(
            os.environ, PATH=f"{binary}{os.pathsep}{os.environ['PATH']}",
            LINUX_IMAGE_REF=self.image, IMAGE_KEY=key,
            DOCKER_CALLS=str(self.calls), GITHUB_ENV=str(self.output),
        )

    def run_handoff(self, failures):
        self.calls.unlink(missing_ok=True)
        self.output.unlink(missing_ok=True)
        return subprocess.run(
            ["bash", ".github/scripts/linux-build-handoff.sh"],
            cwd=self.workspace,
            env=dict(self.environment, DOCKER_PULL_FAILURES=str(failures)),
            text=True, capture_output=True, check=False,
        )

    def commands(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_success_and_transient_failures_restore_the_same_digest(self):
        for failures in (0, 1, 2):
            with self.subTest(failures=failures):
                result = self.run_handoff(failures)
                self.assertEqual(result.returncode, 0, result.stderr)
                pulls = [args for args in self.commands() if args[0] == "pull"]
                self.assertEqual(pulls, [["pull", self.image]] * (failures + 1))
                self.assertEqual(
                    self.output.read_text(), f"LINUX_BUILD_IMAGE={self.image}\n"
                )

    def test_persistent_failure_returns_the_original_error_without_export(self):
        result = self.run_handoff(3)
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(self.commands(), [["pull", self.image]] * 3)
        self.assertIn("connection reset by peer", result.stderr)
        self.assertFalse(self.output.exists())

    def test_download_success_does_not_retry_or_accept_an_identity_mismatch(self):
        self.environment["IMAGE_KEY"] = "0" * 64
        result = self.run_handoff(0)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([args[0] for args in self.commands()], ["pull", "image"])
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
