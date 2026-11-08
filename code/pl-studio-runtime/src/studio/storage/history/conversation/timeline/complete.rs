//! Completion-only derived rows and indexed reconstruction of unfinished frontiers.
use super::*;
use crate::studio::thread_projection::{
    TimelineProjection,
    timeline::{Frontier, TimelineInput, TimelineUpdate},
};

pub(in crate::studio::storage::history) const CREATE: &str = "
CREATE TABLE timeline_items (
 item_id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL, position INTEGER NOT NULL UNIQUE,
 commit_seq INTEGER NOT NULL, metadata BLOB NOT NULL, projection_version INTEGER NOT NULL
);
CREATE INDEX timeline_items_by_commit ON timeline_items(commit_seq,position);
CREATE TABLE timeline_item_members (
 item_id TEXT NOT NULL, member_order INTEGER NOT NULL, member_id TEXT NOT NULL,
 completion_item_id TEXT, admitted_effect INTEGER NOT NULL, updated_effect INTEGER NOT NULL,
 payload_bytes INTEGER, metadata BLOB NOT NULL,
 PRIMARY KEY(item_id,member_order), UNIQUE(item_id,member_id)
) WITHOUT ROWID;
CREATE INDEX timeline_members_by_member ON timeline_item_members(member_id);
CREATE INDEX conversation_facts_by_source_position
 ON conversation_atom_facts(json_extract(metadata,'$.source'),effect_seq,suborder,fact_order,atom_id,phase);
CREATE INDEX conversation_legacy_ends_by_source
 ON conversation_atom_facts(phase,CAST(metadata AS TEXT),effect_seq,suborder);
";

pub(in crate::studio::storage::history) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    for sql in [
        "SELECT effect_seq,suborder,atom_id,phase,fact_order,metadata FROM conversation_atom_facts LIMIT 0",
        "SELECT item_id,kind,position,commit_seq,metadata,projection_version FROM timeline_items LIMIT 0",
        "SELECT item_id,member_order,member_id,completion_item_id,admitted_effect,updated_effect,payload_bytes,metadata FROM timeline_item_members LIMIT 0",
    ] {
        db.query_all_raw(statement(sql, vec![])).await?;
    }
    let head = read_state(db)
        .await?
        .context("completed timeline has no recovery cut")?;
    let _: Vec<Frontier> = serde_json::from_slice(&head.recovery)
        .context("completed timeline has an invalid recovery cut")?;
    Ok(())
}

async fn save_completed(
    db: &impl ConnectionTrait,
    database: &str,
    update: &TimelineUpdate,
    committed: &[PreparedTimelineItem],
    effect: u64,
) -> Result<()> {
    for member in update.completed_members() {
        ensure!(
            committed
                .iter()
                .any(|entry| entry.item.id == member.item_id)
                || update
                    .updates()
                    .iter()
                    .any(|item| item.id == member.item_id),
            "final member has no completed group"
        );
        ensure!(
            matches!(member.atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
            "active member cannot enter a completed group"
        );
        let bytes = serde_json::to_vec(&lightweight(&member.atom))?;
        let canonical = db
            .query_one_raw(statement(
                "SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase='terminal'",
                vec![member.atom.id.clone().into()],
            ))
            .await?
            .context("completed member has no reliable terminal fact")?;
        ensure!(
            canonical.try_get::<Vec<u8>>("", "metadata")? == bytes,
            "final member differs from its reliable terminal"
        );
        if member.atom.completion_item_id.is_none() {
            ensure!(
                matches!(
                    member.atom.kind,
                    ChatAtomKind::Text | ChatAtomKind::Reasoning
                ) && matches!(
                    member.atom.lifecycle,
                    ChatAtomLifecycle::Terminal {
                        started: Some(_),
                        ended: Some(_),
                        outcome: pl_protocol::ChatTerminalOutcome::Cancelled
                    }
                ) && member.atom.attempt_id.is_some()
                    && member.atom.completion_seq.is_none()
                    && member.atom.contents.is_empty()
                    && member.atom.content_present.is_none()
                    && member.payload_bytes.is_none(),
                "member without a completion is not a proven model interruption"
            );
        } else {
            let row = db
                .query_one_raw(statement(
                    "SELECT seq,length(payload) AS bytes FROM conversation_items WHERE item_id=?",
                    vec![member.atom.completion_item_id.clone().into()],
                ))
                .await?
                .context("final member completion is missing")?;
            ensure!(
                Some(u64::try_from(row.try_get::<i64>("", "seq")?)?) == member.atom.completion_seq
                    && Some(u64::try_from(row.try_get::<i64>("", "bytes")?)?)
                        == member.payload_bytes,
                "final member completion reference differs"
            );
        }
        let start = db.query_one_raw(statement(
            "SELECT effect_seq FROM conversation_atom_facts WHERE atom_id=? AND phase IN ('start','legacyAdmission')
             ORDER BY effect_seq,suborder LIMIT 1", vec![member.atom.id.clone().into()],
        )).await?;
        let ended = match member.atom.lifecycle {
            ChatAtomLifecycle::Terminal { ended, .. } => ended.map_or(effect, |at| at.effect_seq),
            _ => unreachable!("terminal checked above"),
        };
        let admitted = start
            .map(|row| row.try_get::<i64>("", "effect_seq"))
            .transpose()?
            .unwrap_or(integer(ended)?);
        let written = db.execute_raw(statement(
            "INSERT INTO timeline_item_members(item_id,member_order,member_id,completion_item_id,admitted_effect,updated_effect,payload_bytes,metadata)
             VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(item_id,member_order) DO UPDATE SET metadata=excluded.metadata
             WHERE timeline_item_members.member_id=excluded.member_id
               AND timeline_item_members.completion_item_id IS excluded.completion_item_id
               AND timeline_item_members.payload_bytes IS excluded.payload_bytes
               AND timeline_item_members.metadata=excluded.metadata",
            vec![member.item_id.clone().into(), integer(member.member_order)?.into(),
                member.atom.id.clone().into(), member.atom.completion_item_id.clone().into(),
                admitted.into(), integer(ended)?.into(),
                member.payload_bytes.map(integer).transpose()?.into(), bytes.into()],
        )).await?;
        ensure!(
            written.rows_affected() == 1,
            "immutable group member conflict"
        );
    }
    // Qualify the old tail before inserting any visible separator from this delta.
    for item in update.updates() {
        if !committed.iter().any(|entry| entry.item.id == item.id) {
            let previous = db
                .query_one_raw(statement(
                    "SELECT metadata FROM timeline_items WHERE item_id=?
                 AND position=(SELECT MAX(position) FROM timeline_items)",
                    vec![item.id.clone().into()],
                ))
                .await?
                .context("background update is not the committed history tail")?;
            let previous: Vec<u8> = previous.try_get("", "metadata")?;
            let item = deferred_item(database, item);
            validate_background_extension(db, serde_json::from_slice(&previous)?, &item).await?;
            let written = db
                .execute_raw(statement(
                    "UPDATE timeline_items SET metadata=? WHERE item_id=? AND metadata=?",
                    vec![
                        serde_json::to_vec(&item)?.into(),
                        item.id.into(),
                        previous.into(),
                    ],
                ))
                .await?;
            ensure!(
                written.rows_affected() == 1,
                "background tail update conflict"
            );
        }
    }
    for entry in committed {
        let item = deferred_item(database, &entry.item);
        ensure!(
            item.position.is_some() && item.admission_closed,
            "only completed display items may be persisted"
        );
        validate_item(&item, database, update.generation())?;
        let bytes = serde_json::to_vec(&item)?;
        let written = db.execute_raw(statement(
            "INSERT INTO timeline_items(item_id,kind,position,commit_seq,metadata,projection_version)
             VALUES(?,?,?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET metadata=excluded.metadata
             WHERE timeline_items.kind=excluded.kind AND timeline_items.position=excluded.position
               AND timeline_items.metadata=excluded.metadata AND timeline_items.projection_version=excluded.projection_version
               AND timeline_items.commit_seq=excluded.commit_seq",
            vec![item.id.into(), item.kind.as_str().into(), item.position.map(integer).transpose()?.into(),
                integer(effect)?.into(), bytes.into(),
                i64::from(TIMELINE_PROJECTION_VERSION).into()],
        )).await?;
        ensure!(
            written.rows_affected() == 1,
            "immutable completed timeline conflict"
        );
    }
    Ok(())
}

pub(in crate::studio::storage::history) async fn apply(
    db: &impl ConnectionTrait,
    database: &str,
    current: &PreparedCurrent,
    head: &mut ProjectionState,
) -> Result<()> {
    let update = &current.timeline_update;
    if update.generation().is_empty() {
        return validate_unqualified(current);
    }
    ensure!(
        head.generation == update.generation(),
        "retired timeline generation cannot write"
    );
    let mut next = head.next_position;
    for entry in current.timeline.iter() {
        ensure!(
            entry.item.position == Some(next),
            "completed timeline prefix is not contiguous"
        );
        next = next.checked_add(1).context("timeline order overflow")?;
    }
    ensure!(
        next == update.next_position(),
        "completed timeline cut changed order"
    );
    for atom in update.facts() {
        save_fact(db, atom, current.projection().source_effect_seq).await?;
    }
    save_completed(
        db,
        database,
        update,
        &current.timeline,
        current.projection().source_effect_seq,
    )
    .await?;
    head.next_position = next;
    head.source_effect_seq = current.projection().source_effect_seq;
    Ok(())
}

pub(in crate::studio::storage::history) async fn save_head(
    db: &impl ConnectionTrait,
    update: &TimelineUpdate,
    effect: u64,
) -> Result<()> {
    if update.generation().is_empty() {
        return Ok(());
    }
    let _: Vec<Frontier> = serde_json::from_slice(update.frontier())?;
    db.execute_raw(statement(
        "UPDATE timeline_projection_state SET next_position=?,source_effect_seq=?,recovery=? WHERE singleton_id=1 AND projection_generation=?",
        vec![integer(update.next_position())?.into(), integer(effect)?.into(),
            update.frontier().to_vec().into(), update.generation().to_owned().into()],
    )).await?;
    Ok(())
}

/// Only the indexed source tails named by the durable cut are folded on ordinary reopen.
pub(in crate::studio::storage::history) async fn restore(
    db: &impl ConnectionTrait,
    database: &str,
    head: &ProjectionState,
) -> Result<TimelineProjection> {
    let cuts: Vec<Frontier> = serde_json::from_slice(&head.recovery)?;
    let mut projection =
        TimelineProjection::new(database.into(), head.generation.clone(), head.next_position);
    // The ordering of independent sources is selected by the same canonical input order.
    // The source-position index supplies bounded pages at the saved cut.
    replay(
        db,
        database,
        &mut projection,
        Some(&cuts),
        head.source_effect_seq,
        false,
    )
    .await?;
    if let Some(row) = db
        .query_one_raw(statement(
            "SELECT metadata FROM timeline_items ORDER BY position DESC LIMIT 1",
            vec![],
        ))
        .await?
    {
        let item: TimelineItem = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        if item.kind == TimelineItemKind::WorkGroup
            && matches!(item.source, ChatSourceId::BackgroundResult { .. })
        {
            projection.restore_background_tail(item)?;
        }
    }
    Ok(projection)
}

pub(in crate::studio::storage::history) async fn open_member_rows(
    db: &impl ConnectionTrait,
    reference: &TimelineMembersRef,
    before: Option<u64>,
    ceiling: u64,
    effect: u64,
    limit: usize,
) -> Result<Option<Vec<(u64, pl_protocol::ChatEntry)>>> {
    let head = read_state(db)
        .await?
        .context("open member read has no recovery cut")?;
    ensure!(
        head.generation == reference.projection_generation
            && reference.projection_version == TIMELINE_PROJECTION_VERSION,
        pl_core::chat::ChatError::StaleContent
    );
    if db
        .query_one_raw(statement(
            "SELECT 1 FROM timeline_items WHERE item_id=?",
            vec![reference.item_id.clone().into()],
        ))
        .await?
        .is_some()
    {
        return Ok(None);
    }
    ensure!(
        head.source_effect_seq <= effect,
        pl_core::chat::ChatError::StaleContent
    );
    let owner = restore(db, &reference.database_id, &head).await?;
    let (_, members) = owner
        .member_page(
            &reference.item_id,
            before.unwrap_or(ceiling).min(ceiling),
            limit,
        )
        .context(pl_core::chat::ChatError::StaleContent)?;
    Ok(Some(
        members
            .into_iter()
            .map(|member| {
                let mut atom = member.atom;
                if let (Some(id), Some(bytes)) = (&atom.completion_item_id, member.payload_bytes) {
                    atom.payload = Some(PayloadData::Deferred {
                        reference: ContentRef {
                            database_id: reference.database_id.clone(),
                            target: ContentTarget::ItemPayload {
                                item_id: id.clone(),
                            },
                        },
                        byte_length: bytes,
                    });
                }
                (
                    member.member_order,
                    pl_protocol::ChatEntry::Atom(Box::new(atom)),
                )
            })
            .collect(),
    ))
}

pub(in crate::studio::storage::history) async fn rebuild(
    db: &impl ConnectionTrait,
    database: &str,
    generation: String,
    effect: u64,
) -> Result<()> {
    let mut projection = TimelineProjection::new(database.into(), generation.clone(), 0);
    db.execute_raw(statement(
        "UPDATE timeline_projection_state SET projection_generation=?,next_position=0,source_effect_seq=?,recovery=? WHERE singleton_id=1",
        vec![generation.into(),integer(effect)?.into(),b"[]".to_vec().into()],
    )).await?;
    replay(db, database, &mut projection, None, effect, true).await?;
    save_head(db, &projection.take_update()?, effect).await
}

async fn replay(
    db: &impl ConnectionTrait,
    database: &str,
    projection: &mut TimelineProjection,
    cuts: Option<&[Frontier]>,
    effect: u64,
    persist: bool,
) -> Result<()> {
    let cuts_json = cuts.map(serde_json::to_string).transpose()?;
    let mut cursor = (-1i64, -1i64, -1i64, -1i64, String::new(), String::new());
    loop {
        let rows = db.query_all_raw(statement(
            "WITH selected AS (
               SELECT effect_seq,suborder,atom_id,phase,fact_order,metadata FROM conversation_atom_facts
                WHERE ? IS NULL
               UNION ALL
               SELECT f.effect_seq,f.suborder,f.atom_id,f.phase,f.fact_order,f.metadata
                FROM json_each(?) c JOIN conversation_atom_facts f
                  ON json_extract(f.metadata,'$.source')=json_extract(c.value,'$.source')
                 AND (f.effect_seq,f.suborder)>=(json_extract(c.value,'$.effect'),json_extract(c.value,'$.suborder'))
                 AND (json_extract(c.value,'$.source_order') IS NULL
                      OR COALESCE(json_extract(f.metadata,'$.sourceOrder'),json_extract(f.metadata,'$.completionSeq'),0)>=json_extract(c.value,'$.source_order'))
                WHERE NOT EXISTS(SELECT 1 FROM timeline_items i WHERE i.item_id='status:'||f.atom_id)
               UNION ALL
               SELECT f.effect_seq,f.suborder,f.atom_id,f.phase,f.fact_order,f.metadata
                FROM json_each(?) c JOIN conversation_atom_facts f
                  ON f.phase='legacySourceEnd' AND CAST(f.metadata AS TEXT)=json_extract(c.value,'$.source')
                WHERE ? IS NOT NULL
             ), selected_sources AS (
               SELECT s.* FROM conversation_sources s WHERE ? IS NULL
               UNION ALL SELECT s.* FROM json_each(?) c JOIN conversation_sources s
                 ON s.source_key=json_extract(c.value,'$.source') WHERE ? IS NOT NULL
             ), inputs AS (
               SELECT effect_seq AS effect,suborder AS sub,fact_order AS ordering,
                 CASE WHEN phase='legacySourceEnd' THEN 9223372036854775807 WHEN effect_seq=0
                   THEN COALESCE(json_extract(metadata,'$.sourceOrder'),json_extract(metadata,'$.completionSeq'),0)
                   ELSE COALESCE(json_extract(metadata,'$.completionSeq'),0) END AS completion_order,
                 atom_id AS identity,phase,metadata,
                 CASE WHEN phase='legacySourceEnd' THEN CAST(metadata AS TEXT) END AS source_key FROM selected
               UNION ALL SELECT COALESCE(ended_effect,ended_observed),COALESCE(ended_suborder,4294967295),
                 9223372036854775807,0,source_key,'source',NULL,source_key FROM selected_sources s
                 WHERE ended_observed IS NOT NULL
                 AND NOT EXISTS(SELECT 1 FROM conversation_atom_facts f WHERE f.atom_id='legacy-source:'||s.source_key AND f.phase='legacySourceEnd')
             ) SELECT * FROM inputs WHERE effect<=? AND (effect,sub,ordering,completion_order,identity,phase)>(?,?,?,?,?,?)
               ORDER BY effect,sub,ordering,completion_order,identity,phase LIMIT 128",
            vec![cuts_json.clone().into(),cuts_json.clone().into(),cuts_json.clone().into(),cuts_json.clone().into(),cuts_json.clone().into(),cuts_json.clone().into(),cuts_json.clone().into(),
                integer(effect)?.into(),cursor.0.into(),cursor.1.into(),cursor.2.into(),cursor.3.into(),cursor.4.clone().into(),cursor.5.clone().into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            cursor = (
                row.try_get("", "effect")?,
                row.try_get("", "sub")?,
                row.try_get("", "ordering")?,
                row.try_get("", "completion_order")?,
                row.try_get("", "identity")?,
                row.try_get("", "phase")?,
            );
            if let Some(source) = row.try_get::<Option<String>>("", "source_key")? {
                projection.end_source(&serde_json::from_str(&source)?);
            } else {
                let mut atom: ChatAtom =
                    serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
                if cursor.5 == "legacyAdmission" {
                    projection.admit_legacy_header_retained(&atom)?;
                } else {
                    let payload = if let Some(id) = &atom.completion_item_id {
                        let row = db.query_one_raw(statement("SELECT length(payload) AS bytes FROM conversation_items WHERE item_id=?",vec![id.clone().into()]))
                            .await?.context("replay completion reference is missing")?;
                        Some(PayloadData::Deferred {
                            reference: ContentRef {
                                database_id: database.into(),
                                target: ContentTarget::ItemPayload {
                                    item_id: id.clone(),
                                },
                            },
                            byte_length: u64::try_from(row.try_get::<i64>("", "bytes")?)?,
                        })
                    } else {
                        None
                    };
                    let summary = if atom.completion_item_id.is_some() {
                        rebuild_thinking_summary(db, &atom).await?
                    } else {
                        None
                    };
                    atom.payload = None;
                    if matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }) {
                        atom.contents.clear();
                    }
                    projection.apply_input(TimelineInput::Atom {
                        atom: Box::new(atom),
                        payload,
                        thinking_summary: summary,
                    })?;
                }
            }
            projection.commit_ready()?;
            let committed = projection
                .take_committed()
                .into_iter()
                .map(|item| PreparedTimelineItem { item })
                .collect::<Vec<_>>();
            let update = projection.take_changes();
            if persist {
                save_completed(db, database, &update, &committed, u64::try_from(cursor.0)?).await?;
            } else {
                ensure!(
                    committed.is_empty(),
                    "recovery cut unexpectedly replays completed items"
                );
            }
            projection.accept_members(&update);
        }
        projection.check_recovery_budget()?;
    }
    Ok(())
}
