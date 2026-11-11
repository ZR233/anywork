"""Linux-only acceptance-owned file lease. No product state or media is supplied."""

import fcntl
import json
import os
from pathlib import Path
import selectors
import signal
import stat
import sys
import time


def hold(source, directory):
    directory = Path(directory)

    def record(name, value):
        temporary = directory / (name + ".tmp")
        temporary.write_text(json.dumps(value) + "\n", encoding="utf-8")
        temporary.replace(directory / (name + ".json"))

    descriptor = None
    broken = None
    released = False
    stop = False
    wake_read, wake_write = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
    previous_wakeup = signal.set_wakeup_fd(wake_write)

    def stopping(_signal, _frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGIO, lambda _signal, _frame: None)
    signal.signal(signal.SIGTERM, stopping)
    signal.signal(signal.SIGINT, stopping)
    try:
        if sys.platform != "linux":
            raise RuntimeError("media-handoff requires Linux F_SETLEASE")
        break_seconds = float(Path("/proc/sys/fs/lease-break-time").read_text())
        if break_seconds <= 2:
            raise RuntimeError("lease-break-time leaves no safe observation window")
        descriptor = os.open(source, os.O_RDWR | os.O_CLOEXEC)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise RuntimeError("lease source must be a harness-owned regular file")
        if os.get_inheritable(descriptor):
            raise RuntimeError("lease FD must be close-on-exec")
        fcntl.fcntl(descriptor, fcntl.F_SETLEASE, fcntl.F_WRLCK)
        record("ready", {
            "leaseAcquired": True, "pid": os.getpid(), "closeOnExec": True,
            "kernelBreakSeconds": break_seconds, "source": Path(source).name,
        })
        with selectors.DefaultSelector() as selector:
            selector.register(wake_read, selectors.EVENT_READ, "signal")
            selector.register(sys.stdin, selectors.EVENT_READ, "owner")
            previous_poll = time.monotonic()
            while True:
                for key, _events in selector.select(0.02):
                    if key.data == "owner" and not os.read(sys.stdin.fileno(), 1):
                        raise RuntimeError("owner channel lost before explicit release")
                    if key.data == "signal":
                        signals = os.read(wake_read, 4096)
                        if signal.SIGIO in signals and broken is None:
                            # Conservative earliest possible break, including a
                            # scheduling pause before signal delivery.
                            broken = previous_poll
                            record("break", {"sigio": True, "pid": os.getpid()})
                previous_poll = time.monotonic()
                if stop or (directory / "abort.json").exists():
                    raise RuntimeError("acceptance cancelled; explicit cleanup unlock")
                if broken is not None and time.monotonic() - broken >= min(
                    20, break_seconds * 0.75
                ):
                    raise RuntimeError("explicit release missed pre-kernel-break deadline")
                request_file = directory / "releaseRequest.json"
                if not request_file.exists():
                    continue
                request = json.loads(request_file.read_text(encoding="utf-8"))
                if broken is None:
                    raise RuntimeError("release requested without real SIGIO break")
                if not all(isinstance(request.get(key), str) and request[key] for key in (
                    "inputId", "callId", "taskId", "foregroundAtomId", "turnId"
                )):
                    raise RuntimeError("release request has no observed call/task identity")
                # F_GETLEASE reports the target lease after a break request, not
                # whether the blocking opener was already admitted. The deadline
                # above is strictly before the kernel's downgrade deadline.
                fcntl.fcntl(descriptor, fcntl.F_SETLEASE, fcntl.F_UNLCK)
                if time.monotonic() - broken >= min(20, break_seconds * 0.75):
                    raise RuntimeError("unlock completed beyond pre-kernel-break deadline")
                released = True
                os.close(descriptor)
                descriptor = None
                record("released", {
                    "explicitUnlock": True, "breakObserved": True,
                    "releaseRequest": request, "pid": os.getpid(),
                    "breakToUnlockMillis": (time.monotonic() - broken) * 1000,
                })
                return 0
    except BaseException as error:
        record("error", {"error": str(error), "pid": os.getpid()})
        return 1
    finally:
        if descriptor is not None:
            try:
                fcntl.fcntl(descriptor, fcntl.F_SETLEASE, fcntl.F_UNLCK)
            finally:
                os.close(descriptor)
        record("closed", {"pid": os.getpid(), "successfulRelease": released})
        signal.set_wakeup_fd(previous_wakeup)
        os.close(wake_read)
        os.close(wake_write)


if __name__ == "__main__":
    sys.exit(hold(sys.argv[1], sys.argv[2]))
