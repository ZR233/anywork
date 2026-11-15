#!/usr/bin/env python3
"""Recognize the repository's version-only Release Please changes."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


_VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
_SHA = re.compile(r"[0-9a-f]{40}")
_REPOSITORY = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
_RELEASE_BRANCH = "release-please--branches--main--components--studio"
_MANIFEST = ".release-please-manifest.json"
_VERSION_FILE = "studio-version.txt"
_APP = "code/anywork/pubspec.yaml"
_PREVIEW_LOCK = "code/anywork_previews/pubspec.lock"
_CHANGELOG = "CHANGELOG.md"
_VERSION_FILES = frozenset({_MANIFEST, _VERSION_FILE, _APP, _PREVIEW_LOCK})


def _git(*args: str, git_dir: str | None = None) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=git_dir, stderr=subprocess.DEVNULL, text=True, timeout=30
    )


def _content(commit: str, path: str, git_dir: str | None) -> str:
    return _git("show", f"{commit}:{path}", git_dir=git_dir)


def _replace_version_match(text: str, match: re.Match[str], version: str) -> str | None:
    if match.group("version") != version:
        return None
    start, end = match.span("version")
    return text[:start] + "<release-version>" + text[end:]


def _normalize_version_file(text: str, version: str) -> str | None:
    match = re.fullmatch(rf"(?P<version>{_VERSION})\n?", text)
    return _replace_version_match(text, match, version) if match else None


def _normalize_app(text: str, version: str) -> str | None:
    matches = list(re.finditer(
        rf"^version: (?P<version>{_VERSION}) # x-release-please-version$", text, re.MULTILINE
    ))
    return _replace_version_match(text, matches[0], version) if len(matches) == 1 else None


def _normalize_preview_lock(text: str, version: str) -> str | None:
    lines = text.splitlines(keepends=True)
    starts = [index for index, line in enumerate(lines) if line.rstrip("\n") == "  anywork:"]
    if len(starts) != 1:
        return None
    start = starts[0] + 1
    end = next(
        (index for index in range(start, len(lines)) if re.match(r"^  \S", lines[index])),
        len(lines),
    )
    matches = [
        (index, re.fullmatch(rf"    version: (?P<version>{_VERSION})\n?", lines[index]))
        for index in range(start, end)
        if lines[index].startswith("    version:")
    ]
    if len(matches) != 1 or matches[0][1] is None:
        return None
    index, match = matches[0]
    normalized = _replace_version_match(lines[index], match, version)
    if normalized is None:
        return None
    lines[index] = normalized
    return "".join(lines)


def _known_configuration(base: str, git_dir: str | None) -> bool:
    config = json.loads(_content(base, "release-please-config.json", git_dir))
    packages = config["packages"]
    if set(packages) != {"."} or config.get("changelog-path") != _CHANGELOG:
        return False
    package = packages["."]
    return (
        package.get("component") == "studio"
        and package.get("version-file") == _VERSION_FILE
        and package.get("extra-files") == [
            {"type": "generic", "path": _APP},
            {"type": "yaml", "path": _PREVIEW_LOCK, "jsonpath": "$.packages.anywork.version"},
        ]
    )


def _version_only_diff(base: str, head: str, paths: list[str], git_dir: str | None) -> bool:
    changed = set(paths)
    if not _VERSION_FILES <= changed or changed - _VERSION_FILES - {_CHANGELOG}:
        return False
    if not _known_configuration(base, git_dir):
        return False

    old_manifest = json.loads(_content(base, _MANIFEST, git_dir))
    new_manifest = json.loads(_content(head, _MANIFEST, git_dir))
    old_version = old_manifest.pop(".")
    new_version = new_manifest.pop(".")
    if (
        not isinstance(old_version, str)
        or not isinstance(new_version, str)
        or not re.fullmatch(_VERSION, old_version)
        or not re.fullmatch(_VERSION, new_version)
        or old_version == new_version
        or old_manifest != new_manifest
    ):
        return False
    for path, normalize in (
        (_VERSION_FILE, _normalize_version_file),
        (_APP, _normalize_app),
        (_PREVIEW_LOCK, _normalize_preview_lock),
    ):
        old = normalize(_content(base, path, git_dir), old_version)
        new = normalize(_content(head, path, git_dir), new_version)
        if old is None or new is None or old != new:
            return False
    if _CHANGELOG in changed:
        _content(base, _CHANGELOG, git_dir)
        _content(head, _CHANGELOG, git_dir)
    return True


def _release_pull_request(pull: dict, repository: str) -> bool:
    owner = repository.split("/", 1)[0]
    return (
        pull["base"]["ref"] == "main"
        and pull["base"]["repo"]["full_name"].casefold() == repository.casefold()
        and pull["head"]["ref"] == _RELEASE_BRANCH
        and pull["head"]["repo"]["full_name"].casefold() == repository.casefold()
        and pull["user"]["login"].casefold() == owner.casefold()
    )


def _associated_pull_requests(repository: str, commit: str) -> list[dict]:
    try:
        output = subprocess.check_output(
            [
                "gh", "api", "--paginate", "--slurp",
                f"repos/{repository}/commits/{commit}/pulls?per_page=100",
            ],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=30,
        )
        pages = json.loads(output)
        if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
            raise ValueError("unexpected GitHub pull request response")
        return [pull for page in pages for pull in page]
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        print(
            f"::notice::GitHub release association unavailable ({type(error).__name__}); "
            "ordinary quality checks remain enabled",
            file=sys.stderr,
        )
        raise


def _release_push(base: str, head: str, repository: str, git_dir: str | None) -> bool:
    _git("merge-base", "--is-ancestor", base, head, git_dir=git_dir)
    commits = _git("rev-list", "--first-parent", "--reverse", f"{base}..{head}", git_dir=git_dir).splitlines()
    if not commits or len(commits) > 100:
        return False
    pull_number = None
    for commit in commits:
        pulls = [
            pull for pull in _associated_pull_requests(repository, commit)
            if pull.get("state") == "closed"
            and pull.get("merged_at")
            and _release_pull_request(pull, repository)
        ]
        if len(pulls) != 1:
            return False
        pull = pulls[0]
        if pull_number is not None and pull["number"] != pull_number:
            return False
        if pull["merge_commit_sha"] != head:
            return False
        pull_number = pull["number"]
    return True


def is_release_only(
    *,
    event_name: str,
    base: str,
    head: str,
    paths: list[str],
    repository: str,
    ref: str,
    event_path: str,
    git_dir: str | None = None,
) -> bool:
    """Return false if the event or any version-only evidence cannot be proved."""
    if (
        event_name not in {"pull_request", "push"}
        or not _SHA.fullmatch(base)
        or not _SHA.fullmatch(head)
        or not _REPOSITORY.fullmatch(repository)
    ):
        return False
    try:
        if not _version_only_diff(base, head, paths, git_dir):
            return False
        if event_name == "push":
            return ref == "refs/heads/main" and _release_push(base, head, repository, git_dir)
        event = json.loads(Path(event_path).read_text(encoding="utf-8"))
        pull = event["pull_request"]
        if not _release_pull_request(pull, repository) or pull["base"]["sha"] != base:
            return False
        pull_head = pull["head"]["sha"]
        if not _SHA.fullmatch(pull_head):
            return False
        _git("merge-base", "--is-ancestor", pull_head, head, git_dir=git_dir)
        return True
    except (OSError, subprocess.SubprocessError, ValueError, TypeError, KeyError, AttributeError):
        return False
