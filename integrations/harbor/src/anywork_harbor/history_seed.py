"""只从显式开发运行冻结原生 data；持有与产品相同的 Linux 排他锁。"""

import argparse
import fcntl
import json
import shutil
import sqlite3
import tomllib
from contextlib import closing
from pathlib import Path
from uuid import RFC_4122, UUID

from .artifacts import read_and_validate_run_artifacts, read_json, safe_file, sha256
from .render_profile import load_profile


def tree_hashes(root: Path) -> dict:
    hashes = {}
    if root.is_symlink() or not root.is_dir():
        raise ValueError("快照根目录无效")
    for file in sorted(root.rglob("*")):
        if file.is_symlink() or not (file.is_dir() or file.is_file()):
            raise ValueError("快照拒绝链接和特殊文件")
        if file.is_file():
            hashes[file.relative_to(root).as_posix()] = sha256(file.read_bytes())
    return hashes


def catalog_identity(config: dict) -> str:
    return sha256(json.dumps(config["models"]["accounts"], sort_keys=True).encode())


def _canonical_uuid4(value) -> bool:
    if not isinstance(value, str):
        return False
    try:
        parsed = UUID(value)
    except ValueError:
        return False
    return parsed.version == 4 and parsed.variant == RFC_4122 and str(parsed) == value


def validate_current(current: dict, thread_id: str) -> None:
    if set(current) != {
        "schemaVersion",
        "threadId",
        "savedRuntimeEpoch",
        "snapshotRevision",
        "savedAt",
        "state",
        "modelCall",
    }:
        raise ValueError("种子 Current JSON 顶层字段无效")
    if (
        current["schemaVersion"] != 1
        or current["threadId"] != thread_id
        or not _canonical_uuid4(current["savedRuntimeEpoch"])
        or not isinstance(current["snapshotRevision"], int)
        or isinstance(current["snapshotRevision"], bool)
        or current["snapshotRevision"] < 0
        or not isinstance(current["savedAt"], int)
        or isinstance(current["savedAt"], bool)
        or current["savedAt"] < 0
        or not isinstance(current["state"], dict)
    ):
        raise ValueError("种子 Current JSON 身份或格式无效")
    if set(current["state"]) != {
        "lifecycle",
        "execution",
        "continuation",
        "inputs",
        "inputOrdinal",
        "terminalInputs",
        "context",
        "privateContext",
        "tasks",
        "taskStartOrdinal",
        "toolPreviews",
        "deliveries",
        "discoveredTools",
        "runtimeFacts",
        "extensions",
        "extensionSequence",
        "inbox",
        "inboxSequence",
        "consumedMessages",
        "wakeMessagesThrough",
        "consumedMessageIdentities",
        "interactions",
        "permissions",
        "lastAttemptUsage",
        "lastAttemptUsageOrigin",
        "usageSummary",
    }:
        raise ValueError("种子 Current state 字段无效")
    model_call = current["modelCall"]
    if model_call is not None:
        if not isinstance(model_call, dict) or set(model_call) != {
            "sourceRunId",
            "sourceExecutionId",
            "sourceTurnId",
            "sourceAttemptId",
            "tools",
            "toolCallMode",
            "soloToolIds",
            "preparedParameters",
            "phase",
        }:
            raise ValueError("种子 Current modelCall 字段无效")
        if (
            not _canonical_uuid4(model_call["sourceRunId"])
            or not model_call["sourceExecutionId"]
            or not model_call["sourceTurnId"]
            or not model_call["sourceAttemptId"]
            or not isinstance(model_call["phase"], dict)
            or model_call["phase"].get("kind")
            not in ("preparing", "streaming", "applied")
        ):
            raise ValueError("种子 Current modelCall 身份或阶段无效")


def validate_seed(
    directory: Path,
    *,
    config: Path,
    expected_version: str,
    expected_commit: str | None = None,
    excluded_tasks=(),
) -> dict:
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError("种子根目录无效")
    seed = read_json(safe_file(directory, "seed.json"))
    digest = seed.pop("seedHash")
    if seed.get("schemaVersion") != 1 or digest != sha256(
        json.dumps(seed, sort_keys=True).encode()
    ):
        raise ValueError("种子清单摘要或版本无效")
    if seed["build"]["version"] != expected_version:
        raise ValueError("种子产品版本不匹配")
    if expected_commit is not None and seed["build"]["gitCommit"] != expected_commit:
        raise ValueError("种子构建身份不匹配")
    if seed["catalogHash"] != catalog_identity(load_profile(config)):
        raise ValueError("种子与当前账号/候选目录不一致")
    if set(seed["developmentTaskIds"]) & set(excluded_tasks):
        raise ValueError("种子开发任务与待评测任务重叠")
    if tree_hashes(directory / "data") != seed["files"]:
        raise ValueError("种子数据快照摘要不匹配")
    _inspect_data(directory / "data")
    seed["seedHash"] = digest
    return seed


def _inspect_data(data: Path) -> dict:
    try:
        return _inspect_data_unchecked(data)
    except sqlite3.Error as error:
        raise ValueError("种子数据库不可读或缺少当前格式") from error


def _inspect_data_unchecked(data: Path) -> dict:
    stats = {}
    layout = tomllib.loads(safe_file(data, "layout.toml").read_text())
    if layout.get("schemaVersion") != 2:
        raise ValueError("种子必须使用当前 data 布局")
    for relative in ("studio.sqlite", "calls/calls.sqlite", "catalog.toml", "workspaces.toml"):
        safe_file(data, relative)
    for workspace in (data / "workspaces").glob("*"):
        record = tomllib.loads(safe_file(workspace, "workspace.toml").read_text())
        if record.get("schemaVersion") != 2 or workspace.name != sha256(
            record["workspaceId"].encode()
        ):
            raise ValueError("种子工作区归属无效")
        for session in (workspace / "sessions").glob("*"):
            member = tomllib.loads(safe_file(session, "session.toml").read_text())
            if (
                member.get("schemaVersion") != 2
                or member["workspaceId"] != record["workspaceId"]
                or session.name != sha256(member["threadId"].encode())
            ):
                raise ValueError("种子会话归属无效")
            safe_file(session, "history.sqlite")
            current = read_json(safe_file(session, "current.json"))
            validate_current(current, member["threadId"])
    # 只读检查当前原生格式，不改写数据库或工作区路径。
    for path in sorted(data.rglob("*.sqlite")):
        wal = path.with_name(path.name + "-wal")
        if wal.exists() and wal.stat().st_size:
            raise ValueError("种子尚未形成独立 SQLite 快照")
        with closing(
            sqlite3.connect(f"{path.absolute().as_uri()}?mode=ro&immutable=1", uri=True)
        ) as db:
            if db.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                raise ValueError("种子 SQLite 一致性检查失败")
            if db.execute("PRAGMA foreign_key_check").fetchone() is not None:
                raise ValueError("种子 SQLite 引用检查失败")
            if (
                path.name == "studio.sqlite"
                and db.execute("PRAGMA user_version").fetchone()[0] != 27
            ):
                raise ValueError("种子产品数据库格式与当前构建不匹配")
            if path.name == "history.sqlite":
                session_record = tomllib.loads(
                    safe_file(path.parent, "session.toml").read_text()
                )
                meta = db.execute(
                    "SELECT schema_version,database_id,thread_id "
                    "FROM history_store_meta WHERE singleton=1"
                ).fetchone()
                tables = {
                    row[0]
                    for row in db.execute("SELECT name FROM sqlite_schema WHERE type='table'")
                }
                if (
                    meta is None
                    or meta[0] != 25
                    or not meta[1]
                    or not meta[2]
                    or meta[2] != session_record["threadId"]
                    or "history_meta" in tables
                ):
                    raise ValueError("种子历史数据库不是当前 schema 25 格式")
            if path.name == "calls.sqlite":
                row = db.execute(
                    "SELECT schema_version,pending_cleanup FROM calls_meta WHERE id=1"
                ).fetchone()
                if row != (9, 0):
                    raise ValueError("种子调用数据库格式或清理状态无效")
            tables = {
                row[0] for row in db.execute("SELECT name FROM sqlite_schema WHERE type='table'")
            }
            if "studio_objects" in tables:
                for kind, payload in db.execute(
                    "SELECT object_kind,payload_json FROM studio_objects"
                ):
                    value = json.loads(payload)
                    if kind == "agentClose" and (
                        not value["executionClosed"]
                        or value["worktreeCleanup"]["kind"]
                        not in ("removed", "notPresent", "notApplicable")
                    ):
                        raise ValueError("种子含未完成的智能体关闭")
                    if kind in ("threadDelete", "threadArchive") and value["phase"] != "published":
                        raise ValueError("种子含未完成的存储操作")
                    if kind == "worktreeLease" and value["state"] != "cleaned":
                        raise ValueError("种子含未清理工作树租约")
            for table in ("agent_evaluations", "performance_samples"):
                if table in tables:
                    rows = db.execute(
                        f"SELECT account_id,model_id,COUNT(*) FROM {table} "
                        "GROUP BY account_id,model_id"
                    ).fetchall()
                    stats[table] = [
                        {"accountId": row[0], "modelId": row[1], "count": row[2]} for row in rows
                    ]
    for path in data.rglob("*.toml"):
        document = tomllib.loads(path.read_text())

        def check(value, source=path):
            if isinstance(value, dict):
                if "lease" in value and value["lease"].get("state") != "cleaned":
                    raise ValueError("种子含未清理工作树租约")
                if value.get("status") in ("running", "starting", "closing", "busy"):
                    raise ValueError("种子含活动会话")
                if "/bots/" in source.as_posix() and value.get("enabled") is True:
                    raise ValueError("种子含启用的机器人")
                for item in value.values():
                    check(item)
            elif isinstance(value, list):
                for item in value:
                    check(item)

        check(document)
    return stats


def _snapshot_databases(data: Path):
    # 仅在独立副本使用官方 backup API 合并 WAL；源 home 全程不打开数据库。
    for path in sorted(data.rglob("*.sqlite")):
        snapshot = path.with_name(path.name + ".snapshot")
        if snapshot.exists():
            raise ValueError("快照临时文件已存在")
        with (
            closing(sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True)) as source,
            closing(sqlite3.connect(snapshot)) as destination,
        ):
            source.backup(destination)
        snapshot.replace(path)
        for suffix in ("-wal", "-shm"):
            sidecar = path.with_name(path.name + suffix)
            sidecar.unlink(missing_ok=True)


def freeze(home: Path, artifacts: Path, development_manifest: Path, output: Path) -> dict:
    home = home.resolve()
    output = output.resolve()
    if output.is_relative_to(home):
        raise ValueError("种子输出必须位于源 home 之外")
    # 不创建源锁文件；缺失说明尚未形成可证明清洁的原生 home。
    with (home / "studio/runtime.lock").open("r+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        run = read_and_validate_run_artifacts(artifacts)
        if Path(run.manifest["invocation"]["studioHome"]).resolve() != home:
            raise ValueError("结果不属于种子源 home")
        config = safe_file(home, "config.toml")
        config_input = next(
            (item for item in run.manifest["configInputs"] if item["logicalName"] == "config.toml"),
            None,
        )
        if config_input is None or config_input["sha256"] != sha256(config.read_bytes()):
            raise ValueError("种子源配置与开发运行不一致")
        migration = home / "storage-migration.toml"
        if migration.exists() and tomllib.loads(migration.read_text()).get("phase") != "completed":
            raise ValueError("种子存在未完成的布局迁移")
        development = read_json(development_manifest)
        if development.get("suite") not in ("smoke", "development", "dev"):
            raise ValueError("种子必须来自专用开发或合成任务")
        ids = [task["id"] for task in development["tasks"]]
        if not ids or run.manifest["build"]["gitCommit"] is None:
            raise ValueError("种子缺少开发来源或构建身份")
        if (home / "startup-recovery.toml").exists():
            raise ValueError("种子存在启动恢复状态")
        source = home / "data"
        before = tree_hashes(source)
        output.mkdir(parents=True, exist_ok=False)
        shutil.copytree(source, output / "data")
        if tree_hashes(source) != before or tree_hashes(output / "data") != before:
            raise ValueError("持锁复制期间数据发生变化")
        _snapshot_databases(output / "data")
        stats = _inspect_data(output / "data")
        seed = {
            "schemaVersion": 1,
            "build": run.manifest["build"],
            "configSchemaVersion": 33,
            "developmentTaskIds": ids,
            "developmentManifestSha256": sha256(development_manifest.read_bytes()),
            "catalogHash": catalog_identity(load_profile(home / "config.toml")),
            "sourceFiles": before,
            "files": tree_hashes(output / "data"),
            "statistics": stats,
        }
        seed["seedHash"] = sha256(json.dumps(seed, sort_keys=True).encode())
        (output / "seed.json").write_text(json.dumps(seed, indent=2))
        return seed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--studio-home", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--development-manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    freeze(args.studio_home, args.artifacts, args.development_manifest, args.output)
    return 0
