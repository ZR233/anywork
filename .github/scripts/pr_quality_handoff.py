#!/usr/bin/env python3
"""Pack and restore same-run PR CI artifacts; never build or fetch anything."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tarfile


_TOOL = {"pl-xtask": Path("target/xtask/debug/pl-xtask")}
_HELPERS = {
    f"{target}/{name}": Path("dist/remote-helper") / target / name
    for target in ("x86_64-unknown-linux-musl", "aarch64-unknown-linux-musl")
    for name in (
        "pl-remote-helper",
        "pl-remote-helper.metadata.json",
        "pl-remote-helper.sha256",
    )
}
_IMAGE = re.compile(r"(?:ghcr\.io/[a-z0-9._/-]+@)?sha256:[0-9a-f]{64}")


def _check_source(workspace: Path, expected: str) -> None:
    actual = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=workspace,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()
    if actual != expected:
        raise ValueError(f"Source SHA mismatch in {workspace}: {actual} != {expected}")


def _check_image(image: str) -> None:
    if not _IMAGE.fullmatch(image):
        raise ValueError(f"Expected immutable image digest, got: {image}")


def _sha256(stream) -> str:
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def _publish(values: dict[str, str]) -> None:
    if any("\n" in value or "\r" in value for value in values.values()):
        raise ValueError("Artifact output identities must be single-line values")
    output = "".join(f"{key}={value}\n" for key, value in values.items())
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            stream.write(output)
    sys.stdout.write(output)


def _pack(
    workspace: Path, archive: Path, source_sha: str, tool: bool, environment: str = ""
) -> None:
    _check_source(workspace, source_sha)
    if tool:
        _check_image(environment)
    files = _TOOL if tool else _HELPERS
    # Check all fixed inputs before creating an archive. Do not follow links.
    for relative in files.values():
        path = workspace / relative
        if not stat.S_ISREG(path.lstat().st_mode):
            raise ValueError(f"Expected regular artifact file: {path}")
        if path.resolve() != path:
            raise ValueError(f"Artifact source traverses a symbolic link: {path}")
    with tarfile.open(archive, "w:gz", format=tarfile.USTAR_FORMAT) as tar:
        for name, relative in files.items():
            path = workspace / relative
            info = tar.gettarinfo(str(path), arcname=name)
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mode &= 0o777
            # Each expected name is a regular member, even for hardlinked inputs.
            info.type = tarfile.REGTYPE
            info.linkname = ""
            info.size = path.stat().st_size
            with path.open("rb") as stream:
                tar.addfile(info, stream)
    with archive.open("rb") as stream:
        digest = _sha256(stream)
    values = {
        "archiveSha256": digest,
        "sourceSha": source_sha,
        "workspace": str(workspace),
    }
    if tool:
        values["environment"] = environment
    _publish(values)


def _restore(
    workspace: Path,
    archive: Path,
    digest: str,
    source_sha: str,
    destination: Path,
    tool: bool,
    producer_workspace: str = "",
    environment: str = "",
    expected_environment: str = "",
) -> None:
    _check_source(workspace, source_sha)
    if tool:
        if producer_workspace != str(workspace):
            raise ValueError(
                f"Tool workspace mismatch: {producer_workspace} != {workspace}"
            )
        _check_image(environment)
        _check_image(expected_environment)
        if environment != expected_environment:
            raise ValueError(
                f"Tool image mismatch: {environment} != {expected_environment}"
            )
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError(f"Malformed archive SHA-256 for {archive}: {digest}")
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"Restore destination already exists: {destination}")
    expected = set(_TOOL if tool else _HELPERS)
    with archive.open("rb") as stream:
        if _sha256(stream) != digest:
            raise ValueError(f"Archive SHA-256 mismatch: {archive}")
        stream.seek(0)
        with tarfile.open(fileobj=stream, mode="r:*") as tar:
            members = tar.getmembers()
            seen = set()
            for member in members:
                # Exact POSIX names also exclude absolute paths, '..', Windows
                # drive paths/backslashes, directory aliases and unexpected files.
                if (
                    member.name not in expected
                    or member.name in seen
                    or not member.isreg()
                    or member.issparse()
                ):
                    raise ValueError(
                        f"Invalid or duplicate archive member in {archive}: {member.name}"
                    )
                seen.add(member.name)
                # Verify all payloads can be read before creating the destination.
                with tar.extractfile(member) as payload:
                    size = 0
                    for chunk in iter(lambda: payload.read(1024 * 1024), b""):
                        size += len(chunk)
                    if size != member.size:
                        raise ValueError(f"Truncated archive member: {member.name}")
            if seen != expected:
                raise ValueError(
                    f"Missing archive members in {archive}: {sorted(expected - seen)}"
                )
            destination.mkdir(parents=True, exist_ok=False)
            for member in members:
                path = destination / member.name
                path.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as payload, path.open("xb") as output:
                    shutil.copyfileobj(payload, output)
                # On Windows chmod has limited semantics; Linux payloads are not run.
                path.chmod(member.mode & 0o777)


def main(argv: list[str] | None = None, *, _workspace: Path | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    ids = commands.add_parser("require-id")
    ids.add_argument("ids", nargs="+")
    for name in ("pack-tool", "restore-tool", "pack-helpers", "restore-helpers"):
        command = commands.add_parser(name)
        command.add_argument("--archive", required=True, type=Path)
        command.add_argument("--source-sha", required=True)
        if name.endswith("tool"):
            command.add_argument("--environment", required=True)
        if name.startswith("restore"):
            command.add_argument("--sha256", required=True)
            command.add_argument("--destination", required=True, type=Path)
            if name.endswith("tool"):
                command.add_argument("--workspace", required=True)
                command.add_argument("--expected-environment", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "require-id":
            for artifact_id in args.ids:
                if not re.fullmatch(r"[1-9][0-9]*", artifact_id):
                    raise ValueError(f"Missing or invalid producer artifact ID: {artifact_id}")
        else:
            workspace = (_workspace or Path(__file__).resolve().parents[2]).resolve()
            tool = args.command.endswith("tool")
            if args.command.startswith("pack"):
                _pack(
                    workspace, args.archive, args.source_sha, tool,
                    args.environment if tool else "",
                )
            else:
                _restore(
                    workspace, args.archive, args.sha256, args.source_sha,
                    args.destination, tool,
                    args.workspace if tool else "",
                    args.environment if tool else "",
                    args.expected_environment if tool else "",
                )
        return 0
    except (OSError, ValueError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print(f"Artifact handoff failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
