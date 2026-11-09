"""Minimal LSP peer for host-binding tests; not a language-service implementation."""
import json
import sys
import os
import time
from pathlib import Path

log_path = sys.argv[1]


def log(value):
    with open(log_path, "a", encoding="utf-8") as output:
        output.write(json.dumps(value) + "\n")


def send(value):
    body = json.dumps(value).encode("utf-8")
    sys.stdout.buffer.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    sys.stdout.buffer.flush()


def publish_diagnostic(message):
    log({"method": "fixture/publishDiagnostics", "message": message})
    send({"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics",
          "params": {"uri": (Path.cwd() / "source.fixture").as_uri(),
                     "diagnostics": [{"range": {"start": {"line": 0, "character": 0},
                                                "end": {"line": 0, "character": 1}},
                                      "severity": 1, "message": message}]}})

log({"method": "fixture/start", "pid": os.getpid(), "cwd": os.getcwd(),
     "env": os.environ.get("LSP_FIXTURE_VALUE")})

while True:
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            sys.exit(0)
        if line in (b"\r\n", b"\n"):
            break
        key, value = line.decode("ascii").split(":", 1)
        headers[key.lower()] = value.strip()
    message = json.loads(sys.stdin.buffer.read(int(headers["content-length"])))
    log(message)
    if "method" not in message:
        continue
    method = message.get("method")
    if method == "exit":
        break
    if method == "initialized" and os.environ.get("LSP_FIXTURE_EXIT") == "1":
        sys.exit(7)
    if method == "initialized" and os.environ.get("LSP_FIXTURE_DIAGNOSTIC"):
        publish_diagnostic(os.environ["LSP_FIXTURE_DIAGNOSTIC"])
    if "id" not in message:
        continue
    if method == "initialize":
        time.sleep(float(os.environ.get("LSP_FIXTURE_DELAY", "0")))
        result = {"capabilities": {"hoverProvider": True, "textDocumentSync": 1}}
        if os.environ.get("LSP_FIXTURE_FAIL") == "1":
            send({"jsonrpc": "2.0", "id": message["id"],
                  "error": {"code": -32603, "message": "fixture handshake rejected"}})
            continue
        if os.environ.get("LSP_FIXTURE_CONFIGURATION") == "1":
            send({"jsonrpc": "2.0", "id": "configuration-request",
                  "method": "workspace/configuration",
                  "params": {"items": [{"section": "fixture.nested"}, {"section": "absent"}]}})
    elif method == "textDocument/hover":
        result = {"contents": {"kind": "plaintext", "value": os.environ.get("LSP_FIXTURE_HOVER", "fixture hover")}}
    elif method == "shutdown":
        if os.environ.get("LSP_FIXTURE_LATE_DIAGNOSTIC"):
            publish_diagnostic(os.environ["LSP_FIXTURE_LATE_DIAGNOSTIC"])
        result = None
    else:
        send({"jsonrpc": "2.0", "id": message["id"],
              "error": {"code": -32601, "message": "unsupported fixture method"}})
        continue
    send({"jsonrpc": "2.0", "id": message["id"], "result": result})
