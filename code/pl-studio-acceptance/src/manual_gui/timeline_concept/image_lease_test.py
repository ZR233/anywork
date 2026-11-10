"""Targeted real Linux lease lifecycle tests; never launches the GUI."""

import json
import os
from pathlib import Path
import subprocess
import signal
import sys
import tempfile
import time
import unittest


HOLDER = Path(__file__).with_name("image_lease.py")
PNG = Path(__file__).parents[4] / "anywork/integration_test/fixtures/tool-image.png"


class ImageLeaseLifecycle(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(
            prefix="image-lease-", dir=os.environ["ANYWORK_MEDIA_LEASE_TEST_TEMP"]
        )
        self.directory = Path(self.temp.name)
        self.source = self.directory / "source.png"
        self.source.write_bytes(PNG.read_bytes())
        self.holder = subprocess.Popen(
            [sys.executable, "-u", str(HOLDER), str(self.source), str(self.directory)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.reader = None
        self.addCleanup(self.cleanup)
        self.wait_for("ready")

    def cleanup(self):
        # Same ordering as the native owner: unlock and join before reader wait.
        (self.directory / "abort.json").write_text("{}")
        try:
            self.holder.wait(timeout=5)
        finally:
            if self.holder.poll() is None:
                self.holder.kill()
                self.holder.wait()
            if self.reader is not None:
                self.reader.communicate(timeout=5)
            self.holder.communicate()
            self.temp.cleanup()

    def wait_for(self, name):
        marker = self.directory / (name + ".json")
        deadline = time.monotonic() + 5
        while not marker.exists():
            if self.holder.poll() is not None or time.monotonic() >= deadline:
                self.fail(f"holder stopped/timed out waiting for {name}: "
                          f"{list(self.directory.iterdir())}")
            time.sleep(0.01)
        return json.loads(marker.read_text())

    def start_reader(self):
        self.reader = subprocess.Popen(
            [sys.executable, "-c",
             "import pathlib,sys;sys.stdout.buffer.write(pathlib.Path(sys.argv[1]).read_bytes())",
             str(self.source)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.assertTrue(self.wait_for("break")["sigio"])
        self.assertIsNone(self.reader.poll())
        self.assertFalse((self.directory / "released.json").exists())

    def test_explicit_identity_release_unblocks_original_bytes(self):
        self.start_reader()
        identity = {
            "inputId": "input-a", "callId": "call-a", "taskId": "task-a",
            "foregroundAtomId": "atom-a", "turnId": "turn-a",
        }
        (self.directory / "releaseRequest.json").write_text(json.dumps(identity))
        self.assertEqual(self.holder.wait(timeout=5), 0)
        released = json.loads((self.directory / "released.json").read_text())
        self.assertEqual(released["releaseRequest"], identity)
        self.assertTrue(released["explicitUnlock"])
        self.assertTrue(released["breakObserved"])
        output, error = self.reader.communicate(timeout=5)
        self.assertEqual(self.reader.returncode, 0, error)
        self.assertEqual(output, PNG.read_bytes())
        self.assertFalse((self.directory / "error.json").exists())

    def test_abort_unlocks_and_joins_before_blocked_reader(self):
        self.start_reader()
        (self.directory / "abort.json").write_text("{}")
        self.assertEqual(self.holder.wait(timeout=5), 1)
        self.assertFalse((self.directory / "released.json").exists())
        self.assertTrue((self.directory / "closed.json").exists())
        output, error = self.reader.communicate(timeout=5)
        self.assertEqual(self.reader.returncode, 0, error)
        self.assertEqual(output, PNG.read_bytes())

    def test_owner_channel_loss_is_failure_not_release(self):
        self.start_reader()
        self.holder.stdin.close()
        self.holder.stdin = None
        self.assertEqual(self.holder.wait(timeout=5), 1)
        self.assertIn("channel lost", self.wait_for("error")["error"])
        self.assertFalse((self.directory / "released.json").exists())
        self.assertEqual(self.reader.communicate(timeout=5)[0], PNG.read_bytes())

    def test_invalid_identity_after_break_unlocks_without_success(self):
        self.start_reader()
        identity = {
            "inputId": "input-a", "callId": "call-a", "taskId": "",
            "foregroundAtomId": "atom-a", "turnId": "turn-a",
        }
        (self.directory / "releaseRequest.json").write_text(json.dumps(identity))
        self.assertEqual(self.holder.wait(timeout=5), 1)
        self.assertIn("call/task identity", self.wait_for("error")["error"])
        self.assertFalse((self.directory / "released.json").exists())
        self.assertTrue((self.directory / "closed.json").exists())
        output, error = self.reader.communicate(timeout=5)
        self.assertEqual(self.reader.returncode, 0, error)
        self.assertEqual(output, PNG.read_bytes())

    def test_sigterm_unlocks_and_joins_without_successful_release(self):
        self.start_reader()
        self.holder.send_signal(signal.SIGTERM)
        self.assertEqual(self.holder.wait(timeout=5), 1)
        self.assertIn("cancelled", self.wait_for("error")["error"])
        self.assertFalse((self.directory / "released.json").exists())
        self.assertFalse(self.wait_for("closed")["successfulRelease"])
        output, error = self.reader.communicate(timeout=5)
        self.assertEqual(self.reader.returncode, 0, error)
        self.assertEqual(output, PNG.read_bytes())

    def test_release_without_break_is_rejected(self):
        (self.directory / "releaseRequest.json").write_text("{}")
        self.assertEqual(self.holder.wait(timeout=5), 1)
        self.assertIn("without real SIGIO", self.wait_for("error")["error"])
        self.assertFalse((self.directory / "released.json").exists())


if __name__ == "__main__":
    unittest.main()
