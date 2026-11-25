CREATE TABLE history_store_meta (
    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
    schema_version INTEGER NOT NULL CHECK(schema_version = 27),
    database_id TEXT NOT NULL UNIQUE,
    thread_id TEXT NOT NULL
);

CREATE TABLE history_bodies (
    body_id TEXT PRIMARY KEY NOT NULL,
    owner_event_id TEXT NOT NULL REFERENCES history_events(event_id)
        DEFERRABLE INITIALLY DEFERRED,
    ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
    body_key TEXT NOT NULL,
    role TEXT NOT NULL,
    byte_length INTEGER NOT NULL CHECK(byte_length >= 0),
    media_type TEXT,
    digest BLOB NOT NULL CHECK(length(digest) = 32),
    UNIQUE(owner_event_id, ordinal),
    UNIQUE(owner_event_id, body_key)
) WITHOUT ROWID;

CREATE TABLE history_body_chunks (
    body_id TEXT NOT NULL REFERENCES history_bodies(body_id),
    chunk_no INTEGER NOT NULL CHECK(chunk_no >= 0),
    data BLOB NOT NULL CHECK(length(data) BETWEEN 1 AND 65536),
    PRIMARY KEY(body_id, chunk_no)
) WITHOUT ROWID;

CREATE TABLE history_events (
    seq INTEGER PRIMARY KEY CHECK(seq > 0),
    event_id TEXT NOT NULL UNIQUE CHECK(length(event_id) > 0),
    kind TEXT NOT NULL CHECK(length(kind) > 0),
    timeline_role INTEGER NOT NULL CHECK(timeline_role IN (0, 1, 2)),
    occurred_at INTEGER,
    recorded_at INTEGER NOT NULL,
    run_id TEXT,
    turn_id TEXT,
    attempt_id TEXT,
    call_id TEXT,
    entity_id TEXT,
    message_id TEXT,
    tool_name TEXT,
    source_id TEXT,
    query_class TEXT,
    parent_id TEXT,
    original_kind TEXT,
    row_scope TEXT CHECK(row_scope IN ('turn', 'source', 'cost', 'accounting')),
    row_key TEXT,
    is_anchor INTEGER NOT NULL DEFAULT 0 CHECK(is_anchor IN (0, 1)),
    payload_schema TEXT NOT NULL CHECK(length(payload_schema) > 0),
    payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
    CHECK((query_class IS NULL) = (original_kind IS NULL)),
    CHECK(query_class IS NOT NULL OR parent_id IS NULL),
    CHECK((row_scope IS NULL) = (row_key IS NULL)),
    CHECK(is_anchor = 0 OR row_key IS NOT NULL),
    CHECK(row_scope IS NULL OR timeline_role = 0)
);

CREATE INDEX idx_events_boundaries
    ON history_events(seq DESC) WHERE timeline_role = 2;
CREATE INDEX idx_events_work
    ON history_events(seq DESC) WHERE timeline_role = 1;
CREATE UNIQUE INDEX history_one_anchor
    ON history_events(row_key) WHERE is_anchor = 1;
CREATE INDEX history_row_head
    ON history_events(row_key, seq DESC) WHERE row_key IS NOT NULL;
CREATE INDEX history_business_anchors
    ON history_events(row_scope, seq DESC, row_key) WHERE is_anchor = 1;
CREATE INDEX idx_events_entity
    ON history_events(entity_id, seq DESC) WHERE entity_id IS NOT NULL;
CREATE INDEX idx_events_turn
    ON history_events(turn_id, seq DESC) WHERE turn_id IS NOT NULL;
CREATE INDEX idx_events_source
    ON history_events(source_id, seq DESC) WHERE source_id IS NOT NULL;
CREATE INDEX idx_events_call
    ON history_events(call_id, seq DESC) WHERE call_id IS NOT NULL;
CREATE INDEX idx_events_originals_all
    ON history_events(seq DESC, query_class) WHERE query_class IS NOT NULL;
CREATE INDEX idx_events_originals_parent
    ON history_events(parent_id, seq DESC, query_class)
    WHERE query_class IS NOT NULL AND parent_id IS NOT NULL;
CREATE INDEX idx_events_originals_text
    ON history_events(seq DESC)
    WHERE query_class IS NOT NULL AND original_kind IN ('text', 'input');

CREATE TRIGGER history_events_no_update
BEFORE UPDATE ON history_events BEGIN
    SELECT RAISE(ABORT, 'history events are append-only');
END;
CREATE TRIGGER history_events_no_delete
BEFORE DELETE ON history_events BEGIN
    SELECT RAISE(ABORT, 'history events are append-only');
END;
CREATE TRIGGER history_bodies_no_update
BEFORE UPDATE ON history_bodies BEGIN
    SELECT RAISE(ABORT, 'history bodies are immutable');
END;
CREATE TRIGGER history_bodies_no_delete
BEFORE DELETE ON history_bodies BEGIN
    SELECT RAISE(ABORT, 'history bodies are immutable');
END;
CREATE TRIGGER history_body_chunks_no_update
BEFORE UPDATE ON history_body_chunks BEGIN
    SELECT RAISE(ABORT, 'history body chunks are immutable');
END;
CREATE TRIGGER history_body_chunks_no_delete
BEFORE DELETE ON history_body_chunks BEGIN
    SELECT RAISE(ABORT, 'history body chunks are immutable');
END;
