//! Schema 17 -> 18. Only immutable read indexes are added; original bytes never change.
use super::legacy_completion_types::{
    ChatReadHint, ChatRunPosition, ChatRunSeed, native_read_hint_v1,
};
use super::*;
use pl_protocol::{ChatAtom, ChatAtomLifecycle};

mod summary_coverage;

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
    let mut seed = super::legacy_completion_types::ChatPublicationSeed {
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

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::{ChatAtomKind, ChatAtomLifecycle, ChatSourceId, ChatTerminalOutcome};
    use sea_orm::{Database, DatabaseConnection, TransactionTrait};
    use sea_orm_migration::MigratorTraitSelf;

    const THREAD: &str = "immutable-completion-migration";
    struct Published17;
    impl MigratorTraitSelf for Published17 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            Migrator {
                thread_id: THREAD.into(),
                bot_root: None,
                execution_identity: None,
            }
            .migrations()
            .into_iter()
            .take_while(|step| step.name() != IMMUTABLE_COMPLETION_RUNS)
            .collect()
        }
    }

    async fn fixture() -> Result<(tempfile::TempDir, DatabaseConnection)> {
        let dir = tempfile::tempdir()?;
        let db = Database::connect(format!(
            "sqlite://{}?mode=rwc",
            dir.path().join("history.sqlite").display()
        ))
        .await?;
        Published17.up(&db, None).await?;
        Ok((dir, db))
    }

    async fn seed(db: &impl ConnectionTrait, count: u64) -> Result<()> {
        for seq in 1..=count {
            let mut atom: ChatAtom = serde_json::from_slice(
                &crate::studio::storage::history::conversation::tests::metadata(&format!(
                    "original-{seq}"
                )),
            )?;
            atom.kind = if seq == 130 {
                ChatAtomKind::Inference
            } else {
                ChatAtomKind::ToolCall
            };
            atom.source = ChatSourceId::ForegroundTurn {
                turn_id: "前台:F".into(),
            };
            atom.delivery = pl_protocol::ChatDeliveryKind::Foreground;
            atom.lifecycle = ChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                outcome: ChatTerminalOutcome::Completed,
            };
            // Deliberate non-JSON bytes: migration must never decode or rewrite the original BLOB.
            db.execute_raw(statement(
                "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata)
             VALUES(?,?,'conversation',?,?,?)",
                vec![
                    integer(seq)?.into(),
                    format!("original-{seq}").into(),
                    "4:turn真实父域".into(),
                    vec![0u8, 255, 10, 13, seq as u8].into(),
                    serde_json::to_vec(&atom)?.into(),
                ],
            ))
            .await?;
        }
        Ok(())
    }

    async fn original_bytes(
        db: &impl ConnectionTrait,
    ) -> Result<Vec<(i64, String, String, Option<String>, Vec<u8>, Vec<u8>)>> {
        db.query_all_raw(statement(
        "SELECT seq,item_id,query_class,parent_id,payload,metadata FROM conversation_items ORDER BY seq",
        vec![],
    )).await?.into_iter().map(|row| Ok((
        row.try_get("","seq")?,row.try_get("","item_id")?,row.try_get("","query_class")?,
        row.try_get("","parent_id")?,row.try_get("","payload")?,row.try_get("","metadata")?,
    ))).collect()
    }

    async fn migrate(db: &DatabaseConnection) -> Result<()> {
        // Keep this published migration's own contract/fixtures at its v18 boundary.
        // The v18 -> v19 runner is exercised independently by display_snapshots tests.
        preflight(db, THREAD).await?;
        let migrator = Migrator {
            thread_id: THREAD.into(),
            execution_identity: None,
            bot_root: None,
        };
        let steps = migrator
            .get_pending_migrations_read_only(db)
            .await?
            .iter()
            .take_while(|step| step.name() != WORK_SNAPSHOTS)
            .count();
        migrator.up(db, Some(u32::try_from(steps)?)).await?;
        Ok(())
    }

    #[tokio::test]
    async fn nonempty_official_upgrade_preserves_all_original_bytes_and_reopen_does_no_backfill()
    -> Result<()> {
        let (_dir, db) = fixture().await?;
        seed(&db, 259).await?;
        use pl_core::chat::{
            ChatContent, ChatContentKey, ChatContents, ChatKey, ContentData, ContentDescriptor,
        };
        use std::sync::Arc;
        let key = ChatContentKey {
            owner: ChatKey::new("item", "original-1")?,
            key: "tool-result".into(),
        };
        let content = Arc::new(ChatContent {
            descriptor: ContentDescriptor {
                key: key.clone(),
                byte_length: 140_000,
                generation: 19,
                media_type: Some("application/octet-stream".into()),
            },
            data: ContentData::Bytes(Arc::from(vec![255; 140_000])),
        });
        super::super::super::conversation::write_contents(
            &db,
            "original-1",
            &ChatContents::from([(key, content)]),
        )
        .await?;
        db.execute_unprepared(
        "INSERT INTO completion_boundary_archive_contents SELECT * FROM conversation_contents;
         INSERT INTO completion_boundary_archive_content_chunks SELECT * FROM conversation_content_chunks;"
    ).await?;
        let manifests = content_bytes(&db).await?;
        let bytes = original_bytes(&db).await?;
        migrate(&db).await?;
        assert_eq!(version(&db).await?, 18);
        assert_eq!(original_bytes(&db).await?, bytes);
        assert_eq!(content_bytes(&db).await?, manifests);
        let rows = db
        .query_all_raw(statement(
            "SELECT seq,display_run_start,display_run_ordinal FROM conversation_items ORDER BY seq",
            vec![],
        ))
        .await?;
        assert_eq!(
            rows[129].try_get::<Option<i64>>("", "display_run_start")?,
            None
        );
        assert_eq!(rows[258].try_get::<i64>("", "display_run_start")?, 1);
        assert_eq!(rows[258].try_get::<i64>("", "display_run_ordinal")?, 258);
        assert!(!SchemaManager::new(&db).has_table("timeline_items").await?);
        assert!(
            SchemaManager::new(&db)
                .has_table("conversation_atom_facts")
                .await?
        );
        assert!(
            SchemaManager::new(&db)
                .has_table("completion_boundary_archive_contents")
                .await?
        );
        db.execute_unprepared(
            "CREATE TRIGGER reject_rebackfill BEFORE UPDATE ON conversation_items
         BEGIN SELECT RAISE(ABORT,'unexpected second backfill'); END;",
        )
        .await?;
        migrate(&db).await?;
        validate(&db).await?;
        Ok(())
    }

    #[tokio::test]
    async fn failures_rollback_columns_backfill_version_and_applied_and_can_retry() -> Result<()> {
        for failure in ["backfill", "version", "applied"] {
            let (_dir, db) = fixture().await?;
            seed(&db, 140).await?;
            let before = original_bytes(&db).await?;
            let sql = match failure {
                "backfill" => {
                    "CREATE TRIGGER injected_failure BEFORE UPDATE ON conversation_items
                WHEN NEW.seq=129 BEGIN SELECT RAISE(ABORT,'backfill failure'); END;"
                }
                "version" => {
                    "CREATE TRIGGER injected_failure BEFORE UPDATE ON history_meta
                WHEN NEW.schema_version=18 BEGIN SELECT RAISE(ABORT,'version failure'); END;"
                }
                _ => {
                    "CREATE TRIGGER injected_failure BEFORE INSERT ON seaql_migrations
                WHEN NEW.version='m20261110_000001_history_immutable_completion_runs'
                BEGIN SELECT RAISE(ABORT,'Applied failure'); END;"
                }
            };
            db.execute_unprepared(sql).await?;
            assert!(migrate(&db).await.is_err(), "{failure}");
            assert_eq!(version(&db).await?, 17);
            assert_eq!(original_bytes(&db).await?, before);
            assert!(SchemaManager::new(&db).has_table("timeline_items").await?);
            let columns = db
                .query_all_raw(statement("PRAGMA table_info(conversation_items)", vec![]))
                .await?;
            assert!(
                !columns
                    .iter()
                    .any(|row| row.try_get::<String>("", "name").unwrap() == "display_run_start")
            );
            assert!(
                db.query_one_raw(statement(
                    "SELECT 1 FROM seaql_migrations WHERE version=?",
                    vec![IMMUTABLE_COMPLETION_RUNS.into()],
                ))
                .await?
                .is_none()
            );
            db.execute_unprepared("DROP TRIGGER injected_failure")
                .await?;
            migrate(&db).await?;
            assert_eq!(original_bytes(&db).await?, before);
        }
        Ok(())
    }

    #[tokio::test]
    async fn unique_derived_material_refuses_drop_and_applied_damage_is_never_repaired()
    -> Result<()> {
        let (_dir, db) = fixture().await?;
        seed(&db, 1).await?;
        let atom = crate::studio::storage::history::conversation::tests::metadata("uncovered");
        db.execute_raw(statement(
        "INSERT INTO timeline_item_members(item_id,member_order,member_id,completion_item_id,
          admitted_effect,updated_effect,payload_bytes,metadata) VALUES('unique',1,'uncovered',NULL,1,1,NULL,?)",
        vec![atom.to_vec().into()],
    )).await?;
        assert!(migrate(&db).await.is_err());
        assert_eq!(version(&db).await?, 17);
        assert!(SchemaManager::new(&db).has_table("timeline_items").await?);
        db.execute_unprepared("DELETE FROM timeline_item_members WHERE item_id='unique'")
            .await?;
        migrate(&db).await?;
        db.execute_unprepared("DROP INDEX conversation_items_visible_seq")
            .await?;
        assert!(migrate(&db).await.is_err());
        assert!(validate(&db).await.is_err());
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_master WHERE name='conversation_items_visible_seq'",
                vec![],
            ))
            .await?
            .is_none()
        );
        assert_eq!(latest_original_seq(&db).await?, 1);
        Ok(())
    }

    async fn latest_original_seq(db: &impl ConnectionTrait) -> Result<u64> {
        super::super::super::conversation::latest_append_seq(db).await
    }

    #[tokio::test]
    async fn applied_missing_run_column_is_rejected_without_repairing_originals() -> Result<()> {
        let (_dir, db) = fixture().await?;
        seed(&db, 2).await?;
        migrate(&db).await?;
        let originals = original_bytes(&db).await?;
        db.execute_unprepared("ALTER TABLE conversation_items DROP COLUMN display_run_ordinal")
            .await?;
        assert!(migrate(&db).await.is_err());
        assert!(validate(&db).await.is_err());
        assert!(
            !SchemaManager::new(&db)
                .has_column("conversation_items", "display_run_ordinal")
                .await?
        );
        assert_eq!(version(&db).await?, 18);
        assert_eq!(original_bytes(&db).await?, originals);
        Ok(())
    }

    #[tokio::test]
    async fn post_boundary_summary_requires_complete_original_or_archived_text_before_drop()
    -> Result<()> {
        use super::super::legacy_timeline_types::{
            TIMELINE_PROJECTION_VERSION, TimelineCategory, TimelineCategoryCount,
            TimelineGroupSummary, TimelineItem, TimelineItemKind, TimelineMembersRef,
        };
        use pl_core::chat::{
            ChatContent, ChatContentKey, ChatContents, ChatKey, ContentData, ContentDescriptor,
        };
        use pl_protocol::{
            ChatAtomContent, ChatContentRole, ContentOwner, ContentRef, ContentTarget,
        };
        use std::sync::Arc;

        for case in [
            "complete",
            "missing_manifest",
            "missing_prefix",
            "missing_tail",
            "different_text",
            "archive_only",
            "archive_covers_damaged_live",
        ] {
            let (_dir, db) = fixture().await?;
            seed(&db, 1).await?;
            let database: String = db
                .query_one_raw(statement(
                    "SELECT database_id FROM history_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .context("database")?
                .try_get("", "database_id")?;
            let generation: String = db
            .query_one_raw(statement(
                "SELECT projection_generation FROM timeline_projection_state WHERE singleton_id=1",
                vec![],
            ))
            .await?
            .context("projection")?
            .try_get("", "projection_generation")?;
            let text = "最后一行真实摘要 🦀";
            let body = format!(
                "{}\n{text}",
                "x".repeat(3 * conversation::content::CHUNK_BYTES)
            );
            let key = ChatContentKey {
                owner: ChatKey::new("item", "original-1")?,
                key: "summary".into(),
            };
            let content = Arc::new(ChatContent {
                descriptor: ContentDescriptor {
                    key: key.clone(),
                    byte_length: body.len() as u64,
                    generation: 1,
                    media_type: Some("text/plain".into()),
                },
                data: ContentData::Bytes(Arc::from(body.into_bytes())),
            });
            conversation::write_contents(&db, "original-1", &ChatContents::from([(key, content)]))
                .await?;
            let mut atom: ChatAtom = serde_json::from_slice(
                &crate::studio::storage::history::conversation::tests::metadata("original-1"),
            )?;
            atom.kind = ChatAtomKind::Reasoning;
            atom.source = ChatSourceId::ForegroundTurn {
                turn_id: "after-boundary".into(),
            };
            atom.delivery = pl_protocol::ChatDeliveryKind::Foreground;
            atom.completion_seq = Some(1);
            atom.contents = vec![ChatAtomContent {
                role: ChatContentRole::ReasoningSummary,
                reference: ContentRef {
                    database_id: database.clone(),
                    target: ContentTarget::Body {
                        owner: ContentOwner::Item {
                            item_id: "original-1".into(),
                        },
                        key: "summary".into(),
                    },
                },
            }];
            let member = serde_json::to_vec(&atom)?;
            db.execute_raw(statement(
                "UPDATE conversation_items SET metadata=? WHERE seq=1",
                vec![member.clone().into()],
            ))
            .await?;
            db.execute_raw(statement(
            "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata)
             VALUES(1,0,'original-1','terminal',1,?)", vec![member.clone().into()],
        )).await?;
            let group = TimelineItem {
                id: "new-group-after-completion-boundary".into(),
                kind: TimelineItemKind::WorkGroup,
                source: atom.source.clone(),
                atom_kind: None,
                delivery: atom.delivery,
                text_channel: None,
                turn_id: None,
                started_at: None,
                finished_at: None,
                outcome: None,
                summary: Some(TimelineGroupSummary {
                    latest_thinking_summary: Some(
                        if case == "different_text" {
                            "只有组头保留的文字"
                        } else {
                            text
                        }
                        .into(),
                    ),
                    member_count: 1,
                    active_count: 0,
                    failed_count: 0,
                    cancelled_count: 0,
                    categories: vec![TimelineCategoryCount {
                        category: TimelineCategory::Thinking,
                        count: 1,
                    }],
                    started_at: None,
                    finished_at: None,
                }),
                members: Some(TimelineMembersRef {
                    database_id: database,
                    projection_version: TIMELINE_PROJECTION_VERSION,
                    projection_generation: generation,
                    item_id: "new-group-after-completion-boundary".into(),
                }),
                contents: vec![],
                payload: None,
                content_item_id: None,
                position: Some(0),
                admission_closed: true,
            };
            db.execute_raw(statement(
            "INSERT INTO timeline_items(item_id,kind,position,commit_seq,metadata,projection_version)
             VALUES(?,'workGroup',0,1,?,2)",
            vec![group.id.clone().into(), serde_json::to_vec(&group)?.into()],
        )).await?;
            db.execute_raw(statement(
            "INSERT INTO timeline_item_members(item_id,member_order,member_id,completion_item_id,
              admitted_effect,updated_effect,payload_bytes,metadata) VALUES(?,1,'original-1','original-1',1,1,5,?)",
            vec![group.id.clone().into(), member.into()],
        )).await?;
            assert!(
                db.query_one_raw(statement(
                    "SELECT 1 FROM completion_boundary_archive_timeline_items WHERE item_id=?",
                    vec![group.id.clone().into()],
                ))
                .await?
                .is_none(),
                "this group was created after the published archive boundary"
            );
            if case.starts_with("archive_") {
                db.execute_unprepared(
                "INSERT INTO completion_boundary_archive_contents SELECT * FROM conversation_contents;
                 INSERT INTO completion_boundary_archive_content_chunks SELECT * FROM conversation_content_chunks;"
            ).await?;
            }
            match case {
                "missing_manifest" | "archive_only" => {
                    db.execute_unprepared(
                    "DELETE FROM conversation_content_chunks; DELETE FROM conversation_contents",
                )
                .await?;
                }
                "missing_prefix" | "archive_covers_damaged_live" => {
                    db.execute_unprepared(
                        "DELETE FROM conversation_content_chunks WHERE byte_offset=0",
                    )
                    .await?;
                }
                "missing_tail" => {
                    db.execute_unprepared("DELETE FROM conversation_content_chunks WHERE byte_offset=(SELECT MAX(byte_offset) FROM conversation_content_chunks)").await?;
                }
                _ => {}
            }
            let original = original_bytes(&db).await?;
            let contents = content_bytes(&db).await?;
            let protected = summary_evidence(&db).await?;
            let ledger = db
                .query_all_raw(statement(
                    "SELECT version,applied_at FROM seaql_migrations ORDER BY version",
                    vec![],
                ))
                .await?
                .into_iter()
                .map(|r| {
                    Ok((
                        r.try_get::<String>("", "version")?,
                        r.try_get::<i64>("", "applied_at")?,
                    ))
                })
                .collect::<Result<Vec<_>>>()?;
            let result = migrate(&db).await;
            let succeeds = matches!(
                case,
                "complete" | "archive_only" | "archive_covers_damaged_live"
            );
            if succeeds {
                result.with_context(|| case.to_owned())?;
                assert_eq!(version(&db).await?, 18);
            } else {
                let error = result.expect_err(case);
                assert!(
                    format!("{error:#}").contains("display summary text is not covered"),
                    "{error:#}"
                );
                assert_eq!(version(&db).await?, 17);
                for table in [
                    "timeline_items",
                    "timeline_item_members",
                    "timeline_projection_state",
                ] {
                    assert!(
                        SchemaManager::new(&db).has_table(table).await?,
                        "{case}: {table}"
                    );
                }
                assert_eq!(summary_evidence(&db).await?, protected, "{case}");
                assert!(
                    !SchemaManager::new(&db)
                        .has_column("conversation_items", "display_run_start")
                        .await?
                );
                let after = db
                    .query_all_raw(statement(
                        "SELECT version,applied_at FROM seaql_migrations ORDER BY version",
                        vec![],
                    ))
                    .await?
                    .into_iter()
                    .map(|r| {
                        Ok((
                            r.try_get::<String>("", "version")?,
                            r.try_get::<i64>("", "applied_at")?,
                        ))
                    })
                    .collect::<Result<Vec<_>>>()?;
                assert_eq!(after, ledger, "{case}: Applied must not advance");
            }
            assert_eq!(original_bytes(&db).await?, original, "{case}");
            assert_eq!(content_bytes(&db).await?, contents, "{case}");
            eprintln!(
                "summary coverage case={case} migration_succeeded={succeeds} original_bytes_preserved=true"
            );
        }
        Ok(())
    }

    async fn summary_evidence(db: &impl ConnectionTrait) -> Result<Vec<String>> {
        db.query_all_raw(statement(
        "SELECT 'item:'||item_id||':'||hex(metadata) AS value FROM timeline_items
         UNION ALL SELECT 'member:'||item_id||':'||member_order||':'||hex(metadata) FROM timeline_item_members
         UNION ALL SELECT 'fact:'||atom_id||':'||phase||':'||hex(metadata) FROM conversation_atom_facts
         UNION ALL SELECT 'head:'||projection_generation||':'||hex(recovery) FROM timeline_projection_state
         ORDER BY value", vec![],
    )).await?.into_iter().map(|row| row.try_get("", "value").map_err(Into::into)).collect()
    }

    #[tokio::test]
    async fn original_deferred_display_payload_is_covered_but_conflicting_references_roll_back()
    -> Result<()> {
        use super::super::legacy_timeline_types::{TimelineItem, TimelineItemKind};
        use pl_protocol::{ContentRef, ContentTarget, PayloadData};
        for conflict in ["none", "database", "item", "length"] {
            let (_dir, db) = fixture().await?;
            seed(&db, 1).await?;
            let row = db
                .query_one_raw(statement(
                    "SELECT metadata FROM conversation_items WHERE seq=1",
                    vec![],
                ))
                .await?
                .context("original completion")?;
            let mut atom: ChatAtom =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            atom.kind = ChatAtomKind::Text;
            db.execute_raw(statement(
                "UPDATE conversation_items SET metadata=? WHERE seq=1",
                vec![serde_json::to_vec(&atom)?.into()],
            ))
            .await?;
            let database: String = db
                .query_one_raw(statement(
                    "SELECT database_id FROM history_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .context("database")?
                .try_get("", "database_id")?;
            let item = TimelineItem {
                id: "text:original-1".into(),
                kind: TimelineItemKind::Text,
                source: atom.source.clone(),
                atom_kind: Some(atom.kind),
                delivery: atom.delivery,
                text_channel: None,
                turn_id: None,
                started_at: None,
                finished_at: None,
                outcome: Some(ChatTerminalOutcome::Completed),
                summary: None,
                members: None,
                contents: vec![],
                payload: Some(PayloadData::Deferred {
                    reference: ContentRef {
                        database_id: if conflict == "database" {
                            "other".into()
                        } else {
                            database
                        },
                        target: ContentTarget::ItemPayload {
                            item_id: if conflict == "item" {
                                "other".into()
                            } else {
                                "original-1".into()
                            },
                        },
                    },
                    byte_length: if conflict == "length" { 6 } else { 5 },
                }),
                content_item_id: Some("original-1".into()),
                position: Some(0),
                admission_closed: true,
            };
            db.execute_raw(statement(
            "INSERT INTO timeline_items(item_id,kind,position,commit_seq,metadata,projection_version)
             VALUES(?,'text',0,1,?,2)",
            vec![item.id.clone().into(), serde_json::to_vec(&item)?.into()],
        )).await?;
            let originals = original_bytes(&db).await?;
            let result = migrate(&db).await;
            if conflict == "none" {
                result?;
                assert_eq!(version(&db).await?, 18);
            } else {
                assert!(result.is_err(), "{conflict}");
                assert_eq!(version(&db).await?, 17);
                assert!(SchemaManager::new(&db).has_table("timeline_items").await?);
            }
            assert_eq!(original_bytes(&db).await?, originals);
        }
        Ok(())
    }

    async fn content_bytes(
        db: &impl ConnectionTrait,
    ) -> Result<Vec<(String, String, Option<i64>, Vec<u8>)>> {
        db.query_all_raw(statement(
        "SELECT 'live:'||owner_key AS owner,content_key,NULL AS offset,payload AS bytes FROM conversation_contents
         UNION ALL SELECT 'live:'||owner_key,content_key,byte_offset,data FROM conversation_content_chunks
         UNION ALL SELECT 'archive:'||owner_key,content_key,NULL,payload FROM completion_boundary_archive_contents
         UNION ALL SELECT 'archive:'||owner_key,content_key,byte_offset,data FROM completion_boundary_archive_content_chunks
         ORDER BY owner,content_key,offset", vec![],
    )).await?.into_iter().map(|row| Ok((row.try_get("","owner")?, row.try_get("","content_key")?,
                                      row.try_get("","offset")?, row.try_get("","bytes")?))).collect()
    }

    #[tokio::test]
    async fn cancelling_an_uncommitted_upgrade_preserves_the_old_store_and_allows_fresh_retry()
    -> Result<()> {
        let (_dir, db) = fixture().await?;
        seed(&db, 140).await?;
        let originals = original_bytes(&db).await?;
        let tx = db.begin().await?;
        upgrade(&tx).await?;
        // Dropping the transaction is the cancellation path, before SeaORM can publish Applied.
        drop(tx);
        assert_eq!(version(&db).await?, 17);
        assert_eq!(original_bytes(&db).await?, originals);
        assert!(SchemaManager::new(&db).has_table("timeline_items").await?);
        migrate(&db).await?;
        assert_eq!(version(&db).await?, 18);
        assert_eq!(original_bytes(&db).await?, originals);
        Ok(())
    }

    #[tokio::test]
    async fn receiptless_interruption_fact_is_retained_without_creating_a_completion() -> Result<()>
    {
        let (_dir, db) = fixture().await?;
        let mut atom: ChatAtom = serde_json::from_slice(
            &crate::studio::storage::history::conversation::tests::metadata("interrupted"),
        )?;
        atom.completion_item_id = None;
        atom.completion_seq = None;
        atom.kind = ChatAtomKind::Reasoning;
        atom.attempt_id = Some("attempt".into());
        atom.lifecycle = ChatAtomLifecycle::Terminal {
            started: Some(pl_protocol::ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            ended: Some(pl_protocol::ChatFactPosition {
                effect_seq: 2,
                suborder: 0,
            }),
            outcome: ChatTerminalOutcome::Cancelled,
        };
        let bytes = serde_json::to_vec(&atom)?;
        db.execute_raw(statement(
        "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata)
         VALUES(2,0,'interrupted','terminal',1,?)",
        vec![bytes.clone().into()],
    ))
    .await?;
        db.execute_raw(statement(
            "INSERT INTO timeline_item_members(item_id,member_order,member_id,completion_item_id,
          admitted_effect,updated_effect,payload_bytes,metadata)
         VALUES('old-interrupted',1,'interrupted',NULL,1,2,NULL,?)",
            vec![bytes.clone().into()],
        ))
        .await?;
        migrate(&db).await?;
        assert_eq!(latest_original_seq(&db).await?, 0);
        let fact = db.query_one_raw(statement(
        "SELECT metadata FROM conversation_atom_facts WHERE atom_id='interrupted' AND phase='terminal'",
        vec![],
    )).await?.context("interruption fact was lost")?;
        assert_eq!(fact.try_get::<Vec<u8>>("", "metadata")?, bytes);
        Ok(())
    }
}
