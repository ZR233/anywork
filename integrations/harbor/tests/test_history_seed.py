import fcntl
import json
import shutil
import sqlite3
from pathlib import Path

import pytest
from conftest import rewrite_events

from anywork_harbor.artifacts import sha256
from anywork_harbor.history_seed import freeze, tree_hashes, validate_seed


@pytest.fixture
def source_home(tmp_path, archive):
    home = tmp_path / "home"
    data = home / "data"
    (home / "studio").mkdir(parents=True)
    (home / "studio/runtime.lock").touch()
    (data / "calls").mkdir(parents=True)
    (data / "layout.toml").write_text("schemaVersion=2\noperationId='fixture'\n")
    for name in ("catalog.toml", "workspaces.toml"):
        (data / name).write_text("")
    workspace = data / "workspaces" / sha256(b"workspace")
    session = workspace / "sessions" / sha256(b"thread")
    session.mkdir(parents=True)
    (workspace / "workspace.toml").write_text("schemaVersion=2\nworkspaceId='workspace'\n")
    (session / "session.toml").write_text(
        "schemaVersion=2\nworkspaceId='workspace'\nthreadId='thread'\n"
    )
    with sqlite3.connect(session / "history.sqlite") as db:
        db.executescript(
            "CREATE TABLE history_meta(id,schema_version); INSERT INTO history_meta VALUES(1,24);"
        )
    config = Path(__file__).resolve().parents[1] / "profiles/fixture.toml"
    shutil.copy2(config, home / "config.toml")
    with sqlite3.connect(data / "studio.sqlite") as db:
        db.executescript(
            "PRAGMA user_version=27; CREATE TABLE studio_objects(object_kind,payload_json);"
            "CREATE TABLE agent_evaluations(account_id,model_id);"
        )
    with sqlite3.connect(data / "calls/calls.sqlite") as db:
        db.executescript(
            "CREATE TABLE calls_meta(id,schema_version,pending_cleanup);"
            "INSERT INTO calls_meta VALUES(1,9,0);"
            "CREATE TABLE performance_samples(account_id,model_id);"
            "INSERT INTO performance_samples VALUES('fixture','vendor/harbor-fixture');"
        )
    manifest = json.loads((archive / "run.json").read_text())
    manifest["invocation"]["studioHome"] = str(home)
    manifest["configInputs"] = [
        {
            "logicalName": "config.toml",
            "present": True,
            "sha256": sha256(config.read_bytes()),
            "redactedSummary": None,
        }
    ]
    (archive / "run.json").write_text(json.dumps(manifest))
    events = [json.loads(line) for line in (archive / "events.jsonl").read_text().splitlines()]
    events[0]["data"]["manifestSha256"] = sha256((archive / "run.json").read_bytes())
    rewrite_events(archive, events)
    development = tmp_path / "development.json"
    development.write_text(json.dumps({"suite": "development", "tasks": [{"id": "dev-only"}]}))
    return home, development


def test_seed_is_locked_validated_and_each_copy_is_independent(source_home, archive, tmp_path):
    home, development = source_home
    output = tmp_path / "seed"
    with (home / "studio/runtime.lock").open("rb") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with pytest.raises(BlockingIOError):
            freeze(home, archive, development, output)
    assert not output.exists()
    seed = freeze(home, archive, development, output)
    assert seed["statistics"]["performance_samples"][0]["count"] == 1
    validate_seed(output, config=home / "config.toml", expected_version="1.0.0-test")
    for name in ("trial-one", "trial-two"):
        shutil.copytree(output / "data", tmp_path / name)
    with sqlite3.connect(tmp_path / "trial-one/calls/calls.sqlite") as db:
        db.execute("INSERT INTO performance_samples VALUES('new','model')")
    assert tree_hashes(output / "data") == tree_hashes(tmp_path / "trial-two")
    assert tree_hashes(tmp_path / "trial-one") != tree_hashes(tmp_path / "trial-two")
    with pytest.raises(ValueError, match="重叠"):
        validate_seed(
            output,
            config=home / "config.toml",
            expected_version="1.0.0-test",
            excluded_tasks=["dev-only"],
        )
    (output / "data/catalog.toml").write_text("changed=true")
    with pytest.raises(ValueError, match="摘要"):
        validate_seed(output, config=home / "config.toml", expected_version="1.0.0-test")


@pytest.mark.parametrize("fault", ["close", "lease", "migration", "config", "missing"])
def test_seed_refuses_pending_operations_changed_config_and_missing_data(
    source_home, archive, tmp_path, fault
):
    home, development = source_home
    if fault in ("close", "lease"):
        kind, payload = (
            ("agentClose", {"executionClosed": False, "worktreeCleanup": {"kind": "removed"}})
            if fault == "close"
            else ("worktreeLease", {"state": "active"})
        )
        with sqlite3.connect(home / "data/studio.sqlite") as db:
            db.execute("INSERT INTO studio_objects VALUES(?,?)", (kind, json.dumps(payload)))
    elif fault == "migration":
        (home / "storage-migration.toml").write_text("phase='building'\n")
    elif fault == "config":
        with (home / "config.toml").open("a") as stream:
            stream.write("\n# changed\n")
    else:
        (home / "data/catalog.toml").unlink()
    with pytest.raises(ValueError):
        freeze(home, archive, development, tmp_path / "seed")


def test_wal_snapshot_keeps_committed_samples_without_modifying_source(
    source_home, archive, tmp_path
):
    from contextlib import closing

    home, development = source_home
    with closing(sqlite3.connect(home / "data/calls/calls.sqlite")) as writer:
        writer.execute("PRAGMA journal_mode=WAL")
        writer.execute("INSERT INTO performance_samples VALUES('fixture','vendor/harbor-fixture')")
        writer.commit()
        before = tree_hashes(home / "data")
        output = tmp_path / "seed"
        seed = freeze(home, archive, development, output)
        assert tree_hashes(home / "data") == before
        assert seed["statistics"]["performance_samples"][0]["count"] == 2
        assert not list((output / "data").rglob("*-wal"))
        validate_seed(output, config=home / "config.toml", expected_version="1.0.0-test")
        assert tree_hashes(output / "data") == seed["files"]


def test_seed_output_cannot_recursively_copy_its_own_source(source_home, archive):
    home, development = source_home
    output = home / "data/seed"
    with pytest.raises(ValueError, match="之外"):
        freeze(home, archive, development, output)
    assert not output.exists()
