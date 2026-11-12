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


if __name__ == "__main__":
    unittest.main()
