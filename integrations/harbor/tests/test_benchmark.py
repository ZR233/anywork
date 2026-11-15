import argparse
import json
from pathlib import Path

from anywork_harbor.benchmark import atomic_json, digest_object, job_config, run_plan
from anywork_harbor.errors import ERROR_POLICY
from anywork_harbor.render_profile import load_profile, render_profile
from anywork_harbor.summarize import aggregate, paired_bootstrap, purpose_usage, quantile

ROOT = Path(__file__).resolve().parents[1]


def test_profile_fixed_routes_preserve_capabilities_and_cold_hot_share_catalog():
    original = load_profile(ROOT / "profiles/fixture.toml")
    original["models"]["routes"] = {"explorer": {"account_id": "other", "model_id": "other"}}
    fixed = render_profile(original, "B", "fixture", "vendor/harbor-fixture", None)
    assert all(
        route == {"account_id": "fixture", "model_id": "vendor/harbor-fixture"}
        for route in [*fixed["mode_model_routes"].values(), *fixed["models"]["routes"].values()]
    )
    cold = render_profile(original, "C", "fixture", "vendor/harbor-fixture", None)
    hot = render_profile(original, "D", "fixture", "vendor/harbor-fixture", None)
    assert cold == hot
    assert cold["models"]["accounts"] == original["models"]["accounts"]
    assert cold["delegation"]["mode"] == "automatic"
    assert cold["runtime"]["tool_capabilities"]["mcp"] is False
    assert cold["skills"]["auto_learn"] is False


def test_report_denominators_unknown_cost_and_no_success():
    plan = {"slots": [1, 2, 3, 4], "passThreshold": 1}
    records = [
        {
            "rewardValid": True,
            "reward": 1,
            "cliCompleted": True,
            "costComplete": True,
            "costUsd": 2,
            "knownCostUsd": 2,
            "timing": {"agentWallMs": 10, "harborAgentMs": 20},
        },
        {"rewardValid": True, "reward": 0, "costComplete": True, "costUsd": 3, "knownCostUsd": 3},
        {
            "rewardValid": False,
            "reward": 1,
            "costComplete": False,
            "costUsd": None,
            "knownCostUsd": 0.5,
            "timedOut": True,
        },
    ]
    summary = aggregate(plan, records)
    assert (summary["planned"], summary["scheduled"], summary["valid"], summary["invalid"]) == (
        4,
        3,
        2,
        1,
    )
    assert summary["validRewardMean"] == 0.5
    assert summary["deliveryRate"] == 1 / 3
    assert summary["knownCostUsdLowerBound"] == 5.5
    assert summary["costUsd"] is None
    assert summary["costPerSuccess"] is None
    assert summary["latency"]["agentWallMs"] == {"n": 1, "p50": 10, "p95": 10}
    summary = aggregate(plan, records[1:])
    assert summary["costPerSuccessStatus"] == "notApplicable"


def test_task_level_bootstrap_aggregates_repeats_and_is_reproducible():
    records = [
        {"taskId": task, "variant": variant, "rewardValid": True, "reward": reward}
        for task in ("one", "two")
        for variant, reward in (("B", 0), ("C", 1))
        for _ in range(3)
    ]
    comparison = paired_bootstrap(records, "B", "C", 1)
    assert comparison["nTasks"] == 2
    assert comparison["interval95"] == [1, 1]
    assert not comparison["stableConclusionAllowed"]
    assert quantile([1, 3], 0.95) == 2.9


def test_standard_policy_is_present_in_every_generated_job(tmp_path):
    plan = {
        "tasks": [{"id": "task", "path": str(ROOT / "fixtures/tasks/file-task")}],
        "envNames": [],
        "binaryPath": "/binary",
        "profiles": {"B": {"path": "/config"}},
        "model": "vendor/model",
        "skipModelParsing": True,
        "accountId": "fixture",
        "mode": "mode.simple",
        "maxModelSteps": None,
        "effort": None,
        "skills": [],
        "suite": "smoke",
    }
    config = job_config(plan, {"variant": "B", "taskId": "task"}, tmp_path, "test")
    assert config.n_attempts == config.n_concurrent_trials == 1
    assert config.retry.max_retries == 0
    assert {
        key: value.model_dump() for key, value in config.override_error_policy.items()
    } == ERROR_POLICY


async def test_interrupted_admission_is_not_automatically_retried(tmp_path, monkeypatch):
    plan = {"schemaVersion": 1, "slots": [{"slotId": "slot"}], "costStopUsd": 10}
    plan["hash"] = digest_object(plan)
    monkeypatch.setattr("anywork_harbor.benchmark.validate_plan", lambda path: plan)
    output = tmp_path / "run"
    output.mkdir()
    atomic_json(
        output / "checkpoint.json",
        {
            "planHash": plan["hash"],
            "slots": {"slot": {"status": "started", "attemptId": "original"}},
        },
    )
    await run_plan(
        argparse.Namespace(
            plan=tmp_path / "plan.json", output=output, cost_stop_usd=10, wall_budget_sec=None
        )
    )
    state = json.loads((output / "checkpoint.json").read_text())
    assert state["slots"]["slot"]["status"] == "interrupted"
    assert state["slots"]["slot"]["attemptId"] == "original"
    assert state["slots"]["slot"]["costUsd"] is None
    assert state["stopReason"] == "interruptedTrialRequiresCleanupAndCostReconciliation"


def test_purpose_groups_preserve_auxiliary_calls_once_and_unknown_values(archive):
    from anywork_harbor.artifacts import read_and_validate_run_artifacts

    groups = purpose_usage(read_and_validate_run_artifacts(archive))
    assert sum(group["inferenceCount"] for group in groups) == 2
    assert sum(group["totals"]["inputTokens"] for group in groups) == 140
    auxiliary = next(group for group in groups if group["auxiliary"])
    assert auxiliary["purpose"] == "title"
    assert auxiliary["totals"]["inputTokens"] == 100


def test_corrupt_harbor_result_is_retained_as_unknown_cost(tmp_path):
    from anywork_harbor.summarize import read_trial

    result = tmp_path / "result.json"
    result.write_text('{"broken":')
    record = read_trial(result, {}, {})
    assert record["artifactValidation"] == "failed"
    assert not record["rewardValid"]
    assert record["costUsd"] is None
    assert record["invalidReason"] == ["unreadableTrialArtifacts"]
