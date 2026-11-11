"""Hash actual capture files and unchanged media sources after both GUI exits."""

import hashlib
import json
from pathlib import Path
import struct
import sys


def png(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"not a PNG: {path.name}")
    width, height = struct.unpack(">II", data[16:24])
    return {
        "file": path.name, "byteSize": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "width": width, "height": height,
    }


output, project = map(Path, sys.argv[1:])
captures = []
for phase in ("media-handoff", "media-handoff-reopen"):
    names = ["sent-pure-attachments", "background-main-details", "background-main-viewer"]
    if phase == "media-handoff":
        names.insert(0, "pure-attachments-draft")
    for name in names:
        captures.append({
            **png(output / f"concept-{phase}-{name}.png"),
            "phase": phase, "stage": name,
            "sentCanonicalInput": name == "sent-pure-attachments",
            "source": "official integration_test production RepaintBoundary capture",
        })
inputs = [png(project / f"concept-input-{name}.png") for name in "abc"]
tool = png(project / "concept-image-a.png")
expected_inputs = [
    "e75b8140cad993ca5a23db4170bf70d3a4db3d7af55c9e8b43d432022aa58cd4",
    "316558a02d6a9d35fc19480c9397cdab46a0b1ff83132e25fa184af837e4cfc2",
    "eee576e2d47e68f0b0a185080f6b6e063d43cdee506cd6df180bd598a4034929",
]
if [item["sha256"] for item in inputs] != expected_inputs:
    raise ValueError("input source digest changed")
if tool["sha256"] != "0a23b4c2e99e7de221fedb9e4e96d910c786d32385a17dc44dbc1138c13a2b4b":
    raise ValueError("tool source digest changed")
(output / "media-handoff-evidence.json").write_text(json.dumps({
    "platform": sys.platform, "captures": captures,
    "inputSources": inputs, "toolSource": tool,
}, indent=2) + "\n", encoding="utf-8")
