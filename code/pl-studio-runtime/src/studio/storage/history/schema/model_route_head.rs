//! Schema 12 → 13: prepare historical route/Profile encodings and project the checkpoint head.
use super::*;

pub(super) struct RootModelRouteHead {
    pub(super) thread_id: String,
}

impl MigrationName for RootModelRouteHead {
    fn name(&self) -> &str {
        MODEL_ROUTE_HEAD
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for RootModelRouteHead {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let result: anyhow::Result<()> = async {
            ensure!(
                version(db).await? == 12,
                "model route head migration requires schema 12"
            );
            demand_conversation::validate_tables(db).await?;
            validate_source(db).await?;
            // Reuse all canonical hash, identity, context and fence validation. Only this
            // explicit migration reads the full checkpoint to backfill the narrow head.
            let original = checkpoint::read(db, &self.thread_id).await?;
            db.execute_unprepared(
                "ALTER TABLE history_meta ADD COLUMN model_route_json TEXT NULL;
                 ALTER TABLE history_meta ADD COLUMN model_route_hash TEXT NULL",
            )
            .await?;
            if let Some(original) = original {
                let mut migrated = original.clone();
                crate::studio::model_route::migration::upgrade(&mut migrated.state)?;
                checkpoint::write_representation(db, &original, &migrated).await?;
                checkpoint::write_model_route_head(db, &migrated.state).await?;
            }
            validate_tables(db).await?;
            checkpoint::read_model_route_head(db).await?;
            set_version(db, 13).await?;
            Ok(())
        }
        .await;
        result.map_err(conversion)
    }
}

pub(super) async fn validate_source(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        db.query_all_raw(statement(
            "SELECT name FROM pragma_table_info('history_meta')
             WHERE name IN ('model_route_json','model_route_hash')",
            vec![],
        ))
        .await?
        .is_empty(),
        "pending model route head migration has pre-existing output columns; existing data preserved"
    );
    Ok(())
}

/// Shape admission never selects the recovery payload or context rows.
pub(super) async fn validate_tables(db: &impl ConnectionTrait) -> Result<()> {
    db.query_all_raw(statement(
        "SELECT model_route_json,model_route_hash FROM history_meta LIMIT 0",
        vec![],
    ))
    .await?;
    let columns = db
        .query_all_raw(statement(
            "SELECT name,type,\"notnull\" FROM pragma_table_info('history_meta')
             WHERE name IN ('model_route_json','model_route_hash')",
            vec![],
        ))
        .await?;
    ensure!(columns.len() == 2, "model route head columns are missing");
    for column in columns {
        ensure!(
            column
                .try_get::<String>("", "type")?
                .eq_ignore_ascii_case("TEXT")
                && column.try_get::<i64>("", "notnull")? == 0,
            "model route head columns must be nullable TEXT"
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::model_route;
    use pl_core::{
        context::{
            ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload,
            content_hash,
        },
        thread::{ThreadCheckpoint, ThreadSnapshot, extensions::ExtensionRecord},
    };

    const THREAD: &str = "model-route-head";

    struct Published12;
    impl MigratorTraitSelf for Published12 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            Migrator {
                thread_id: THREAD.into(),
                bot_root: None,
                execution_identity: None,
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

    async fn source() -> Result<(tempfile::TempDir, DatabaseConnection)> {
        let dir = tempfile::tempdir()?;
        let db = super::super::super::connect(
            &dir.path().join("history.sqlite"),
            crate::studio::paths::SqliteFileMode::Create,
        )
        .await?;
        let steps = Published12
            .migrations()
            .iter()
            .take_while(|step| !is_lifecycle_migration(step.name()))
            .count();
        Published12.up(&db, Some(u32::try_from(steps)?)).await?;
        assert_eq!(version(&db).await?, 12);
        Ok((dir, db))
    }

    fn legacy_checkpoint() -> Result<ThreadCheckpoint> {
        let mut state = ThreadSnapshot {
            commit_sequence: 9,
            extension_sequence: 7,
            context: ContextSnapshot {
                revision: 4,
                records: vec![ContextRecord {
                    id: "original-context".into(),
                    turn_id: None,
                    source: ContextSource::Instruction,
                    content: vec![ContextContent::Text {
                        text: std::sync::Arc::from("原上下文 🦀"),
                    }],
                    tool_calls: vec![],
                }]
                .into(),
            },
            ..Default::default()
        };
        for (id, revision, payload) in [
            (
                model_route::MODEL_ROUTE_EXTENSION,
                7,
                OpaquePayload::new(
                    model_route::MODEL_ROUTE_FORMAT,
                    1,
                    r#"{"provider":"saved-account","model":"original-model","effort":"high"}"#,
                )?,
            ),
            (
                model_route::BOT_OWNER_EXTENSION,
                5,
                model_route::encode_bot_owner("original-bot")?,
            ),
            (
                model_route::AGENT_PROFILE_EXTENSION,
                6,
                OpaquePayload::new(
                    model_route::AGENT_PROFILE_FORMAT,
                    1,
                    serde_json::json!({
                        "profileId":"reviewer","displayName":"Reviewer","description":"",
                        "whenToUse":"","systemInstructions":"","providerId":"saved-account",
                        "model":"profile-model","effort":"high","source":"config","revision":"1",
                        "contentHash":"","system":true,"enabled":true,"workspaceMode":"unrestricted"
                    })
                    .to_string(),
                )?,
            ),
        ] {
            state
                .extensions
                .insert(id.into(), ExtensionRecord { revision, payload });
        }
        Ok(ThreadCheckpoint::capture(THREAD.into(), 9, state)?)
    }

    async fn seed(db: &DatabaseConnection) -> Result<()> {
        write_published_checkpoint(db, &legacy_checkpoint()?).await?;
        db.execute_unprepared("UPDATE history_meta SET applied_write_seq=9")
            .await?;
        Ok(())
    }

    async fn retained(db: &DatabaseConnection) -> Result<Vec<String>> {
        let mut facts = Vec::new();
        for sql in [
            "SELECT json_array(database_id,thread_id,applied_write_seq) AS fact FROM history_meta",
            "SELECT json_array(ordinal,record_id,payload,payload_hash) AS fact FROM current_context ORDER BY ordinal",
            "SELECT json_array(ordinal,item_id,payload,last_write_seq) AS fact FROM history_items ORDER BY ordinal",
            "SELECT json_array(append_seq,record_id,payload) AS fact FROM timeline_records ORDER BY append_seq",
            "SELECT json_array(seq,item_id,typeof(payload),hex(payload)) AS fact FROM conversation_items ORDER BY seq",
        ] {
            for row in db.query_all_raw(statement(sql, vec![])).await? {
                facts.push(row.try_get("", "fact")?);
            }
        }
        Ok(facts)
    }

    #[tokio::test]
    async fn schema12_preserves_checkpoint_route_revision_owner_and_recovery_facts() -> Result<()> {
        let (dir, db) = source().await?;
        seed(&db).await?;
        let store = HistoryStore::open(&dir.path().join("history.sqlite"), THREAD).await?;
        let mut item = pl_protocol::ThreadItem::completed_user_message(
            "original-message".into(),
            THREAD.into(),
            String::new(),
            "原历史正文 🦀".into(),
            vec![],
            17,
        );
        item.ordinal = 1;
        item.revision = 1;
        store.upsert_item(&db, 9, item).await?;
        let completion = pl_core::chat::ChatItem::complete(
            pl_core::chat::ChatDraft::new(
                "original-message",
                "conversation",
                std::sync::Arc::from(b"{\"unknownProducer\":\"retained\"}".as_slice()),
            ),
            1,
            None,
        );
        super::super::super::conversation::migration::append_published(&db, &completion).await?;
        let before = retained(&db).await?;
        let mut expected = checkpoint::read(&db, THREAD).await?.unwrap();
        assert!(model_route::saved(&legacy_checkpoint()?.state).is_err());
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
        assert_eq!(retained(&db).await?, before);
        let recovered = checkpoint::read(&db, THREAD).await?.unwrap();
        model_route::migration::upgrade(&mut expected.state)?;
        assert_eq!(
            serde_json::to_value(&recovered)?,
            serde_json::to_value(expected)?
        );
        let head = checkpoint::read_model_route_head(&db).await?.unwrap();
        assert_eq!(head.revision, 7);
        assert_eq!(head.bot_id.as_deref(), Some("original-bot"));
        assert_eq!(head.route.account_id.as_str(), "saved-account");
        assert_eq!(head.route.model_id, "original-model");
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT count(*) AS count FROM pragma_table_info('history_meta')
             WHERE name IN ('model_route_json','model_route_hash')",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<i64>("", "count")?,
            2
        );
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT count(*) AS count FROM pragma_table_info('session_checkpoint')
             WHERE name IN ('model_route_json','model_route_hash')",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<i64>("", "count")?,
            0,
            "the narrow head must not share the recovery payload record"
        );
        assert_eq!(
            recovered.state.extensions[model_route::AGENT_PROFILE_EXTENSION].revision,
            6
        );
        assert_eq!(
            recovered.state.extensions[model_route::AGENT_PROFILE_EXTENSION]
                .payload
                .version(),
            2
        );
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![MODEL_ROUTE_HEAD.into()],
            ))
            .await?
            .is_some()
        );
        // This remains content preparation, not model/execution owner preparation.
        assert!(
            Migrator {
                thread_id: THREAD.into(),
                bot_root: None,
                execution_identity: None
            }
            .get_pending_migrations_read_only(&db)
            .await?
            .iter()
            .any(|step| step.name() == MODEL_ACCESS)
        );
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        Ok(())
    }

    #[tokio::test]
    async fn current_representation_changes_and_checkpoint_route_removal_update_the_same_head()
    -> Result<()> {
        let (_dir, db) = source().await?;
        seed(&db).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        let original = checkpoint::read(&db, THREAD).await?.unwrap();
        let mut migrated = original.clone();
        migrated.state.extensions.insert(
            model_route::BOT_OWNER_EXTENSION.into(),
            ExtensionRecord {
                revision: 8,
                payload: model_route::encode_bot_owner("replacement-bot")?,
            },
        );
        migrated.state.extension_sequence = 8;
        let tx = db.begin().await?;
        checkpoint::write_representation(&tx, &original, &migrated).await?;
        assert_eq!(
            checkpoint::read_model_route_head(&tx)
                .await?
                .unwrap()
                .bot_id
                .as_deref(),
            Some("replacement-bot")
        );
        tx.rollback().await?;
        assert_eq!(
            checkpoint::read_model_route_head(&db)
                .await?
                .unwrap()
                .bot_id
                .as_deref(),
            Some("original-bot")
        );
        let tx = db.begin().await?;
        migrated
            .state
            .extensions
            .remove(model_route::MODEL_ROUTE_EXTENSION);
        checkpoint::write(&tx, &migrated, None, None).await?;
        assert!(checkpoint::read_model_route_head(&tx).await?.is_none());
        tx.commit().await?;
        let saved = checkpoint::read(&db, THREAD).await?.unwrap();
        assert!(model_route::saved(&saved.state)?.is_none());
        assert!(checkpoint::read_model_route_head(&db).await?.is_none());
        Ok(())
    }

    #[tokio::test]
    async fn schema12_failed_head_backfill_rolls_back_encoding_columns_version_and_retries()
    -> Result<()> {
        let (_dir, db) = source().await?;
        seed(&db).await?;
        let before = retained(&db).await?;
        let original: String = db
            .query_one_raw(statement(
                "SELECT payload FROM session_checkpoint WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "payload")?;
        // Fail after ALTER and representation conversion, not merely before the first write.
        db.execute_unprepared(
            "CREATE TRIGGER reject_head BEFORE UPDATE ON history_meta
         WHEN NEW.schema_version=OLD.schema_version
         BEGIN SELECT RAISE(ABORT,'controlled head backfill failure'); END",
        )
        .await?;
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(version(&db).await?, 12);
        assert_eq!(retained(&db).await?, before);
        validate_source(&db).await?;
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT payload FROM session_checkpoint WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "payload")?,
            original
        );
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![MODEL_ROUTE_HEAD.into()],
            ))
            .await?
            .is_none()
        );
        db.execute_unprepared("DROP TRIGGER reject_head").await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
        assert_eq!(
            checkpoint::read_model_route_head(&db)
                .await?
                .unwrap()
                .revision,
            7
        );
        Ok(())
    }

    #[tokio::test]
    async fn schema12_rejects_bad_checkpoint_hash_identity_fence_and_route_without_advancing()
    -> Result<()> {
        for damage in ["hash", "identity", "fence", "route"] {
            let (_dir, db) = source().await?;
            seed(&db).await?;
            let row = db
                .query_one_raw(statement(
                    "SELECT payload,payload_hash FROM session_checkpoint WHERE id=1",
                    vec![],
                ))
                .await?
                .unwrap();
            let original: String = row.try_get("", "payload")?;
            let original_hash: String = row.try_get("", "payload_hash")?;
            let mut raw: serde_json::Value = serde_json::from_str(&original)?;
            match damage {
                "identity" => raw["threadId"] = "another-thread".into(),
                "fence" => raw["historyFence"] = 8.into(),
                "route" => {
                    raw["state"]["extensions"][model_route::MODEL_ROUTE_EXTENSION]["payload"]["content"] =
                        "{".into()
                }
                _ => {}
            }
            let damaged = serde_json::to_string(&raw)?;
            let hash = if damage == "hash" {
                "wrong-hash".into()
            } else {
                content_hash(damaged.as_bytes())
            };
            db.execute_raw(statement(
                "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
                vec![damaged.clone().into(), hash.into()],
            ))
            .await?;
            assert!(
                prepare(&db, THREAD, Preparation::Schema, None)
                    .await
                    .is_err(),
                "{damage}"
            );
            assert_eq!(version(&db).await?, 12);
            validate_source(&db).await?;
            assert_eq!(
                db.query_one_raw(statement(
                    "SELECT payload FROM session_checkpoint WHERE id=1",
                    vec![],
                ))
                .await?
                .unwrap()
                .try_get::<String>("", "payload")?,
                damaged
            );
            db.execute_raw(statement(
                "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
                vec![original.into(), original_hash.into()],
            ))
            .await?;
            prepare(&db, THREAD, Preparation::Schema, None).await?;
            assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
        }
        Ok(())
    }

    async fn cold(store: &HistoryStore) -> Result<ColdStateFacet> {
        store
            .cold_state_facet()
            .await?
            .context("cold State missing")
    }

    #[tokio::test]
    async fn current_cold_head_ignores_recovery_bodies_but_rejects_bad_head_without_fallback()
    -> Result<()> {
        let (dir, db) = source().await?;
        seed(&db).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        let original = db
            .query_one_raw(statement(
                "SELECT payload FROM session_checkpoint WHERE id=1",
                vec![],
            ))
            .await?
            .context("original checkpoint")?
            .try_get::<String>("", "payload")?;
        let store = HistoryStore::open(&dir.path().join("history.sqlite"), THREAD).await?;
        let saved = cold(&store).await?.model_route.unwrap();
        assert_eq!(saved.revision, 7);
        assert_eq!(saved.bot_id.as_deref(), Some("original-bot"));
        db.execute_unprepared(
        "UPDATE session_checkpoint SET payload=json_set(payload,'$.state.context','invalid recovery body');
         UPDATE current_context SET payload='invalid context body'",
    )
    .await?;
        assert!(
            store.conversation_current().await?.is_some(),
            "small current must not decode the corrupt recovery body"
        );
        // Content remains independent of recovery bodies. State additionally owns
        // saved statistics, so it must reject an envelope whose integrity was lost.
        let error = match cold(&store).await {
            Err(error) => error,
            Ok(_) => anyhow::bail!("State accepted a tampered statistics envelope"),
        };
        assert!(
            error
                .to_string()
                .contains("checkpoint content hash mismatch")
        );
        assert!(checkpoint::read(&db, THREAD).await.is_err());
        assert!(store.state.writer.get().is_none());
        // Restore only the original envelope; the bad recovery context remains.
        // The remaining cases isolate route-head validation rather than hash failure.
        db.execute_raw(statement(
            "UPDATE session_checkpoint SET payload=? WHERE id=1",
            vec![original.into()],
        ))
        .await?;
        let valid = serde_json::to_string(&saved)?;
        for (json, hash) in [
            (Some(valid.clone()), None),
            (None, Some(content_hash(valid.as_bytes()))),
            (Some(valid.clone()), Some("wrong-hash".into())),
            (Some("{".into()), Some(content_hash(b"{"))),
            (Some("null".into()), Some(content_hash(b"null"))),
        ] {
            db.execute_raw(statement(
                "UPDATE history_meta SET model_route_json=?,model_route_hash=? WHERE id=1",
                vec![json.into(), hash.into()],
            ))
            .await?;
            assert!(cold(&store).await.is_err());
            assert!(store.state.writer.get().is_none());
        }
        let mut state = legacy_checkpoint()?.state;
        model_route::migration::upgrade(&mut state)?;
        db.execute_unprepared("DELETE FROM history_meta WHERE id=1")
            .await?;
        assert!(checkpoint::read_model_route_head(&db).await.is_err());
        assert!(
            checkpoint::write_model_route_head(&db, &state)
                .await
                .is_err()
        );
        Ok(())
    }

    #[tokio::test]
    async fn schema12_missing_original_route_stays_null_despite_profile_and_bot_owner() -> Result<()>
    {
        let (_dir, db) = source().await?;
        let mut original = legacy_checkpoint()?;
        original
            .state
            .extensions
            .remove(model_route::MODEL_ROUTE_EXTENSION);
        write_published_checkpoint(&db, &original).await?;
        db.execute_unprepared("UPDATE history_meta SET applied_write_seq=9")
            .await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert!(checkpoint::read_model_route_head(&db).await?.is_none());
        let row = db
            .query_one_raw(statement(
                "SELECT model_route_json,model_route_hash FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap();
        assert!(
            row.try_get::<Option<String>>("", "model_route_json")?
                .is_none()
        );
        assert!(
            row.try_get::<Option<String>>("", "model_route_hash")?
                .is_none()
        );
        Ok(())
    }
}
