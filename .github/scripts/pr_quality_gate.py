#!/usr/bin/env python3
"""Fail closed unless every required PR Quality Gate job succeeded."""

from __future__ import annotations

import argparse
import os
import sys

KNOWN_JOBS = (
    "changes",
    "docs-policy",
    "pr-title",
    "release-configuration",
    "rust-quality",
    "rust-deterministic",
    "linux-environment",
    "studio-server-linux",
    "flutter-quality",
    "flutter-ui",
    "macos-desktop",
)


def evaluate(required_jobs: list[str], results: dict[str, str]) -> list[str]:
    errors: list[str] = []
    if results.get("changes") != "success":
        errors.append(
            f"changes result is {results.get('changes', 'missing')!r}; "
            "ci-gate cannot accept a missing plan"
        )

    required = []
    seen = set()
    for name in required_jobs:
        job = name.strip()
        if not job or job in seen:
            continue
        seen.add(job)
        required.append(job)
    if not required:
        errors.append("changes plan did not publish required_jobs")
        return errors
    if "changes" not in seen:
        required.insert(0, "changes")

    for job in required:
        result = results.get(job) or "missing"
        if result == "success":
            continue
        if result == "skipped":
            errors.append(
                f"{job} was skipped while the changes plan required it "
                "(upstream failure/cancel must not look like an allowed skip)"
            )
            continue
        errors.append(f"{job} result is {result!r}; required jobs must succeed")

    allowed_skip = set(KNOWN_JOBS) - set(required)
    for job, result in results.items():
        if job in required:
            continue
        if result in {"success", "skipped"}:
            continue
        if job in allowed_skip and result == "skipped":
            continue
        errors.append(
            f"{job} result is {result!r}; cancelled or failed jobs cannot pass ci-gate"
        )
    return errors


def _parse_required(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--required-jobs",
        default=os.environ.get("REQUIRED_JOBS", ""),
    )
    args = parser.parse_args(argv)
    results = {
        job: os.environ.get(f"{job.upper().replace('-', '_')}_RESULT", "missing")
        for job in KNOWN_JOBS
    }
    errors = evaluate(_parse_required(args.required_jobs), results)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        print(
            "Suggested required check name: ci-gate. "
            "Editing this workflow does not configure repository required checks.",
            file=sys.stderr,
        )
        return 1
    print("ci-gate accepted the changes plan and required job results")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
