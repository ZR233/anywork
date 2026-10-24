#!/usr/bin/env python3
"""Process owner for the isolated acceptance Studio server.

This program is the single parent and reaper of everything the observation
launcher starts inside its private ``dbus-run-session``: the Secret Service
daemon, the readiness probe, and the real ``pl-studio-server``. It exists so the
graceful stop is a kernel-verified, replay-free operation instead of a signal
sent to a pid parsed out of a log:

* the server pidfd is opened immediately after ``Popen`` and before any
  ``poll``/``wait``/``waitpid`` of that child. This process is the only parent,
  so there is no window in which the pid could be reaped and reused;
* every signal for a child goes through its pidfd (``signal.pidfd_send_signal``).
  A bare pid is never signalled while a pidfd exists. Only when a pidfd could not
  be opened does the documented exception apply: this process is provably the
  only parent of an unreaped child, so the standard ``Popen`` calls are used for
  that child and only for it;
* a stop is reported as *delivered* only when the kernel accepted this instance's
  SIGINT. The delivery count, the escalation, and every cleanup result are
  measured, never assumed;
* every wait is bounded (``Popen.wait(timeout=...)``). Readiness timeouts leave
  the registered child owned by ``finish``, which attempts bounded cleanup.
  Unreaped children remain a failure, reported as ``cleanup_complete=false``.
  A failed server signal is not a dead end: the same pidfd is used for bounded
  escalation and waiting;
* any cleanup that cannot complete is reported as a failure with
  ``cleanup_complete=false`` and a non-zero exit, so the caller can refuse a
  graceful claim instead of trusting a zero launcher status.

Channels are separated on purpose. File descriptor 1 is the owner's private
receipt channel (created by the caller for this instance only) and carries one
JSON object per line. File descriptor 2 is the ordinary launcher log, and every
child gets exactly that log as its stdout/stderr, so nothing the server prints
can ever be read as an owner receipt.

    {"kind":"control_ready","instance":...,"server_pid":...}
    {"kind":"stop_delivered","instance":...,"op":...,"signal":"INT","pid":...,"count":1}
    {"kind":"stop_already_exited","instance":...,"op":...}
    {"kind":"stop_failed","instance":...,"op":...,"reason":...,"errno":...}
    {"kind":"stop_duplicate","instance":...,"op":...}
    {"kind":"stop_escalated","instance":...,"op":...,"signal":"KILL","pid":...}
    {"kind":"control_rejected","instance":...,"length":...}
    {"kind":"control_closed","instance":...}
    {"kind":"control_error","instance":...,"reason":...,"detail":...}
    {"kind":"owner_exit","instance":...,"server_exit":...,"keyring_exit":...,
     "readiness_exit":...,"delivered":...,"escalated":...,
     "graceful":...,"failure":...,"cleanup_complete":...,
     "server_reaped":...,"keyring_reaped":...,"readiness_reaped":...,
     "cleanup_errors":[...]}

The control face is one private line protocol on stdin::

    stop <operation-id>              # exactly one SIGINT for this instance
"""

import json
import os
import re
import selectors
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True

STOP_LINE = re.compile(r"\Astop ([A-Za-z0-9_-]{1,64})\Z")
KEYRING_ARGV = ("gnome-keyring-daemon", "--foreground", "--unlock", "--components=secrets")
READINESS_ARGV = ("gdbus", "wait", "--session", "--timeout", "10", "org.freedesktop.secrets")
READINESS_TIMEOUT = 20.0
GRACEFUL_TIMEOUT = 6.0
KILL_TIMEOUT = 3.0
REAP_TIMEOUT = 3.0
POLL_STEP = 0.05
RECEIPT_FD = 1
LOG_FD = 2
OWNER_FAILURE_CODE = 70
OWNER_CONFIGURATION_CODE = 78
OWNER_NOT_READY_CODE = 65


class ControlError(Exception):
    """A start-up condition that must fail the observation instead of degrading."""

    def __init__(self, token, detail=None):
        super().__init__(token)
        self.token = token
        self.detail = detail


INSTANCE = os.environ.get("ANYWORK_ACCEPTANCE_INSTANCE", "")


def receipt(kind, **fields):
    """One flushed JSON receipt on the owner-only channel; a closed fd is ignored."""
    payload = {"kind": kind, "instance": INSTANCE}
    payload.update(fields)
    try:
        os.write(RECEIPT_FD, (json.dumps(payload, sort_keys=True) + "\n").encode("utf-8"))
    except OSError:
        pass


def wait_bounded(process, timeout):
    """Bounded wait: returns the exit code, or ``None`` when the window expired."""
    if process is None:
        return None
    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


def launcher_code(returncode):
    if returncode is None:
        return OWNER_FAILURE_CODE
    return 128 - returncode if returncode < 0 else returncode


class Child:
    """One direct child of this owner, registered the moment it is created."""

    def __init__(self, name, process):
        self.name = name
        self.process = process
        self.pidfd = None
        self.exit_code = None
        self.reaped = False
        self.error = None
        self.signal_errors = []

    def open_pidfd(self):
        try:
            self.pidfd = os.pidfd_open(self.process.pid)
        except OSError as error:
            # Not fatal: this owner is the only parent of an unreaped child, so the
            # documented Popen fallback below can still reclaim it.
            self.error = "pidfd-open errno=%d" % (error.errno or 0)
            return False
        return True

    def send(self, signum, record=True):
        if self.pidfd is not None:
            try:
                signal.pidfd_send_signal(self.pidfd, signum)
                return None
            except OSError as error:
                if record:
                    self.signal_errors.append("pidfd errno=%d" % (error.errno or 0))
                return error
        try:
            if signum == signal.SIGKILL:
                self.process.kill()
            else:
                self.process.send_signal(signum)
            return None
        except OSError as error:
            if record:
                self.signal_errors.append("popen errno=%d" % (error.errno or 0))
            return error


class Owner:
    def __init__(self, server_argv):
        self.server_argv = server_argv
        self.keyring = None
        self.server = None
        self.buffer = b""
        self.control_open = True
        self.delivered = 0
        self.stop_op = None
        self.deadline = None
        self.escalated = False
        self.abandoned = False
        self.failure = None
        self.readiness_exit = None
        self.readiness_reaped = False
        # The readiness probe is registered here the moment `Popen` returns, so it is
        # only non-`None` when a real child exists and this owner must reap it.
        self.readiness = None
        # Set by `finish`; the start-up branches read it so an incomplete teardown
        # can outrank their own diagnosis instead of being hidden by it.
        self.cleanup_complete = False

    # -- start -----------------------------------------------------------------
    def start(self):
        if not INSTANCE:
            raise ControlError("missing-instance")
        if not hasattr(os, "pidfd_open") or not hasattr(signal, "pidfd_send_signal"):
            raise ControlError("pidfd-unsupported")
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "")
        password = os.path.join(runtime_dir, "fixture-password")
        try:
            secret = open(password, "rb")
        except OSError as error:
            raise ControlError("keyring-password-unreadable", "errno=%d" % (error.errno or 0)) from error
        with secret:
            # Registered before any pidfd work, so a failed pidfd still reclaims it.
            self.keyring = Child("keyring", subprocess.Popen(list(KEYRING_ARGV), stdin=secret, stdout=LOG_FD, stderr=LOG_FD, close_fds=True))
        self.keyring.open_pidfd()

        # The readiness probe is a real child of this owner like the others: it is
        # registered the instant `Popen` returns and reaped by the same bounded
        # cleanup, so "no readiness resource" and "an unreaped readiness resource"
        # stay distinguishable. `subprocess.run` is not used because a `Popen`
        # construction failure there would leave the probe's ownership ambiguous.
        try:
            self.readiness = Child(
                "readiness",
                subprocess.Popen(
                    list(READINESS_ARGV),
                    stdout=LOG_FD,
                    stderr=LOG_FD,
                    close_fds=True,
                ),
            )
        except OSError as error:
            # Nothing was created, so there is no readiness resource to reap.
            raise ControlError(
                "readiness-spawn-failed", "errno=%d" % (error.errno or 0)
            ) from error
        status = wait_bounded(self.readiness.process, READINESS_TIMEOUT)
        if status is None:
            raise ControlError("secret-service-timeout", "after %ss" % READINESS_TIMEOUT)
        self.readiness_exit = status
        self.readiness_reaped = True
        if status != 0:
            raise ControlError("secret-service-not-ready", "status=%d" % status)

        self.server = Child(
            "server",
            subprocess.Popen(
                self.server_argv,
                stdin=subprocess.DEVNULL,
                stdout=LOG_FD,
                stderr=LOG_FD,
                close_fds=True,
            ),
        )
        # Opened before any poll/wait of this child: this owner is its only parent,
        # so the pid cannot have been reaped and reused at this point.
        self.server.open_pidfd()
        if self.server.pidfd is None:
            # A stop that cannot be delivered through a pidfd must not be offered.
            raise ControlError("server-pidfd-open", self.server.error)
        receipt("control_ready", server_pid=self.server.process.pid)

    # -- service loop ----------------------------------------------------------
    def serve(self):
        selector = selectors.DefaultSelector()
        selector.register(self.server.pidfd, selectors.EVENT_READ, "server")
        control_fd = sys.stdin.fileno()
        if self.control_open:
            selector.register(control_fd, selectors.EVENT_READ, "control")
        try:
            while self.server.exit_code is None and not self.abandoned:
                timeout = POLL_STEP
                if self.deadline is not None:
                    timeout = min(POLL_STEP, max(0.0, self.deadline - time.monotonic()))
                for key, _ in selector.select(timeout):
                    if key.data == "server":
                        self.reap_server()
                    elif key.data == "control":
                        self.read_control(selector, control_fd)
                if self.server.exit_code is not None or self.abandoned:
                    break
                if self.deadline is not None and time.monotonic() >= self.deadline:
                    if self.escalated:
                        self.abandoned = True
                        self.failure = self.failure or "server-kill-timeout"
                        self.server.error = self.server.error or "unreaped-after-kill"
                    else:
                        self.escalate()
        finally:
            selector.close()

    def read_control(self, selector, control_fd):
        try:
            chunk = os.read(control_fd, 4096)
        except OSError:
            chunk = b""
        if not chunk:
            self.control_open = False
            selector.unregister(control_fd)
            receipt("control_closed")
            return
        self.buffer += chunk
        while b"\n" in self.buffer:
            raw, self.buffer = self.buffer.split(b"\n", 1)
            self.handle(raw.decode("utf-8", "replace").strip())

    def handle(self, line):
        match = STOP_LINE.match(line)
        if match is None:
            receipt("control_rejected", length=len(line))
            return
        op = match.group(1)
        if self.stop_op is not None:
            # One instance gets at most one delivery attempt; repeating a stop never
            # delivers a second signal.
            receipt("stop_duplicate", op=op)
            return
        self.stop_op = op
        # A stop for an already-finished server is answered, not signalled: `poll`
        # reaps an exited child, so the pidfd is not used on a decided outcome.
        status = self.server.process.poll()
        if self.server.exit_code is not None or status is not None:
            self.server.exit_code = status if status is not None else self.server.exit_code
            self.server.reaped = self.server.exit_code is not None
            receipt("stop_already_exited", op=op)
            return
        # A refused SIGINT is a stop failure, not a cleanup defect: it is reported as
        # such, and the escalation below still reclaims the child.
        error = self.server.send(signal.SIGINT, record=False)
        if error is not None:
            # Nothing reached the child, so this is not a delivery; the same pidfd is
            # still escalated inside the bounded drain instead of leaving a live one.
            self.failure = self.failure or "sigint-delivery"
            receipt("stop_failed", op=op, reason="signal", errno=error.errno or 0)
            self.escalate()
            return
        self.delivered += 1
        self.deadline = time.monotonic() + GRACEFUL_TIMEOUT
        receipt("stop_delivered", op=op, signal="INT", pid=self.server.process.pid, count=self.delivered)

    def reap_server(self):
        status = wait_bounded(self.server.process, GRACEFUL_TIMEOUT if not self.escalated else KILL_TIMEOUT)
        if status is None:
            self.failure = self.failure or "server-wait-timeout"
            self.escalate()
            return
        self.server.exit_code = status
        self.server.reaped = True
        self.deadline = None

    def escalate(self):
        self.escalated = True
        self.failure = self.failure or "sigint-timeout"
        receipt("stop_escalated", op=self.stop_op or "-", signal="KILL", pid=self.server.process.pid)
        if self.server.send(signal.SIGKILL) is not None and self.failure == "sigint-timeout":
            self.failure = "kill-signal"
        self.deadline = time.monotonic() + KILL_TIMEOUT

    # -- teardown --------------------------------------------------------------
    def cleanup_child(self, child, signum):
        """Reclaim one registered child with bounded waits; records every attempt."""
        if child is None or child.reaped:
            return
        if child.process.poll() is not None:
            child.exit_code = child.process.returncode
            child.reaped = True
            return
        if child.send(signum) is None and wait_bounded(child.process, REAP_TIMEOUT) is not None:
            child.exit_code = child.process.returncode
            child.reaped = True
            return
        if child.send(signal.SIGKILL) is None and wait_bounded(child.process, REAP_TIMEOUT) is not None:
            child.exit_code = child.process.returncode
            child.reaped = True
            return
        child.error = child.error or "unreaped-after-kill"

    def finish(self):
        errors = []
        # Every registered child is attempted, in a fixed order, whatever the
        # first failure was: one stuck child must not hide the others.
        if self.server is not None:
            self.cleanup_child(self.server, signal.SIGKILL)
            if not self.server.reaped:
                errors.append("server:%s" % (self.server.error or "unreaped"))
        if self.keyring is not None:
            self.cleanup_child(self.keyring, signal.SIGTERM)
            if not self.keyring.reaped:
                errors.append("keyring:%s" % (self.keyring.error or "unreaped"))
        if self.readiness is not None:
            self.cleanup_child(self.readiness, signal.SIGKILL)
            if not self.readiness.reaped:
                errors.append("readiness:%s" % (self.readiness.error or "unreaped"))
            else:
                self.readiness_reaped = True
                if self.readiness_exit is None:
                    self.readiness_exit = self.readiness.exit_code
        for child in (self.server, self.keyring, self.readiness):
            if child is not None:
                errors.extend("%s-signal:%s" % (child.name, item) for item in child.signal_errors)
                if child.pidfd is not None:
                    try:
                        os.close(child.pidfd)
                    except OSError as error:
                        errors.append("%s-pidfd-close:%d" % (child.name, error.errno or 0))
                    child.pidfd = None

        server_exit = self.server.exit_code if self.server is not None else None
        keyring_exit = self.keyring.exit_code if self.keyring is not None else None
        # Every child that exists contributes an error when it cannot be reaped, so a
        # clean list means a complete cleanup. A readiness probe that was never
        # created adds no error and no resource: only a real child can be unreaped.
        cleanup_complete = not errors
        self.cleanup_complete = cleanup_complete
        graceful = (
            server_exit == 0
            and self.delivered == 1
            and not self.escalated
            and self.failure is None
            and cleanup_complete
        )
        receipt(
            "owner_exit",
            server_exit=server_exit,
            keyring_exit=keyring_exit,
            readiness_exit=self.readiness_exit,
            delivered=self.delivered,
            escalated=self.escalated,
            graceful=graceful,
            failure=self.failure,
            cleanup_complete=cleanup_complete,
            server_reaped=bool(self.server is not None and self.server.reaped),
            keyring_reaped=bool(self.keyring is not None and self.keyring.reaped),
            readiness_reaped=self.readiness_reaped,
            cleanup_errors=errors,
        )
        if not cleanup_complete or server_exit is None:
            return OWNER_FAILURE_CODE
        return launcher_code(server_exit)


def main(argv):
    if len(argv) < 2:
        receipt("control_error", reason="missing-server-argv", detail=None)
        return OWNER_NOT_READY_CODE
    owner = Owner(argv[1:])
    try:
        owner.start()
        owner.serve()
    except ControlError as error:
        owner.failure = error.token
        receipt("control_error", reason=error.token, detail=error.detail)
        owner.finish()
        # The start-up diagnosis is kept only when the teardown really completed:
        # children that could not be reclaimed must surface as the cleanup-failure
        # code instead of a tidy 65/78.
        if not owner.cleanup_complete:
            return OWNER_FAILURE_CODE
        if error.token == "pidfd-unsupported":
            return OWNER_CONFIGURATION_CODE
        return OWNER_NOT_READY_CODE
    except Exception as error:  # noqa: BLE001 - one teardown path for every bug
        owner.failure = "owner-exception"
        receipt("control_error", reason="owner-exception", detail=type(error).__name__)
        owner.finish()
        return OWNER_FAILURE_CODE
    return owner.finish()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
