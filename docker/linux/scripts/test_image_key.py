#!/usr/bin/env python3
"""Exercise the actual CLI after copying it into an independent fixture."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


class ImageKeyTest(unittest.TestCase):
    def test_environment_changes_and_source_independence(self):
        source = Path(__file__).resolve().parents[3]
        with tempfile.TemporaryDirectory(
            prefix="anywork-image-key-", dir=os.environ.get("TMPDIR")
        ) as directory:
            root = Path(directory)
            shutil.copytree(source / "docker/linux", root / "docker/linux")
            shutil.copyfile(source / "rust-toolchain.toml", root / "rust-toolchain.toml")
            script = root / "docker/linux/scripts/image-key.py"

            def key():
                result = subprocess.check_output(
                    [sys.executable, str(script)], cwd="/", text=True
                )
                self.assertRegex(result, re.compile(r"\A[0-9a-f]{64}\n\Z"))
                return result

            baseline = key()
            for relative in ("README.md", "Cargo.lock", ".github/workflows/test.yml",
                             "code/example.rs", "docker/linux/README.md",
                             "docker/linux/scripts/test_ignored.py"):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("not an environment input\n")
                self.assertEqual(key(), baseline, relative)
            for relative in ("rust-toolchain.toml", "docker/linux/Dockerfile",
                             "docker/linux/Dockerfile.dockerignore",
                             "docker/linux/versions.env",
                             "docker/linux/scripts/run.sh",
                             "docker/linux/scripts/image-key.py"):
                path = root / relative
                original = path.read_bytes()
                path.write_bytes(original + b"\n# changed input\n")
                self.assertNotEqual(key(), baseline, relative)
                path.write_bytes(original)
                self.assertEqual(key(), baseline)
            extra = root / "docker/linux/scripts/extra.sh"
            extra.write_text("#!/bin/bash\n")
            self.assertNotEqual(key(), baseline)
            extra.unlink()
            self.assertEqual(key(), baseline)


if __name__ == "__main__":
    unittest.main()
