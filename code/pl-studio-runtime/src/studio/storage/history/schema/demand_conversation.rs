//! The single schema-11 → schema-12 content transition. The manager supplies the real transaction;
//! no pool acquisition, live owner, tool decoder or execution activation occurs inside it.

use super::super::conversation;
use super::legacy_current::{
    CurrentContentWrite, CurrentEntryChange, CurrentEntryWrite, LegacyCurrent as PreparedCurrent,
};
use super::legacy_timeline_types::CurrentProjection;
use super::*;
use pl_core::chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor};
use pl_protocol::{
    ContentOwner, ContentRef, ContentTarget, CurrentCollectionRef, CurrentPlanHead,
    CurrentTurnHead, ThreadStatus,
};
use std::sync::Arc;

pub(super) struct DemandConversation {
    pub(super) thread_id: String,
}

impl MigrationName for DemandConversation {
    fn name(&self) -> &str {
        DEMAND_CONVERSATION
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for DemandConversation {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let result: anyhow::Result<()> = async {
            ensure!(
                version(db).await? == 11,
                "conversation migration requires schema 11"
            );
            validate_tables_source(db).await?;
            db.execute_unprepared(conversation::migration::CREATE_SCHEMA)
                .await?;
            let expected = conversation::migration::backfill(db, &self.thread_id).await?;
            seed_current(db, &self.thread_id).await?;
            validate_tables(db).await?;
            ensure!(
                conversation::latest_append_seq(db).await? == expected,
                "conversation migration changed the completed prefix"
            );
            let row = db
                .query_one_raw(statement(
                    "SELECT count(*) AS count FROM conversation_items",
                    vec![],
                ))
                .await?
                .context("conversation count query returned no row")?;
            ensure!(
                u64::try_from(row.try_get::<i64>("", "count")?)? == expected,
                "conversation migration lost an indexed completion"
            );
            ensure!(
                db.query_all_raw(statement("PRAGMA foreign_key_check", vec![]))
                    .await?
                    .is_empty(),
                "conversation migration has a foreign-key violation"
            );
            set_version(db, 12).await?;
            Ok(())
        }
        .await;
        result.map_err(conversion)
    }
}

async fn validate_tables_source(db: &impl ConnectionTrait) -> Result<()> {
    super::validate_tables(db).await
}

pub(super) async fn validate_tables(db: &impl ConnectionTrait) -> Result<()> {
    validate_v9_tables(db).await?;
    for sql in [
        "SELECT seq,item_id,query_class,parent_id,payload FROM conversation_items LIMIT 0",
        "SELECT owner_key,content_key,payload FROM conversation_contents LIMIT 0",
        "SELECT owner_key,content_key,byte_offset,data FROM conversation_content_chunks LIMIT 0",
        "SELECT singleton_id,payload FROM conversation_view_state LIMIT 0",
        "SELECT collection,position,entry_id,payload FROM conversation_view_entries LIMIT 0",
    ] {
        db.query_all_raw(statement(sql, vec![])).await?;
    }
    for (table, primary, integer_primary, unique) in [
        ("conversation_items", &["seq"][..], true, &["item_id"][..]),
        (
            "conversation_contents",
            &["owner_key", "content_key"][..],
            false,
            &[][..],
        ),
        (
            "conversation_content_chunks",
            &["owner_key", "content_key", "byte_offset"][..],
            false,
            &[][..],
        ),
        (
            "conversation_view_state",
            &["singleton_id"][..],
            true,
            &[][..],
        ),
        (
            "conversation_view_entries",
            &["collection", "position"][..],
            false,
            &[][..],
        ),
    ] {
        validate_keys(db, table, primary, integer_primary, unique).await?;
        if !integer_primary {
            validate_ordered_unique_key(db, table, primary, true).await?;
        }
    }
    validate_ordered_unique_key(
        db,
        "conversation_view_entries",
        &["collection", "entry_id"],
        false,
    )
    .await?;
    for table in [
        "conversation_contents",
        "conversation_content_chunks",
        "conversation_view_entries",
    ] {
        let row = db
            .query_one_raw(statement(
                "SELECT wr FROM pragma_table_list WHERE schema='main' AND name=?",
                vec![table.into()],
            ))
            .await?
            .context("conversation table metadata missing")?;
        ensure!(
            row.try_get::<i64>("", "wr")? == 1,
            "conversation table must be WITHOUT ROWID"
        );
    }
    for (name, columns) in [
        ("conversation_items_by_class", vec!["query_class", "seq"]),
        (
            "conversation_items_by_parent_class",
            vec!["parent_id", "query_class", "seq"],
        ),
        (
            "conversation_contents_unsealed",
            vec!["owner_key", "content_key"],
        ),
    ] {
        let rows = db
            .query_all_raw(statement(
                "SELECT name FROM pragma_index_info(?) ORDER BY seqno",
                vec![name.into()],
            ))
            .await?;
        let actual = rows
            .iter()
            .map(|r| r.try_get::<String>("", "name"))
            .collect::<Result<Vec<_>, _>>()?;
        ensure!(
            actual == columns,
            "conversation query index is missing or invalid"
        );
    }
    let row = db
        .query_one_raw(statement(
            "SELECT partial FROM pragma_index_list('conversation_contents')
         WHERE name='conversation_contents_unsealed'",
            vec![],
        ))
        .await?
        .context("active content index is missing")?;
    ensure!(
        row.try_get::<i64>("", "partial")? == 1,
        "active content index must be partial"
    );
    Ok(())
}

/// One explicit migration-only checkpoint read. All recovery tables remain untouched.
pub(in super::super) async fn seed_current(
    db: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<()> {
    let watermark = u64::try_from(super::super::applied_write_seq(db).await?)?;
    let identity = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("history identity missing")?
        .try_get::<String>("", "database_id")?;
    let mut projection = CurrentProjection::empty(watermark, ThreadStatus::Idle);
    let Some(checkpoint) = checkpoint::read(db, thread_id).await? else {
        // v2 imports can prepare their SQLite facts before importing the external checkpoint.
        // There is no persisted execution source yet; that explicit import reseeds this projection
        // in its checkpoint transaction before its preparation barrier is released.
        let prepared = PreparedCurrent::new(
            super::legacy_timeline_types::FrozenCurrentProjection::new(projection),
            Arc::from([]),
            Arc::from([]),
        );
        return super::legacy_current::apply(db, watermark, &prepared).await;
    };
    ensure!(
        checkpoint.history_fence == watermark,
        "current migration checkpoint fence differs"
    );
    let state = &checkpoint.state;
    projection.logical_status = crate::studio::thread_projection::status(state);
    if let Some(turn) = crate::studio::thread_projection::project_active_turn(thread_id, state, 0)?
        && let Some(phase) = turn.phase()
    {
        projection.active_turn = Some(CurrentTurnHead { id: turn.id, phase });
    }
    let mut entries = Vec::new();
    let mut contents = Vec::new();
    if let Some(activity) =
        crate::studio::thread_projection::project_activity(thread_id, state, None)
    {
        projection.active = Some(pl_protocol::CurrentActivityHead {
            id: activity.identity,
            kind: activity.kind,
            summary: activity.summary,
            thinking_summary: activity.thinking_summary,
            thinking_seconds: activity.thinking_seconds,
            tool_count: activity.tools.count,
            background_tool_count: activity.tools.background,
            latest_tool: activity.tools.latest_started.as_ref().map(|tool| {
                pl_protocol::CurrentToolHead {
                    call_id: tool.call_id.clone(),
                    name: tool.name.clone(),
                    state: tool.state,
                }
            }),
        });
        projection.collections.push(CurrentCollectionRef {
            database_id: identity.clone(),
            collection: "tools".into(),
            revision: watermark,
        });
        for (position, tool) in activity.tools.active.iter().enumerate() {
            entries.push(CurrentEntryChange::Put(CurrentEntryWrite {
                collection: "tools".into(),
                position: i64::try_from(position)?,
                entry_id: tool.call_id.clone(),
                payload: Arc::from(serde_json::to_vec(tool)?),
            }));
        }
    }
    if !state.interactions.is_empty() || !state.permissions.is_empty() {
        projection.interactions = Some(CurrentCollectionRef {
            database_id: identity.clone(),
            collection: "interactions".into(),
            revision: watermark,
        });
        for (position, id) in state
            .interactions
            .keys()
            .chain(state.permissions.keys())
            .enumerate()
        {
            let payload =
                crate::thread_assembler::project_thread_interaction(thread_id, id, state)?
                    .context("migration interaction cannot be projected")?;
            entries.push(CurrentEntryChange::Put(CurrentEntryWrite {
                collection: "interactions".into(),
                position: i64::try_from(position)?,
                entry_id: payload.interaction_id.clone(),
                payload: Arc::from(serde_json::to_vec(&payload)?),
            }));
        }
    }
    if let Some(record) = state.extensions.get(crate::plan_tool::PLAN_EXTENSION) {
        let plan = crate::plan_tool::decode_plan_state(&record.payload)?;
        let owner = ContentOwner::Current {
            domain: "plan".into(),
            id: "document".into(),
            revision: plan.revision,
        };
        let owner_key = crate::studio::conversation_identity::content_owner_key(&owner)?;
        let document = plan.document.as_ref().map(|document| {
            let bytes = Arc::<[u8]>::from(document.markdown.as_bytes());
            contents.push(CurrentContentWrite {
                content: Arc::new(ChatContent {
                    descriptor: ContentDescriptor {
                        key: ChatContentKey {
                            owner: owner_key.clone(),
                            key: "document".into(),
                        },
                        byte_length: bytes.len() as u64,
                        generation: 1,
                        media_type: Some("text/plain; charset=utf-8".into()),
                    },
                    data: ContentData::Bytes(bytes),
                }),
                sealed: true,
            });
            ContentRef {
                database_id: identity.clone(),
                target: ContentTarget::Body {
                    owner: owner.clone(),
                    key: "document".into(),
                },
            }
        });
        projection.plan = Some(CurrentPlanHead {
            revision: plan.revision,
            phase: plan.state,
            document,
        });
        if !plan.history_tail.is_empty() {
            projection.collections.push(CurrentCollectionRef {
                database_id: identity,
                collection: "planHistory".into(),
                revision: plan.revision,
            });
            for record in &plan.history_tail {
                entries.push(CurrentEntryChange::Put(CurrentEntryWrite {
                    collection: "planHistory".into(),
                    position: integer(record.revision)?,
                    entry_id: record.operation_id.clone(),
                    payload: Arc::from(serde_json::to_vec(record)?),
                }));
            }
        }
    }
    // Persisted running remains a logical fact; it does not reactivate the old execution.
    projection.execution_present = false;
    let prepared = PreparedCurrent::new(
        super::legacy_timeline_types::FrozenCurrentProjection::new(projection),
        Arc::from(entries),
        Arc::from(contents),
    );
    super::legacy_current::apply(db, watermark, &prepared).await
}

#[cfg(test)]
mod tests {
    use super::super::super::{AccountingCommit, CheckpointEffect, EffectCommit, HistoryStore};
    use super::*;
    use sea_orm_migration::MigratorTraitSelf;

    const THREAD: &str = "demand-migration";

    async fn fixture_current(db: &impl ConnectionTrait) -> Result<CurrentProjection> {
        if completion_boundary::applied(db).await? {
            super::super::legacy_current::read_archived(db).await
        } else {
            super::super::legacy_current::read(db).await
        }
    }

    struct Published11;
    impl MigratorTraitSelf for Published11 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            Migrator {
                thread_id: THREAD.into(),
                execution_identity: None,
                bot_root: None,
            }
            .migrations()
            .into_iter()
            .filter(|step| {
                !matches!(
                    step.name(),
                    BACKGROUND_RESULTS
                        | MEMBER_READ_METADATA
                        | TIMELINE_THINKING_SUMMARY
                        | TIMELINE_BACKGROUND_TAIL
                        | SOURCE_CLASSIFICATION
                        | COMPLETION_BOUNDARY
                        | IMMUTABLE_COMPLETION_RUNS
                        | WORK_SNAPSHOTS
                        | DISPLAY_BLOCK_ORDER
                        | EXECUTION_FACTS
                )
            })
            .filter(|step| {
                !matches!(
                    step.name(),
                    DEMAND_CONVERSATION | MODEL_ROUTE_HEAD | ATOM_METADATA | TIMELINE_ITEMS
                )
            })
            .collect()
        }
    }

    /// Exercise the published 11→12 transition without silently replacing its target with 13.
    struct Published12;
    impl MigratorTraitSelf for Published12 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            Migrator {
                thread_id: THREAD.into(),
                execution_identity: None,
                bot_root: None,
            }
            .migrations()
            .into_iter()
            .filter(|step| {
                !matches!(
                    step.name(),
                    BACKGROUND_RESULTS
                        | MEMBER_READ_METADATA
                        | TIMELINE_THINKING_SUMMARY
                        | TIMELINE_BACKGROUND_TAIL
                        | SOURCE_CLASSIFICATION
                        | COMPLETION_BOUNDARY
                        | IMMUTABLE_COMPLETION_RUNS
                        | WORK_SNAPSHOTS
                        | DISPLAY_BLOCK_ORDER
                        | EXECUTION_FACTS
                )
            })
            .filter(|step| {
                !matches!(
                    step.name(),
                    MODEL_ROUTE_HEAD | ATOM_METADATA | TIMELINE_ITEMS
                )
            })
            .collect()
        }
    }

    async fn prepare_published12(db: &DatabaseConnection) -> Result<()> {
        preflight(db, THREAD).await?;
        let steps = Published12
            .get_pending_migrations_read_only(db)
            .await?
            .iter()
            .take_while(|step| !is_lifecycle_migration(step.name()))
            .count();
        Published12.up(db, Some(u32::try_from(steps)?)).await?;
        Ok(())
    }

    async fn source() -> Result<(tempfile::TempDir, DatabaseConnection)> {
        let dir = tempfile::tempdir()?;
        let db = super::super::super::connect(
            &dir.path().join("history.sqlite"),
            crate::studio::paths::SqliteFileMode::Create,
        )
        .await?;
        let count = Published11
            .migrations()
            .iter()
            .take_while(|step| !is_lifecycle_migration(step.name()))
            .count();
        Published11.up(&db, Some(u32::try_from(count)?)).await?;
        assert_eq!(version(&db).await?, 11);
        Ok((dir, db))
    }

    /// Explicit observation, not a machine-sensitive timing gate in the normal suite.
    /// Fixture setup and the data-preservation audit are outside the measured interval.
    #[tokio::test]
    #[ignore = "explicit nonempty migration cost observation"]
    async fn nonempty_schema11_migration_cost_is_separate_from_current_reads() -> Result<()> {
        use sea_orm::TransactionTrait as _;
        for count in [100_u64, 20_000] {
            let (_dir, db) = source().await?;
            let tx = db.begin().await?;
            for seq in 1..=count {
                let id = format!("old-{seq}");
                let kind = if seq % 2 == 0 { "tool" } else { "text" };
                tx.execute_raw(statement(
                    "INSERT INTO timeline_records(append_seq,record_id,turn_id,kind,payload)
                 VALUES(?,?,'a:b',?,?)",
                    vec![
                        integer(seq)?.into(),
                        id.clone().into(),
                        kind.into(),
                        record(&id, seq, kind)?.into(),
                    ],
                ))
                .await?;
            }
            tx.commit().await?;
            assert_eq!(version(&db).await?, 11);
            let started = std::time::Instant::now();
            prepare(&db, THREAD, Preparation::Schema, None).await?;
            let migration_us = started.elapsed().as_micros();
            assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
            assert_eq!(conversation::latest_append_seq(&db).await?, count);
            let mismatch: i64 = db
            .query_one_raw(statement(
                "SELECT count(*) AS n FROM timeline_records old
                 LEFT JOIN conversation_items new ON new.seq=old.append_seq
                 WHERE new.item_id IS NULL OR new.item_id<>old.record_id
                    OR new.query_class<>CASE WHEN old.kind='tool' THEN 'activity' ELSE 'conversation' END",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "n")?;
            assert_eq!(mismatch, 0);
            for seq in [1, count] {
                let item = conversation::read_item(&db, &format!("old-{seq}"))
                    .await?
                    .unwrap();
                let payload: serde_json::Value = serde_json::from_slice(&item.payload)?;
                assert_eq!(payload["data"]["oldUnknown"]["opaque"], "原文 🦀");
                let content = item
                    .contents
                    .values()
                    .find(|content| content.descriptor.key.key == "tool.result")
                    .unwrap();
                assert_eq!(
                    content
                        .data
                        .range(0, content.descriptor.byte_length as usize)?
                        .as_bytes(),
                    "公开原文 🦀".as_bytes()
                );
            }
            println!(
                "{}",
                serde_json::json!({
                    "observation": "schema11_to_current",
                    "sourceRows": count,
                    "sourceSchema": 11,
                    "targetSchema": HISTORY_SCHEMA_VERSION,
                    "migrationMicros": migration_us,
                    "identityOrScopeMismatches": mismatch,
                })
            );
            db.close().await?;
        }
        Ok(())
    }

    fn record(id: &str, seq: u64, kind: &str) -> Result<String> {
        Ok(serde_json::to_string(&serde_json::json!({
            "itemId":id,"appendSeq":seq,"turnId":"a:b","sourceEffectSeq":null,"sealedAt":null,
            "meta":serde_json::to_vec(&serde_json::json!({
                "id":id,"threadId":THREAD,"turnId":"a:b",
                "descriptor":{"kind":kind,"data":{"oldUnknown":{"opaque":"原文 🦀"}}}
            }))?,
            "fields":[{"identity":{"kind":"host","value":"tool.result"},"text":"公开原文 🦀"}]
        }))?)
    }

    /// Inspect the published schema-12 representation without invoking a current-format reader.
    async fn published_item(db: &DatabaseConnection, id: &str) -> Result<pl_core::chat::ChatItem> {
        let row = db.query_one_raw(statement(
        "SELECT seq,item_id,query_class,parent_id,payload FROM conversation_items WHERE item_id=?",
        vec![id.into()],
    )).await?.context("published item missing")?;
        let mut draft = pl_core::chat::ChatDraft::new(
            row.try_get::<String>("", "item_id")?,
            row.try_get::<String>("", "query_class")?,
            std::sync::Arc::from(row.try_get::<Vec<u8>>("", "payload")?),
        );
        draft.parent_id = row
            .try_get::<Option<String>>("", "parent_id")?
            .map(pl_core::chat::ChatKey::from_encoded)
            .transpose()?;
        draft.contents = std::sync::Arc::new(conversation::read_contents(db, id).await?);
        Ok(pl_core::chat::ChatItem::complete(
            draft,
            u64::try_from(row.try_get::<i64>("", "seq")?)?,
        ))
    }

    async fn insert(
        db: &DatabaseConnection,
        id: &str,
        seq: u64,
        kind: &str,
        payload: &str,
    ) -> Result<()> {
        db.execute_raw(statement(
        "INSERT INTO timeline_records(append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload)
         VALUES(?,?,'a:b',NULL,NULL,?,?)",
        vec![integer(seq)?.into(), id.into(), kind.into(), payload.into()],
    )).await?;
        Ok(())
    }

    #[tokio::test]
    async fn formal_schema12_preserves_nonempty_unknown_records_and_identity() -> Result<()> {
        let (_dir, db) = source().await?;
        let original = record("old-tool", 1, "tool")?;
        insert(&db, "old-tool", 1, "tool", &original).await?;
        let mut malformed: serde_json::Value =
            serde_json::from_str(&record("bad-meta", 2, "tool")?)?;
        malformed["meta"] = serde_json::json!([255, 254, 0]);
        let malformed = serde_json::to_string(&malformed)?;
        insert(&db, "bad-meta", 2, "tool", &malformed).await?;
        insert(&db, "neighbor", 3, "text", &record("neighbor", 3, "text")?).await?;
        let before: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "database_id")?;
        prepare_published12(&db).await?;
        assert_eq!(version(&db).await?, 12);
        let item = published_item(&db, "old-tool").await?;
        assert_eq!(item.header.append_seq, 1);
        assert_eq!(item.header.query_class, "activity");
        assert_eq!(
            item.header.parent_id,
            Some(pl_core::chat::ChatKey::new("turn", "a:b")?)
        );
        let payload: serde_json::Value = serde_json::from_slice(&item.payload)?;
        assert_eq!(payload["data"]["oldUnknown"]["opaque"], "原文 🦀");
        assert!(payload["data"].get("presentationContract").is_none());
        assert_eq!(conversation::latest_append_seq(&db).await?, 3);
        let unsupported = published_item(&db, "bad-meta").await?;
        let content = unsupported.contents.values().next().unwrap();
        assert_eq!(content.descriptor.key.key, "legacy.record");
        assert_eq!(
            content.data.range(0, malformed.len())?.as_bytes(),
            malformed.as_bytes()
        );
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT payload FROM timeline_records WHERE record_id='old-tool'",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "payload")?,
            original
        );
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "database_id")?,
            before
        );
        assert!(!fixture_current(&db).await?.execution_present);
        prepare_published12(&db).await?;
        assert_eq!(conversation::latest_append_seq(&db).await?, 3);
        Ok(())
    }

    #[tokio::test]
    async fn formal_migration_rolls_back_all_outputs_and_bookkeeping_then_retries() -> Result<()> {
        let (_dir, db) = source().await?;
        let first = record("one", 1, "text")?;
        insert(&db, "one", 1, "text", &first).await?;
        insert(&db, "wrong-index", 2, "tool", &record("two", 2, "tool")?).await?;
        assert!(prepare_published12(&db).await.is_err());
        assert_eq!(version(&db).await?, 11);
        for table in [
            "conversation_items",
            "conversation_contents",
            "conversation_content_chunks",
            "conversation_view_state",
            "conversation_view_entries",
        ] {
            assert!(!SchemaManager::new(&db).has_table(table).await?);
        }
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![DEMAND_CONVERSATION.into()],
            ))
            .await?
            .is_none()
        );
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT payload FROM timeline_records WHERE append_seq=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "payload")?,
            first
        );
        db.execute_unprepared("UPDATE timeline_records SET record_id='two' WHERE append_seq=2")
            .await?;
        prepare_published12(&db).await?;
        assert_eq!(version(&db).await?, 12);
        assert_eq!(conversation::latest_append_seq(&db).await?, 2);
        Ok(())
    }

    #[tokio::test]
    async fn formal_migration_rejects_malformed_nullable_provenance_and_retries() -> Result<()> {
        use serde_json::{Value as Json, json};

        let cases = [
            ("sourceEffectSeq", json!("damaged")),
            ("sourceEffectSeq", json!(-1)),
            ("sourceEffectSeq", json!(1.5)),
            ("sourceEffectSeq", json!(u64::MAX)),
            (
                "sourceEffectSeq",
                serde_json::from_str::<Json>("18446744073709551616")?,
            ),
            ("turnId", json!(123)),
            ("turnId", json!(true)),
            ("sealedAt", json!("damaged")),
            ("sealedAt", json!(false)),
            ("sealedAt", json!(i64::MAX as u64 + 1)),
            (
                "sealedAt",
                serde_json::from_str::<Json>("-9223372036854775809")?,
            ),
            ("sealedAt", json!(1.5)),
        ];
        for (index, (field, value)) in cases.iter().enumerate() {
            let (_dir, db) = source().await?;
            let first = record("neighbor", 1, "text")?;
            insert(&db, "neighbor", 1, "text", &first).await?;
            let mut container = json!({
                "itemId":"damaged","appendSeq":2,
                "turnId":null,"sourceEffectSeq":null,"sealedAt":null,
                "meta":serde_json::to_vec(&json!({
                    "id":"damaged","threadId":THREAD,
                    "descriptor":{"kind":"tool","data":{"unknown":"保留原文 🦀"}}
                }))?,
                "fields":[{"identity":{"kind":"host","value":"tool.result"},"text":"公开原文 🦀"}]
            });
            container[*field] = value.clone();
            let malformed = serde_json::to_string(&container)?;
            db.execute_raw(statement(
            "INSERT INTO timeline_records(append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload)
             VALUES(2,'damaged',NULL,NULL,NULL,'tool',?)",
            vec![malformed.clone().into()],
        )).await?;
            let applied = db
                .query_all_raw(statement(
                    "SELECT version FROM seaql_migrations ORDER BY version",
                    vec![],
                ))
                .await?
                .into_iter()
                .map(|row| row.try_get::<String>("", "version"))
                .collect::<std::result::Result<Vec<_>, _>>()?;

            let error = prepare_published12(&db)
                .await
                .expect_err("malformed optional provenance must not compare equal to a NULL index");
            let diagnostic = format!("{error:#}");
            assert!(
                diagnostic.contains("provenance") || diagnostic.contains("sourceEffectSeq"),
                "{field}={value}: {diagnostic}"
            );
            assert_eq!(version(&db).await?, 11);
            for table in [
                "conversation_items",
                "conversation_contents",
                "conversation_content_chunks",
                "conversation_view_state",
                "conversation_view_entries",
            ] {
                assert!(
                    !SchemaManager::new(&db).has_table(table).await?,
                    "{field}={value}: {table}"
                );
            }
            let after = db
                .query_all_raw(statement(
                    "SELECT version FROM seaql_migrations ORDER BY version",
                    vec![],
                ))
                .await?
                .into_iter()
                .map(|row| row.try_get::<String>("", "version"))
                .collect::<std::result::Result<Vec<_>, _>>()?;
            assert_eq!(
                after, applied,
                "failed migration must publish no SeaORM record"
            );
            assert!(!after.iter().any(|name| name == DEMAND_CONVERSATION));
            let original = db
                .query_all_raw(statement(
                    "SELECT payload FROM timeline_records ORDER BY append_seq",
                    vec![],
                ))
                .await?
                .into_iter()
                .map(|row| row.try_get::<String>("", "payload"))
                .collect::<std::result::Result<Vec<_>, _>>()?;
            assert_eq!(
                original,
                [first, malformed],
                "all source bytes must survive rollback"
            );

            // Repair only the offending header in this original database. Missing and explicit NULL
            // are both published optional-field representations and must remain legal.
            if index % 2 == 0 {
                container.as_object_mut().unwrap().remove(*field);
            } else {
                container[*field] = Json::Null;
            }
            let corrected = serde_json::to_string(&container)?;
            db.execute_raw(statement(
                "UPDATE timeline_records SET payload=? WHERE record_id='damaged'",
                vec![corrected.clone().into()],
            ))
            .await?;
            prepare_published12(&db).await?;
            assert_eq!(version(&db).await?, 12);
            assert_eq!(conversation::latest_append_seq(&db).await?, 2);
            assert!(
                db.query_one_raw(statement(
                    "SELECT 1 FROM seaql_migrations WHERE version=?",
                    vec![DEMAND_CONVERSATION.into()],
                ))
                .await?
                .is_some()
            );
            let migrated = published_item(&db, "damaged").await?;
            let retained = migrated
                .contents
                .values()
                .find(|content| content.descriptor.key.key == "legacy.record")
                .context("original unknown tool container must remain declared content")?;
            assert_eq!(
                retained.data.range(0, corrected.len())?.as_bytes(),
                corrected.as_bytes()
            );
        }
        eprintln!(
            "formal nullable provenance: {} malformed NULL-index cases rolled back and retried; missing/null repairs both accepted",
            cases.len()
        );
        Ok(())
    }

    #[tokio::test]
    async fn formal_current_entries_validate_one_ordered_composite_unique_constraint() -> Result<()>
    {
        let (_dir, db) = source().await?;
        prepare_published12(&db).await?;
        let db = &db;
        assert_eq!(
            version(db).await?,
            12,
            "the published current-entry layout is checked at its own migration boundary"
        );
        for (collection, position, id) in [("a", 1i64, "same"), ("a", 2, "other"), ("b", 1, "same")]
        {
            db.execute_raw(statement(
            "INSERT INTO conversation_view_entries(collection,position,entry_id,payload) VALUES(?,?,?,?)",
            vec![collection.into(), position.into(), id.into(), b"{}".to_vec().into()],
        )).await?;
        }
        assert!(db.execute_raw(statement(
        "INSERT INTO conversation_view_entries(collection,position,entry_id,payload) VALUES('a',3,'same',?)",
        vec![b"{}".to_vec().into()],
    )).await.is_err(), "only the same collection + entry identity conflicts");
        validate_tables(db).await?;

        let valid_columns = "collection TEXT NOT NULL,position INTEGER NOT NULL,entry_id TEXT NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(collection,position)";
        for (name, ddl) in [
        ("absent", format!("CREATE TABLE conversation_view_entries({valid_columns}) WITHOUT ROWID")),
        ("reversed", format!("CREATE TABLE conversation_view_entries({valid_columns},UNIQUE(entry_id,collection)) WITHOUT ROWID")),
        ("descending", format!("CREATE TABLE conversation_view_entries({valid_columns},UNIQUE(collection DESC,entry_id)) WITHOUT ROWID")),
        ("nocase", format!("CREATE TABLE conversation_view_entries({valid_columns},UNIQUE(collection,entry_id COLLATE NOCASE)) WITHOUT ROWID")),
        ("nullable", "CREATE TABLE conversation_view_entries(collection TEXT NOT NULL,position INTEGER NOT NULL,entry_id TEXT,payload BLOB NOT NULL,PRIMARY KEY(collection,position),UNIQUE(collection,entry_id)) WITHOUT ROWID".into()),
        ("singles", "CREATE TABLE conversation_view_entries(collection TEXT NOT NULL UNIQUE,position INTEGER NOT NULL,entry_id TEXT NOT NULL UNIQUE,payload BLOB NOT NULL,PRIMARY KEY(collection,position)) WITHOUT ROWID".into()),
        ("partial", format!("CREATE TABLE conversation_view_entries({valid_columns}) WITHOUT ROWID; CREATE UNIQUE INDEX damaged_entry_unique ON conversation_view_entries(collection,entry_id) WHERE position>=0")),
        ("expression", format!("CREATE TABLE conversation_view_entries({valid_columns}) WITHOUT ROWID; CREATE UNIQUE INDEX damaged_entry_unique ON conversation_view_entries(collection,lower(entry_id))")),
    ] {
        db.execute_unprepared("DROP TABLE conversation_view_entries").await?;
        db.execute_unprepared(&ddl).await?;
        assert!(validate_tables(db).await.is_err(), "damaged {name} constraint must fail closed");
    }
        Ok(())
    }

    #[tokio::test]
    async fn future_schema_is_refused_without_mutating_source() -> Result<()> {
        let (_dir, db) = source().await?;
        db.execute_unprepared("UPDATE history_meta SET schema_version=99")
            .await?;
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(version(&db).await?, 99);
        assert!(
            !SchemaManager::new(&db)
                .has_table("conversation_items")
                .await?
        );
        Ok(())
    }

    unsafe extern "C" fn deny_quick_check(
        _: *mut std::ffi::c_void,
        action: i32,
        argument: *const std::ffi::c_char,
        _: *const std::ffi::c_char,
        _: *const std::ffi::c_char,
        _: *const std::ffi::c_char,
    ) -> i32 {
        if action == libsqlite3_sys::SQLITE_PRAGMA && !argument.is_null() {
            // SAFETY: SQLite supplies a live NUL-terminated action argument for this callback.
            // It is inspected synchronously and neither retained nor passed across threads.
            if unsafe { std::ffi::CStr::from_ptr(argument) }
                .to_bytes()
                .eq_ignore_ascii_case(b"quick_check")
            {
                return libsqlite3_sys::SQLITE_DENY;
            }
        }
        libsqlite3_sys::SQLITE_OK
    }

    #[tokio::test]
    async fn current_admission_neither_quick_checks_nor_decodes_recovery_checkpoint() -> Result<()>
    {
        let (_dir, db) = source().await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        let checkpoint = pl_core::thread::ThreadCheckpoint::capture(
            THREAD.into(),
            0,
            pl_core::thread::ThreadSnapshot::default(),
        )?;
        checkpoint::write(&db, &checkpoint, None, None).await?;
        db.execute_unprepared(
            "UPDATE session_checkpoint SET payload='{\"schemaVersion\":999}' WHERE id=1",
        )
        .await?;
        {
            let mut connection = db.get_sqlite_connection_pool().acquire().await?;
            let mut handle = connection.lock_handle().await?;
            // SAFETY: the SQLx handle excludes its worker while installing the callback. The callback
            // is a static function, has no borrowed user data, and remains valid until SQLite closes
            // this connection, including error/cancellation paths. It never reenters SQLite.
            let result = unsafe {
                libsqlite3_sys::sqlite3_set_authorizer(
                    handle.as_raw_handle().as_ptr(),
                    Some(deny_quick_check),
                    std::ptr::null_mut(),
                )
            };
            assert_eq!(result, libsqlite3_sys::SQLITE_OK);
        }
        assert!(
            db.query_all_raw(statement("PRAGMA quick_check", vec![]))
                .await
                .is_err()
        );
        super::super::super::validate_existing(&db, THREAD).await?;
        assert!(
            checkpoint::read(&db, THREAD).await.is_err(),
            "explicit recovery still validates the sentinel"
        );
        Ok(())
    }

    #[tokio::test]
    async fn production_batch_commits_context_completions_and_current_as_one_prefix() -> Result<()>
    {
        use pl_core::{
            context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
            thread::{ThreadCheckpoint, ThreadEffectBatch, ThreadSnapshot, journal::ContextChange},
        };
        let dir = tempfile::tempdir()?;
        let store = HistoryStore::open(&dir.path().join("history.sqlite"), THREAD).await?;
        let _writer = store.writer().await?;
        let record = |id: &str| ContextRecord {
            id: id.into(),
            turn_id: None,
            source: ContextSource::Instruction,
            content: vec![ContextContent::Text {
                text: Arc::from(id),
            }],
            tool_calls: vec![],
        };
        let first_record = record("one");
        let second_record = record("two");
        let first_state = ThreadSnapshot {
            commit_sequence: 1,
            context: ContextSnapshot {
                revision: 1,
                records: vec![first_record.clone()].into(),
            },
            ..Default::default()
        };
        let second_state = ThreadSnapshot {
            commit_sequence: 2,
            context: ContextSnapshot {
                revision: 2,
                records: vec![first_record.clone(), second_record.clone()].into(),
            },
            ..Default::default()
        };
        let mut first = ThreadCheckpoint::capture(THREAD.into(), 1, first_state)?;
        let mut second = ThreadCheckpoint::capture(THREAD.into(), 2, second_state)?;
        for (checkpoint, revision, model) in [
            (&mut first, 1, "first-model"),
            (&mut second, 2, "second-model"),
        ] {
            checkpoint.state.extensions.insert(
                crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
                pl_core::thread::extensions::ExtensionRecord {
                    revision,
                    payload: crate::studio::model_route::encode(
                        &pl_model::config::ModelRouteConfig {
                            account_id: pl_model::config::AccountId::new("batch-account")?,
                            model_id: model.into(),
                            effort: None,
                        },
                    )?,
                },
            );
            checkpoint.state.extension_sequence = revision;
        }
        let e1 = ThreadEffectBatch {
            thread_id: THREAD.into(),
            sequence: 1,
            context: Some(ContextChange::Append {
                revision: 1,
                records: vec![first_record].into(),
            }),
            ..Default::default()
        };
        let e2 = ThreadEffectBatch {
            thread_id: THREAD.into(),
            sequence: 2,
            context: Some(ContextChange::Append {
                revision: 2,
                records: vec![second_record].into(),
            }),
            ..Default::default()
        };
        let a1 = crate::studio::thread_projection::PreparedAccounting::prepare(&e1)?;
        let a2 = crate::studio::thread_projection::PreparedAccounting::prepare(&e2)?;
        a1.fold_into(&mut first.state.usage_summary);
        second.state.usage_summary = first.state.usage_summary.clone();
        a2.fold_into(&mut second.state.usage_summary);
        let c1 = super::super::super::test_current(1);
        let c2 = super::super::super::test_current(2);
        let empty = std::collections::BTreeSet::new();
        let completion = |id: &str, seq| {
            let mut draft =
                pl_core::chat::ChatDraft::new(id, "conversation", Arc::from(b"{}".as_slice()));
            draft.metadata = super::super::super::conversation::tests::metadata(id);

            Arc::new(pl_core::chat::ChatItem::complete(draft, seq))
        };
        let completions1 = [completion("first", 1)];
        let completions2 = [completion("second", 2)];
        fn history<'a>(
            current: &'a crate::studio::storage::history::conversation::current::PreparedCurrent,
            completions: &'a [Arc<pl_core::chat::ChatItem>],
            empty: &'a std::collections::BTreeSet<String>,
        ) -> EffectCommit<'a> {
            EffectCommit {
                turns: &[],
                execution_order: 0,
                completions,
                current,
                rolled_back_turns: empty,
                identities: &[],
                messages: &[],
                receipts: &[],
                tasks: &[],
                deliveries: &[],
                delivery_repairs: &[],
                attempt: None,
            }
        }
        let effects = [
            CheckpointEffect {
                checkpoint: &first,
                effect: &e1,
                history: history(&c1, &completions1, &empty),
                accounting: AccountingCommit {
                    facts: &a1,
                    material_changed: false,
                },
            },
            CheckpointEffect {
                checkpoint: &second,
                effect: &e2,
                history: history(&c2, &completions2, &empty),
                accounting: AccountingCommit {
                    facts: &a2,
                    material_changed: false,
                },
            },
        ];
        store.writer().await?.db.execute_unprepared(
        "CREATE TRIGGER reject_second BEFORE UPDATE ON history_meta
         WHEN NEW.applied_write_seq=2 BEGIN SELECT RAISE(ABORT,'controlled second effect rejection'); END",
    ).await?;
        assert!(store.commit_checkpoint_effects(&effects).await.is_err());
        assert_eq!(store.watermark().await?, 0);
        assert_eq!(store.publication_seed().await?.head_seq, 0);
        assert!(store.checkpoint().await?.is_none());
        assert!(
            checkpoint::read_model_route_head(&store.reader().await?.unwrap().db)
                .await?
                .is_none()
        );
        assert_eq!(
            store
                .cold_current_state()
                .await?
                .context("cold domain state")?
                .projection()
                .source_effect_seq,
            0
        );
        store
            .writer()
            .await?
            .db
            .execute_unprepared("DROP TRIGGER reject_second")
            .await?;
        assert_eq!(store.commit_checkpoint_effects(&effects).await?.len(), 2);
        assert_eq!(store.watermark().await?, 2);
        let head = checkpoint::read_model_route_head(&store.reader().await?.unwrap().db)
            .await?
            .unwrap();
        assert_eq!(head.revision, 2);
        assert_eq!(head.route.model_id, "second-model");
        assert_eq!(store.publication_seed().await?.head_seq, 2);
        assert_eq!(
            store
                .checkpoint()
                .await?
                .unwrap()
                .state
                .context
                .records
                .len(),
            2
        );
        assert_eq!(
            store
                .cold_current_state()
                .await?
                .context("cold domain state")?
                .projection()
                .source_effect_seq,
            2
        );
        assert_eq!(store.commit_checkpoint_effects(&effects).await?.len(), 2);
        Ok(())
    }
}
