#!/usr/bin/env python3
"""Recompute source-size evidence from a Git revision or the current workspace.

Only standard-library modules are used. Run from the repository root. This is
source-size accounting, not a semantic dependency checker or performance test.
"""

import argparse
import collections
import hashlib
import json
import pathlib
import posixpath
import re
import subprocess


RUST_ROOTS = (
    "code/pl-protocol/src/",
    "code/pl-studio-runtime/src/",
    "code/pl-studio-server/src/",
    "code/anywork/rust/src/",
)
PART = re.compile(r"^part\s+['\"]([^'\"]+)['\"];", re.MULTILINE)


def git(*args):
    return subprocess.check_output(["git", *args])


def classify(path):
    if path.startswith("code/anywork/lib/") and path.endswith(".dart"):
        generated = (
            path.endswith((".g.dart", ".freezed.dart"))
            or path.startswith("code/anywork/lib/src/rust/")
            or pathlib.PurePosixPath(path).name.startswith("app_localizations")
        )
        return "app.generated" if generated else "app.production"
    if path.startswith("code/anywork/test/") and path.endswith(".dart"):
        return "app.test"
    if path.startswith("code/anywork/test_driver/") and path.endswith(".dart"):
        return "app.driver"
    if path.startswith("code/anywork_client/lib/") and path.endswith(".dart"):
        if path.endswith((".g.dart", ".freezed.dart")):
            return "client.generated"
        return "client.production"
    if path.startswith("code/anywork_client/test/") and path.endswith(".dart"):
        return "client.test"
    if path.startswith(RUST_ROOTS) and path.endswith(".rs"):
        if pathlib.PurePosixPath(path).name == "frb_generated.rs":
            return "rust.generated"
        # Rust tests embedded in src/ are intentionally included and identified.
        # Splitting cfg(test) lexically would misclassify nested/module code.
        return "rust.handwritten_source"
    return None


def load_sources(revision, worktree):
    if worktree:
        entries = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
    else:
        entries = git("ls-tree", "-r", "--name-only", "-z", revision)
    paths = sorted(set(p.decode("utf-8") for p in entries.split(b"\0") if p))
    result = {}
    for path in paths:
        if classify(path) is None:
            continue
        if worktree:
            source = pathlib.Path(path)
            if not source.exists():
                continue  # A tracked deletion is absent from the new tree.
            if source.is_symlink():
                raise ValueError(f"source-size evidence does not follow symlinks: {path}")
            result[path] = source.read_bytes()
        else:
            result[path] = git("show", f"{revision}:{path}")
    return result


def measure(sources, revision, worktree):
    totals = collections.defaultdict(
        lambda: {"files": 0, "physicalLines": 0, "nonBlankLines": 0}
    )
    sizes = {}
    large = collections.Counter()
    handwritten = {}
    identity = hashlib.sha256()
    for path, raw in sources.items():
        identity.update(path.encode("utf-8") + b"\0")
        identity.update(hashlib.sha256(raw).digest())
        text = raw.decode("utf-8")
        lines = text.splitlines()
        category = classify(path)
        totals[category]["files"] += 1
        totals[category]["physicalLines"] += len(lines)
        totals[category]["nonBlankLines"] += sum(bool(line.strip()) for line in lines)
        if category in (
            "app.production", "client.production", "rust.handwritten_source"
        ):
            sizes[path] = len(lines)
            if len(lines) > 500:
                large[category] += 1
        if category in ("app.production", "client.production"):
            handwritten[path] = text

    libraries = []
    for path, text in handwritten.items():
        parts = []
        for relative in PART.findall(text):
            target = posixpath.normpath(posixpath.join(posixpath.dirname(path), relative))
            if target in handwritten:
                parts.append(target)
        if parts:
            libraries.append({
                "entry": path,
                "handwrittenParts": len(parts),
                "physicalLines": sizes[path] + sum(sizes[p] for p in parts),
                "parts": sorted(parts),
            })
    return {
        "schemaVersion": 2,
        "baseline": revision,
        "tree": "worktree" if worktree else "committed",
        "sourceContentHash": "sha256:" + identity.hexdigest(),
        "classification": {
            "dartProduction": "lib/**/*.dart excluding generated sources",
            "dartGenerated": ".g.dart/.freezed.dart, app lib/src/rust/, app_localizations*",
            "appTest": "all app test/**/*.dart, including support and non-gated tests",
            "appDriver": "test_driver/**/*.dart; separate from automated app tests",
            "rustSourceRoots": list(RUST_ROOTS),
            "rustHandwritten": "src/**/*.rs including embedded cfg(test) code; not pure production LOC",
            "rustGenerated": "frb_generated.rs",
            "parts": "direct handwritten part directives; generated parts excluded",
            "counting": "UTF-8 splitlines; blank = whitespace-only; >500 is strict",
            "untracked": "included only with --worktree; ignored build/data files excluded",
        },
        "totals": dict(sorted(totals.items())),
        "handwrittenFilesOver500": dict(sorted(large.items())),
        "largestHandwrittenFiles": [
            {"path": path, "lines": count}
            for path, count in sorted(sizes.items(), key=lambda pair: (-pair[1], pair[0]))[:20]
        ],
        "handwrittenLibraries": sorted(
            libraries, key=lambda value: (-value["physicalLines"], value["entry"])
        ),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", default="HEAD")
    parser.add_argument("--worktree", action="store_true")
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()
    revision = git("rev-parse", "--verify", args.revision + "^{commit}").decode().strip()
    result = measure(load_sources(revision, args.worktree), revision, args.worktree)
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
        print(args.output)
    else:
        print(encoded, end="")


if __name__ == "__main__":
    main()
