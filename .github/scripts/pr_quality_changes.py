#!/usr/bin/env python3
"""Classify PR Quality Gate jobs from Git path data and directory rules."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from collections.abc import Iterable
from pathlib import Path

OUTPUT_FLAGS = (
    "docs_policy",
    "release_configuration",
    "rust_quality",
    "rust_deterministic",
    "linux_environment",
    "flutter_quality",
    "macos_desktop",
)

_ZERO_SHA = "0" * 40

_DOCS_EXACT = frozenset(
    {
        "CHANGELOG.md",
        "LICENSE",
        "README.md",
        "code/anywork/README.md",
        "code/pl-studio-acceptance/DELEGATION.md",
        "code/pl-studio-runtime/THIRD_PARTY_NOTICES.md",
        "docker/linux/README.md",
    }
)
_DOCS_PREFIXES = (
    "design/",
    "reports/",
    "site/",
)

# Collaboration, CI, locks, generators, fixtures and platform runners are never
# treated as skippable documentation.
_POLICY_EXACT = frozenset(
    {
        ".editorconfig",
        ".gitattributes",
        ".gitignore",
        ".release-please-manifest.json",
        "AGENTS.md",
        "CLAUDE.md",
        "Cargo.lock",
        "Cargo.toml",
        "release-please-config.json",
        "rust-toolchain.toml",
        "rustfmt.toml",
        "studio-version.txt",
        "code/anywork/analysis_options.yaml",
        "code/anywork/build.yaml",
        "code/anywork/dart_test.yaml",
        "code/anywork/l10n.yaml",
        "code/anywork/pubspec.lock",
        "code/anywork/pubspec.yaml",
        "code/anywork_client/analysis_options.yaml",
        "code/anywork_client/pubspec.lock",
        "code/anywork_client/pubspec.yaml",
    }
)
_POLICY_PREFIXES = (
    ".agents/",
    ".cargo/",
    ".claude/",
    ".github/",
    "docker/",
    "xtask/",
    "code/pl-provider-fixture/",
    "code/pl-studio-runtime/assets/",
)

_RUST_EXACT = frozenset(
    {
        "Cargo.lock",
        "Cargo.toml",
        "rust-toolchain.toml",
        "rustfmt.toml",
    }
)
_RUST_PREFIXES = (
    "code/pl-",
    "code/anywork/rust/",
)

_FLUTTER_PREFIXES = (
    "code/anywork/",
    "code/anywork_client/",
)

_DESKTOP_PREFIXES = (
    "code/anywork/integration_test/",
    "code/anywork/linux/",
    "code/anywork/macos/",
    "code/anywork/runner_common/",
    "code/anywork/rust/",
    "code/anywork/tool/",
    "code/anywork/windows/",
    "code/pl-dev-support/",
    "code/pl-studio-acceptance/",
    "xtask/",
)


def _posix(path: str) -> str:
    normalized = path.replace("\\", "/")
    while normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized


def _has_prefix(path: str, prefixes: Iterable[str]) -> bool:
    return any(path == prefix.rstrip("/") or path.startswith(prefix) for prefix in prefixes)


def classify_path(path: str) -> frozenset[str]:
    """Return category tags for one repository-relative path."""
    path = _posix(path)
    if not path or path.endswith("/"):
        return frozenset({"unknown"})
    tags: set[str] = set()
    if path in _DOCS_EXACT or _has_prefix(path, _DOCS_PREFIXES):
        tags.add("docs")
    if path in _POLICY_EXACT or _has_prefix(path, _POLICY_PREFIXES):
        tags.add("policy")
    if path in _RUST_EXACT or _has_prefix(path, _RUST_PREFIXES):
        tags.add("rust")
    if _has_prefix(path, _FLUTTER_PREFIXES):
        tags.add("flutter")
    if _has_prefix(path, _DESKTOP_PREFIXES):
        tags.add("desktop")
    if not tags:
        tags.add("unknown")
    return frozenset(tags)


def _empty_flags() -> dict[str, bool]:
    return {name: False for name in OUTPUT_FLAGS}


def _full_flags() -> dict[str, bool]:
    flags = {name: True for name in OUTPUT_FLAGS}
    return flags


def plan_from_paths(paths: Iterable[str], *, event_name: str) -> dict[str, object]:
    normalized = [_posix(path) for path in paths if _posix(path)]
    if not normalized:
        flags = _full_flags()
        return _finish(
            flags,
            event_name=event_name,
            plan="full",
            reason="missing, empty, or unclassifiable diff; run the full applicable suite",
        )

    tags: set[str] = set()
    for path in normalized:
        tags.update(classify_path(path))

    if "unknown" in tags or "policy" in tags:
        flags = _full_flags()
        reason = "unknown path category or non-skippable policy/fixture/skill/CI path"
        return _finish(flags, event_name=event_name, plan="full", reason=reason)

    if tags == {"docs"}:
        flags = _empty_flags()
        flags["docs_policy"] = True
        return _finish(
            flags,
            event_name=event_name,
            plan="docs-only",
            reason="all paths are design or documentation",
        )

    flags = _empty_flags()
    if "docs" in tags:
        flags["docs_policy"] = True
    if "rust" in tags:
        flags["rust_quality"] = True
        flags["rust_deterministic"] = True
        flags["linux_environment"] = True
    if "flutter" in tags:
        flags["flutter_quality"] = True
    if "desktop" in tags:
        flags["macos_desktop"] = True
        flags["linux_environment"] = True
    plan_name = "+".join(
        name for name in ("docs", "rust", "flutter", "desktop") if name in tags
    )
    return _finish(
        flags,
        event_name=event_name,
        plan=plan_name or "full",
        reason="directory rules selected the applicable heavy jobs",
    )


def _finish(
    flags: dict[str, bool], *, event_name: str, plan: str, reason: str
) -> dict[str, object]:
    required = ["changes"]
    if flags["docs_policy"]:
        required.append("docs-policy")
    if event_name == "pull_request":
        required.append("pr-title")
    if flags["release_configuration"]:
        required.append("release-configuration")
    if flags["rust_quality"]:
        required.append("rust-quality")
    if flags["rust_deterministic"]:
        required.append("rust-deterministic")
    if flags["linux_environment"]:
        required.extend(["linux-environment", "studio-server-linux"])
    if flags["flutter_quality"]:
        required.append("flutter-quality")
    if flags["macos_desktop"]:
        required.append("macos-desktop")
    return {
        **flags,
        "required_jobs": tuple(required),
        "plan": plan,
        "reason": reason,
    }


def _is_missing_sha(value: str | None) -> bool:
    if not value:
        return True
    return value == _ZERO_SHA or set(value) == {"0"}


def parse_name_status(parts: list[str]) -> list[str] | None:
    """Return changed paths, or None when a rename/copy cannot be classified."""
    paths: list[str] = []
    index = 0
    while index < len(parts):
        status = parts[index]
        if not status:
            return None
        code = status[0]
        if code in {"R", "C", "U"}:
            return None
        if index + 1 >= len(parts):
            return None
        paths.append(parts[index + 1])
        index += 2
    return paths


def changed_paths(base: str, head: str, *, git_dir: str | None = None) -> list[str] | None:
    if _is_missing_sha(base) or _is_missing_sha(head):
        return None
    command = [
        "git",
        "diff",
        "--name-status",
        "-z",
        f"{base}...{head}",
    ]
    try:
        payload = subprocess.check_output(command, cwd=git_dir)
    except (OSError, subprocess.CalledProcessError):
        return None
    parts = [item.decode("utf-8") for item in payload.split(b"\0") if item]
    return parse_name_status(parts)


def write_github_output(plan: dict[str, object], stream) -> None:
    for name in OUTPUT_FLAGS:
        stream.write(f"{name}={'true' if plan[name] else 'false'}\n")
    stream.write("required_jobs=" + ",".join(plan["required_jobs"]) + "\n")
    stream.write(f"plan={plan['plan']}\n")
    stream.write(f"reason={plan['reason']}\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-name", default=os.environ.get("EVENT_NAME", ""))
    parser.add_argument("--base-sha", default=os.environ.get("BASE_SHA", ""))
    parser.add_argument("--head-sha", default=os.environ.get("HEAD_SHA", ""))
    parser.add_argument(
        "--paths-file",
        help="Read NUL-separated paths instead of git; used by tests",
    )
    args = parser.parse_args(argv)

    if args.paths_file:
        if args.paths_file == "-":
            data = sys.stdin.buffer.read()
        else:
            data = Path(args.paths_file).read_bytes()
        paths = [path.decode("utf-8") for path in data.split(b"\0") if path]
    else:
        paths = changed_paths(args.base_sha, args.head_sha)
        if paths is None:
            paths = []

    plan = plan_from_paths(paths, event_name=args.event_name)
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as handle:
            write_github_output(plan, handle)
    write_github_output(plan, sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
