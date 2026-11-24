//! Lossless, zero-copy Schema 25 -> Schema 26 migration inside a single IMMEDIATE transaction.
//!
//! Existing `history_bodies` and `history_body_chunks` rows remain untouched in place (zero bytes
//! copied for existing BLOBs). Only `history_events` and `history_store_meta` are transformed.

use std::collections::{BTreeMap, BTreeSet};

use sea_orm::{ConnectionTrait, QueryResult};
use sha2::{Digest, Sha256};

use super::super::{
    BODY_CHUNK_BYTES, HistoryBodyManifestEntry, HistoryBodyRole, HistoryBusinessRowHead,
    HistoryEntityKind, HistoryEntityState, HistoryError, HistoryEventBodyRef, HistoryEventKind,
    HistoryEventMeta, HistorySource, HistoryTimelineRole, INLINE_BODY_MAX_BYTES,
    INLINE_EVENT_MAX_BYTES, Result,
    body::{BusinessEnvelope, BusinessFactEnvelope, EventPayloadEnvelope},
    db::{number, statement},
};
use super::v25_schema::{
    HistoryEntityHeadV25, HistoryEventKindV25, HistoryObservationV25, HistoryRowHeadV25,
};

#[derive(Clone)]
struct V25BodyMeta {
    body_id: String,
    owner_event_id: String,
    ordinal: u64,
    body_key: String,
    role: String,
    byte_length: u64,
    media_type: Option<String>,
}

impl V25BodyMeta {
    fn reference(&self, database_id: &str) -> HistoryEventBodyRef {
        HistoryEventBodyRef {
            database_id: database_id.to_owned(),
            owner_event_id: self.owner_event_id.clone(),
            body_key: self.body_key.clone(),
            body_id: self.body_id.clone(),
            byte_start: 0,
            byte_length: self.byte_length,
        }
    }

    fn manifest_entry(&self, database_id: &str) -> HistoryBodyManifestEntry {
        HistoryBodyManifestEntry {
            key: self.body_key.clone(),
            role: self.role.clone(),
            byte_length: self.byte_length,
            media_type: self.media_type.clone(),
            inline_text: None,
            reference: Some(self.reference(database_id)),
        }
    }
}

struct V25EventRow {
    seq: u64,
    event_id: String,
    kind: HistoryEventKindV25,
    run_id: Option<String>,
    attempt_id: Option<String>,
    entity_id: Option<String>,
    turn_id: Option<String>,
    source_kind: Option<String>,
    source_id: Option<String>,
    call_id: Option<String>,
    message_id: Option<String>,
    query_class: Option<String>,
    parent_id: Option<String>,
    original_kind: Option<String>,
    tool_name: Option<String>,
    row_scope: Option<String>,
    row_key: Option<String>,
    is_anchor: bool,
    occurred_at: Option<i64>,
    recorded_at: i64,
    head_json: Option<String>,
    payload_body_id: Option<String>,
}

const V26_STAGING_DDL: &str = r#"
CREATE TABLE history_events_v26 (
    seq INTEGER PRIMARY KEY CHECK(seq > 0),
    event_id TEXT NOT NULL UNIQUE CHECK(length(event_id) > 0),
    kind TEXT NOT NULL CHECK(length(kind) > 0),
    timeline_role TEXT NOT NULL CHECK(timeline_role IN ('divider', 'work', 'hidden')),
    occurred_at INTEGER,
    recorded_at INTEGER NOT NULL,
    run_id TEXT,
    turn_id TEXT,
    attempt_id TEXT,
    call_id TEXT,
    entity_id TEXT,
    message_id TEXT,
    tool_name TEXT,
    source_kind TEXT,
    source_id TEXT,
    query_class TEXT,
    parent_id TEXT,
    original_kind TEXT,
    row_scope TEXT CHECK(row_scope IN ('turn', 'source', 'cost', 'accounting')),
    row_key TEXT,
    is_anchor INTEGER NOT NULL DEFAULT 0 CHECK(is_anchor IN (0, 1)),
    payload_schema TEXT NOT NULL CHECK(length(payload_schema) > 0),
    payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
    CHECK((source_kind IS NULL) = (source_id IS NULL)),
    CHECK((query_class IS NULL) = (original_kind IS NULL)),
    CHECK(query_class IS NOT NULL OR parent_id IS NULL),
    CHECK((row_scope IS NULL) = (row_key IS NULL)),
    CHECK(is_anchor = 0 OR row_key IS NOT NULL),
    CHECK(row_scope IS NULL OR timeline_role = 'hidden')
)
"#;

const V26_INDEXES_AND_TRIGGERS: &str = r#"
CREATE INDEX idx_events_dividers
    ON history_events(seq DESC) WHERE timeline_role = 'divider';
CREATE INDEX idx_events_work
    ON history_events(seq DESC, occurred_at, run_id) WHERE timeline_role = 'work';
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
    ON history_events(source_kind, source_id, seq DESC) WHERE source_id IS NOT NULL;
CREATE INDEX idx_events_call
    ON history_events(call_id, seq DESC) WHERE call_id IS NOT NULL;
CREATE INDEX idx_events_message
    ON history_events(message_id, seq DESC) WHERE message_id IS NOT NULL;
CREATE INDEX idx_events_attempt
    ON history_events(run_id, attempt_id, seq DESC) WHERE attempt_id IS NOT NULL;
CREATE INDEX idx_events_originals_class
    ON history_events(query_class, seq DESC) WHERE query_class IS NOT NULL;
CREATE INDEX idx_events_originals_all
    ON history_events(seq DESC) WHERE query_class IS NOT NULL;
CREATE INDEX idx_events_originals_parent
    ON history_events(parent_id, seq DESC) WHERE query_class IS NOT NULL;
CREATE INDEX idx_events_originals_parent_class
    ON history_events(parent_id, query_class, seq DESC) WHERE query_class IS NOT NULL;
CREATE INDEX idx_events_originals_text
    ON history_events(seq DESC)
    WHERE query_class IS NOT NULL AND original_kind IN ('text', 'input');
CREATE INDEX idx_events_originals_tool
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
"#;

pub(in crate::history) async fn migrate_v25_to_v26(
    db: &impl ConnectionTrait,
    expected_thread_id: &str,
) -> Result<(String, u64)> {
    let meta = db
        .query_one_raw(statement(
            "SELECT schema_version,database_id,thread_id FROM history_store_meta WHERE singleton=1",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("schema 25 history_store_meta missing".into()))?;
    let schema_version: i64 = meta.try_get("", "schema_version")?;
    let database_id: String = meta.try_get("", "database_id")?;
    let thread_id: String = meta.try_get("", "thread_id")?;
    if schema_version != 25 || thread_id != expected_thread_id || database_id.is_empty() {
        return Err(HistoryError::Integrity(
            "schema 25 identity differs from expected Thread".into(),
        ));
    }

    let (entities_with_terminal, single_latest_seq, payload_body_ids) = prescan_events(db).await?;
    let bodies_by_owner = load_body_metadata(db).await?;

    db.execute_raw(statement("DROP TABLE IF EXISTS history_events_v26", vec![]))
        .await?;
    db.execute_unprepared(V26_STAGING_DDL).await?;

    let mut after_seq: i64 = 0;
    let mut migrated_rows: u64 = 0;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT seq,event_id,kind,run_id,attempt_id,entity_id,turn_id,\
                        source_kind,source_id,call_id,message_id,query_class,parent_id,\
                        original_kind,tool_name,row_scope,row_key,is_anchor,occurred_at,\
                        recorded_at,head_json,payload_body_id \
                 FROM history_events WHERE seq>? ORDER BY seq ASC LIMIT 256",
                vec![after_seq.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for query_row in rows {
            let row = decode_v25_row(query_row)?;
            after_seq = number(row.seq)?;
            if let Some(converted) = convert_row(
                db,
                &database_id,
                &row,
                &bodies_by_owner,
                &payload_body_ids,
                &entities_with_terminal,
                &single_latest_seq,
            )
            .await?
            {
                let mut converted = converted;
                index_current_manifest(
                    &mut converted,
                    &database_id,
                    bodies_by_owner.get(&row.event_id),
                )?;
                insert_v26_row(db, &converted).await?;
                migrated_rows += 1;
            }
        }
    }

    db.execute_raw(statement("DROP TABLE history_events", vec![]))
        .await?;
    db.execute_raw(statement(
        "ALTER TABLE history_events_v26 RENAME TO history_events",
        vec![],
    ))
    .await?;
    db.execute_unprepared(V26_INDEXES_AND_TRIGGERS).await?;

    db.execute_raw(statement(
        "DROP TABLE IF EXISTS history_store_meta_v26",
        vec![],
    ))
    .await?;
    db.execute_unprepared(
        "CREATE TABLE history_store_meta_v26 (\
            singleton INTEGER PRIMARY KEY CHECK(singleton = 1),\
            schema_version INTEGER NOT NULL CHECK(schema_version = 26),\
            database_id TEXT NOT NULL UNIQUE,\
            thread_id TEXT NOT NULL\
        )",
    )
    .await?;
    db.execute_raw(statement(
        "INSERT INTO history_store_meta_v26(singleton,schema_version,database_id,thread_id) VALUES(1,26,?,?)",
        vec![database_id.clone().into(), thread_id.clone().into()],
    ))
    .await?;
    db.execute_raw(statement("DROP TABLE history_store_meta", vec![]))
        .await?;
    db.execute_raw(statement(
        "ALTER TABLE history_store_meta_v26 RENAME TO history_store_meta",
        vec![],
    ))
    .await?;

    let fk_errors = db
        .query_all_raw(statement("PRAGMA foreign_key_check", vec![]))
        .await?;
    if !fk_errors.is_empty() {
        return Err(HistoryError::Integrity(format!(
            "schema 25 -> 26 migration detected {} foreign key violations",
            fk_errors.len()
        )));
    }

    super::schema26_manifest::mark_repaired(db).await?;
    Ok((database_id, migrated_rows))
}

async fn prescan_events(
    db: &impl ConnectionTrait,
) -> Result<(
    BTreeSet<String>,
    BTreeMap<String, u64>,
    BTreeMap<String, String>,
)> {
    let mut entities_with_terminal = BTreeSet::new();
    let mut single_latest_seq = BTreeMap::new();
    let mut payload_body_ids = BTreeMap::new();
    let mut after_seq: i64 = 0;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT seq,event_id,kind,entity_id,row_scope,row_key,payload_body_id \
                 FROM history_events WHERE seq>? ORDER BY seq ASC LIMIT 512",
                vec![after_seq.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let seq_i64: i64 = row.try_get("", "seq")?;
            let seq = u64::try_from(seq_i64)
                .map_err(|_| HistoryError::Integrity("negative v25 event seq".into()))?;
            after_seq = seq_i64;
            let event_id: String = row.try_get("", "event_id")?;
            let kind: String = row.try_get("", "kind")?;
            let entity_id: Option<String> = row.try_get("", "entity_id")?;
            let row_scope: Option<String> = row.try_get("", "row_scope")?;
            let row_key: Option<String> = row.try_get("", "row_key")?;
            let payload_body_id: Option<String> = row.try_get("", "payload_body_id")?;
            if let Some(body_id) = payload_body_id {
                payload_body_ids.insert(event_id, body_id);
            }
            if kind == "entity_ended"
                && matches!(row_scope.as_deref(), Some("single" | "member"))
                && let Some(entity_id) = entity_id
            {
                entities_with_terminal.insert(entity_id);
            }
            if row_scope.as_deref() == Some("single")
                && let Some(row_key) = row_key
            {
                single_latest_seq.insert(row_key, seq);
            }
        }
    }
    Ok((entities_with_terminal, single_latest_seq, payload_body_ids))
}

async fn load_body_metadata(
    db: &impl ConnectionTrait,
) -> Result<BTreeMap<String, Vec<V25BodyMeta>>> {
    let mut map: BTreeMap<String, Vec<V25BodyMeta>> = BTreeMap::new();
    let rows = db
        .query_all_raw(statement(
            "SELECT body_id,owner_event_id,ordinal,body_key,role,byte_length,media_type \
             FROM history_bodies ORDER BY owner_event_id ASC, ordinal ASC",
            vec![],
        ))
        .await?;
    for row in rows {
        let ordinal = u64::try_from(row.try_get::<i64>("", "ordinal")?)
            .map_err(|_| HistoryError::Integrity("negative v25 body ordinal".into()))?;
        let byte_length = u64::try_from(row.try_get::<i64>("", "byte_length")?)
            .map_err(|_| HistoryError::Integrity("negative v25 body length".into()))?;
        let meta = V25BodyMeta {
            body_id: row.try_get("", "body_id")?,
            owner_event_id: row.try_get("", "owner_event_id")?,
            ordinal,
            body_key: row.try_get("", "body_key")?,
            role: row.try_get("", "role")?,
            byte_length,
            media_type: row.try_get("", "media_type")?,
        };
        map.entry(meta.owner_event_id.clone())
            .or_default()
            .push(meta);
    }
    Ok(map)
}

fn decode_v25_row(row: QueryResult) -> Result<V25EventRow> {
    let seq = u64::try_from(row.try_get::<i64>("", "seq")?)
        .map_err(|_| HistoryError::Integrity("negative v25 seq".into()))?;
    let kind: String = row.try_get("", "kind")?;
    Ok(V25EventRow {
        seq,
        event_id: row.try_get("", "event_id")?,
        kind: kind.into(),
        run_id: row.try_get("", "run_id")?,
        attempt_id: row.try_get("", "attempt_id")?,
        entity_id: row.try_get("", "entity_id")?,
        turn_id: row.try_get("", "turn_id")?,
        source_kind: row.try_get("", "source_kind")?,
        source_id: row.try_get("", "source_id")?,
        call_id: row.try_get("", "call_id")?,
        message_id: row.try_get("", "message_id")?,
        query_class: row.try_get("", "query_class")?,
        parent_id: row.try_get("", "parent_id")?,
        original_kind: row.try_get("", "original_kind")?,
        tool_name: row.try_get("", "tool_name")?,
        row_scope: row.try_get("", "row_scope")?,
        row_key: row.try_get("", "row_key")?,
        is_anchor: row.try_get::<i64>("", "is_anchor")? == 1,
        occurred_at: row.try_get("", "occurred_at")?,
        recorded_at: row.try_get("", "recorded_at")?,
        head_json: row.try_get("", "head_json")?,
        payload_body_id: row.try_get("", "payload_body_id")?,
    })
}

struct ConvertedV26Row {
    seq: u64,
    event_id: String,
    kind: String,
    timeline_role: HistoryTimelineRole,
    occurred_at: Option<i64>,
    recorded_at: i64,
    run_id: Option<String>,
    turn_id: Option<String>,
    attempt_id: Option<String>,
    call_id: Option<String>,
    entity_id: Option<String>,
    message_id: Option<String>,
    tool_name: Option<String>,
    source_kind: Option<String>,
    source_id: Option<String>,
    query_class: Option<String>,
    parent_id: Option<String>,
    original_kind: Option<String>,
    row_scope: Option<String>,
    row_key: Option<String>,
    is_anchor: bool,
    payload_schema: String,
    payload_json: String,
}

async fn convert_row(
    db: &impl ConnectionTrait,
    database_id: &str,
    row: &V25EventRow,
    bodies_by_owner: &BTreeMap<String, Vec<V25BodyMeta>>,
    payload_body_ids: &BTreeMap<String, String>,
    entities_with_terminal: &BTreeSet<String>,
    single_latest_seq: &BTreeMap<String, u64>,
) -> Result<Option<ConvertedV26Row>> {
    let owner_bodies = bodies_by_owner
        .get(&row.event_id)
        .map(Vec::as_slice)
        .unwrap_or(&[]);
    // 1. Derived work-group rows: drop when unreferenced by any body; preserve as hidden if a body FK exists.
    if matches!(
        row.kind,
        HistoryEventKindV25::GroupOpened
            | HistoryEventKindV25::GroupHeadChanged
            | HistoryEventKindV25::GroupClosed
    ) {
        if owner_bodies.is_empty() {
            return Ok(None);
        }
        let manifest: Vec<HistoryBodyManifestEntry> = owner_bodies
            .iter()
            .map(|b| b.manifest_entry(database_id))
            .collect();
        return Ok(Some(ConvertedV26Row {
            seq: row.seq,
            event_id: row.event_id.clone(),
            kind: HistoryEventKind::LegacyObserved.as_str().to_owned(),
            timeline_role: HistoryTimelineRole::Hidden,
            occurred_at: row.occurred_at,
            recorded_at: row.recorded_at,
            run_id: row.run_id.clone(),
            turn_id: row.turn_id.clone(),
            attempt_id: row.attempt_id.clone(),
            call_id: row.call_id.clone(),
            entity_id: row.entity_id.clone(),
            message_id: row.message_id.clone(),
            tool_name: row.tool_name.clone(),
            source_kind: row.source_kind.clone(),
            source_id: row.source_id.clone(),
            query_class: row.query_class.clone(),
            parent_id: row.parent_id.clone(),
            original_kind: row.original_kind.clone(),
            row_scope: None,
            row_key: None,
            is_anchor: false,
            payload_schema: "anywork.business/1".into(),
            payload_json: serde_json::to_string(&BusinessFactEnvelope {
                fact_type: row.kind.as_str().to_owned(),
                data: None,
                bodies: manifest,
            })?,
        }));
    }

    // 2.BoundaryObserved: hide (if entity reached terminal) or retain as work (if truncated prefix without terminal).
    let is_superseded_boundary = row.kind == HistoryEventKindV25::BoundaryObserved
        && row
            .entity_id
            .as_ref()
            .is_some_and(|id| entities_with_terminal.contains(id));
    if is_superseded_boundary {
        if owner_bodies.is_empty() {
            return Ok(None);
        }
        let manifest: Vec<HistoryBodyManifestEntry> = owner_bodies
            .iter()
            .filter(|b| {
                b.role != "canonical_payload"
                    && b.role != "canonical_metadata"
                    && b.role != "legacy_metadata"
            })
            .map(|b| b.manifest_entry(database_id))
            .collect();
        return Ok(Some(ConvertedV26Row {
            seq: row.seq,
            event_id: row.event_id.clone(),
            kind: HistoryEventKind::LegacyObserved.as_str().to_owned(),
            timeline_role: HistoryTimelineRole::Hidden,
            occurred_at: row.occurred_at,
            recorded_at: row.recorded_at,
            run_id: row.run_id.clone(),
            turn_id: row.turn_id.clone(),
            attempt_id: row.attempt_id.clone(),
            call_id: row.call_id.clone(),
            entity_id: row.entity_id.clone(),
            message_id: row.message_id.clone(),
            tool_name: row.tool_name.clone(),
            source_kind: row.source_kind.clone(),
            source_id: row.source_id.clone(),
            query_class: None,
            parent_id: None,
            original_kind: None,
            row_scope: None,
            row_key: None,
            is_anchor: false,
            payload_schema: "anywork.business/1".into(),
            payload_json: serde_json::to_string(&BusinessFactEnvelope {
                fact_type: "superseded_boundary_observed".into(),
                data: None,
                bodies: manifest,
            })?,
        }));
    }

    let parsed_head = row
        .head_json
        .as_deref()
        .map(serde_json::from_str::<HistoryRowHeadV25>)
        .transpose()?;

    // 3. Business rows (turn / source / cost / accounting)
    if let Some(
        head @ (HistoryRowHeadV25::Turn(_)
        | HistoryRowHeadV25::Source(_)
        | HistoryRowHeadV25::Cost(_)
        | HistoryRowHeadV25::Accounting(_)),
    ) = &parsed_head
    {
        let (business_head, payload_schema, scope_str) = match head {
            HistoryRowHeadV25::Turn(v) => (
                HistoryBusinessRowHead::Turn(v.clone()),
                "anywork.turn/1",
                "turn",
            ),
            HistoryRowHeadV25::Source(v) => (
                HistoryBusinessRowHead::Source(v.clone()),
                "anywork.source/1",
                "source",
            ),
            HistoryRowHeadV25::Cost(v) => (
                HistoryBusinessRowHead::Cost(v.clone()),
                "anywork.cost/1",
                "cost",
            ),
            HistoryRowHeadV25::Accounting(v) => (
                HistoryBusinessRowHead::Accounting(v.clone()),
                "anywork.accounting/1",
                "accounting",
            ),
            _ => unreachable!(),
        };
        let manifest: Vec<HistoryBodyManifestEntry> = owner_bodies
            .iter()
            .filter(|b| b.role != "canonical_metadata")
            .map(|b| b.manifest_entry(database_id))
            .collect();
        let payload_json = match &business_head {
            HistoryBusinessRowHead::Turn(h) => serde_json::to_string(&BusinessEnvelope {
                head: h,
                bodies: manifest,
            })?,
            HistoryBusinessRowHead::Source(h) => serde_json::to_string(&BusinessEnvelope {
                head: h,
                bodies: manifest,
            })?,
            HistoryBusinessRowHead::Cost(h) => serde_json::to_string(&BusinessEnvelope {
                head: h,
                bodies: manifest,
            })?,
            HistoryBusinessRowHead::Accounting(h) => serde_json::to_string(&BusinessEnvelope {
                head: h,
                bodies: manifest,
            })?,
        };
        let row_key = row.row_key.clone().ok_or_else(|| {
            HistoryError::Integrity(format!("v25 business row {} missing row_key", row.event_id))
        })?;
        return Ok(Some(ConvertedV26Row {
            seq: row.seq,
            event_id: row.event_id.clone(),
            kind: row.kind.as_str().to_owned(),
            timeline_role: HistoryTimelineRole::Hidden,
            occurred_at: row.occurred_at,
            recorded_at: row.recorded_at,
            run_id: row.run_id.clone(),
            turn_id: row.turn_id.clone(),
            attempt_id: row.attempt_id.clone(),
            call_id: row.call_id.clone(),
            entity_id: row.entity_id.clone(),
            message_id: row.message_id.clone(),
            tool_name: row.tool_name.clone(),
            source_kind: row.source_kind.clone(),
            source_id: row.source_id.clone(),
            query_class: row.query_class.clone(),
            parent_id: row.parent_id.clone(),
            original_kind: row.original_kind.clone(),
            row_scope: Some(scope_str.into()),
            row_key: Some(row_key),
            is_anchor: row.is_anchor,
            payload_schema: payload_schema.into(),
            payload_json,
        }));
    }

    // 4. Entity rows (Single / Member / Observation / UnavailableLegacy / CanonicalOriginal without row_scope)
    let entity_from_body = if parsed_head.is_none() && row.query_class.is_some() {
        if let Some(meta_body) = owner_bodies.iter().find(|b| b.role == "canonical_metadata") {
            let bytes = read_v25_body_bytes(db, meta_body).await?;
            serde_json::from_slice::<HistoryEntityHeadV25>(&bytes).ok()
        } else {
            None
        }
    } else {
        None
    };
    let entity_opt = match &parsed_head {
        Some(HistoryRowHeadV25::Single(entity) | HistoryRowHeadV25::Member(entity)) => Some(entity),
        _ => entity_from_body.as_ref(),
    };
    if let Some(entity) = entity_opt {
        let timeline_role = if row.row_scope.as_deref() == Some("single") {
            let is_latest = row
                .row_key
                .as_ref()
                .is_some_and(|key| single_latest_seq.get(key) == Some(&row.seq));
            if is_latest {
                HistoryTimelineRole::Divider
            } else {
                HistoryTimelineRole::Hidden
            }
        } else if row.row_scope.as_deref() == Some("member")
            || (row.kind == HistoryEventKindV25::BoundaryObserved
                && row.row_scope.as_deref() != Some("single"))
        {
            HistoryTimelineRole::Work
        } else {
            HistoryTimelineRole::Hidden
        };

        let meta = entity_meta_from_v25(entity);
        let call_id = row
            .call_id
            .clone()
            .or_else(|| entity.tool.as_ref().map(|t| t.call_id.clone()));
        let tool_name = row
            .tool_name
            .clone()
            .or_else(|| entity.tool.as_ref().map(|t| t.name.clone()));

        let (payload_body_id, payload_source_bodies): (Option<&str>, &[V25BodyMeta]) =
            if let Some(pbid) = row.payload_body_id.as_deref() {
                (Some(pbid), owner_bodies)
            } else if let Some(detail_id) = entity.detail_event_id.as_deref()
                && detail_id != row.event_id
            {
                (
                    payload_body_ids.get(detail_id).map(String::as_str),
                    bodies_by_owner
                        .get(detail_id)
                        .map(Vec::as_slice)
                        .unwrap_or(&[]),
                )
            } else {
                (None, owner_bodies)
            };

        let mut payload_envelope = if let Some(payload_body_id) = payload_body_id {
            load_and_lift_canonical_payload(
                db,
                CanonicalLiftInput {
                    database_id,
                    row_event_id: &row.event_id,
                    row_own_bodies: owner_bodies,
                    payload_body_id,
                    payload_source_bodies,
                    observation: &entity.observation,
                    meta: &meta,
                },
            )
            .await?
        } else {
            None
        };

        if payload_envelope.is_none() {
            payload_envelope = Some(synthesize_envelope_from_head(
                database_id,
                payload_source_bodies,
                owner_bodies,
                entity,
                &meta,
                row.turn_id.as_deref(),
            ));
        }

        let envelope = payload_envelope.expect("payload_envelope built");
        let atomic_kind = map_entity_kind(row, entity, &envelope);
        let payload_json = serde_json::to_string(&envelope)?;

        return Ok(Some(ConvertedV26Row {
            seq: row.seq,
            event_id: row.event_id.clone(),
            kind: atomic_kind.as_str().to_owned(),
            timeline_role,
            occurred_at: row.occurred_at,
            recorded_at: row.recorded_at,
            run_id: row.run_id.clone(),
            turn_id: row.turn_id.clone(),
            attempt_id: row.attempt_id.clone(),
            call_id,
            entity_id: row.entity_id.clone(),
            message_id: row.message_id.clone(),
            tool_name,
            source_kind: row.source_kind.clone(),
            source_id: row.source_id.clone(),
            query_class: row.query_class.clone(),
            parent_id: row.parent_id.clone(),
            original_kind: row.original_kind.clone(),
            row_scope: None,
            row_key: None,
            is_anchor: false,
            payload_schema: "anywork.event/1".into(),
            payload_json,
        }));
    }

    // 5. Non-entity hidden events (run_started, usage_*, delivery, resources, input_consumed/discarded, etc.)
    let manifest: Vec<HistoryBodyManifestEntry> = owner_bodies
        .iter()
        .filter(|b| b.role != "canonical_metadata")
        .map(|b| b.manifest_entry(database_id))
        .collect();
    let payload_json = serde_json::to_string(&BusinessFactEnvelope {
        fact_type: row.kind.as_str().to_owned(),
        data: None,
        bodies: manifest,
    })?;

    Ok(Some(ConvertedV26Row {
        seq: row.seq,
        event_id: row.event_id.clone(),
        kind: row.kind.as_str().to_owned(),
        timeline_role: HistoryTimelineRole::Hidden,
        occurred_at: row.occurred_at,
        recorded_at: row.recorded_at,
        run_id: row.run_id.clone(),
        turn_id: row.turn_id.clone(),
        attempt_id: row.attempt_id.clone(),
        call_id: row.call_id.clone(),
        entity_id: row.entity_id.clone(),
        message_id: row.message_id.clone(),
        tool_name: row.tool_name.clone(),
        source_kind: row.source_kind.clone(),
        source_id: row.source_id.clone(),
        query_class: row.query_class.clone(),
        parent_id: row.parent_id.clone(),
        original_kind: row.original_kind.clone(),
        row_scope: None,
        row_key: None,
        is_anchor: false,
        payload_schema: "anywork.business/1".into(),
        payload_json,
    }))
}

fn entity_meta_from_v25(head: &HistoryEntityHeadV25) -> HistoryEventMeta {
    HistoryEventMeta {
        entity_id: head.entity_id.clone(),
        entity_kind: head.kind,
        delivery: head.delivery,
        state: head.state.clone(),
        started_at: head.started_at,
        finished_at: head.finished_at,
        text_channel: head.text_channel,
        single_visibility: head.single_visibility,
        presentation_contract: head.presentation_contract.clone(),
        source_order: None,
        content_present: if matches!(
            head.observation,
            HistoryObservationV25::UnavailableLegacy { .. }
        ) {
            Some(false)
        } else {
            head.content_present
        },
        wait: head.wait.clone(),
        tool: head.tool.clone(),
    }
}

struct CanonicalLiftInput<'a> {
    database_id: &'a str,
    row_event_id: &'a str,
    row_own_bodies: &'a [V25BodyMeta],
    payload_body_id: &'a str,
    payload_source_bodies: &'a [V25BodyMeta],
    observation: &'a HistoryObservationV25,
    meta: &'a HistoryEventMeta,
}

async fn load_and_lift_canonical_payload(
    db: &impl ConnectionTrait,
    input: CanonicalLiftInput<'_>,
) -> Result<Option<EventPayloadEnvelope>> {
    let CanonicalLiftInput {
        database_id,
        row_event_id,
        row_own_bodies,
        payload_body_id,
        payload_source_bodies,
        observation,
        meta,
    } = input;
    let Some(body_meta) = payload_source_bodies
        .iter()
        .find(|b| b.body_id == payload_body_id)
    else {
        return Ok(None);
    };
    if body_meta.role != "canonical_payload"
        || body_meta.byte_length > pl_core::chat::MAX_READ_BYTES as u64
    {
        return Ok(None);
    }
    let raw = read_v25_body_bytes(db, body_meta).await?;
    let Ok(json) = serde_json::from_slice::<serde_json::Value>(&raw) else {
        return Ok(None);
    };
    let Some(obj) = json.as_object() else {
        return Ok(None);
    };
    let contract = obj.get("contract").and_then(serde_json::Value::as_str);
    if contract != Some("anywork.chat/1") {
        return Ok(None);
    }
    let item_type = obj
        .get("type")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("raw")
        .to_owned();
    let data = obj
        .get("data")
        .cloned()
        .unwrap_or_else(|| serde_json::json!({}));
    let source_order = obj.get("sourceOrder").and_then(serde_json::Value::as_u64);
    let turn_id = obj
        .get("turnId")
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned);
    let captured_at = obj
        .get("capturedAt")
        .and_then(serde_json::Value::as_i64)
        .or(match observation {
            HistoryObservationV25::Boundary { captured_at }
            | HistoryObservationV25::UnavailableLegacy { captured_at } => *captured_at,
            HistoryObservationV25::Original => None,
        });

    let mut lifted_meta = meta.clone();
    lifted_meta.source_order = source_order;

    let mut next_ordinal = row_own_bodies
        .iter()
        .map(|b| b.ordinal)
        .max()
        .map_or(0, |max_ord| max_ord + 1);
    let mut inline_used: usize = 0;
    let mut manifest = Vec::new();
    let mut listed_keys = BTreeSet::new();
    let mut listed_body_ids = BTreeSet::new();

    if let Some(entries) = obj.get("bodies").and_then(serde_json::Value::as_array) {
        for item in entries {
            let Some(item_obj) = item.as_object() else {
                continue;
            };
            let Some(key) = item_obj.get("key").and_then(serde_json::Value::as_str) else {
                continue;
            };
            let byte_length = item_obj
                .get("byteLength")
                .and_then(serde_json::Value::as_u64)
                .unwrap_or(0);
            listed_keys.insert(key.to_owned());

            let mut reference: Option<HistoryEventBodyRef> = item_obj
                .get("reference")
                .and_then(|v| serde_json::from_value(v.clone()).ok());
            let matching_meta = reference
                .as_ref()
                .and_then(|r| {
                    payload_source_bodies
                        .iter()
                        .find(|b| b.body_id == r.body_id)
                })
                .or_else(|| payload_source_bodies.iter().find(|b| b.body_key == key));
            let role = matching_meta
                .map(|m| m.role.clone())
                .unwrap_or_else(|| default_role_for_key(key).to_owned());
            let media_type = matching_meta.and_then(|m| m.media_type.clone());

            let inline_text = item_obj
                .get("inlineText")
                .and_then(serde_json::Value::as_str)
                .map(str::to_owned);

            let resolved_inline = if let Some(text) = inline_text {
                inline_used = inline_used.saturating_add(text.len());
                Some(text)
            } else if let Some(inline_arr) =
                item_obj.get("inline").and_then(serde_json::Value::as_array)
            {
                let raw_bytes: Vec<u8> = inline_arr
                    .iter()
                    .filter_map(|v| v.as_u64().and_then(|n| u8::try_from(n).ok()))
                    .collect();
                let fits_inline = role != HistoryBodyRole::Attachment.as_str()
                    && raw_bytes.len() <= INLINE_BODY_MAX_BYTES
                    && inline_used + raw_bytes.len() <= INLINE_EVENT_MAX_BYTES;
                if fits_inline && let Ok(text) = std::str::from_utf8(&raw_bytes) {
                    inline_used += raw_bytes.len();
                    Some(text.to_owned())
                } else if reference.is_none() {
                    let body_id = insert_migrated_inline_blob(
                        db,
                        row_event_id,
                        next_ordinal,
                        key,
                        &role,
                        media_type.as_deref(),
                        &raw_bytes,
                    )
                    .await?;
                    next_ordinal += 1;
                    reference = Some(HistoryEventBodyRef {
                        database_id: database_id.to_owned(),
                        owner_event_id: row_event_id.to_owned(),
                        body_key: key.to_owned(),
                        body_id,
                        byte_start: 0,
                        byte_length: raw_bytes.len() as u64,
                    });
                    None
                } else {
                    None
                }
            } else {
                None
            };
            if resolved_inline.is_none() && reference.is_none() {
                reference = matching_meta.and_then(|m| m.manifest_entry(database_id).reference);
            }
            if let Some(r) = &reference {
                listed_body_ids.insert(r.body_id.clone());
            }
            if let Some(m) = matching_meta {
                listed_body_ids.insert(m.body_id.clone());
            }

            manifest.push(HistoryBodyManifestEntry {
                key: key.to_owned(),
                role,
                byte_length,
                media_type,
                inline_text: resolved_inline,
                reference,
            });
        }
    }

    for extra in payload_source_bodies.iter().chain(row_own_bodies.iter()) {
        if extra.role != "canonical_payload"
            && extra.role != "canonical_metadata"
            && extra.role != "legacy_metadata"
            && !listed_keys.contains(&extra.body_key)
            && listed_body_ids.insert(extra.body_id.clone())
        {
            manifest.push(extra.manifest_entry(database_id));
        }
    }

    Ok(Some(EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type,
        meta: lifted_meta,
        data,
        bodies: manifest,
        source_order,
        turn_id,
        captured_at,
    }))
}

fn synthesize_envelope_from_head(
    database_id: &str,
    payload_source_bodies: &[V25BodyMeta],
    row_own_bodies: &[V25BodyMeta],
    head: &HistoryEntityHeadV25,
    meta: &HistoryEventMeta,
    turn_id: Option<&str>,
) -> EventPayloadEnvelope {
    let mut seen_body_ids = BTreeSet::new();
    let manifest: Vec<HistoryBodyManifestEntry> = payload_source_bodies
        .iter()
        .chain(row_own_bodies.iter())
        .filter(|b| {
            b.role != "canonical_payload"
                && b.role != "canonical_metadata"
                && b.role != "legacy_metadata"
                && seen_body_ids.insert(b.body_id.clone())
        })
        .map(|b| b.manifest_entry(database_id))
        .collect();

    let (item_type, data) = if head.kind == HistoryEntityKind::ToolCall
        && let Some(tool) = &head.tool
    {
        let state = match &head.state {
            HistoryEntityState::KnownActive { status } => match status {
                crate::ChatActiveStatus::Waiting => serde_json::json!({
                    "kind": "waitingApproval",
                    "startedAt": head.started_at.map(|ms| ms / 1000)
                }),
                _ if head.entity_id.ends_with(":background-started")
                    || head.entity_id.starts_with("tool-background:") =>
                {
                    serde_json::json!({
                        "kind": "backgroundStarted",
                        "startedAt": head.started_at.map(|ms| ms / 1000)
                    })
                }
                _ => serde_json::json!({
                    "kind": "running",
                    "startedAt": head.started_at.map(|ms| ms / 1000)
                }),
            },
            HistoryEntityState::KnownTerminal { outcome } => serde_json::json!({
                "kind": match outcome {
                    crate::ChatTerminalOutcome::Completed => "succeeded",
                    crate::ChatTerminalOutcome::Cancelled => "cancelled",
                    crate::ChatTerminalOutcome::Failed => "failed",
                    crate::ChatTerminalOutcome::Transferred => "backgroundStarted",
                },
                "startedAt": head.started_at.map(|ms| ms / 1000),
                "finishedAt": head.finished_at.map(|ms| ms / 1000),
            }),
            HistoryEntityState::Unknown => serde_json::json!({ "kind": "unknown" }),
        };
        (
            "tool".to_owned(),
            serde_json::json!({
                "invocation": {
                    "toolCallId": tool.call_id,
                    "callId": tool.call_id,
                    "name": tool.name,
                    "presentationContract": head.presentation_contract,
                },
                "state": state,
                "userInput": serde_json::Value::Null,
                "wait": serde_json::Value::Null,
            }),
        )
    } else {
        let kind_name = match head.kind {
            HistoryEntityKind::Input | HistoryEntityKind::Text => "text",
            HistoryEntityKind::Reasoning => "thinking",
            HistoryEntityKind::Plan => "plan",
            HistoryEntityKind::TurnReceipt => "turn",
            HistoryEntityKind::Agent => "agent",
            HistoryEntityKind::FileChange => "file",
            HistoryEntityKind::Skill => "skill",
            HistoryEntityKind::Compaction => "contextCompaction",
            _ => "raw",
        };
        let channel = match head.text_channel {
            Some(crate::ThreadTextChannel::User) => "user",
            Some(crate::ThreadTextChannel::ParentAgent) => "parentAgent",
            Some(crate::ThreadTextChannel::Commentary) => "commentary",
            Some(crate::ThreadTextChannel::Final) | None => "final",
        };
        (
            kind_name.to_owned(),
            serde_json::json!({
                "channel": channel,
                "attachments": [],
                "legacyUnavailable": matches!(head.observation, HistoryObservationV25::UnavailableLegacy { .. }),
            }),
        )
    };

    EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type,
        meta: meta.clone(),
        data,
        bodies: manifest,
        source_order: None,
        turn_id: turn_id.map(str::to_owned),
        captured_at: match head.observation {
            HistoryObservationV25::Boundary { captured_at }
            | HistoryObservationV25::UnavailableLegacy { captured_at } => captured_at,
            HistoryObservationV25::Original => None,
        },
    }
}

fn map_entity_kind(
    row: &V25EventRow,
    head: &HistoryEntityHeadV25,
    envelope: &EventPayloadEnvelope,
) -> HistoryEventKind {
    match &head.observation {
        HistoryObservationV25::Boundary { .. } => {
            return HistoryEventKind::Other("boundary_observed".into());
        }
        HistoryObservationV25::UnavailableLegacy { .. } => {
            return HistoryEventKind::LegacyObserved;
        }
        HistoryObservationV25::Original => {}
    }
    if row.kind == HistoryEventKindV25::BoundaryObserved {
        return HistoryEventKind::Other("boundary_observed".into());
    }
    if row.row_scope.is_none() && row.kind == HistoryEventKindV25::LegacyObserved {
        return HistoryEventKind::LegacyObserved;
    }
    if row.kind == HistoryEventKindV25::InputAccepted || head.kind == HistoryEntityKind::Input {
        return HistoryEventKind::InputAccepted;
    }
    if head.kind == HistoryEntityKind::ToolCall {
        let state_kind = envelope
            .data
            .get("state")
            .and_then(|v| v.get("kind"))
            .and_then(serde_json::Value::as_str);
        return match &head.state {
            HistoryEntityState::KnownTerminal {
                outcome: crate::ChatTerminalOutcome::Transferred,
            } => HistoryEventKind::ToolBackgrounded,
            HistoryEntityState::KnownTerminal { .. } => HistoryEventKind::ToolCompleted,
            HistoryEntityState::KnownActive { status } => {
                if state_kind == Some("backgroundStarted")
                    || head.entity_id.ends_with(":background-started")
                    || head.entity_id.starts_with("tool-background:")
                {
                    HistoryEventKind::ToolBackgrounded
                } else if *status == crate::ChatActiveStatus::Waiting
                    || state_kind == Some("waitingApproval")
                {
                    HistoryEventKind::ToolWaitingApproval
                } else {
                    HistoryEventKind::ToolCalled
                }
            }
            HistoryEntityState::Unknown => HistoryEventKind::ItemRecorded,
        };
    }
    match head.kind {
        HistoryEntityKind::Text => match head.state {
            HistoryEntityState::KnownTerminal { .. } => HistoryEventKind::TextCompleted,
            _ => HistoryEventKind::ItemRecorded,
        },
        HistoryEntityKind::Reasoning => match head.state {
            HistoryEntityState::KnownTerminal { .. } => HistoryEventKind::ReasoningCompleted,
            _ => HistoryEventKind::ReasoningStarted,
        },
        HistoryEntityKind::Compaction => match head.state {
            HistoryEntityState::KnownTerminal { .. } => HistoryEventKind::CompactionCompleted,
            _ => HistoryEventKind::CompactionStarted,
        },
        HistoryEntityKind::Agent => match head.state {
            HistoryEntityState::KnownTerminal { .. } => HistoryEventKind::AgentCompleted,
            _ => HistoryEventKind::AgentSpawned,
        },
        HistoryEntityKind::Plan => HistoryEventKind::PlanResolved,
        HistoryEntityKind::TurnReceipt => HistoryEventKind::TurnReceiptRecorded,
        _ => {
            if matches!(head.source, HistorySource::InboxMessage { .. }) {
                HistoryEventKind::InboxMessageReceived
            } else {
                HistoryEventKind::ItemRecorded
            }
        }
    }
}

fn default_role_for_key(key: &str) -> &'static str {
    match key {
        "body" => "body",
        k if k.starts_with("part.outputText.") || k.starts_with("part.reasoningText.") => "body",
        k if k.starts_with("part.summaryText.") => "reasoning_summary",
        "tool.arguments" => "tool_arguments",
        "tool.result" => "tool_output",
        "tool.output-artifacts" => "attachment",
        _ => "producer_detail",
    }
}

async fn read_v25_body_bytes(db: &impl ConnectionTrait, body: &V25BodyMeta) -> Result<Vec<u8>> {
    let chunks = body.byte_length.div_ceil(BODY_CHUNK_BYTES as u64);
    let mut bytes = Vec::with_capacity(body.byte_length as usize);
    for chunk_no in 0..chunks {
        let row = db
            .query_one_raw(statement(
                "SELECT data FROM history_body_chunks WHERE body_id=? AND chunk_no=?",
                vec![body.body_id.clone().into(), number(chunk_no)?.into()],
            ))
            .await?
            .ok_or_else(|| {
                HistoryError::Integrity(format!(
                    "v25 body {} missing chunk {chunk_no}",
                    body.body_id
                ))
            })?;
        let chunk: Vec<u8> = row.try_get("", "data")?;
        bytes.extend_from_slice(&chunk);
    }
    if bytes.len() as u64 != body.byte_length {
        return Err(HistoryError::Integrity(format!(
            "v25 body {} length mismatch",
            body.body_id
        )));
    }
    Ok(bytes)
}

async fn insert_migrated_inline_blob(
    db: &impl ConnectionTrait,
    owner_event_id: &str,
    ordinal: u64,
    body_key: &str,
    role: &str,
    media_type: Option<&str>,
    bytes: &[u8],
) -> Result<String> {
    let body_id = uuid::Uuid::new_v4().to_string();
    let digest = Sha256::digest(bytes).to_vec();
    db.execute_raw(statement(
        "INSERT INTO history_bodies(body_id,owner_event_id,ordinal,body_key,role,byte_length,media_type,digest) \
         VALUES(?,?,?,?,?,?,?,?)",
        vec![
            body_id.clone().into(),
            owner_event_id.to_owned().into(),
            number(ordinal)?.into(),
            body_key.to_owned().into(),
            role.to_owned().into(),
            number(bytes.len() as u64)?.into(),
            media_type.map(str::to_owned).into(),
            digest.into(),
        ],
    ))
    .await?;
    for (chunk_no, chunk) in bytes.chunks(BODY_CHUNK_BYTES).enumerate() {
        db.execute_raw(statement(
            "INSERT INTO history_body_chunks(body_id,chunk_no,data) VALUES(?,?,?)",
            vec![
                body_id.clone().into(),
                number(chunk_no as u64)?.into(),
                chunk.to_vec().into(),
            ],
        ))
        .await?;
    }
    Ok(body_id)
}

fn index_current_manifest(
    row: &mut ConvertedV26Row,
    database_id: &str,
    owner_bodies: Option<&Vec<V25BodyMeta>>,
) -> Result<()> {
    let accounting = row.row_scope.as_deref() == Some("accounting");
    let stored: Vec<super::schema26_manifest::StoredBody> = owner_bodies
        .into_iter()
        .flatten()
        .filter(|body| {
            body.body_key == super::schema26_manifest::TOOL_TASK_KEY
                || (accounting && body.body_key == super::schema26_manifest::LEGACY_USAGE_KEY)
        })
        .map(|body| super::schema26_manifest::StoredBody {
            body_id: body.body_id.clone(),
            body_key: body.body_key.clone(),
            role: body.role.clone(),
            byte_length: body.byte_length,
            media_type: body.media_type.clone(),
        })
        .collect();
    if !accounting && stored.is_empty() {
        return Ok(());
    }
    if let Some(payload) = super::schema26_manifest::rewrite_payload(
        &row.payload_json,
        accounting,
        database_id,
        &row.event_id,
        &stored,
    )? {
        row.payload_json = payload;
    }
    Ok(())
}

async fn insert_v26_row(db: &impl ConnectionTrait, row: &ConvertedV26Row) -> Result<()> {
    let (source_kind, source_id) = match (&row.source_kind, &row.source_id) {
        (Some(k), Some(id)) => (Some(k.clone()), Some(id.clone())),
        _ => (None, None),
    };
    let (query_class, parent_id, original_kind) = match (&row.query_class, &row.original_kind) {
        (Some(qc), Some(ok)) => (Some(qc.clone()), row.parent_id.clone(), Some(ok.clone())),
        _ => (None, None, None),
    };
    db.execute_raw(statement(
        "INSERT INTO history_events_v26(\
            seq,event_id,kind,timeline_role,occurred_at,recorded_at,\
            run_id,turn_id,attempt_id,call_id,entity_id,message_id,tool_name,\
            source_kind,source_id,query_class,parent_id,original_kind,\
            row_scope,row_key,is_anchor,payload_schema,payload_json\
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        vec![
            number(row.seq)?.into(),
            row.event_id.clone().into(),
            row.kind.clone().into(),
            row.timeline_role.as_str().to_owned().into(),
            row.occurred_at.into(),
            row.recorded_at.into(),
            row.run_id.clone().into(),
            row.turn_id.clone().into(),
            row.attempt_id.clone().into(),
            row.call_id.clone().into(),
            row.entity_id.clone().into(),
            row.message_id.clone().into(),
            row.tool_name.clone().into(),
            source_kind.into(),
            source_id.into(),
            query_class.into(),
            parent_id.into(),
            original_kind.into(),
            row.row_scope.clone().into(),
            row.row_key.clone().into(),
            i64::from(row.is_anchor).into(),
            row.payload_schema.clone().into(),
            row.payload_json.clone().into(),
        ],
    ))
    .await?;
    Ok(())
}
