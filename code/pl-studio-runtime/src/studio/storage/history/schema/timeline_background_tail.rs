//! Schema 16 → 17 changes only the rebuildable background-result grouping.
use super::super::conversation::timeline;
use super::*;

pub(super) struct TimelineBackgroundTail;

impl MigrationName for TimelineBackgroundTail {
    fn name(&self) -> &str {
        TIMELINE_BACKGROUND_TAIL
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for TimelineBackgroundTail {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        async {
            let db = manager.get_connection();
            ensure!(
                version(db).await? == 16,
                "background tail migration requires schema 16"
            );
            let row = db
                .query_one_raw(statement(
                    "SELECT database_id FROM history_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .context("background tail migration has no history identity")?;
            timeline::rebuild(db, &row.try_get::<String>("", "database_id")?).await?;
            set_version(db, 17).await?;
            Ok::<_, anyhow::Error>(())
        }
        .await
        .map_err(conversion)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::paths::SqliteFileMode;
    use crate::studio::storage::history::{connect, conversation};
    use anyhow::Result;
    use pl_protocol::*;

    const THREAD: &str = "background-tail-migration";
    async fn migration_records(db: &impl ConnectionTrait) -> Result<Vec<String>> {
        db.query_all_raw(statement(
            "SELECT json_array(version,applied_at) AS record FROM seaql_migrations ORDER BY version",
            vec![],
        )).await?.into_iter()
            .map(|row| row.try_get("", "record").map_err(Into::into)).collect()
    }
    struct Published16;
    impl MigratorTraitSelf for Published16 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            Migrator {
                thread_id: THREAD.into(),
                execution_identity: None,
                bot_root: None,
            }
            .migrations()
            .into_iter()
            .filter(|step| {
                step.name() != TIMELINE_BACKGROUND_TAIL && !is_lifecycle_migration(step.name())
            })
            .collect()
        }
    }

    #[tokio::test]
    async fn schema16_background_tail_rebuild_preserves_facts_and_migration_ledger() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let db = connect(&path, SqliteFileMode::Create).await?;
        Published16.up(&db, None).await?;
        assert_eq!(version(&db).await?, 16);
        let row = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("database identity")?;
        let database: String = row.try_get("", "database_id")?;
        let mut facts = Vec::new();
        for seq in 1..=3_u64 {
            let at = Some(ChatFactPosition {
                effect_seq: seq,
                suborder: 0,
            });
            let atom = ChatAtom {
                id: format!("result-{seq}"),
                completion_item_id: Some(format!("result-{seq}")),
                completion_seq: Some(seq),
                source: ChatSourceId::BackgroundResult {
                    message_id: format!("message-{seq}"),
                },
                source_state: None,
                source_order: Some(seq),
                kind: ChatAtomKind::ToolCall,
                delivery: ChatDeliveryKind::Independent,
                lifecycle: ChatAtomLifecycle::Terminal {
                    started: at,
                    ended: at,
                    outcome: ChatTerminalOutcome::Completed,
                },
                turn_id: Some(format!("origin-{seq}")),
                attempt_id: None,
                tool: None,
                wait: None,
                text_channel: None,
                started_at: Some(seq as i64),
                finished_at: Some(seq as i64),
                content_present: None,
                contents: Vec::new(),
                payload: None,
            };
            let bytes = serde_json::to_vec(&atom)?;
            db.execute_raw(statement(
                "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,metadata,payload)
                 VALUES(?,?,'conversation',NULL,?,?)",
                vec![
                    integer(seq)?.into(),
                    atom.id.clone().into(),
                    bytes.clone().into(),
                    format!("original-{seq}").into_bytes().into(),
                ],
            ))
            .await?;
            db.execute_raw(statement(
                "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata)
                 VALUES(?,0,?,'terminal',?,?)",
                vec![integer(seq)?.into(), atom.id.clone().into(), integer(seq)?.into(), bytes.clone().into()],
            )).await?;
            facts.push(bytes);
        }
        db.execute_raw(statement(
            "UPDATE conversation_view_state SET payload=? WHERE singleton_id=1",
            vec![serde_json::to_vec(&CurrentProjection::empty(3, ThreadStatus::Idle))?.into()],
        ))
        .await?;
        db.execute_unprepared("UPDATE history_meta SET applied_write_seq=3 WHERE id=1")
            .await?;
        timeline::rebuild_schema16(&db, &database).await?;
        let before =
            conversation::timeline::page_rows(&db, &ChatScope::Main, None, 100, 3, 8, &[]).await?;
        assert_eq!(
            before.len(),
            3,
            "published fold must retain its old grouping"
        );
        let old_ledger = migration_records(&db).await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_tail_marker BEFORE UPDATE OF schema_version ON history_meta
             WHEN NEW.schema_version=17 BEGIN SELECT RAISE(ABORT,'injected tail marker failure'); END;"
        ).await?;
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(version(&db).await?, 16);
        assert_eq!(migration_records(&db).await?, old_ledger);
        assert_eq!(
            conversation::timeline::page_rows(&db, &ChatScope::Main, None, 100, 3, 8, &[]).await?,
            before
        );
        db.execute_unprepared("DROP TRIGGER reject_tail_marker")
            .await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(version(&db).await?, 17);
        let page =
            conversation::timeline::page_rows(&db, &ChatScope::Main, None, 100, 3, 8, &[]).await?;
        assert_eq!(page.len(), 1);
        let ChatEntry::Item(group) = &page[0].1 else {
            panic!("background group")
        };
        assert_eq!(group.position, Some(0));
        assert_eq!(group.summary.as_ref().unwrap().member_count, 3);
        let ledger = migration_records(&db).await?;
        assert_eq!(ledger.len(), old_ledger.len() + 1);
        for record in old_ledger {
            assert!(ledger.contains(&record));
        }
        let stored_facts = db
            .query_all_raw(statement(
                "SELECT metadata FROM conversation_atom_facts ORDER BY effect_seq",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<Vec<u8>>("", "metadata"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(facts, stored_facts);
        db.close().await?;
        let reopened = connect(&path, SqliteFileMode::ReadWrite).await?;
        prepare(&reopened, THREAD, Preparation::Schema, None).await?;
        assert_eq!(migration_records(&reopened).await?, ledger);
        assert_eq!(
            conversation::timeline::page_rows(&reopened, &ChatScope::Main, None, 100, 3, 8, &[])
                .await?,
            page
        );
        Ok(())
    }
}
