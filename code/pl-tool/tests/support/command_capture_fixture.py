from pathlib import Path
import sys
import time


def write_bytes(stream, data):
    remaining = memoryview(data)
    while remaining:
        written = stream.write(remaining)
        if written is None or written <= 0:
            raise OSError("binary fixture write made no progress")
        remaining = remaining[written:]
    stream.flush()


mode = sys.argv[1]
if mode == "endless":
    while True:
        write_bytes(sys.stdout.buffer, b"0123456789abcdef")
elif mode == "rollover":
    write_bytes(sys.stdout.buffer, b"h" * 262144)
    write_bytes(sys.stderr.buffer, b"e" * 196608)
elif mode == "stdin":
    Path("stdin.txt").write_bytes(sys.stdin.buffer.read())
    write_bytes(sys.stdout.buffer, b"done")
elif mode == "utf8-split":
    data = "中文🌙".encode("utf-8")
    write_bytes(sys.stdout.buffer, data[:2])
    time.sleep(0.02)
    write_bytes(sys.stdout.buffer, data[2:])
    write_bytes(sys.stderr.buffer, b"error")
elif mode == "invalid-utf8":
    write_bytes(sys.stdout.buffer, bytes([255, 97, 226]))
elif mode == "long-utf8":
    write_bytes(sys.stdout.buffer, "中文🌙".encode("utf-8") * 20000)
else:
    raise ValueError(f"unknown command capture fixture mode: {mode}")
