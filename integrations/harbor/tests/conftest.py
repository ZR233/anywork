import json
import shutil
from pathlib import Path

import pytest

from anywork_harbor.artifacts import sha256

ROOT = Path(__file__).resolve().parents[3]


def rewrite_events(directory, events, result=None):
    raw = b"".join(
        json.dumps({**event, "eventSeq": index}, separators=(",", ":")).encode() + b"\n"
        for index, event in enumerate(events, 1)
    )
    (directory / "events.jsonl").write_bytes(raw)
    result = result or json.loads((directory / "result.json").read_text())
    result["trace"].update(
        eventsSha256=sha256(raw), eventCount=len(events), lastEventSeq=len(events)
    )
    (directory / "result.json").write_text(json.dumps(result))


@pytest.fixture
def archive(tmp_path):
    source = ROOT / "code/pl-studio-runtime/tests/fixtures/run-export/v2"
    destination = tmp_path / "native"
    shutil.copytree(source, destination)
    events = [json.loads(line) for line in (destination / "events.jsonl").read_text().splitlines()]
    # canonical 黄金样例只演示原件序列化；补入该样例声明的真实 spawn 工具身份。
    root = next(e for e in events if e["type"] == "completion" and e["threadId"] == "thread-root")
    root["data"]["atom"]["tool"] = {"callId": "call-spawn-1", "name": "spawn_agent"}
    root["data"]["atom"]["kind"] = "toolCall"
    rewrite_events(destination, events)
    return destination
