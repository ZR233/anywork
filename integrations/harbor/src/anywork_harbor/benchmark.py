"""冻结计划并顺序运行单 trial Harbor job；模型调用仅发生在显式 run。"""

import argparse
import asyncio
import json
import math
import os
import re
import shutil
import subprocess
import time
import urllib.request
from pathlib import Path
from uuid import uuid4

import tomlkit
from harbor.agents.agent_auth_resolution import parse_model_name
from harbor.job import Job
from harbor.models.job.config import DatasetConfig, JobConfig
from harbor.models.task.task import Task
from harbor.models.trial.config import TaskConfig

from .artifacts import read_json, sha256
from .errors import ERROR_POLICY
from .history_seed import catalog_identity, tree_hashes, validate_seed
from .render_profile import load_profile, render_profile

HARBOR_COMMIT = "06d0e86a8cfbac213548e0caec533afc5d81ff31"
DATASET = "terminal-bench/terminal-bench"
DATASET_VERSION = "4.0.0"


def atomic_json(path: Path, value: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def digest_object(value):
    return sha256(json.dumps(value, sort_keys=True, allow_nan=False).encode())


def freeze_images(directory: Path) -> list[dict]:
    """Use Docker's own resolver; rewrite only the frozen task copy to immutable references."""
    images = []

    def resolve(reference):
        if "$" in reference:
            raise ValueError("镜像包含未冻结的构建参数，请先提供显式镜像引用")
        if "@sha256:" in reference:
            resolved = reference
        else:
            subprocess.run(["docker", "pull", "--platform", "linux/amd64", reference], check=True)
            digests = json.loads(
                subprocess.check_output(
                    ["docker", "image", "inspect", "--format", "{{json .RepoDigests}}", reference],
                    text=True,
                )
            )
            if not digests:
                raise ValueError("镜像缺少可复现的仓库摘要")
            resolved = min(digests)
        images.append({"source": reference, "resolved": resolved})
        return resolved

    config_path = directory / "task.toml"
    config = tomlkit.parse(config_path.read_text())
    image = config.get("environment", {}).get("docker_image")
    if image:
        config["environment"]["docker_image"] = resolve(image)
        config_path.write_text(tomlkit.dumps(config))
        return images
    dockerfile = directory / "environment/Dockerfile"
    if not dockerfile.is_file():
        raise ValueError("本地评测要求单 Dockerfile 或显式 docker_image")
    aliases = set()
    lines = []
    for line in dockerfile.read_text().splitlines(keepends=True):
        match = re.match(r"^(FROM\s+(?:--platform=\S+\s+)?)(\S+)(.*)$", line, re.IGNORECASE)
        if match:
            reference = match[2]
            if reference.lower() not in aliases and reference.lower() != "scratch":
                line = (
                    match[1] + resolve(reference) + match[3] + ("\n" if line.endswith("\n") else "")
                )
            alias = re.search(r"\sAS\s+(\S+)", match[3], re.IGNORECASE)
            if alias:
                aliases.add(alias[1].lower())
        lines.append(line)
    if not images:
        raise ValueError("任务未声明可核对的基础镜像")
    dockerfile.write_text("".join(lines))
    return images


def install_release(version: str, destination: Path) -> Path:
    import re

    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("release 必须是固定稳定版本号")
    name = f"anywork-{version}-linux-x86_64.deb"
    base = f"https://github.com/ZR233/anywork/releases/download/v{version}"
    destination.mkdir(parents=True, exist_ok=False)
    archive = destination / name
    urllib.request.urlretrieve(f"{base}/{name}", archive)
    with urllib.request.urlopen(f"{base}/{name}.sha256") as response:
        sidecar = response.read().decode()
    if sidecar != f"{sha256(archive.read_bytes())}  {name}\n":
        raise ValueError("发布包 sidecar 校验失败")
    subprocess.run(
        ["dpkg-deb", "--extract", str(archive), str(destination / "package")], check=True
    )
    binary = destination / "package/opt/anywork/bin/anywk"
    if not binary.is_file() or binary.is_symlink():
        raise ValueError("固定桌面包未包含 anywk 资源；不能退回其他版本")
    return binary


def binary_identity(binary: Path, build_info: Path | None = None) -> dict:
    version = subprocess.check_output([str(binary), "--version"], text=True).strip()
    if not version.startswith("anywk "):
        raise ValueError("不是 anywk 二进制")
    info = (
        read_json(build_info)
        if build_info
        else {
            "version": version.removeprefix("anywk "),
            "gitCommit": None,
            "target": "unknown",
            "buildEnvironment": "local",
        }
    )
    if info["version"] != version.removeprefix("anywk "):
        raise ValueError("二进制与构建声明版本不一致")
    digest = sha256(binary.read_bytes())
    if info.get("binarySha256", digest) != digest:
        raise ValueError("二进制与构建声明摘要不一致")
    return {**info, "binarySha256": digest}


async def prepare(args) -> Path:
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    if args.release:
        binary = install_release(args.release, output / "release")
        build_info = binary.parent / "build-info.json"
    else:
        binary = args.binary.resolve()
        build_info = args.build_info or (
            binary.parent / "build-info.json"
            if (binary.parent / "build-info.json").is_file()
            else None
        )
    identity = binary_identity(binary, build_info)
    if args.release and identity["gitCommit"] is None:
        raise ValueError("发布构件必须具有真实构建提交")
    shutil.copy2(binary, output / "anywk")
    base = load_profile(args.base_config)
    if base.get("skills", {}).get("external_dirs"):
        raise ValueError("冻结评测请使用 --skill-dir 上传来源，并清空未冻结的容器 external_dirs")
    _, native_model = parse_model_name(args.model, skip_model_parsing=args.skip_model_parsing)
    for name in args.env_name:
        if name not in {
            account.get("bearer_token_env") for account in base["models"]["accounts"].values()
        }:
            raise ValueError("env-name 必须引用原生账号声明的凭据变量")
    manifest = read_json(args.task_manifest)
    reward_keys = manifest.get("rewardKeys", [])
    if len(reward_keys) > 1 and args.reward_key is None:
        raise ValueError("多个奖励键时必须显式选择 --reward-key")
    if reward_keys and args.reward_key is not None and args.reward_key not in reward_keys:
        raise ValueError("所选奖励键不在任务清单中")
    suite = args.suite
    if manifest["suite"] != suite:
        raise ValueError("任务 manifest 与 suite 不一致")
    if suite == "smoke":
        configs = [
            TaskConfig(path=(args.task_manifest.parent / task["path"]).resolve())
            for task in manifest["tasks"]
        ]
    else:
        if manifest.get("dataset") != f"{DATASET}@{DATASET_VERSION}":
            raise ValueError("只支持固定 Terminal-Bench 4.0.0 数据集")
        configs = await DatasetConfig(name=DATASET, version=DATASET_VERSION).get_task_configs()
        configs.sort(key=lambda config: str(config.get_task_id()))
        if suite == "dev":
            configs = configs[:10]
        if suite == "dev" and len(configs) != 10:
            raise ValueError("开发集必须解析出十个任务")
    tasks = []
    for index, config in enumerate(configs):
        source = config.get_local_path()
        task = Task(source)
        destination = output / "tasks" / f"{index:04}"
        before = tree_hashes(source)
        shutil.copytree(source, destination)
        if suite == "smoke":
            if args.fixture_binary is None:
                raise ValueError("离线 smoke 必须提供 --fixture-binary")
            shutil.copy2(args.fixture_binary, destination / "environment/pl-provider-fixture")
        image_inputs = freeze_images(destination)
        frozen_files = tree_hashes(destination)
        task_config = Task(destination).config.model_dump(mode="json")
        tasks.append(
            {
                "id": task.name,
                "source": config.model_dump(mode="json"),
                "path": str(destination),
                "files": frozen_files,
                "sourceContentHash": digest_object(before),
                "contentHash": digest_object(frozen_files),
                "taskConfig": task_config,
                "images": image_inputs,
                "agentTimeoutSec": 1800 if suite == "dev" else task.config.agent.timeout_sec,
            }
        )
    if not tasks or len({task["id"] for task in tasks}) != len(tasks):
        raise ValueError("任务为空或身份重复")
    variants = args.variants or (["B"] if suite == "smoke" else ["A", "B", "C", "D"])
    if "A" in variants and not args.baseline_version:
        raise ValueError("外部基线必须固定 baseline-version")
    if "D" in variants and identity["gitCommit"] is None:
        raise ValueError("D 组必须提供具有真实提交的二进制构建声明")
    if "D" in variants and args.history_seed is None:
        raise ValueError("D 组必须提供专用开发集冻结种子")
    seed_hash = None
    if args.history_seed:
        seed = validate_seed(
            args.history_seed,
            config=args.base_config,
            expected_version=identity["version"],
            expected_commit=identity["gitCommit"],
            excluded_tasks=[task["id"] for task in tasks],
        )
        seed_hash = seed["seedHash"]
        shutil.copytree(args.history_seed, output / "history-seed")
    profiles = {}
    skills = []
    for index, source in enumerate(args.skill_dir):
        frozen = output / "skills" / f"{index:03}"
        hashes = tree_hashes(source)
        shutil.copytree(source, frozen)
        skills.append({"path": str(frozen), "files": hashes})
    for variant in variants:
        if variant != "A":
            profile = render_profile(base, variant, args.account, native_model, args.effort)
            profile_path = output / f"profile-{variant}.toml"
            profile_path.write_text(tomlkit.dumps(profile))
            profiles[variant] = {
                "path": str(profile_path),
                "sha256": sha256(profile_path.read_bytes()),
            }
    if not math.isfinite(args.pass_threshold):
        raise ValueError("奖励阈值必须是有限数值")
    attempts = args.attempts or {"smoke": 1, "dev": 3, "full": 5}[suite]
    slots = [
        {
            "slotId": str(uuid4()),
            "taskId": task["id"],
            "variant": variant,
            "repeat": repeat,
            "replacementParentId": None,
        }
        for task in tasks
        for repeat in range(1, attempts + 1)
        for variant in variants
    ]
    package = Path(__file__).resolve().parents[2]
    lock = package / "uv.lock"
    plan = {
        "schemaVersion": 1,
        "planId": str(uuid4()),
        "suite": suite,
        "binary": identity,
        "binaryPath": str(output / "anywk"),
        "harborCommit": HARBOR_COMMIT,
        "lockHash": sha256(lock.read_bytes()) if lock.exists() else args.lock_hash,
        "adapterSourceHash": adapter_source_hash(),
        "dataset": manifest.get("dataset"),
        "taskManifestHash": sha256(args.task_manifest.read_bytes()),
        "tasks": tasks,
        "profiles": profiles,
        "catalogHash": catalog_identity(base),
        "pricingHash": digest_object(
            {key: account["catalog"] for key, account in base["models"]["accounts"].items()}
        ),
        "variants": variants,
        "model": args.model,
        "nativeModel": native_model,
        "skipModelParsing": args.skip_model_parsing,
        "accountId": args.account,
        "effort": args.effort,
        "mode": args.mode,
        "maxModelSteps": args.max_model_steps,
        "baselineAgent": args.baseline_agent,
        "baselineVersion": args.baseline_version,
        "historySeedHash": seed_hash,
        "historySeedDir": str(output / "history-seed") if seed_hash else None,
        "envNames": args.env_name,
        "skills": skills,
        "attempts": attempts,
        "slots": slots,
        "rewardKey": args.reward_key or (reward_keys[0] if len(reward_keys) == 1 else "reward"),
        "rewardKeyExplicit": args.reward_key is not None,
        "passThreshold": args.pass_threshold,
        "costStopUsd": args.cost_stop_usd,
        "concurrency": 1,
        "retry": 0,
    }
    if not plan["lockHash"]:
        raise ValueError("安装包运行时须提供 --lock-hash")
    plan["hash"] = digest_object(plan)
    atomic_json(output / "plan.json", plan)
    return output / "plan.json"


def validate_plan(path: Path) -> dict:
    plan = read_json(path)
    digest = plan.pop("hash")
    if digest_object(plan) != digest or plan["schemaVersion"] != 1:
        raise ValueError("计划摘要不匹配")
    plan["hash"] = digest
    if sha256(Path(plan["binaryPath"]).read_bytes()) != plan["binary"]["binarySha256"]:
        raise ValueError("二进制已改变")
    if plan["harborCommit"] != HARBOR_COMMIT:
        raise ValueError("Harbor 身份已改变")
    if plan["adapterSourceHash"] != adapter_source_hash():
        raise ValueError("适配器源码已改变，必须重新冻结计划")
    for profile in plan["profiles"].values():
        if sha256(Path(profile["path"]).read_bytes()) != profile["sha256"]:
            raise ValueError("原生配置已改变")
    for task in plan["tasks"]:
        if tree_hashes(Path(task["path"])) != task["files"]:
            raise ValueError("冻结任务已改变")
    for skill in plan["skills"]:
        if tree_hashes(Path(skill["path"])) != skill["files"]:
            raise ValueError("冻结技能已改变")
    return plan


def adapter_source_hash():
    root = Path(__file__).parent
    return digest_object(
        {
            path.relative_to(root).as_posix(): sha256(path.read_bytes())
            for path in sorted(root.rglob("*"))
            if path.is_file() and "__pycache__" not in path.parts and path.suffix in (".py", ".sh")
        }
    )


def job_config(plan, slot, output: Path, job_name: str) -> JobConfig:
    task = next(task for task in plan["tasks"] if task["id"] == slot["taskId"])
    env = {}
    for name in plan["envNames"]:
        if not os.environ.get(name):
            raise ValueError(f"缺少显式注入的凭据环境变量：{name}")
        env[name] = os.environ[name]
    if slot["variant"] == "A":
        agent = {
            "name": plan["baselineAgent"],
            "model_name": plan["model"],
            "env": env,
            "kwargs": {"version": plan["baselineVersion"]},
        }
        if plan["effort"]:
            agent["kwargs"]["reasoning_effort"] = plan["effort"]
    else:
        agent = {
            "import_path": "anywork_harbor.agent:AnyworkInstalledAgent",
            "model_name": plan["model"],
            "skip_model_parsing": plan["skipModelParsing"],
            "env": env,
            "kwargs": {
                "binary_path": plan["binaryPath"],
                "config_path": plan["profiles"][slot["variant"]]["path"],
                "account_id": plan["accountId"],
                "mode": plan["mode"],
                "max_model_steps": plan["maxModelSteps"],
                "reasoning_effort": plan["effort"],
                "no_default_user_skills": True,
                "extra_skill_dirs": [skill["path"] for skill in plan["skills"]],
            },
        }
        if slot["variant"] == "D":
            agent["kwargs"]["history_seed_dir"] = plan["historySeedDir"]
            agent["kwargs"]["expected_git_commit"] = plan["binary"]["gitCommit"]
    if plan["suite"] == "dev":
        agent["override_timeout_sec"] = 1800
    return JobConfig.model_validate(
        {
            "job_name": job_name,
            "jobs_dir": str(output / "jobs"),
            "n_attempts": 1,
            "n_concurrent_trials": 1,
            "retry": {"max_retries": 0},
            "override_error_policy": ERROR_POLICY,
            "agents": [agent],
            "tasks": [{"path": task["path"]}],
            "environment": {"type": "docker"},
        }
    )


def trial_budget_seconds(task: dict) -> float:
    config = task["taskConfig"]
    # 包含 environment/setup/verifier 与清理上传余量；agent 不是唯一计时器。
    return (
        config["environment"]["build_timeout_sec"]
        + 360
        + task["agentTimeoutSec"]
        + config["verifier"]["timeout_sec"]
        + 180
    )


async def run_plan(args):
    import fcntl

    from .summarize import read_trial

    plan = validate_plan(args.plan)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with (output / "launcher.lock").open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state_path = output / "checkpoint.json"
        if state_path.exists():
            state = read_json(state_path)
            if state["planHash"] != plan["hash"]:
                raise ValueError("输出目录属于另一冻结计划")
        else:
            state = {
                "planHash": plan["hash"],
                "launcherRunId": str(uuid4()),
                "slots": {},
                "stopReason": None,
            }
            atomic_json(output / "plan.json", plan)
        threshold = args.cost_stop_usd if args.cost_stop_usd is not None else plan["costStopUsd"]
        if threshold != plan["costStopUsd"]:
            raise ValueError("费用停止阈值属于冻结计划，修改须 prepare 新计划")
        if any(value["status"] == "started" for value in state["slots"].values()):
            state["stopReason"] = "interruptedTrialRequiresCleanupAndCostReconciliation"
            for value in state["slots"].values():
                if value["status"] == "started":
                    value.update(status="interrupted", costComplete=False, costUsd=None)
            atomic_json(state_path, state)
            return
        started = time.monotonic()
        for slot in plan["slots"]:
            if slot["slotId"] in state["slots"]:
                continue
            records = list(state["slots"].values())
            if any(
                not r.get("costComplete")
                or not r.get("cleanupClean", True)
                or r.get("artifactValidation") == "failed"
                for r in records
            ):
                state["stopReason"] = "unknownCostOrUncleanInfrastructure"
                break
            if sum(r["costUsd"] for r in records) >= threshold:
                state["stopReason"] = "costStopReached"
                break
            task = next(t for t in plan["tasks"] if t["id"] == slot["taskId"])
            if args.wall_budget_sec is not None and (
                time.monotonic() - started + trial_budget_seconds(task) > args.wall_budget_sec
            ):
                state["stopReason"] = "insufficientWallBudgetForNextTrial"
                break
            attempt_id = str(uuid4())
            job_name = f"anywk-{attempt_id}"
            record = {
                **slot,
                "attemptId": attempt_id,
                "status": "started",
                "runId": None,
                "launcherRunId": state["launcherRunId"],
                "jobName": job_name,
            }
            state["slots"][slot["slotId"]] = record
            atomic_json(state_path, state)  # 在 Harbor admission 之前保存，崩溃不能隐式重跑。
            config = job_config(plan, slot, output, job_name)
            try:
                job = await Job.create(config)
                await job.run()
            except (OSError, RuntimeError, ValueError) as error:
                record["launcherError"] = type(error).__name__
            results = list((output / "jobs" / job_name).glob("*/result.json"))
            if len(results) == 1:
                record.update(read_trial(results[0], plan, slot))
            else:
                record.update(
                    costComplete=False,
                    costUsd=None,
                    cleanupClean=False,
                    artifactValidation="failed",
                    invalidReason="missingTrialResult",
                )
            record["status"] = "terminal"
            atomic_json(state_path, state)
        atomic_json(state_path, state)


def positive(value):
    parsed = float(value)
    if not math.isfinite(parsed) or parsed <= 0:
        raise argparse.ArgumentTypeError("必须是有限正数")
    return parsed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prep = sub.add_parser("prepare", help="冻结输入；不调用模型")
    source = prep.add_mutually_exclusive_group(required=True)
    source.add_argument("--binary", type=Path)
    source.add_argument("--release")
    prep.add_argument("--build-info", type=Path)
    prep.add_argument("--fixture-binary", type=Path)
    prep.add_argument("--skill-dir", type=Path, action="append", default=[])
    prep.add_argument("--base-config", type=Path, required=True)
    prep.add_argument("--suite", choices=["smoke", "dev", "full"], required=True)
    prep.add_argument("--task-manifest", type=Path, required=True)
    prep.add_argument("--account", required=True)
    prep.add_argument("--model", required=True)
    prep.add_argument("--skip-model-parsing", action="store_true")
    prep.add_argument("--effort")
    prep.add_argument("--mode", default="mode.simple")
    prep.add_argument("--max-model-steps", type=int)
    prep.add_argument("--variants", nargs="+", choices=list("ABCD"))
    prep.add_argument("--attempts", type=int)
    prep.add_argument("--baseline-agent", default="codex")
    prep.add_argument("--baseline-version")
    prep.add_argument("--history-seed", type=Path)
    prep.add_argument("--env-name", action="append", default=[])
    prep.add_argument("--lock-hash")
    prep.add_argument("--reward-key")
    prep.add_argument("--pass-threshold", type=float, default=1.0)
    prep.add_argument("--cost-stop-usd", type=positive, required=True)
    prep.add_argument("--output", type=Path, required=True)
    run = sub.add_parser("run", help="按计划显式调用 Harbor")
    run.add_argument("--plan", type=Path, required=True)
    run.add_argument("--output", type=Path, required=True)
    run.add_argument("--cost-stop-usd", type=positive)
    run.add_argument("--wall-budget-sec", type=positive)
    args = parser.parse_args(argv)
    if args.command == "prepare":
        for name in ("attempts", "max_model_steps"):
            if getattr(args, name) is not None and getattr(args, name) <= 0:
                parser.error(f"{name} 必须为正整数")
        print(asyncio.run(prepare(args)))
    else:
        asyncio.run(run_plan(args))
    return 0
