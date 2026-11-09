//! Schema 17 -> 18. Only immutable read indexes are added; original bytes never change.
use super::*;
use crate::studio::runtime::chat_item::native_read_hint_v1;
use pl_core::chat::{ChatReadHint, ChatRunPosition, ChatRunSeed};
use pl_protocol::{ChatAtom, ChatAtomLifecycle};

mod summary_coverage;
#[cfg(test)]
mod tests;

pub(super) struct ImmutableCompletionRuns;
impl MigrationName for ImmutableCompletionRuns {
    fn name(&self) -> &str {
        IMMUTABLE_COMPLETION_RUNS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ImmutableCompletionRuns {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        upgrade(manager.get_connection()).await.map_err(conversion)
    }
}

pub(in crate::studio::storage::history) const CREATE: &str = "
ALTER TABLE conversation_items ADD COLUMN display_run_start INTEGER;
ALTER TABLE conversation_items ADD COLUMN display_run_ordinal INTEGER CHECK (
 (display_run_start IS NULL AND display_run_ordinal IS NULL) OR
 (display_run_start IS NOT NULL AND display_run_ordinal IS NOT NULL
  AND display_run_start > 0 AND display_run_start <= seq AND display_run_ordinal > 0));
CREATE INDEX conversation_items_visible_seq ON conversation_items(seq)
 WHERE display_run_start IS NOT NULL;
CREATE INDEX conversation_items_by_run_seq ON conversation_items(display_run_start,seq)
 WHERE display_run_start IS NOT NULL;
";

async fn upgrade(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(version(db).await? == 17, "immutable runs require schema 17");
    completion_boundary::validate(db).await?;
    db.execute_unprepared(CREATE).await?;
    let mut after = 0;
    let mut last: Option<ChatRunSeed> = None;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT seq,query_class,metadata FROM conversation_items WHERE seq>?
             ORDER BY seq LIMIT 128",
                vec![integer(after)?.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let seq = u64::try_from(row.try_get::<i64>("", "seq")?)?;
            let atom: ChatAtom =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)
                    .context("invalid original completion metadata; original database preserved")?;
            ensure!(seq > after, "completion sequence is not positive");
            let hint = native_read_hint_v1(&row.try_get::<String>("", "query_class")?, &atom);
            let run = position(seq, &hint, last.as_ref())?;
            db.execute_raw(statement(
                "UPDATE conversation_items SET display_run_start=?,display_run_ordinal=? WHERE seq=?",
                vec![run.map(|run| integer(run.start_seq)).transpose()?.into(),
                     run.map(|run| integer(run.ordinal)).transpose()?.into(), integer(seq)?.into()],
            )).await?;
            if let Some(position) = run {
                last = Some(ChatRunSeed {
                    seq,
                    hint,
                    position,
                });
            }
            after = seq;
        }
    }
    validate_backfill(db).await?;
    prove_derived_coverage(db).await?;
    db.execute_unprepared(
        "DROP TABLE timeline_item_members; DROP TABLE timeline_items;
         DROP TABLE timeline_projection_state; UPDATE history_meta SET schema_version=18 WHERE id=1;"
    ).await?;
    validate(db).await
}

fn position(
    seq: u64,
    hint: &ChatReadHint,
    last: Option<&ChatRunSeed>,
) -> Result<Option<ChatRunPosition>> {
    let mut seed = pl_core::chat::ChatPublicationSeed {
        head_seq: seq.checked_sub(1).context("completion sequence is zero")?,
        last_visible: last.cloned(),
    };
    Ok(seed.advance(hint)?.1)
}

/// One-time, bounded proof. Normal opens do not replay history.
async fn validate_backfill(db: &impl ConnectionTrait) -> Result<()> {
    let mut after = 0;
    let mut last = None;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT seq,query_class,metadata,display_run_start,display_run_ordinal
             FROM conversation_items WHERE seq>? ORDER BY seq LIMIT 128",
                vec![integer(after)?.into()],
            ))
            .await?;
        if rows.is_empty() {
            return Ok(());
        }
        for row in rows {
            let seq = u64::try_from(row.try_get::<i64>("", "seq")?)?;
            let atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            let hint = native_read_hint_v1(&row.try_get::<String>("", "query_class")?, &atom);
            let expected = position(seq, &hint, last.as_ref())?;
            let actual = (
                row.try_get::<Option<i64>>("", "display_run_start")?,
                row.try_get::<Option<i64>>("", "display_run_ordinal")?,
            );
            ensure!(
                actual
                    == (
                        expected.map(|run| integer(run.start_seq)).transpose()?,
                        expected.map(|run| integer(run.ordinal)).transpose()?,
                    ),
                "immutable run backfill differs from source facts"
            );
            if let Some(position) = expected {
                last = Some(ChatRunSeed {
                    seq,
                    hint,
                    position,
                });
            }
            after = seq;
        }
    }
}

/// Refuse DROP if even one member has unique material. In particular, a terminal without a
/// completion receipt must already be a real durable fact; migration never invents a receipt.
async fn prove_derived_coverage(db: &impl ConnectionTrait) -> Result<()> {
    use super::legacy_timeline_types::{TimelineItem, TimelineItemKind};
    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("derived coverage has no database identity")?
        .try_get("", "database_id")?;
    let mut after = (String::new(), 0i64);
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT item_id,member_order,member_id,completion_item_id,payload_bytes,metadata
             FROM timeline_item_members WHERE (item_id,member_order)>(?,?)
             ORDER BY item_id,member_order LIMIT 128",
                vec![after.0.clone().into(), after.1.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = (
                row.try_get("", "item_id")?,
                row.try_get("", "member_order")?,
            );
            let bytes: Vec<u8> = row.try_get("", "metadata")?;
            let atom: ChatAtom = serde_json::from_slice(&bytes)?;
            ensure!(
                row.try_get::<String>("", "member_id")? == atom.id
                    && matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
                "derived member has unique or unfinished material; original database preserved"
            );
            let fact = db.query_one_raw(statement(
                "SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase='terminal'",
                vec![atom.id.clone().into()],
            )).await?.context("derived member lacks original terminal fact; original database preserved")?;
            ensure!(
                fact.try_get::<Vec<u8>>("", "metadata")? == bytes,
                "derived member differs from original fact; original database preserved"
            );
            let completion: Option<String> = row.try_get("", "completion_item_id")?;
            ensure!(
                completion == atom.completion_item_id,
                "derived completion identity differs"
            );
            if let Some(id) = completion {
                let record = db.query_one_raw(statement(
                    "SELECT seq,length(payload) AS bytes FROM conversation_items WHERE item_id=?",
                    vec![id.into()],
                )).await?.context("derived member completion missing; original database preserved")?;
                ensure!(
                    atom.completion_seq == Some(u64::try_from(record.try_get::<i64>("", "seq")?)?)
                        && row.try_get::<Option<i64>>("", "payload_bytes")?
                            == Some(record.try_get("", "bytes")?),
                    "derived member completion reference differs"
                );
            } else {
                ensure!(
                    atom.contents.is_empty()
                        && atom.payload.is_none()
                        && row.try_get::<Option<i64>>("", "payload_bytes")?.is_none(),
                    "receiptless member has unique content; original database preserved"
                );
            }
        }
    }
    let mut after = String::new();
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT item_id,metadata FROM timeline_items WHERE item_id>? ORDER BY item_id LIMIT 128",
            vec![after.clone().into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "item_id")?;
            let item: TimelineItem =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            ensure!(item.id == after, "derived item identity differs");
            if item.kind == TimelineItemKind::WorkGroup {
                ensure!(
                    item.content_item_id.is_none()
                        && item.contents.is_empty()
                        && item.payload.is_none(),
                    "derived group has unique content"
                );
                summary_coverage::prove(db, &item, &database).await?;
            } else if let Some(id) = &item.content_item_id {
                let record = db
                    .query_one_raw(statement(
                        "SELECT metadata,length(payload) AS bytes FROM conversation_items WHERE item_id=?",
                        vec![id.as_str().into()],
                    ))
                    .await?
                    .context("derived item original completion missing")?;
                let atom: ChatAtom =
                    serde_json::from_slice(&record.try_get::<Vec<u8>>("", "metadata")?)?;
                ensure!(
                    atom.contents == item.contents && atom.source == item.source,
                    "derived item has unique content references"
                );
                if let Some(payload) = &item.payload {
                    ensure!(
                        matches!(payload, pl_protocol::PayloadData::Deferred { reference, byte_length }
                            if reference.database_id == database
                                && matches!(&reference.target, pl_protocol::ContentTarget::ItemPayload { item_id } if item_id == id)
                                && *byte_length == u64::try_from(record.try_get::<i64>("", "bytes")?)?),
                        "derived item has unique payload"
                    );
                }
            } else {
                // The published fold can retain a receiptless interrupted text. Its identity
                // is decoded only in this migration; preserve the real terminal, never mint a
                // completion for the old placeholder.
                let prefix = if item.kind == TimelineItemKind::Text {
                    "text:"
                } else {
                    "status:"
                };
                let id = item
                    .id
                    .strip_prefix(prefix)
                    .context("receiptless item has no original identity")?;
                let fact = db.query_one_raw(statement(
                    "SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase='terminal'",
                    vec![id.into()],
                )).await?.context("receiptless item has no original terminal; original database preserved")?;
                let atom: ChatAtom =
                    serde_json::from_slice(&fact.try_get::<Vec<u8>>("", "metadata")?)?;
                ensure!(
                    atom.source == item.source
                        && Some(atom.kind) == item.atom_kind
                        && atom.completion_item_id.is_none()
                        && atom.contents.is_empty()
                        && item.contents.is_empty()
                        && item.payload.is_none()
                        && atom.payload.is_none()
                        && matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
                    "receiptless display item has unique material; original database preserved"
                );
            }
        }
    }
    // Recovery is only a set of indexed reliable-fact frontiers. Every referenced source
    // must survive in its original ledger. No checkpoint or body is materialized here.
    let head = super::legacy_timeline_store::read_state(db)
        .await?
        .context("missing legacy cut")?;
    let frontiers: Vec<super::legacy_completion_projection::Frontier> =
        serde_json::from_slice(&head.recovery)?;
    for frontier in frontiers {
        ensure!(
            db.query_one_raw(statement(
                "SELECT 1 AS present FROM conversation_sources WHERE source_key=?
                   AND started_effect=? AND started_suborder=?
                 UNION ALL
                 SELECT 1 FROM conversation_atom_facts
                   WHERE json_extract(metadata,'$.source')=? AND effect_seq=? AND suborder=?
                   AND (? IS NULL OR json_extract(metadata,'$.sourceOrder')=?)
                 LIMIT 1",
                vec![
                    serde_json::to_string(&frontier.source)?.into(),
                    integer(frontier.effect)?.into(),
                    i64::from(frontier.suborder).into(),
                    serde_json::to_string(&frontier.source)?.into(),
                    integer(frontier.effect)?.into(),
                    i64::from(frontier.suborder).into(),
                    frontier.source_order.map(integer).transpose()?.into(),
                    frontier.source_order.map(integer).transpose()?.into()
                ],
            ))
            .await?
            .is_some(),
            "legacy recovery source is not covered; original database preserved"
        );
    }
    Ok(())
}

/// Structural gate only. Applied corruption is rejected, never repaired or replayed.
pub(super) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 18,
        "immutable completion history format is not 18"
    );
    validate_preserved(db).await
}

/// Shared structural proof; the published v18 migration above keeps its exact version gate.
pub(super) async fn validate_preserved(db: &impl ConnectionTrait) -> Result<()> {
    completion_boundary::validate_preserved(db).await?;
    super::validate_tables(db).await?;
    super::model_route_head::validate_tables(db).await?;
    super::atom_metadata::validate_tables(db).await?;
    db.query_all_raw(statement(
        "SELECT seq,item_id,query_class,parent_id,metadata,length(payload),
                display_run_start,display_run_ordinal FROM conversation_items LIMIT 0",
        vec![],
    ))
    .await?;
    super::validate_keys(db, "conversation_items", &["seq"], true, &["item_id"]).await?;
    for (name, columns) in [
        ("conversation_items_visible_seq", &["seq"][..]),
        (
            "conversation_items_by_run_seq",
            &["display_run_start", "seq"][..],
        ),
    ] {
        let row = db.query_one_raw(statement(
            "SELECT sql FROM sqlite_master WHERE type='index' AND name=? AND tbl_name='conversation_items'",
            vec![name.into()],
        )).await?.context("immutable run index missing; original database preserved")?;
        let sql: String = row.try_get("", "sql")?;
        let normalized: String = sql
            .chars()
            .filter(|c| !c.is_whitespace() && *c != '"')
            .flat_map(char::to_lowercase)
            .collect();
        ensure!(
            normalized.ends_with("wheredisplay_run_startisnotnull"),
            "immutable run index predicate differs"
        );
        let keys = db
            .query_all_raw(statement(&format!("PRAGMA index_info('{name}')"), vec![]))
            .await?;
        let names = keys
            .iter()
            .map(|row| row.try_get::<String>("", "name"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        ensure!(names == columns, "immutable run index keys differ");
    }
    for name in [
        "timeline_items",
        "timeline_item_members",
        "timeline_projection_state",
    ] {
        ensure!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                vec![name.into()],
            ))
            .await?
            .is_none(),
            "obsolete display table remains in immutable history"
        );
    }
    checkpoint::read_model_route_head(db).await?;
    Ok(())
}
