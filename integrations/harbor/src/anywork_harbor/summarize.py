"""保留全部投放结果、未知值及配对边界的评测报告。"""

import argparse
import csv
import json
import math
import random
import statistics
from collections import defaultdict
from pathlib import Path

from .artifacts import read_and_validate_run_artifacts, read_json


def _duration(value):
    if value is None or value.started_at is None or value.finished_at is None:
        return None
    return (value.finished_at - value.started_at).total_seconds() * 1000


def purpose_usage(artifacts):
    groups = {}
    for event in artifacts.events:
        if event["type"] != "inferenceFinished":
            continue
        data = event["data"]
        bill = data["billing"]
        key = (bill["purpose"], data["auxiliary"])
        group = groups.setdefault(key, {"purpose": key[0], "auxiliary": key[1], "calls": []})
        accounting = bill["accounting"]
        group["calls"].append(
            {
                "threadId": event["threadId"],
                "inferenceId": bill["inferenceId"],
                "accountId": bill.get("accountId"),
                "modelId": bill.get("modelId"),
                "accounting": accounting,
            }
        )
    for group in groups.values():
        fields = (
            "inputTokens",
            "outputTokens",
            "cacheReadTokens",
            "cacheWriteTokens",
            "reasoningTokens",
            "totalTokens",
        )
        totals, known, missing = {}, {}, {}
        for field in fields:
            values = [(call["accounting"].get("usage") or {}).get(field) for call in group["calls"]]
            missing[field] = sum(value is None for value in values)
            known[field] = sum(value for value in values if value is not None)
            totals[field] = known[field] if not missing[field] else None
        group.update(
            inferenceCount=len(group["calls"]),
            totals=totals,
            knownTotals=known,
            unknownCounts=missing,
        )
    return list(groups.values())


def read_trial(path: Path, plan: dict, slot: dict) -> dict:
    try:
        return _read_trial(path, plan, slot)
    except (OSError, ValueError, TypeError, RuntimeError) as error:
        return {
            "trialResultPath": str(path),
            "rewardValid": False,
            "reward": None,
            "invalidReason": ["unreadableTrialArtifacts"],
            "exceptionTypes": [type(error).__name__],
            "artifactValidation": "failed",
            "cleanupClean": False,
            "costComplete": False,
            "costUsd": None,
            "knownCostUsd": None,
            "usageComplete": False,
            "traceComplete": False,
        }


def _read_trial(path: Path, plan: dict, slot: dict) -> dict:
    from harbor.models.trial.result import TrialResult

    trial = TrialResult.model_validate(read_json(path))
    directory = path.parent / "agent"
    adapter = (
        read_json(directory / "adapter.json") if (directory / "adapter.json").is_file() else {}
    )
    native_path = directory / "native/result.json"
    native = {}
    native_invalid = False
    purposes = []
    if native_path.is_file():
        try:
            native = read_json(native_path)
            artifacts = read_and_validate_run_artifacts(
                directory / "native",
                require_success=native.get("exitCode") == 0,
                expected_exit=adapter.get("cliExitCode"),
            )
            purposes = purpose_usage(artifacts)
        except (RuntimeError, ValueError, TypeError, OSError):
            native_invalid = True
            native = {}
    context = trial.agent_result
    metadata = context.metadata if context and context.metadata else {}
    cleanup = (
        read_json(directory / "cleanup.json")
        if (directory / "cleanup.json").is_file()
        else (metadata.get("cleanup") or {"clean": True})
    )
    errors = [error.exception_type for error in trial.recorded_exceptions()]
    validation = adapter.get("artifactValidation", metadata.get("artifactValidation"))
    reasons = []
    if native_invalid:
        reasons.append("nativeArtifactInvalid")
        validation = "failed"
    if not trial.reward_valid:
        reasons.append("harborRewardInvalid")
    if any(error in ("AnywkSetupError", "AnywkArtifactError") for error in errors):
        reasons.append("anywkInfrastructureError")
    if not cleanup.get("clean"):
        reasons.append("cleanupFailed")
    if validation == "failed" or (native.get("exitCode") == 0 and validation != "passed"):
        reasons.append("artifactValidationFailed")
    rewards = trial.verifier_result.rewards if trial.verifier_result else {}
    if len(rewards or {}) > 1 and not plan.get("rewardKeyExplicit", False):
        reasons.append("ambiguousRewardKey")
    reward = (rewards or {}).get(plan["rewardKey"])
    if not isinstance(reward, (int, float)) or not math.isfinite(reward):
        reasons.append("missingOrInvalidSelectedReward")
        reward = None
    usage = native.get("usage") or {}
    totals, known = usage.get("totals", {}), usage.get("knownTotals", {})
    baseline = slot["variant"] == "A"
    cost = context.cost_usd if baseline and context else totals.get("estimatedCostUsd")
    complete_cost = not native_invalid and (
        cost is not None
        and math.isfinite(cost)
        and (baseline or native.get("costComplete") is True)
    )
    if not complete_cost:
        cost = None
    result = {
        "reward": reward,
        "rewardValid": not reasons,
        "invalidReason": reasons,
        "exceptionTypes": errors,
        "cleanupClean": cleanup.get("clean") is True,
        "cleanup": cleanup,
        "artifactValidation": validation,
        "cliCompleted": native.get("outcome") == "completed" and native.get("exitCode") == 0,
        "traceComplete": native.get("traceComplete"),
        "usageComplete": native.get("usageComplete"),
        "costComplete": complete_cost,
        "costUsd": cost,
        "knownCostUsd": cost if baseline and complete_cost else known.get("estimatedCostUsd"),
        "runId": native.get("runId"),
        "nativeOutcome": native.get("outcome"),
        "nativeExitCode": native.get("exitCode"),
        "usage": usage,
        "purposeUsage": purposes,
        "pricingComparability": "baselineNotRepriced" if baseline else "nativeFrozenCatalog",
        "modelUsage": context.model_usage if baseline and context else None,
        "timing": {
            "harborAgentMs": _duration(trial.agent_execution),
            "environmentSetupMs": _duration(trial.environment_setup),
            "agentSetupMs": _duration(trial.agent_setup),
            "verifierMs": _duration(trial.verifier),
            "adapterValidationMs": adapter.get("validationWallMs"),
            **native.get("timing", {}),
        },
        "timedOut": any("Timeout" in error for error in errors),
        "trialResultPath": str(path),
    }
    if slot["variant"] == "B":
        mismatches = [
            model
            for model in usage.get("byModel", [])
            if model.get("accountId") != plan["accountId"]
            or model.get("modelId") != plan["nativeModel"]
        ]
        if mismatches:
            result["rewardValid"] = False
            result["invalidReason"].append("fixedModelRouteMismatch")
            result["artifactValidation"] = "failed"
    if baseline and context and context.model_usage:
        result["modelUsage"] = {
            key: value.model_dump() for key, value in context.model_usage.items()
        }
    return result


def quantile(values, probability):
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def paired_bootstrap(records, left, right, threshold):
    values = defaultdict(lambda: defaultdict(list))
    for record in records:
        if record.get("rewardValid"):
            values[record["variant"]][record["taskId"]].append(record["reward"])
    a, b = values[left], values[right]
    shared = sorted(set(a) & set(b))
    expected = {r["taskId"] for r in records if r["variant"] in (left, right)}
    differences = [statistics.mean(b[task]) - statistics.mean(a[task]) for task in shared]
    rng = random.Random(20261113)
    samples = (
        [statistics.mean(rng.choices(differences, k=len(differences))) for _ in range(10_000)]
        if differences
        else []
    )
    return {
        "left": left,
        "right": right,
        "nTasks": len(shared),
        "missingPairs": len(expected) - len(shared),
        "meanRewardDifference": statistics.mean(differences) if differences else None,
        "interval95": [quantile(samples, 0.025), quantile(samples, 0.975)],
        "stableConclusionAllowed": len(shared) >= 10,
        "method": "task-mean paired bootstrap; 10000; seed=20261113",
    }


def aggregate(plan: dict, records: list[dict]) -> dict:
    scheduled = len(records)
    valid = [record for record in records if record.get("rewardValid")]
    successes = [record for record in valid if record["reward"] >= plan["passThreshold"]]
    known_cost = sum(
        record["knownCostUsd"] for record in records if record.get("knownCostUsd") is not None
    )
    unknown_costs = sum(not record.get("costComplete") for record in records)
    complete_cost = scheduled > 0 and unknown_costs == 0
    total = sum(record["costUsd"] for record in records) if complete_cost else None
    latencies = {}
    for key in ("harborAgentMs", "agentWallMs"):
        values = [
            record["timing"][key]
            for record in successes
            if not record.get("timedOut") and record.get("timing", {}).get(key) is not None
        ]
        latencies[key] = {
            "n": len(values),
            "p50": quantile(values, 0.5),
            "p95": quantile(values, 0.95),
        }
    return {
        "planned": len(plan["slots"]),
        "scheduled": scheduled,
        "valid": len(valid),
        "invalid": scheduled - len(valid),
        "successes": len(successes),
        "validRewardMean": statistics.mean(r["reward"] for r in valid) if valid else None,
        "validCoverage": len(valid) / scheduled if scheduled else None,
        "deliveryRate": len(successes) / scheduled if scheduled else None,
        "cliCompletedRate": sum(r.get("cliCompleted", False) for r in records) / scheduled
        if scheduled
        else None,
        "costUsd": total,
        "knownCostUsdLowerBound": known_cost,
        "unknownCostRate": unknown_costs / scheduled if scheduled else None,
        "costPerSuccess": total / len(successes) if successes and complete_cost else None,
        "costPerSuccessStatus": "notApplicable"
        if not successes
        else ("known" if complete_cost else "unknown"),
        "timeouts": sum(r.get("timedOut", False) for r in records),
        "timeoutRate": sum(r.get("timedOut", False) for r in records) / scheduled
        if scheduled
        else None,
        "latency": latencies,
    }


def summarize(source: Path, output: Path):
    plan, state = read_json(source / "plan.json"), read_json(source / "checkpoint.json")
    if state["planHash"] != plan["hash"]:
        raise ValueError("检查点与计划身份不一致")
    records = list(state["slots"].values())
    for record in records:
        if record.get("trialResultPath"):
            # 晚发生的 post-run 错误也必须进入报告，不能只信投放时的旧检查点。
            record.update(read_trial(Path(record["trialResultPath"]), plan, record))
    output.mkdir(parents=True, exist_ok=False)
    comparisons = [
        paired_bootstrap(records, left, right, plan["passThreshold"])
        for left, right in (("A", "B"), ("B", "C"), ("C", "D"))
        if left in plan["variants"] and right in plan["variants"]
    ]
    grouped = {
        variant: aggregate(
            {**plan, "slots": [s for s in plan["slots"] if s["variant"] == variant]},
            [r for r in records if r["variant"] == variant],
        )
        for variant in plan["variants"]
    }
    summary = {
        "schemaVersion": 1,
        "planHash": plan["hash"],
        "suite": plan["suite"],
        **aggregate(plan, records),
        "byVariant": grouped,
        "pairedComparisons": comparisons,
        "stopReason": state.get("stopReason"),
        "trials": records,
        "reproduction": plan,
    }
    (output / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2, allow_nan=False)
    )
    keys = sorted({key for record in records for key in record})
    with (output / "trials.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=keys)
        writer.writeheader()
        writer.writerows(
            {
                key: json.dumps(value, ensure_ascii=False)
                if isinstance(value, (dict, list))
                else value
                for key, value in record.items()
            }
            for record in records
        )
    text = [
        f"# Anywork Harbor 评测报告（{plan['suite']}）",
        "",
        f"计划摘要：`{plan['hash']}`。已投放 {len(records)} / {len(plan['slots'])}。",
        "",
        "| 组 | 有效样本平均分 | 全投放成功交付率 | 有效 / 无效 | 完整费用 USD | 已知费用下界 USD |",
        "| --- | ---: | ---: | --- | ---: | ---: |",
    ]
    for variant, result in grouped.items():
        text.append(
            f"| {variant} | {result['validRewardMean']} | {result['deliveryRate']} | "
            f"{result['valid']} / {result['invalid']} | {result['costUsd']} | "
            f"{result['knownCostUsdLowerBound']} |"
        )
    text.extend(
        [
            "",
            "未知值显示为 null，不作为零费用。无成功样本时，成功一次的费用不适用。",
            "延迟仅统计有效成功样本；超时按截尾单列。导出封口耗时属于关闭区间，不重复相加。",
            "A/B 为执行框架比较，B/C/D 为策略比较；少于十个独立任务不作稳定性结论。",
            "全部逐次结果、模型/用途用量、阶段耗时、失败原因和复现身份见 summary.json 与 trials.csv。",
        ]
    )
    (output / "report.md").write_text("\n".join(text) + "\n")
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    summarize(args.input, args.output)
    return 0
