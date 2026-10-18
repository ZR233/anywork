"""Small real Linux-helper acceptance. Run explicitly with python3, outside CI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import time


class Helper:
    def __init__(self, executable, workspace):
        self.process = subprocess.Popen(
            [str(executable), "--serve"], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0,
        )
        self.responses = {}
        self.events = {}
        self.consume_output = True
        self.output_count = 0
        self.send(1, {"method": "hello", "params": {"protocolVersion": 8}})
        assert self.response(1)["result"] == "hello"
        self.send(2, {"method": "openWorkspace", "params": {"path": str(workspace)}})
        self.workspace = self.response(2)["payload"]["workspaceId"]

    def send(self, identity, request, body=b""):
        header = json.dumps({"requestId": identity, "message": {
            "kind": "request", "payload": request}, "bodyLen": len(body)},
            separators=(",", ":")).encode()
        self.process.stdin.write(struct.pack(">I", len(header)) + header + body)
        self.process.stdin.flush()

    def exact(self, count, deadline):
        result = bytearray()
        while len(result) < count:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.process.stdout], [], [], remaining)[0]:
                raise TimeoutError("helper response did not settle")
            chunk = os.read(self.process.stdout.fileno(), count - len(result))
            if not chunk:
                raise RuntimeError("helper exited before response")
            result.extend(chunk)
        return bytes(result)

    def response(self, identity, timeout=3):
        deadline = time.monotonic() + timeout
        while identity not in self.responses:
            self.pump(deadline)
        return self.responses.pop(identity)

    def pump(self, deadline):
        length = struct.unpack(">I", self.exact(4, deadline))[0]
        assert 0 < length <= 65536
        header = json.loads(self.exact(length, deadline))
        assert header["bodyLen"] <= 32 * 1024 * 1024
        self.exact(header["bodyLen"], deadline)
        message = header["message"]
        if message["kind"] == "response":
            self.responses[header["requestId"]] = message["payload"]
        elif message["kind"] == "event":
            event = message["payload"]
            if event["event"] == "processOutput":
                self.output_count += 1
                if self.consume_output:
                    self.send(None, {"method": "outputConsumed", "params": {
                        "processId": event["payload"]["processId"]}})
            elif event["event"] == "processExit":
                process = event["payload"]["processId"]
                assert process not in self.events, "duplicate process terminal event"
                self.events[process] = event["payload"]

    def close(self):
        self.send(None, {"method": "shutdown"})
        self.process.stdin.close()
        self.process.wait(timeout=8)
        errors = self.process.stderr.read().decode(errors="replace")
        assert self.process.returncode == 0, errors
        self.process.stdout.close()
        self.process.stderr.close()


def special_file(executable, root, mode, baseline):
    workspace = root / mode
    workspace.mkdir()
    fifo = workspace / "special.pipe"
    os.mkfifo(fifo)
    helper = Helper(executable, workspace)
    if mode == "capture":
        request = {"method": "spawn", "params": {
            "processId": "fifo-capture", "workspaceId": helper.workspace,
            "command": "printf started > must-not-start", "cwd": ".", "environment": {},
            "capture": {"kind": "file", "path": fifo.name, "limitBytes": 4096}}}
    elif mode == "range":
        request = {"method": "readRange", "params": {
            "workspaceId": helper.workspace, "path": fifo.name, "offset": 0, "maxBytes": 64}}
    elif mode == "append":
        request = {"method": "writeFile", "params": {
            "target": {"workspaceId": helper.workspace, "path": fifo.name}, "mode": "append"}}
    elif mode == "bytes":
        request = {"method": "readBytes", "params": {
            "workspaceId": helper.workspace, "path": fifo.name, "maxBytes": 64}}
    else:
        (workspace / "regular.txt").write_text("synthetic")
        request = {"method": "copyPath", "params": {
            "workspaceId": helper.workspace,
            "source": fifo.name if mode == "copy-source" else "regular.txt",
            "target": "copy.txt" if mode == "copy-source" else fifo.name,
            "recursive": False}}
    helper.send(3, request, b"x" if mode == "append" else b"")
    blocked = False
    try:
        response = helper.response(3)
    except TimeoutError:
        blocked = True
        if mode == "capture":
            helper.send(4, {"method": "terminate", "params": {"processId": "fifo-capture"}})
            assert helper.response(4)["result"] == "ack"
        # Release the old implementation's open without killing its supervision owner.
        partner = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
        try:
            response = helper.response(3)
        finally:
            os.close(partner)
    finally:
        helper.close()
    assert not (workspace / "must-not-start").exists(), "cancelled preparation started a command"
    assert response["result"] == "error", response
    assert blocked == baseline, {"mode": mode, "blocked": blocked, "expected_blocked": baseline}
    print(json.dumps({"scenario": mode, "blocked": blocked, "settled": True,
                      "helperExit": helper.process.returncode, "response": response}), flush=True)


def resources(helper):
    process = Path(f"/proc/{helper.process.pid}")
    status = dict(line.split(":", 1) for line in (process / "status").read_text().splitlines() if ":" in line)
    return {"files": len(list((process / "fd").iterdir())),
            "threads": len(list((process / "task").iterdir())), "rss": status["VmRSS"].strip()}


def workspace_cycles(executable, root):
    workspace = root / "cycles"
    workspace.mkdir()
    helper = Helper(executable, workspace)
    baseline = resources(helper)
    for cycle in range(50):
        path = workspace / str(cycle)
        path.mkdir()
        identity = 100 + cycle * 3
        helper.send(identity, {"method": "openWorkspace", "params": {"path": str(path)}})
        handle = helper.response(identity)["payload"]["workspaceId"]
        helper.send(identity + 1, {"method": "closeWorkspace", "params": {"workspaceId": handle}})
        assert helper.response(identity + 1)["result"] == "ack"
        helper.send(identity + 2, {"method": "stat", "params": {"workspaceId": handle, "path": "."}})
        assert helper.response(identity + 2)["payload"]["code"] == "workspaceNotFound"
    final = resources(helper)
    assert final["files"] == baseline["files"], (baseline, final)
    helper.close()
    print(json.dumps({"scenario": "workspace-50", "baseline": baseline, "final": final, "helperExit": 0}), flush=True)


def connection_end(executable, root, ending):
    workspace = root / ending
    workspace.mkdir()
    helper = Helper(executable, workspace)
    helper.consume_output = False
    helper.send(3, {"method": "spawn", "params": {
        "processId": "backpressure", "workspaceId": helper.workspace,
        "command": "sleep 120 & echo $! > child.pid; dd if=/dev/zero bs=8192 count=1024 2>/dev/null; wait",
        "cwd": ".", "environment": {}, "capture": {"kind": "none"}}})
    start = helper.response(3)
    if start["result"] != "processSpawned":
        helper.close()
        raise AssertionError(start)
    deadline = time.monotonic() + 3
    while not (workspace / "child.pid").exists():
        assert time.monotonic() < deadline
        time.sleep(0.01)
    child = int((workspace / "child.pid").read_text())
    assert Path(f"/proc/{child}").exists()
    # Reading the heartbeat also observes the full output window without returning credits.
    helper.send(4, {"method": "heartbeat"})
    assert helper.response(4)["result"] == "ack"
    deadline = time.monotonic() + 3
    while helper.output_count < 8:
        helper.pump(deadline)
    if ending == "cancel":
        helper.send(5, {"method": "terminate", "params": {"processId": "backpressure"}})
        assert helper.response(5)["result"] == "ack"
        helper.send(6, {"method": "heartbeat"})
        assert helper.response(6)["result"] == "ack"
        deadline = time.monotonic() + 8
        while "backpressure" not in helper.events:
            helper.pump(deadline)
        helper.close()
    else:
        if ending == "shutdown":
            helper.send(None, {"method": "shutdown"})
        if ending in ("shutdown", "eof"):
            helper.process.stdin.close()
        # Lease expiry retains an open input stream and deliberately sends no more traffic.
        helper.process.wait(timeout=38)
        error = helper.process.stderr.read().decode(errors="replace")
        if ending == "lease":
            assert "lease expired" in error, error
            assert helper.process.returncode != 0
            helper.process.stdin.close()
        else:
            assert helper.process.returncode == 0, error
        helper.process.stdout.close()
        helper.process.stderr.close()
    assert not Path(f"/proc/{child}").exists(), f"descendant {child} survived {ending}"
    print(json.dumps({"scenario": ending, "windowOccupied": True, "childReclaimed": True, "helperExit": helper.process.returncode}), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("helper", type=Path)
    parser.add_argument("workspace", type=Path)
    parser.add_argument("--baseline", action="store_true")
    args = parser.parse_args()
    args.workspace.mkdir(mode=0o700)
    print(json.dumps({"helperSha256": hashlib.sha256(args.helper.read_bytes()).hexdigest()}), flush=True)
    modes = ("capture", "range", "append") if args.baseline else ("capture", "range", "append", "bytes", "copy-source", "copy-target")
    for mode in modes:
        special_file(args.helper, args.workspace, mode, args.baseline)
    if not args.baseline:
        workspace_cycles(args.helper, args.workspace)
        for ending in ("cancel", "shutdown", "eof", "lease"):
            connection_end(args.helper, args.workspace, ending)
    print("SPECIAL_FILE_RESOURCE_ACCEPTANCE=PASS", flush=True)


if __name__ == "__main__":
    main()
