import json

import pytest
from conftest import rewrite_events

from anywork_harbor.artifacts import read_and_validate_run_artifacts
from anywork_harbor.errors import AnywkArtifactError


def test_complete_archive_and_exact_content(archive):
    artifacts = read_and_validate_run_artifacts(archive, expected_exit=0)
    assert artifacts.complete
    tool = next(
        e
        for e in artifacts.events
        if e["type"] == "completion" and e["threadId"] == "thread-child-1"
    )
    assert artifacts.content(tool["data"]["contents"][0]) == b"A" * 1024


@pytest.mark.parametrize(
    "fault",
    [
        "missingResult",
        "wrongRun",
        "badHash",
        "badContent",
        "unsealed",
        "sequence",
        "duplicateBill",
        "badParent",
        "badCut",
        "spawn",
        "badSummary",
        "shutdown",
        "schema",
        "symlink",
        "middleLine",
    ],
)
def test_reject_corrupted_success(archive, tmp_path, fault):
    result = json.loads((archive / "result.json").read_text())
    events = [json.loads(line) for line in (archive / "events.jsonl").read_text().splitlines()]
    if fault == "missingResult":
        (archive / "result.json").unlink()
    elif fault == "wrongRun":
        result["runId"] = "00000000-0000-0000-0000-000000000000"
    elif fault == "badHash":
        result["trace"]["eventsSha256"] = "0" * 64
    elif fault == "badContent":
        next((archive / "contents").iterdir()).write_bytes(b"corrupt")
    elif fault == "unsealed":
        events.pop()
    elif fault == "sequence":
        events.pop(4)
    elif fault == "duplicateBill":
        events.insert(5, events[4])
    elif fault == "badParent":
        events[3]["data"]["parentAgentId"] = "wrong"
    elif fault == "badCut":
        events[-1]["data"]["members"][0]["throughEffectSeq"] += 1
    elif fault == "spawn":
        events[3]["data"]["spawnToolCallId"] = "missing-spawn"
    elif fault == "badSummary":
        result["usage"]["byThread"][0]["summary"]["totals"]["inputTokens"] = 999
    elif fault == "shutdown":
        result["shutdown"]["outcome"] = "failed"
    elif fault == "schema":
        result["schemaVersion"] = 1
    elif fault == "symlink":
        content = next((archive / "contents").iterdir())
        external = tmp_path / "external"
        content.rename(external)
        content.symlink_to(external)
    elif fault == "middleLine":
        raw = (archive / "events.jsonl").read_bytes().splitlines(keepends=True)
        raw[3] = b"broken\n"
        (archive / "events.jsonl").write_bytes(b"".join(raw))
    if fault in ("unsealed", "sequence", "duplicateBill", "badParent", "badCut", "spawn"):
        rewrite_events(archive, events, result)
    elif fault not in ("missingResult", "middleLine"):
        (archive / "result.json").write_text(json.dumps(result))
    with pytest.raises(AnywkArtifactError):
        read_and_validate_run_artifacts(archive)


def test_partial_last_line_is_never_complete(archive):
    result = json.loads((archive / "result.json").read_text())
    result.update(
        traceComplete=False, outcome="cancelled", executionOutcome="cancelled", exitCode=143
    )
    result["trace"]["sealed"] = False
    (archive / "result.json").write_text(json.dumps(result))
    raw = (archive / "events.jsonl").read_bytes().splitlines(keepends=True)
    (archive / "events.jsonl").write_bytes(b"".join(raw[:-1]) + b'{"unfinished"')
    partial = read_and_validate_run_artifacts(archive, require_success=False, expected_exit=143)
    assert not partial.complete
    with pytest.raises(AnywkArtifactError):
        read_and_validate_run_artifacts(archive)
