//! Zero-copy in-place migration from Schema 26 to Schema 27.
//!
//! `history_bodies` and `history_body_chunks` stay untouched with zero BLOB copying.
//! Only `history_events` (encoding `timeline_role` as `0 | 1 | 2`, dropping `source_kind`,
//! replacing legacy indexes with sparse Schema 27 indexes) and `history_store_meta`
//! are transformed in one atomic Immediate transaction.

use sea_orm::ConnectionTrait;

use super::super::{HistoryError, Result, db::statement};

const V27_STAGING_DDL: &str = r#"
CREATE TABLE history_events_v27 (
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
"#;

const V27_INDEXES_AND_TRIGGERS: &str = r#"
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
"#;

pub(in crate::history) async fn migrate_v26_to_v27(
    db: &impl ConnectionTrait,
    expected_thread_id: &str,
) -> Result<(String, u64)> {
    let meta = db
        .query_one_raw(statement(
            "SELECT schema_version,database_id,thread_id FROM history_store_meta WHERE singleton=1",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("schema 26 history_store_meta missing".into()))?;
    let schema_version: i64 = meta.try_get("", "schema_version")?;
    let database_id: String = meta.try_get("", "database_id")?;
    let thread_id: String = meta.try_get("", "thread_id")?;
    if schema_version != 26 || thread_id != expected_thread_id || database_id.is_empty() {
        return Err(HistoryError::Integrity(
            "schema 26 identity differs from expected Thread".into(),
        ));
    }

    let source_count_row = db
        .query_one_raw(statement(
            "SELECT COUNT(*) AS c FROM history_events",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("schema 26 event count missing".into()))?;
    let expected_rows = u64::try_from(source_count_row.try_get::<i64>("", "c")?)
        .map_err(|_| HistoryError::Integrity("negative schema 26 event count".into()))?;

    let bad_roles = db
        .query_one_raw(statement(
            "SELECT 1 FROM history_events WHERE timeline_role NOT IN ('hidden', 'work', 'divider') LIMIT 1",
            vec![],
        ))
        .await?;
    if bad_roles.is_some() {
        return Err(HistoryError::Integrity(
            "schema 26 contains unrecognized timeline_role values".into(),
        ));
    }

    db.execute_raw(statement("DROP TABLE IF EXISTS history_events_v27", vec![]))
        .await?;
    db.execute_unprepared(V27_STAGING_DDL).await?;

    db.execute_raw(statement(
        "INSERT INTO history_events_v27(\
            seq,event_id,kind,timeline_role,occurred_at,recorded_at,\
            run_id,turn_id,attempt_id,call_id,entity_id,message_id,tool_name,\
            source_id,query_class,parent_id,original_kind,\
            row_scope,row_key,is_anchor,payload_schema,payload_json\
         ) \
         SELECT \
            seq,event_id,kind,\
            CASE timeline_role WHEN 'hidden' THEN 0 WHEN 'work' THEN 1 WHEN 'divider' THEN 2 END,\
            occurred_at,recorded_at,\
            run_id,turn_id,attempt_id,call_id,entity_id,message_id,tool_name,\
            source_id,query_class,parent_id,original_kind,\
            row_scope,row_key,is_anchor,payload_schema,payload_json \
         FROM history_events \
         ORDER BY seq ASC",
        vec![],
    ))
    .await?;

    let copied_row = db
        .query_one_raw(statement(
            "SELECT COUNT(*) AS c FROM history_events_v27",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("schema 27 staging count missing".into()))?;
    let migrated_rows = u64::try_from(copied_row.try_get::<i64>("", "c")?)
        .map_err(|_| HistoryError::Integrity("negative schema 27 event count".into()))?;
    if migrated_rows != expected_rows {
        return Err(HistoryError::Integrity(format!(
            "schema 26 -> 27 row count mismatch: expected {expected_rows}, copied {migrated_rows}"
        )));
    }

    db.execute_raw(statement("DROP TABLE history_events", vec![]))
        .await?;
    db.execute_raw(statement(
        "ALTER TABLE history_events_v27 RENAME TO history_events",
        vec![],
    ))
    .await?;
    db.execute_unprepared(V27_INDEXES_AND_TRIGGERS).await?;

    db.execute_raw(statement(
        "DROP TABLE IF EXISTS history_store_meta_v27",
        vec![],
    ))
    .await?;
    db.execute_unprepared(
        "CREATE TABLE history_store_meta_v27 (\
            singleton INTEGER PRIMARY KEY CHECK(singleton = 1),\
            schema_version INTEGER NOT NULL CHECK(schema_version = 27),\
            database_id TEXT NOT NULL UNIQUE,\
            thread_id TEXT NOT NULL\
        )",
    )
    .await?;
    db.execute_raw(statement(
        "INSERT INTO history_store_meta_v27(singleton,schema_version,database_id,thread_id) VALUES(1,27,?,?)",
        vec![database_id.clone().into(), thread_id.clone().into()],
    ))
    .await?;
    db.execute_raw(statement("DROP TABLE history_store_meta", vec![]))
        .await?;
    db.execute_raw(statement(
        "ALTER TABLE history_store_meta_v27 RENAME TO history_store_meta",
        vec![],
    ))
    .await?;

    let fk_errors = db
        .query_all_raw(statement("PRAGMA foreign_key_check", vec![]))
        .await?;
    if !fk_errors.is_empty() {
        return Err(HistoryError::Integrity(format!(
            "schema 26 -> 27 migration detected {} foreign key violations",
            fk_errors.len()
        )));
    }

    super::schema26_manifest::mark_repaired(db).await?;
    Ok((database_id, migrated_rows))
}
