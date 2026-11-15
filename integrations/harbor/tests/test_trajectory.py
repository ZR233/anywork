import json

from conftest import rewrite_events
from harbor.models.agent.context import AgentContext
from harbor.utils.trajectory_validator import TrajectoryValidator

from anywork_harbor.artifacts import read_and_validate_run_artifacts
from anywork_harbor.trajectory import convert_run_to_atif, populate_context


def test_tree_usage_is_counted_once_with_real_spawn_reference(archive):
    artifacts = read_and_validate_run_artifacts(archive)
    trajectory = convert_run_to_atif(artifacts)
    assert TrajectoryValidator().validate(trajectory.model_dump(exclude_none=True))
    assert len(trajectory.subagent_trajectories) == 1
    child = trajectory.subagent_trajectories[0]
    assert child.trajectory_id == f"{artifacts.manifest['runId']}:thread-child-1"
    assert (
        trajectory.steps[0].observation.results[-1].subagent_trajectory_ref[0].trajectory_id
        == child.trajectory_id
    )
    context = AgentContext()
    populate_context(context, artifacts, trajectory, {})
    assert context.cost_usd == 0.007
    assert context.n_input_tokens == 140
    assert context.model_usage["vendor/golden-model"].n_input_tokens == 140
    assert sum(step.llm_call_count or 0 for step in trajectory.steps + child.steps) == 2


def test_unknown_tokens_do_not_trigger_harbor_zero_fallback(archive):
    events = [json.loads(line) for line in (archive / "events.jsonl").read_text().splitlines()]
    bill = next(e for e in events if e["type"] == "inferenceFinished")
    bill["data"]["billing"]["accounting"]["usage"]["inputTokens"] = None
    rewrite_events(archive, events)
    artifacts = read_and_validate_run_artifacts(archive)
    trajectory = convert_run_to_atif(artifacts)
    context = AgentContext()
    populate_context(context, artifacts, trajectory, {})
    assert context.model_usage == {}
    assert not context.is_empty()
    child = trajectory.subagent_trajectories[0]
    assert child.steps[0].metrics.prompt_tokens is None


def test_each_call_uses_its_frozen_sent_or_reported_model(archive):
    events = [json.loads(line) for line in (archive / "events.jsonl").read_text().splitlines()]
    for event in events:
        if event["type"] == "inferenceFinished":
            event["data"]["billing"]["modelObservation"] = {
                "configuredModel": "configured",
                "sentModel": "sent-" + event["threadId"],
                "reportedModel": "reported-" + event["threadId"],
            }
    rewrite_events(archive, events)
    trajectory = convert_run_to_atif(read_and_validate_run_artifacts(archive))
    assert trajectory.agent.model_name is None
    child = trajectory.subagent_trajectories[0]
    assert child.steps[0].model_name == "reported-thread-child-1"
    assert trajectory.steps[-1].model_name == "reported-thread-root"
