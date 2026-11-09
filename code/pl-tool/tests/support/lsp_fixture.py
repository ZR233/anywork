"""Minimal LSP peer for host-binding tests; not a language-service implementation."""
import json
import sys

log_path = sys.argv[1]


def log(value):
    with open(log_path, "a", encoding="utf-8") as output:
        output.write(json.dumps(value) + "\n")


def send(value):
    body = json.dumps(value).encode("utf-8")
    sys.stdout.buffer.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    sys.stdout.buffer.flush()


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
    method = message.get("method")
    if method == "exit":
        break
    if "id" not in message:
        continue
    if method == "initialize":
        result = {"capabilities": {"hoverProvider": True, "textDocumentSync": 1}}
    elif method == "textDocument/hover":
        result = {"contents": {"kind": "plaintext", "value": "fixture hover"}}
    elif method == "shutdown":
        result = None
    else:
        send({"jsonrpc": "2.0", "id": message["id"],
              "error": {"code": -32601, "message": "unsupported fixture method"}})
        continue
    send({"jsonrpc": "2.0", "id": message["id"], "result": result})
