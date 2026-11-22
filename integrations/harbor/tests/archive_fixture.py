"""Current public archive fixture: complete parent/child run with immutable History bodies."""

import copy
import json
from pathlib import Path

from anywork_harbor.artifacts import sha256


def write_archive(root: Path, destination: Path):
    golden = root / "code/pl-studio-runtime/tests/fixtures/run-export/v3"
    destination.mkdir()
    (destination / "contents").mkdir()
    manifest = json.loads((golden / "run.json").read_text())
    result = json.loads((golden / "result.json").read_text())
    template = json.loads((golden / "events.jsonl").read_text().splitlines()[1])
    (destination / "run.json").write_text(json.dumps(manifest))
    empty_source = {key: None for key in template["source"]}
    events = []

    def blob(raw, media="application/json"):
        digest = sha256(raw)
        path = f"contents/{digest}.bin"
        (destination / path).write_bytes(raw)
        return {
            "path": path,
            "byteLength": len(raw),
            "sha256": digest,
            "mediaType": media,
            "encoding": "utf-8",
        }

    def add(kind, data, thread=None, **source):
        event = copy.deepcopy(template)
        event.update(type=kind, data=data, threadId=thread, source=empty_source | source)
        events.append(event)

    def cursor(thread, seq):
        return {"cut": {"token": f"opaque-cut:{thread}:{seq}"}, "historySeq": seq}

    def member(thread, parent=None):
        return {
            "agentId": thread,
            "threadId": thread,
            "parentAgentId": parent,
            "parentThreadId": parent,
            "role": "executor" if parent else None,
            "workspaceId": "fixture-workspace",
            "spawnToolCallId": "call-spawn-1" if parent else None,
            "initialEffectSeq": 0,
            "initialHistoryCursor": cursor(thread, 0),
        }

    def completion(thread, seq, suffix, body, tool=None):
        data = copy.deepcopy(template["data"])
        atom, header = data["atom"], data["header"]["event"]
        event_id, entity_id = f"event-{suffix}", f"entity-{suffix}"
        inference = "inference-child" if thread == "thread-child-1" else "inference-root"
        atom.update(
            entityId=entity_id,
            tool=tool,
            entityKind="toolCall" if tool else "text",
            textChannel=None if tool else "final",
            singleVisibility=None if tool else "content",
        )
        header.update(
            seq=seq,
            eventId=event_id,
            entityId=entity_id,
            runId=f"run-{thread}",
            attemptId=inference,
            callId=tool["callId"] if tool else None,
            toolName=tool["name"] if tool else None,
            timelineRole="work" if tool else "divider",
            kind="toolCompleted" if tool else "textCompleted",
        )
        header["original"].update(
            originalKind=atom["entityKind"], toolName=tool["name"] if tool else None
        )
        payload = (
            {
                "contract": "anywork.event/1",
                "type": "tool",
                "meta": atom,
                "data": {
                    "invocation": {"toolCallId": tool["callId"], "name": tool["name"]},
                    "state": {"kind": "succeeded"},
                },
                "bodies": [],
                "turnId": header["turnId"],
            }
            if tool
            else {
                "contract": "anywork.event/1",
                "type": "text",
                "meta": atom,
                "data": {"channel": "final"},
                "bodies": [],
                "turnId": header["turnId"],
            }
        )
        entries = []

        def content(key, role, raw, native_role=None, media="application/json"):
            ref = blob(raw, media)
            entries.append(
                dict(
                    bodyKey=key,
                    nativeRef={
                        "databaseId": f"db-{thread}",
                        "ownerEventId": event_id,
                        "bodyKey": key,
                        "bodyId": f"{event_id}:{key}",
                        "byteStart": 0,
                        "byteLength": len(raw),
                    },
                    role=native_role,
                    historyRole={"kind": role},
                    **ref,
                )
            )
            return ref

        data["payload"] = blob(json.dumps(payload).encode())
        if tool:
            content("tool.arguments", "toolArguments", b'{"task":"analyze"}', "toolArguments")
            if body:
                content("tool.result", "toolOutput", body.encode(), "toolOutput", "text/plain")
        else:
            content("body", "body", body.encode(), "body", "text/plain")
        data["contentsManifest"] = blob(
            b"".join(json.dumps(value).encode() + b"\n" for value in entries),
            "application/x-ndjson",
        )
        add(
            "completion",
            data,
            thread,
            historyEventId=event_id,
            historyEventSeq=seq,
            turnId=header["turnId"],
            attemptId=inference,
            toolCallId=header["callId"],
        )

    def bill(thread, input_tokens, output_tokens, amount):
        add(
            "inferenceFinished",
            {
                "status": "committed",
                "auxiliary": thread == "thread-root",
                "billing": {
                    "inferenceId": "inference-child"
                    if thread == "thread-child-1"
                    else "inference-root",
                    "accountId": "fixture",
                    "modelId": "vendor/golden-model",
                    "recordedAt": 1763046000010,
                    "purpose": "title" if thread == "thread-root" else "main",
                    "accounting": {
                        "usage": {
                            "inputTokens": input_tokens,
                            "outputTokens": output_tokens,
                            "cacheReadTokens": 0,
                            "cacheWriteTokens": 0,
                            "reasoningTokens": 0,
                            "totalTokens": input_tokens + output_tokens,
                        },
                        "pricing": {
                            "kind": "estimated",
                            "cost": {"amount": amount, "currency": "USD"},
                            "cacheSavings": None,
                        },
                        "priceSnapshot": None,
                        "requestStartedAt": None,
                    },
                },
            },
            thread,
            effectSeq=1,
        )

    add(
        "runStarted",
        {
            "runId": manifest["runId"],
            "build": manifest["build"],
            "manifestSha256": sha256((destination / "run.json").read_bytes()),
        },
    )
    root_member, child_member = member("thread-root"), member("thread-child-1", "thread-root")
    add("agentRegistered", root_member, "thread-root")
    completion("thread-root", 1, "spawn", "", {"callId": "call-spawn-1", "name": "spawn_agent"})
    add("agentRegistered", child_member, "thread-child-1")
    bill("thread-child-1", 40, 10, 0.002)
    completion(
        "thread-child-1", 1, "child-tool", "A" * 1024, {"callId": "call-child", "name": "inspect"}
    )
    completion("thread-root", 2, "root-final", result["finalText"])
    bill("thread-root", 100, 25, 0.005)
    cuts = []
    for entry in (child_member, root_member):
        thread = entry["threadId"]
        final_cut = cursor(thread, 2 if thread == "thread-root" else 1)
        summary = next(x["summary"] for x in result["usage"]["byThread"] if x["threadId"] == thread)
        add(
            "threadSealed",
            {
                "threadId": thread,
                "throughEffectSeq": 1,
                "historyCut": final_cut,
                "summary": summary,
                "status": "completed",
                "aborted": False,
                "error": None,
            },
            thread,
        )
        cuts.append(
            {
                "threadId": thread,
                "agentId": entry["agentId"],
                "parentAgentId": entry["parentAgentId"],
                "role": entry["role"],
                "throughEffectSeq": 1,
                "historyCut": final_cut,
                "aborted": False,
                "sealed": True,
            }
        )
    add(
        "runSealed",
        {
            "members": cuts,
            "reconciled": True,
            "reconcileError": None,
            "traceComplete": True,
            "usageComplete": True,
            "costComplete": True,
        },
    )
    raw = b"".join(
        json.dumps(event | {"eventSeq": i}).encode() + b"\n" for i, event in enumerate(events, 1)
    )
    (destination / "events.jsonl").write_bytes(raw)
    result["trace"].update(
        eventsSha256=sha256(raw), eventCount=len(events), lastEventSeq=len(events)
    )
    (destination / "result.json").write_text(json.dumps(result))
    return destination
