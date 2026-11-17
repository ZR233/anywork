"""原生版本 3 归档的只读验证边界。"""

import hashlib
import json
import re
from dataclasses import dataclass
from importlib.resources import files
from pathlib import Path, PurePosixPath
from uuid import UUID

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

from .errors import AnywkArtifactError


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def decode_json(data: bytes) -> dict:
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("JSON 存在重复字段")
            result[key] = value
        return result

    value = json.loads(
        data,
        object_pairs_hook=pairs,
        parse_constant=lambda _: (_ for _ in ()).throw(ValueError("非有限数值")),
    )
    if not isinstance(value, dict):
        raise TypeError("JSON 顶层必须是对象")
    return value


def read_json(path: Path) -> dict:
    return decode_json(path.read_bytes())


def safe_file(root: Path, relative: str) -> Path:
    path = PurePosixPath(relative)
    if path.is_absolute() or not path.parts or any(p in ("..", ".") for p in path.parts):
        raise ValueError("归档引用越界")
    current = root
    for part in path.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("归档不接受符号链接")
    if not current.is_file():
        raise ValueError(f"归档缺少文件：{relative}")
    return current


def _validators() -> dict:
    # 构建时直接打包 canonical schema，不维护另一份协议。
    directory = files("_anywork_run_export_schema").joinpath("v3")
    schemas = {
        name: json.loads(directory.joinpath(f"{name}.schema.json").read_text())
        for name in ("run", "result", "events", "native")
    }


def _manifest(root: Path, reference: dict) -> list[dict]:
    raw = safe_file(root, reference["path"]).read_bytes()
    digest = sha256(raw)
    if (
        len(raw) != reference["byteLength"]
        or digest != reference["sha256"]
        or reference["path"] != f"contents/{digest}.bin"
    ):
        raise ValueError("内容 manifest 长度或摘要不一致")
    return [decode_json(line) for line in raw.splitlines()]
    registry = Registry().with_resources(
        (schema["$id"], Resource.from_contents(schema)) for schema in schemas.values()
    )
    return {
        name: Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())
        for name, schema in schemas.items()
    }


@dataclass(frozen=True)
class RunArtifacts:
    directory: Path
    manifest: dict
    result: dict | None
    events: list[dict]
    complete: bool

    def content(self, reference: dict) -> bytes:
        return safe_file(self.directory, reference["path"]).read_bytes()

    def manifest_contents(self, reference: dict) -> list[dict]:
        raw = self.content(reference)
        entries = []
        for line in raw.splitlines():
            entry = decode_json(line)
            if not isinstance(entry.get("nativeRef"), dict):
                raise ValueError("内容 manifest 缺少 nativeRef")
            entries.append(entry)
        return entries


def read_and_validate_run_artifacts(
    local_dir: Path, *, require_success: bool = True, expected_exit: int | None = None
) -> RunArtifacts:
    try:
        return _validate(Path(local_dir), require_success, expected_exit)
    except AnywkArtifactError:
        raise
    except (OSError, ValueError, KeyError, TypeError, AssertionError) as error:
        raise AnywkArtifactError(f"原生产物验证失败：{error}") from error


def _validate(root: Path, success: bool, expected_exit: int | None) -> RunArtifacts:
    if root.is_symlink() or not root.is_dir():
        raise ValueError("归档根目录无效")
    validators = _validators()

    def validate(kind, value):
        errors = list(validators[kind].iter_errors(value))
        if errors:
            # 不输出 instance，避免验证错误打印任务正文或密钥。
            raise ValueError(f"{kind} schema 不匹配：{list(errors[0].absolute_path)}")

    manifest = read_json(safe_file(root, "run.json"))
    validate("run", manifest)
    UUID(manifest["runId"])
    result_path = root / "result.json"
    result = read_json(safe_file(root, "result.json")) if result_path.exists() else None
    if result is None and success:
        raise ValueError("缺少最终结果")
    if result is not None:
        validate("result", result)
        if result["runId"] != manifest["runId"] or result["build"] != manifest["build"]:
            raise ValueError("结果身份与 manifest 不一致")
        if expected_exit is not None and result["exitCode"] != expected_exit:
            raise ValueError("结果退出码与真实进程不一致")
    events = []
    raw = safe_file(root, "events.jsonl").read_bytes()
    lines = raw.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if not line.endswith(b"\n"):
            if success or index != len(lines) - 1:
                raise ValueError("事件行未完成")
            break
        event = decode_json(line)
        validate("events", event)
        if event["runId"] != manifest["runId"] or event["eventSeq"] != index + 1:
            raise ValueError("事件运行身份或连续序号无效")
        events.append(event)
    if not events or events[0]["type"] != "runStarted":
        raise ValueError("缺少运行开始事件")
    started = events[0]["data"]
    if (
        started["manifestSha256"] != sha256((root / "run.json").read_bytes())
        or started["runId"] != manifest["runId"]
        or started["build"] != manifest["build"]
    ):
        raise ValueError("manifest 摘要或构建身份不一致")
    members, agents, completions, receipts, seals, calls = {}, {}, {}, {}, {}, {}
    run_seal = None
    for event in events[1:]:
        kind, data, thread, source = (event[k] for k in ("type", "data", "threadId", "source"))
        if run_seal is not None:
            raise ValueError("运行封口后仍有事件")
        if kind == "runStarted":
            raise ValueError("重复运行开始事件")
        if kind == "agentRegistered":
            if thread != data["threadId"] or thread in members or data["agentId"] in agents:
                raise ValueError("成员身份重复或矛盾")
            parent = data["parentThreadId"]
            if parent is not None and (
                parent not in members or members[parent]["agentId"] != data["parentAgentId"]
            ):
                raise ValueError("成员父子关系无效")
            if parent is None and data["parentAgentId"] is not None:
                raise ValueError("根成员不能有父智能体")
            members[thread], agents[data["agentId"]] = data, thread
            completions[thread], calls[thread] = {}, set()
        elif kind == "runSealed":
            run_seal = data
        else:
            if thread not in members or thread in seals:
                raise ValueError("未登记成员或成员封口后仍写入")
            initial = members[thread]["initialHistoryCursor"]
            if kind == "inferenceFinished":
                key = (thread, data["billing"]["inferenceId"])
                if key in receipts or source["effectSeq"] is None:
                    raise ValueError("重复调用账单或缺少效果水位")
                receipts[key] = event
            elif kind == "completion":
                header, atom = data["header"]["event"], data["atom"]
                seq, event_id = header["seq"], header["eventId"]
                if event_id in completions[thread] or seq <= initial["historySeq"]:
                    raise ValueError("完成原件重复或早于初始 History 位置")
                if source["historyEventSeq"] != seq or source["historyEventId"] != event_id:
                    raise ValueError("完成原件身份矛盾")
                if (
                    header["entityId"] != atom["entityId"]
                    or header["source"] != atom["source"]
                    or header.get("turnId") != atom.get("turnId")
                ):
                    raise ValueError("History event 与 typed head 身份矛盾")
                completions[thread][event_id] = event
                if atom.get("tool"):
                    calls[thread].add(atom["tool"]["callId"])
                manifest = data["contentsManifest"]
                contents = _manifest(root, manifest)
                if any(
                    item["nativeRef"]["ownerEventId"] != event_id
                    for item in contents
                ) or not any(
                    item["nativeRef"]["ownerEventId"] == event_id
                    and item["historyRole"]["kind"] == "canonicalPayload"
                    for item in contents
                ):
                    raise ValueError("内容 manifest 归属或 canonical payload 无效")
                refs = [data["payload"], *contents]
                for ref in refs:
                    if ref is None:
                        continue
                    if not re.fullmatch(r"contents/[0-9a-f]{64}\.bin", ref["path"]):
                        raise ValueError("内容寻址路径无效")
                    blob = safe_file(root, ref["path"]).read_bytes()
                    digest = sha256(blob)
                    if (
                        len(blob) != ref["byteLength"]
                        or digest != ref["sha256"]
                        or ref["path"] != f"contents/{digest}.bin"
                    ):
                        raise ValueError("内容长度或摘要不一致")
            elif kind == "threadSealed":
                if (
                    data["threadId"] != thread
                    or data["historyCut"]["historySeq"] < initial["historySeq"]
                ):
                    raise ValueError("成员封口身份无效")
                seals[thread] = data
    complete = bool(result and result["traceComplete"])
    if complete or success:
        if (
            not result
            or not run_seal
            or not run_seal["reconciled"]
            or not run_seal["traceComplete"]
        ):
            raise ValueError("缺少完整运行封口")
        trace = result["trace"]
        if (
            not trace["sealed"]
            or trace["eventsPath"] != "events.jsonl"
            or trace["eventsSha256"] != sha256(raw)
            or trace["eventCount"] != len(events)
            or trace["lastEventSeq"] != len(events)
        ):
            raise ValueError("事件摘要、数量或封口不一致")
        if set(members) != set(seals) or len(run_seal["members"]) != len(members):
            raise ValueError("成员集合未完整封口")
        roots = [thread for thread, member in members.items() if member["parentThreadId"] is None]
        if roots != [result["rootThreadId"]]:
            raise ValueError("根成员不唯一或与结果不一致")
        cuts = {cut["threadId"]: cut for cut in run_seal["members"]}
        if len(cuts) != len(members):
            raise ValueError("最终成员重复")
        for thread, member in members.items():
            seal, cut = seals[thread], cuts[thread]
            if seal["summary"]["appliedSequence"] != seal["throughEffectSeq"]:
                raise ValueError("用量归并水位与线程最终水位不一致")
            if (
                cut["historyCut"] != seal["historyCut"]
                or cut["throughEffectSeq"] != seal["throughEffectSeq"]
                or not cut["sealed"]
                or cut["agentId"] != member["agentId"]
                or cut["parentAgentId"] != member["parentAgentId"]
            ):
                raise ValueError("最终成员水位不一致")
            end = seal["historyCut"]["historySeq"]
            if any(
                event["source"]["historyEventSeq"] > end
                for event in completions[thread].values()
            ):
                raise ValueError("完成原件超出成员 History 封口")
            if (
                sum(owner == thread for owner, _ in receipts)
                != seal["summary"]["totals"]["inferenceCount"]
            ):
                raise ValueError("调用账单数量与权威用量摘要不一致")
            for (owner, _), receipt in receipts.items():
                if owner == thread and not (
                    member["initialEffectSeq"]
                    < receipt["source"]["effectSeq"]
                    <= seal["throughEffectSeq"]
                ):
                    raise ValueError("调用账单超出封口水位")
            parent, spawn = member["parentThreadId"], member["spawnToolCallId"]
            if spawn is not None and parent is not None and spawn not in calls[parent]:
                raise ValueError("子智能体缺少真实父工具调用")
        if result["usage"] is not None:
            summaries = {value["threadId"]: value for value in result["usage"]["byThread"]}
            if set(summaries) != set(seals):
                raise ValueError("用量成员集合不一致")
            for thread, seal in seals.items():
                if (
                    summaries[thread]["summary"] != seal["summary"]
                    or summaries[thread]["throughEffectSeq"] != seal["throughEffectSeq"]
                ):
                    raise ValueError("权威用量摘要与最终水位不一致")
    if success and (
        not complete
        or result["exitCode"] != 0
        or result["outcome"] != "completed"
        or result["executionOutcome"] != "completed"
        or result["shutdown"]["outcome"] != "clean"
        or result["shutdown"]["persistence"]["kind"] != "drained"
    ):
        raise ValueError("成功结果缺少完整轨迹或清洁关闭")
    return RunArtifacts(root, manifest, result, events, complete)
