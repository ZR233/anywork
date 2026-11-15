"""准备一次性 Harbor Docker 任务，使用当前源码构建的二进制与共享 fixture。"""

import argparse
import asyncio
import json
import shutil
from pathlib import Path

from harbor.job import Job
from harbor.models.job.config import JobConfig

from .artifacts import read_and_validate_run_artifacts, read_json
from .errors import ERROR_POLICY
from .trajectory import convert_run_to_atif


async def run_smoke(binary: Path, fixture: Path, output: Path, root: Path, case: str = "file"):
    output.mkdir(parents=True, exist_ok=False)
    task = output / "file-task"
    shutil.copytree(root / "fixtures/tasks/file-task", task)
    shutil.copy2(fixture, task / "environment/pl-provider-fixture")
    if case == "cancel":
        dockerfile = task / "environment/Dockerfile"
        dockerfile.write_text(dockerfile.read_text() + "\nENV HARBOR_FIXTURE_CASE=cancel\n")
        (task / "tests/test.sh").write_text(
            "#!/bin/sh\nset -eu\nmkdir -p /logs/verifier\n"
            "before=$(wc -c < /workspace/task/harbor-result.txt)\nsleep 1\n"
            "after=$(wc -c < /workspace/task/harbor-result.txt)\n"
            'if [ "$before" -gt 0 ] && [ "$before" = "$after" ]; then reward=1; else reward=0; fi\n'
            'printf "%s\\n" "$reward" > /logs/verifier/reward.txt\n'
        )
    config = JobConfig.model_validate(
        {
            "job_name": "smoke",
            "jobs_dir": str(output / "jobs"),
            "n_attempts": 1,
            "n_concurrent_trials": 1,
            "retry": {"max_retries": 0},
            "override_error_policy": ERROR_POLICY,
            "agents": [
                {
                    "import_path": "anywork_harbor.agent:AnyworkInstalledAgent",
                    "model_name": "vendor/harbor-fixture",
                    "skip_model_parsing": True,
                    **({"override_timeout_sec": 5} if case == "cancel" else {}),
                    "kwargs": {
                        "binary_path": str(binary),
                        "config_path": str(root / "profiles/fixture.toml"),
                        "account_id": "fixture",
                    },
                }
            ],
            "tasks": [{"path": str(task)}],
            "environment": {"type": "docker"},
        }
    )
    job = await Job.create(config)
    await job.run()
    results = list((output / "jobs/smoke").glob("*/result.json"))
    if len(results) != 1:
        raise RuntimeError("smoke 未产生唯一 trial")
    result = read_json(results[0])
    if (case == "file" and not result.get("reward_valid")) or result.get("verifier_result", {}).get(
        "rewards", {}
    ).get("reward") != 1:
        raise RuntimeError("smoke verifier 未通过；查看 trial 日志")
    if case == "cancel":
        cleanup = read_json(results[0].parent / "agent/cleanup.json")
        from harbor.models.trial.result import TrialResult

        trial = TrialResult.model_validate(result)
        if not cleanup.get("clean") or not any(
            "Timeout" in error.exception_type for error in trial.recorded_exceptions()
        ):
            raise RuntimeError("取消未同时证明外层超时、回收成功与停止写入")
        print(json.dumps({"case": case, "reward": 1, "cleanup": cleanup}))
        return
    artifacts = read_and_validate_run_artifacts(results[0].parent / "agent/native")
    convert_run_to_atif(artifacts)
    print(
        json.dumps(
            {"reward": 1, "runId": artifacts.manifest["runId"], "traceComplete": artifacts.complete}
        )
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=("file", "cancel"), default="file")
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    asyncio.run(
        run_smoke(
            args.binary.resolve(),
            args.fixture.resolve(),
            args.output.resolve(),
            args.root.resolve(),
            args.case,
        )
    )


if __name__ == "__main__":
    main()
