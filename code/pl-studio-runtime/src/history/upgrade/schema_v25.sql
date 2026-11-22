CREATE TABLE history_store_meta (
    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
    schema_version INTEGER NOT NULL CHECK(schema_version = 25),
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
    kind TEXT NOT NULL CHECK(kind IN (
        'run_started','run_ended',
        'turn_started','turn_changed','turn_ended','turn_rolled_back',
        'source_started','source_ended',
        'input_accepted','input_consumed','input_discarded',
        'entity_started','entity_state_changed','entity_ended',
        'content_became_visible',
        'group_opened','group_head_changed','group_closed',
        'boundary_observed',
        'usage_recorded','usage_adjusted',
        'background_delivery_recorded','business_changed','legacy_observed'
    )),
    run_id TEXT,
    attempt_id TEXT,
    entity_id TEXT,
    turn_id TEXT,
    source_kind TEXT,
    source_id TEXT,
    call_id TEXT,
    message_id TEXT,
    query_class TEXT,
    parent_id TEXT,
    original_kind TEXT,
    tool_name TEXT,
    group_id TEXT,
    row_scope TEXT CHECK(row_scope IN ('work','single','member','turn','source','cost','accounting')),
    row_key TEXT,
    is_anchor INTEGER NOT NULL DEFAULT 0 CHECK(is_anchor IN (0,1)),
    occurred_at INTEGER,
    recorded_at INTEGER NOT NULL,
    head_json TEXT CHECK(head_json IS NULL OR
        (json_valid(head_json) AND length(CAST(head_json AS BLOB)) <= 16384)),
    payload_body_id TEXT REFERENCES history_bodies(body_id)
        DEFERRABLE INITIALLY DEFERRED,
    CHECK((source_kind IS NULL) = (source_id IS NULL)),
    CHECK((query_class IS NULL) = (original_kind IS NULL)),
    CHECK(query_class IS NOT NULL OR (parent_id IS NULL AND tool_name IS NULL)),
    CHECK(query_class IS NULL OR payload_body_id IS NOT NULL),
    CHECK((row_scope IS NULL) = (row_key IS NULL)),
    CHECK((row_key IS NULL) = (head_json IS NULL)),
    CHECK(is_anchor = 0 OR row_key IS NOT NULL),
    CHECK(row_scope != 'member' OR (group_id IS NOT NULL AND entity_id IS NOT NULL)),
    CHECK(row_scope != 'work' OR group_id IS NOT NULL)
);

CREATE UNIQUE INDEX history_one_anchor
    ON history_events(row_key) WHERE is_anchor = 1;
CREATE INDEX history_row_head
    ON history_events(row_key, seq DESC) WHERE row_key IS NOT NULL;
CREATE INDEX history_main_anchors
    ON history_events(seq DESC, row_key)
    WHERE is_anchor = 1 AND row_scope IN ('work','single');
CREATE INDEX history_member_anchors
    ON history_events(group_id, seq DESC, row_key)
    WHERE is_anchor = 1 AND row_scope = 'member';
CREATE INDEX history_business_anchors
    ON history_events(row_scope, seq DESC, row_key) WHERE is_anchor = 1;
CREATE INDEX history_entity_events
    ON history_events(entity_id, seq DESC) WHERE entity_id IS NOT NULL;
CREATE INDEX history_turn_events
    ON history_events(turn_id, seq DESC) WHERE turn_id IS NOT NULL;
CREATE INDEX history_source_events
    ON history_events(source_kind, source_id, seq DESC) WHERE source_id IS NOT NULL;
CREATE INDEX history_call_events
    ON history_events(call_id, seq DESC) WHERE call_id IS NOT NULL;
CREATE INDEX history_message_events
    ON history_events(message_id, seq DESC) WHERE message_id IS NOT NULL;
CREATE INDEX history_attempt_events
    ON history_events(run_id, attempt_id, seq DESC) WHERE attempt_id IS NOT NULL;
CREATE INDEX history_originals_class
    ON history_events(query_class, seq DESC) WHERE query_class IS NOT NULL;
CREATE INDEX history_originals_all
    ON history_events(seq DESC) WHERE query_class IS NOT NULL;
CREATE INDEX history_originals_parent
    ON history_events(parent_id, seq DESC) WHERE query_class IS NOT NULL;
CREATE INDEX history_originals_parent_class
    ON history_events(parent_id, query_class, seq DESC) WHERE query_class IS NOT NULL;
CREATE INDEX history_originals_text
    ON history_events(seq DESC)
    WHERE query_class IS NOT NULL AND original_kind IN ('text','input');
CREATE INDEX history_originals_tool
    ON history_events(turn_id, tool_name, seq DESC)
    WHERE query_class IS NOT NULL AND tool_name IS NOT NULL;

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
