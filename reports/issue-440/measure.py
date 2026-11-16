#!/usr/bin/env python3
"""按固定提交复核 #440 的源码物理行数，不修改工作区或启动构建。"""

import argparse
from collections import defaultdict
import io
import json
from pathlib import Path
import subprocess


BASELINE = "6e67dc232e48275197adced253f17ce7902c9d4a"
STAGES = ("7db73029c", "29c1caadb", "219c40f64", "c8548e0a6")
REPO = Path(__file__).resolve().parents[2]


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO)


def revision(ref):
    return git("rev-parse", "--verify", f"{ref}^{{commit}}").decode().strip()


def category(path):
    if not path.endswith((".rs", ".dart")):
        return "other"
    if (
        "/lib/src/rust/" in path
        or "frb_generated" in path
        or path.endswith((".g.dart", ".freezed.dart"))
        or "/l10n/app_localizations" in path
    ):
        return "generated_source"
    if {"test", "tests", "integration_test"}.intersection(Path(path).parts):
        return "test_source_files"
    return "handwritten_source_files_including_inline_tests"


def difference(base, head):
    groups = defaultdict(lambda: {"added": 0, "deleted": 0, "net": 0})
    # 不推测重命名配对，避免同一次比较因相似度阈值而改变路径分类。
    records = git("diff", "--no-renames", "--numstat", "-z", base, head)
    for record in records.split(b"\0"):
        if not record:
            continue
        added, deleted, path = record.decode().split("\t", 2)
        if added == "-":
            continue
        group = groups[category(path)]
        group["added"] += int(added)
        group["deleted"] += int(deleted)
        group["net"] += int(added) - int(deleted)
    return dict(sorted(groups.items()))


def snapshot(ref):
    entries = []
    for record in git("ls-tree", "-rz", ref).split(b"\0"):
        if not record:
            continue
        metadata, path = record.split(b"\t", 1)
        _, kind, oid = metadata.split()
        path = path.decode()
        if kind == b"blob" and path.endswith((".rs", ".dart")):
            entries.append((oid, category(path)))
    blobs = subprocess.run(
        ["git", "cat-file", "--batch"],
        cwd=REPO,
        input=b"".join(oid + b"\n" for oid, _ in entries),
        stdout=subprocess.PIPE,
        check=True,
    ).stdout
    stream = io.BytesIO(blobs)
    groups = defaultdict(lambda: {"files": 0, "physical_lines": 0})
    for oid, group_name in entries:
        actual, kind, size = stream.readline().split()
        if actual != oid or kind != b"blob":
            raise ValueError("Git 对象响应与请求不一致")
        source = stream.read(int(size))
        if stream.read(1) != b"\n":
            raise ValueError("Git 对象响应缺少分隔符")
        group = groups[group_name]
        group["files"] += 1
        group["physical_lines"] += source.count(b"\n") + bool(
            source and not source.endswith(b"\n")
        )
    return dict(sorted(groups.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", default="HEAD", help="本次审计代码提交或当前分支")
    args = parser.parse_args()
    head = revision(args.head)
    stages = [revision(ref) for ref in STAGES]
    totals = defaultdict(lambda: {"added": 0, "deleted": 0, "net": 0})
    changes = []
    for commit in stages:
        groups = difference(f"{commit}^", commit)
        changes.append({"commit": commit, "groups": groups})
        for group, values in groups.items():
            for key, value in values.items():
                totals[group][key] += value
    refs = [revision(BASELINE), revision(f"{stages[0]}^"), stages[-1], head]
    report = {
        "unit": "physical_lines_including_blank_lines_and_comments",
        "limitation": "按文件路径分类；手写源码文件仍含 Rust 内联测试，不等于纯生产逻辑。",
        "snapshots": {ref: snapshot(ref) for ref in dict.fromkeys(refs)},
        "plan_stages": changes,
        "plan_only_total": dict(sorted(totals.items())),
        "audit_cleanup": {"base": stages[-1], "head": head,
                          "groups": difference(stages[-1], head)},
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
