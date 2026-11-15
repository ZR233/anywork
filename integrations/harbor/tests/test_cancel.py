import asyncio
import json
import os
from pathlib import Path
from uuid import uuid4

SCRIPTS = Path(__file__).resolve().parents[1] / "src/anywork_harbor/scripts"


async def test_cancel_stops_independent_process_groups_and_sessions(tmp_path):
    marker = str(uuid4())
    writes = tmp_path / "writes"
    command = 'trap "" TERM; setsid sh -c \'trap "" TERM; while :; do echo writing >> "$1"; sleep 0.05; done\' -- "$1" & wait'
    process = await asyncio.create_subprocess_exec(
        "setsid",
        "--wait",
        "/bin/sh",
        str(SCRIPTS / "launch.sh"),
        str(tmp_path),
        marker,
        "/bin/sh",
        "-c",
        command,
        "--",
        str(writes),
        env={**os.environ, "ANYWK_HARBOR_RUN_ID": marker},
    )
    try:
        for _ in range(100):
            if (tmp_path / "identity.json").exists() and writes.exists():
                break
            await asyncio.sleep(0.02)
        assert writes.exists()
        control = await asyncio.create_subprocess_exec(
            "/bin/sh",
            str(SCRIPTS / "cancel.sh"),
            str(tmp_path),
            marker,
            stdout=asyncio.subprocess.PIPE,
        )
        raw, _ = await asyncio.wait_for(control.communicate(), timeout=5)
        cleanup = json.loads(raw)
        assert cleanup["clean"], cleanup
        assert cleanup["remainingKnownPids"] == []
        await asyncio.wait_for(process.wait(), timeout=2)
        length = writes.stat().st_size
        await asyncio.sleep(0.2)
        assert writes.stat().st_size == length
    finally:
        if process.returncode is None:
            cleanup = await asyncio.create_subprocess_exec(
                "/bin/sh",
                str(SCRIPTS / "cancel.sh"),
                str(tmp_path),
                marker,
                stdout=asyncio.subprocess.DEVNULL,
            )
            await asyncio.wait_for(cleanup.wait(), timeout=5)
            await asyncio.wait_for(process.wait(), timeout=2)


async def test_stale_pid_identity_does_not_kill_unrelated_process(tmp_path):
    unrelated = await asyncio.create_subprocess_exec("sleep", "30")
    try:
        marker = str(uuid4())
        (tmp_path / "identity.json").write_text(
            json.dumps(
                {
                    "launcherId": marker,
                    "pid": unrelated.pid,
                    "pgid": unrelated.pid,
                    "sid": unrelated.pid,
                    "startTimeTicks": 0,
                },
                separators=(",", ":"),
            )
        )
        control = await asyncio.create_subprocess_exec(
            "/bin/sh",
            str(SCRIPTS / "cancel.sh"),
            str(tmp_path),
            marker,
            stdout=asyncio.subprocess.PIPE,
        )
        raw, _ = await asyncio.wait_for(control.communicate(), timeout=5)
        cleanup = json.loads(raw)
        assert cleanup["identityMismatch"]
        assert not cleanup["clean"]
        assert unrelated.returncode is None
    finally:
        unrelated.terminate()
        await unrelated.wait()
