#!/usr/bin/env python3
"""Reproduce issue 453's storage-only comparison from the exact S3/S4 commits."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess

BASELINES = {
    "s3": "6f0e594d882cb9b09d54c24240f5dc0b2090a87a",
    "s4": "a672105919380053cf38b88486ffc25a8848a937",
}
TEST = "studio::storage::thread_writer::storage_fault_tests::measure_history_write_cost"
CONFIG = ["--config", "profile.test.package.pl-studio-runtime.debug=0", "--config", "profile.test.package.pl-studio-runtime.incremental=false"]


def run(args, cwd):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{args!r}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--target-dir", type=Path, help="optional shared Cargo cache")
    parser.add_argument("--existing", action="store_true", help="use already patched baseline worktrees")
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("samples must be positive")
    repo, work, output = args.repo.resolve(), args.work_root.resolve(), args.output.resolve()
    work.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    report_dir = Path(__file__).resolve().parent
    environment = {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "rustc": run(["rustc", "-Vv"], repo),
        "cargo": run(["cargo", "-V"], repo),
        "cc": run(["cc", "--version"], repo),
        "buildConfig": CONFIG,
        "sampleCountPerBaseline": args.samples,
        "test": TEST,
        "RUST_TEST_THREADS": os.environ.get("RUST_TEST_THREADS"),
        "baselines": {},
    }
    for label, sha in BASELINES.items():
        checkout = work / ("anywork-453-" + label)
        patch = report_dir / (label + "-measurement.patch")
        if not args.existing:
            run(["git", "fetch", "origin", sha], repo)
            run(["git", "worktree", "add", "--detach", str(checkout), sha], repo)
            run(["git", "apply", str(patch)], checkout)
        if run(["git", "rev-parse", "HEAD"], checkout).strip() != sha:
            raise RuntimeError(f"wrong baseline: {checkout}")
        actual_patch = subprocess.check_output(["git", "diff", "--binary"], cwd=checkout)
        if actual_patch != patch.read_bytes():
            raise RuntimeError(f"unreviewed baseline changes: {checkout}")
        build = ["cargo", "test", "--locked", "--target-dir", str(args.target_dir.resolve() if args.target_dir else work / "measurement-target"), "--jobs", "1", *CONFIG,
                 "-p", "pl-studio-runtime", "--lib", "--no-run", "--message-format=json"]
        built = subprocess.run(build, cwd=checkout, text=True, capture_output=True)
        (output / (label + "-build.log")).write_text(built.stderr)
        if built.returncode:
            raise RuntimeError(built.stderr)
        executable = None
        for line in built.stdout.splitlines():
            item = json.loads(line)
            if item.get("reason") == "compiler-artifact" and item.get("target", {}).get("name") == "pl_studio_runtime" and item.get("executable"):
                executable = item["executable"]
        if not executable:
            raise RuntimeError("no Runtime test executable produced")
        command = [executable, "--exact", TEST, "--ignored", "--nocapture", "--test-threads=1"]
        results = []
        # The build has finished. Run samples serially, with no other task build/test running.
        for sample in range(1, args.samples + 1):
            measured = subprocess.run(command, cwd=checkout, text=True, capture_output=True)
            raw = measured.stdout + measured.stderr
            (output / f"{label}-{sample}.log").write_text(raw)
            if measured.returncode:
                raise RuntimeError(raw)
            markers = [line.removeprefix("HISTORY_WRITE_METRICS ") for line in raw.splitlines() if line.startswith("HISTORY_WRITE_METRICS ")]
            if len(markers) != 1 or "1 passed" not in raw:
                raise RuntimeError("measurement missing or not executed")
            metric = json.loads(markers[0])
            results.append(metric)
            print(label, sample, json.dumps(metric, ensure_ascii=False), flush=True)
        (output / (label + ".json")).write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
        environment["baselines"][label] = {"sha": sha, "patchSha256": hashlib.sha256(patch.read_bytes()).hexdigest(), "buildCommand": build, "sampleCommand": command}
        (output / "environment.json").write_text(json.dumps(environment, ensure_ascii=False, indent=2) + "\n")
    first = {label: json.loads((output / (label + ".json")).read_text())[0] for label in BASELINES}
    differences = {}
    for key in first["s3"]:
        before, after = first["s3"][key], first["s4"][key]
        if isinstance(before, (int, float)) and isinstance(after, (int, float)):
            differences[key] = {"s3": before, "s4": after, "difference": after - before, "percent": (after / before - 1) * 100 if before else None}
    (output / "comparison.json").write_text(json.dumps(differences, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
