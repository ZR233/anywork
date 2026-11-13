#!/usr/bin/env python3
"""Real archive round trips and fail-closed PR artifact handoff boundaries."""

from __future__ import annotations

import contextlib
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pr_quality_handoff as handoff


TOOL_FILES = {"pl-xtask": Path("target/xtask/debug/pl-xtask")}
HELPER_FILES = {
    f"{target}/{name}": Path("dist/remote-helper") / target / name
    for target in ("x86_64-unknown-linux-musl", "aarch64-unknown-linux-musl")
    for name in (
        "pl-remote-helper",
        "pl-remote-helper.metadata.json",
        "pl-remote-helper.sha256",
    )
}


class HandoffTest(unittest.TestCase):
    def setUp(self):
        # Local runs select the Thread's scratch; ordinary CI needs no custom path.
        self.temp = tempfile.TemporaryDirectory(
            prefix="pr-handoff-", dir=os.environ.get("PR_HANDOFF_TEST_SCRATCH")
        )
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.workspace = self.root / "producer"
        self.workspace.mkdir()
        subprocess.run(
            ["git", "init", "--quiet", str(self.workspace)], check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        subprocess.run(
            ["git", "-c", "user.name=Handoff Test",
             "-c", "user.email=handoff@example.invalid",
             "commit", "--quiet", "--allow-empty", "-m", "fixture"],
            cwd=self.workspace, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.sha = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=self.workspace, text=True
        ).strip()
        self.image = "ghcr.io/example/build@sha256:" + "a" * 64
        self.archive = self.root / "artifact.tar.gz"
        self.destination = self.root / "restored"
        self.output = self.root / "github-output"
        self.env = patch.dict(os.environ, {"GITHUB_OUTPUT": str(self.output)})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.payloads = {}
        for index, relative in enumerate(
            [*TOOL_FILES.values(), *HELPER_FILES.values()]
        ):
            path = self.workspace / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            payload = b"\x00artifact bytes\xff" + bytes([index])
            mode = 0o751 if path.name in ("pl-xtask", "pl-remote-helper") else 0o640
            path.write_bytes(payload)
            path.chmod(mode)
            self.payloads[relative] = (payload, mode)

    def cli(self, *args, workspace=None):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                code = handoff.main(
                    list(args), _workspace=workspace or self.workspace
                )
            except SystemExit as error:
                code = error.code
        return code, stdout.getvalue(), stderr.getvalue()

    def pack(self, tool=True):
        args = ["pack-tool" if tool else "pack-helpers",
                "--archive", str(self.archive), "--source-sha", self.sha]
        if tool:
            args += ["--environment", self.image]
        code, stdout, stderr = self.cli(*args)
        self.assertEqual(code, 0, stderr)
        values = dict(line.split("=", 1) for line in stdout.splitlines())
        self.assertEqual(self.output.read_text(), stdout)
        self.assertEqual(values["sourceSha"], self.sha)
        self.assertEqual(values["workspace"], str(self.workspace))
        self.assertEqual(
            values["archiveSha256"], hashlib.sha256(self.archive.read_bytes()).hexdigest()
        )
        self.assertEqual(set(values), {
            "archiveSha256", "sourceSha", "workspace",
        } | ({"environment"} if tool else set()))
        return values["archiveSha256"]

    def restore(self, digest, tool=True, workspace=None, **overrides):
        options = {
            "--archive": str(self.archive), "--sha256": digest,
            "--source-sha": self.sha, "--destination": str(self.destination),
        }
        if tool:
            options.update({
                "--workspace": str(self.workspace), "--environment": self.image,
                "--expected-environment": self.image,
            })
        options.update(overrides)
        args = ["restore-tool" if tool else "restore-helpers"]
        for name, value in options.items():
            args.extend((name, value))
        return self.cli(*args, workspace=workspace)

    def assert_rejected(self, result):
        code, _, stderr = result
        self.assertNotEqual(code, 0)
        self.assertTrue(stderr)
        self.assertFalse(self.destination.exists())

    def test_tool_and_cross_workspace_helpers_round_trip(self):
        for tool in (True, False):
            with self.subTest(tool=tool):
                self.output.unlink(missing_ok=True)
                digest = self.pack(tool)
                files = TOOL_FILES if tool else HELPER_FILES
                with tarfile.open(self.archive) as tar:
                    self.assertEqual(set(tar.getnames()), set(files))
                # Helpers may cross workspaces, but the checkout must have the same SHA.
                consumer = self.workspace
                if not tool:
                    consumer = self.root / "consumer"
                    shutil.copytree(self.workspace / ".git", consumer / ".git")
                code, _, stderr = self.restore(digest, tool, workspace=consumer)
                self.assertEqual(code, 0, stderr)
                self.assertEqual(
                    {p.relative_to(self.destination).as_posix()
                     for p in self.destination.rglob("*") if p.is_file()},
                    set(files),
                )
                for name, relative in files.items():
                    path = self.destination / name
                    data, mode = self.payloads[relative]
                    self.assertEqual(path.read_bytes(), data)
                    if os.name != "nt":
                        self.assertEqual(path.stat().st_mode & 0o777, mode)
                shutil.rmtree(self.destination)

    def test_identity_failures_leave_no_destination(self):
        digest = self.pack()
        cases = [
            {"--sha256": "0" * 64},
            {"--sha256": "invalid"},
            {"--source-sha": "0" * 40},
            {"--workspace": str(self.root / "elsewhere")},
            {"--environment": "sha256:" + "b" * 64},
            {"--expected-environment": "sha256:" + "b" * 64},
            {"--environment": "ghcr.io/example/build:latest"},
            {"--expected-environment": "ghcr.io/example/build:v1"},
            {"--environment": ""},
        ]
        for options in cases:
            with self.subTest(options=options):
                self.assert_rejected(self.restore(digest, **options))

    def test_helpers_verify_digest_and_source(self):
        digest = self.pack(False)
        for options in ({"--sha256": "0" * 64}, {"--source-sha": "0" * 40}):
            with self.subTest(options=options):
                self.assert_rejected(self.restore(digest, False, **options))

    def test_shared_test_inputs_require_exact_run_and_complete_payloads(self):
        (self.workspace / ".git/info/exclude").write_text("/target/\n/dist/\n")
        for relative in handoff._TEST_INPUTS.values():
            path = self.workspace / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"same-run " + path.name.encode())
        with patch.dict(os.environ, {"GITHUB_RUN_ID": "12345"}):
            code, stdout, stderr = self.cli(
                "pack-tests", "--archive", str(self.archive),
                "--source-sha", self.sha, "--environment", self.image,
            )
            self.assertEqual(code, 0, stderr)
            digest = dict(line.split("=", 1) for line in stdout.splitlines())["archiveSha256"]
            args = ["restore-tests", "--archive", str(self.archive),
                    "--source-sha", self.sha, "--sha256", digest,
                    "--environment", self.image, "--expected-environment", self.image,
                    "--workspace", str(self.workspace), "--destination", str(self.destination)]
            with patch.dict(os.environ, {"GITHUB_RUN_ID": "54321"}):
                self.assert_rejected(self.cli(*args))
            code, _, stderr = self.cli(*args)
            self.assertEqual(code, 0, stderr)
            identity = json.loads((self.destination / "identity.json").read_text())
            for name, expected in identity["artifacts"].items():
                self.assertEqual(hashlib.sha256((self.destination / name).read_bytes()).hexdigest(), expected["sha256"])
            shutil.rmtree(self.destination)
            # A valid outer digest cannot excuse a wrong profile or missing payload.
            with tarfile.open(self.archive) as tar:
                original = [(member, tar.extractfile(member).read()) for member in tar]
            for invalid in ("profile", "libpl_studio_bridge.so", "pl-provider-fixture"):
                with self.subTest(invalid=invalid):
                    with tarfile.open(self.archive, "w:gz") as tar:
                        for member, payload in original:
                            if member.name == invalid:
                                continue
                            member = copy.copy(member)
                            if invalid == "profile" and member.name == "identity.json":
                                identity = json.loads(payload)
                                identity["artifacts"]["pl-provider-fixture"]["profile"] = "dev"
                                payload = json.dumps(identity).encode()
                                member.size = len(payload)
                            tar.addfile(member, io.BytesIO(payload))
                    args[args.index("--sha256") + 1] = hashlib.sha256(self.archive.read_bytes()).hexdigest()
                    self.assert_rejected(self.cli(*args))

    def test_pack_rejects_missing_or_linked_inputs_before_archive(self):
        for tool, relative in (
            (True, next(iter(TOOL_FILES.values()))),
            (False, next(iter(HELPER_FILES.values()))),
        ):
            with self.subTest(tool=tool):
                path = self.workspace / relative
                payload = path.read_bytes()
                path.unlink()
                args = ["pack-tool" if tool else "pack-helpers",
                        "--archive", str(self.archive), "--source-sha", self.sha]
                if tool:
                    args += ["--environment", self.image]
                self.assertNotEqual(self.cli(*args)[0], 0)
                self.assertFalse(self.archive.exists())
                if os.name != "nt":
                    path.symlink_to(self.workspace / ".git" / "HEAD")
                    self.assertNotEqual(self.cli(*args)[0], 0)
                    self.assertFalse(self.archive.exists())
                    path.unlink()
                path.write_bytes(payload)

    def test_pack_rejects_wrong_source_and_mutable_image(self):
        for sha, image in (
            ("0" * 40, self.image),
            (self.sha, "ghcr.io/example/build:latest"),
        ):
            code, _, stderr = self.cli(
                "pack-tool", "--archive", str(self.archive),
                "--source-sha", sha, "--environment", image,
            )
            self.assertNotEqual(code, 0, stderr)
            self.assertFalse(self.archive.exists())

    def write_tar(self, extra=None, omit=False):
        with tarfile.open(self.archive, "w") as tar:
            if not omit:
                member = tarfile.TarInfo("pl-xtask")
                member.size = 4
                member.mode = 0o755
                tar.addfile(member, io.BytesIO(b"tool"))
            if extra is not None:
                member = tarfile.TarInfo(extra[0])
                member.type = extra[1]
                if member.islnk() or member.issym():
                    member.linkname = "../outside"
                tar.addfile(member, io.BytesIO(b""))
        return hashlib.sha256(self.archive.read_bytes()).hexdigest()

    def test_archive_rejects_unsafe_duplicate_extra_and_nonregular_members(self):
        cases = [
            ("../outside", tarfile.REGTYPE),
            ("/outside", tarfile.REGTYPE),
            ("C:\\outside", tarfile.REGTYPE),
            ("./pl-xtask", tarfile.REGTYPE),
            ("unwanted.o", tarfile.REGTYPE),
            ("pl-xtask", tarfile.REGTYPE),
            ("pl-xtask", tarfile.SYMTYPE),
            ("pl-xtask", tarfile.LNKTYPE),
            ("pl-xtask", tarfile.DIRTYPE),
            ("pl-xtask", tarfile.FIFOTYPE),
        ]
        for extra in cases:
            with self.subTest(extra=extra):
                # For nonregular members use the expected name without duplicates,
                # so the test is sensitive to member type rather than only names.
                digest = self.write_tar(extra, omit=extra[1] != tarfile.REGTYPE)
                self.assert_rejected(self.restore(digest))
        self.assertFalse((self.root / "outside").exists())

    def test_missing_and_truncated_archive_leave_no_destination(self):
        self.assert_rejected(self.restore(self.write_tar(omit=True)))
        digest = self.pack(False)
        self.assert_rejected(self.restore(digest))
        self.output.unlink()
        self.pack()
        with tarfile.open(self.archive, "w") as tar:
            info = tarfile.TarInfo("pl-xtask")
            info.size = 4096
            tar.addfile(info, io.BytesIO(b"x" * 4096))
        self.archive.write_bytes(self.archive.read_bytes()[:700])
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.assert_rejected(self.restore(digest))

    def test_existing_destination_is_not_overwritten(self):
        digest = self.pack()
        self.destination.mkdir()
        marker = self.destination / "keep"
        marker.write_bytes(b"original")
        self.assertNotEqual(self.restore(digest)[0], 0)
        self.assertEqual(marker.read_bytes(), b"original")
        self.assertEqual(list(self.destination.iterdir()), [marker])

    def test_id_validation(self):
        self.assertEqual(self.cli("require-id", "1", "98765")[0], 0)
        for ids in ((), ("",), ("0",), ("-1",), ("1.0",), (" 1",),
                    ("01",), ("1\n",), ("１２",), ("1", "bad")):
            with self.subTest(ids=ids):
                self.assertNotEqual(self.cli("require-id", *ids)[0], 0)

    def test_cli_locates_workspace_from_script_not_cwd_or_environment(self):
        scripts = self.workspace / ".github" / "scripts"
        scripts.mkdir(parents=True)
        script = scripts / "pr_quality_handoff.py"
        shutil.copyfile(handoff.__file__, script)
        env = dict(os.environ, GITHUB_WORKSPACE=str(self.root / "wrong"))
        result = subprocess.run(
            [sys.executable, str(script), "pack-tool",
             "--archive", str(self.archive), "--source-sha", self.sha,
             "--environment", "sha256:" + "a" * 64],
            cwd=self.root, env=env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        values = dict(line.split("=", 1) for line in result.stdout.splitlines())
        self.assertEqual(values["workspace"], str(self.workspace))
        result = subprocess.run(
            [sys.executable, str(script), "restore-tool",
             "--archive", str(self.archive), "--sha256", values["archiveSha256"],
             "--source-sha", self.sha, "--workspace", values["workspace"],
             "--environment", values["environment"],
             "--expected-environment", values["environment"],
             "--destination", str(self.destination)],
            cwd=self.root, env=env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.destination / "pl-xtask").read_bytes(),
            self.payloads[TOOL_FILES["pl-xtask"]][0],
        )


if __name__ == "__main__":
    unittest.main()
