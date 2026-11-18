import json
from pathlib import Path

import pytest
from archive_fixture import write_archive

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
    return write_archive(ROOT, tmp_path / "native")
