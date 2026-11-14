//! Schema 15 → 16: rebuild bounded thinking summaries and independent background
//! tool groups from original facts and explicit summary contents.
use super::legacy_timeline_store as timeline;
use super::*;
#[cfg(test)]
use crate::{ExecutionItem, ExecutionShape};

pub(super) struct TimelineThinkingSummary;

impl MigrationName for TimelineThinkingSummary {
    fn name(&self) -> &str {
        TIMELINE_THINKING_SUMMARY
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for TimelineThinkingSummary {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let result: anyhow::Result<()> = async {
            let db = manager.get_connection();
            ensure!(
                version(db).await? == 15,
                "timeline thinking summary migration requires schema 15"
            );
            let row = db
                .query_one_raw(statement(
                    "SELECT database_id FROM history_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .context("timeline thinking summary migration has no history identity")?;
            let database_id: String = row.try_get("", "database_id")?;
            timeline::rebuild_schema16(db, &database_id).await?;
            set_version(db, 16).await?;
            Ok(())
        }
        .await;
        result.map_err(conversion)
    }
}

#[cfg(test)]
mod tests {
    use super::legacy_timeline_types::*;
    use super::legacy_timeline_types::{ChatScope, CurrentProjection};
    use super::*;
    use crate::studio::storage::history::{connect, conversation};
    use anyhow::Result;
    use pl_core::chat::ChatItem;
    use pl_protocol::*;

    const THREAD: &str = "thinking-summary-migration";

    struct Published15;
    impl MigratorTraitSelf for Published15 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            migrator()
                .migrations()
                .into_iter()
                .take_while(|step| !is_lifecycle_migration(step.name()))
                .filter(|step| {
                    !matches!(
                        step.name(),
                        TIMELINE_THINKING_SUMMARY
                            | SOURCE_CLASSIFICATION
                            | TIMELINE_BACKGROUND_TAIL
                            | COMPLETION_BOUNDARY
                            | IMMUTABLE_COMPLETION_RUNS
                            | WORK_SNAPSHOTS
                            | DISPLAY_BLOCK_ORDER
                            | EXECUTION_FACTS
                    )
                })
                .collect()
        }
    }

    fn migrator() -> Migrator {
        Migrator {
            thread_id: THREAD.into(),
            execution_identity: None,
            bot_root: None,
        }
    }

    fn at(effect_seq: u64) -> ChatFactPosition {
        ChatFactPosition {
            effect_seq,
            suborder: 0,
        }
    }

    async fn seed(db: &impl ConnectionTrait, database: &str) -> Result<Vec<ChatItem>> {
        let mut records = Vec::new();
        // Later source member completes first. Full reasoning is deliberately
        // unrelated and large; only the summary role is allowed into the group.
        for (id, ordinal, started, ended, text) in [
            ("late", 2, 2, 3, Some("最新摘要")),
            ("early", 1, 1, 4, Some("较早摘要")),
            ("boundary", 3, 5, 6, None),
            ("background", 1, 7, 7, None),
        ] {
            let state = match text {
                Some(text) => ExecutionShape::Thinking(ThreadThinkingItem::new(
                    vec![format!("{}\r\n{text}\r\n", "🦀".repeat(4096))],
                    vec!["不应作为摘要的正文".repeat(4096)],
                    ThreadContentLifecycle::completed(ended),
                )),
                None if id == "background" => ExecutionShape::Tool(ThreadToolItem::new(
                    ThreadToolInvocation::new("background-call".into(), "exec".into(), "{}".into()),
                    ThreadToolState::Succeeded(SucceededThreadTool::new(
                        ended,
                        ThreadToolOutput::new("后台结果".into(), vec![], vec![], Some(0)),
                    )),
                )),
                None => ExecutionShape::Text(ThreadTextItem::new(
                    ThreadTextChannel::Final,
                    "结果".into(),
                    Vec::new(),
                    ThreadContentLifecycle::completed(ended),
                )),
            };
            let item = ExecutionItem::new(
                id.into(),
                THREAD.into(),
                "turn".into(),
                ordinal,
                1,
                started,
                ended,
                state,
            );
            let mut draft =
                crate::studio::runtime::chat_item::completion_draft(&item, ended as u64, database)?;
            let mut atom: ChatAtom = serde_json::from_slice(&draft.metadata)?;
            if id == "background" {
                atom.source = ChatSourceId::BackgroundResult {
                    message_id: "background-message".into(),
                };
                atom.delivery = ChatDeliveryKind::Independent;
            }
            atom.lifecycle = ChatAtomLifecycle::Terminal {
                started: Some(at(started as u64)),
                ended: Some(at(ended as u64)),
                outcome: ChatTerminalOutcome::Completed,
            };
            atom.completion_seq = Some(records.len() as u64 + 1);
            let terminal = serde_json::to_vec(&atom)?;
            let mut start = atom.clone();
            start.lifecycle = ChatAtomLifecycle::Active {
                started: Some(at(started as u64)),
                status: ChatActiveStatus::Running,
            };
            start.completion_item_id = None;
            start.completion_seq = None;
            start.finished_at = None;
            start.contents.clear();
            for (effect, phase, metadata) in [
                (started, "start", serde_json::to_vec(&start)?),
                (ended, "terminal", terminal.clone()),
            ] {
                db.execute_raw(statement(
                    "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata) VALUES(?,0,?,?,?,?)",
                    vec![effect.into(), id.into(), phase.into(), (ordinal as i64).into(), metadata.into()],
                )).await?;
            }
            draft.metadata = terminal.into();
            records.push(ChatItem::complete(draft, records.len() as u64 + 1));
        }
        for record in &records {
            timeline::append_fixture(db, record).await?;
        }
        let current = CurrentProjection::empty(7, ThreadStatus::Idle);
        db.execute_raw(statement(
            "UPDATE conversation_view_state SET payload=? WHERE singleton_id=1",
            vec![serde_json::to_vec(&current)?.into()],
        ))
        .await?;
        db.execute_unprepared("UPDATE history_meta SET applied_write_seq=7 WHERE id=1")
            .await?;
        timeline::rebuild(db, database).await?;
        // Freeze a published v1 derived boundary. Source rows/content stay intact.
        db.execute_unprepared(
            "UPDATE timeline_items SET
               metadata=CAST(json_set(json_remove(CAST(metadata AS TEXT),'$.summary.latestThinkingSummary'),'$.members.projectionVersion',1) AS BLOB)
               WHERE kind='workGroup';
             UPDATE timeline_items SET kind='status',
               metadata=CAST(json_set(CAST(metadata AS TEXT),'$.kind','status','$.summary',NULL,'$.members',NULL,'$.atomKind','toolCall','$.contentItemId','background') AS BLOB)
               WHERE json_extract(CAST(metadata AS TEXT),'$.source.kind')='backgroundResult';
             UPDATE timeline_items SET projection_version=1;
             UPDATE timeline_projection_state SET projection_version=1;"
        ).await?;
        Ok(records)
    }

    #[tokio::test]
    async fn schema15_summary_rebuild_is_atomic_preserves_sources_and_reopens_once() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let db = connect(&path, crate::studio::paths::SqliteFileMode::Create).await?;
        Published15.up(&db, None).await?;
        assert_eq!(version(&db).await?, 15);
        let database: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("history identity")?
            .try_get("", "database_id")?;
        let originals = seed(&db, &database).await?;
        let facts_before = source_facts(&db).await?;
        let before = db
            .query_one_raw(statement(
                "SELECT metadata FROM timeline_items WHERE kind='workGroup'",
                vec![],
            ))
            .await?
            .context("old group")?
            .try_get::<Vec<u8>>("", "metadata")?;
        let old_head = db
            .query_one_raw(statement(
                "SELECT projection_generation FROM timeline_projection_state",
                vec![],
            ))
            .await?
            .context("old head")?
            .try_get::<String>("", "projection_generation")?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_summary_marker BEFORE UPDATE OF schema_version ON history_meta
             WHEN NEW.schema_version=16 BEGIN SELECT RAISE(ABORT,'injected summary marker failure'); END;"
        ).await?;
        let error = migrator()
            .up(&db, Some(1))
            .await
            .expect_err("marker failure rolls back derived rebuild");
        assert!(
            error
                .to_string()
                .contains("injected summary marker failure")
        );
        assert_eq!(version(&db).await?, 15);
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT metadata FROM timeline_items WHERE kind='workGroup'",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<Vec<u8>>("", "metadata")?,
            before
        );
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![TIMELINE_THINKING_SUMMARY.into()],
            ))
            .await?
            .is_none()
        );
        db.execute_unprepared("DROP TRIGGER reject_summary_marker")
            .await?;
        // Inspect this published step before later migrations archive its display tables.
        migrator().up(&db, Some(1)).await?;
        assert_eq!(version(&db).await?, 16);
        let row = db
            .query_one_raw(statement(
                "SELECT metadata,projection_version FROM timeline_items WHERE kind='workGroup' AND json_extract(CAST(metadata AS TEXT),'$.source.kind')='foregroundTurn'",
                vec![],
            ))
            .await?
            .context("rebuilt group")?;
        assert_eq!(
            row.try_get::<i64>("", "projection_version")?,
            i64::from(TIMELINE_PROJECTION_VERSION)
        );
        let item: TimelineItem = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        assert_eq!(
            item.summary.unwrap().latest_thinking_summary.as_deref(),
            Some("最新摘要")
        );
        let row = db.query_one_raw(statement(
            "SELECT metadata FROM timeline_items WHERE json_extract(CAST(metadata AS TEXT),'$.source.kind')='backgroundResult'", vec![],
        )).await?.context("rebuilt background result")?;
        let item: TimelineItem = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        assert_eq!(item.kind, TimelineItemKind::WorkGroup);
        assert_eq!(
            item.source,
            ChatSourceId::BackgroundResult {
                message_id: "background-message".into()
            }
        );
        assert_eq!(item.position, Some(2));
        let members = timeline::page_rows(
            &db,
            &ChatScope::GroupMembers {
                reference: item.members.context("background group members")?,
            },
            None,
            100,
            7,
            8,
            &[],
        )
        .await?;
        assert!(matches!(&members[0].1, ChatEntry::Atom(atom) if atom.id == "background"));
        assert_eq!(source_facts(&db).await?, facts_before);
        for original in originals {
            let stored = db
                .query_one_raw(statement(
                    "SELECT seq,metadata,payload FROM conversation_items WHERE item_id=?",
                    vec![original.header.item_id.clone().into()],
                ))
                .await?
                .context("original completion")?;
            assert_eq!(
                stored.try_get::<i64>("", "seq")?,
                integer(original.header.append_seq)?
            );
            assert_eq!(
                stored.try_get::<Vec<u8>>("", "metadata")?,
                original.header.metadata.as_ref()
            );
            assert_eq!(
                stored.try_get::<Vec<u8>>("", "payload")?,
                original.payload.as_ref()
            );
            assert_eq!(
                conversation::read_contents(&db, &original.header.item_id).await?,
                *original.contents
            );
        }
        let head = timeline::read_state(&db).await?.context("rebuilt head")?;
        assert_ne!(head.generation, old_head);
        db.close().await?;
        let db = connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        // Later published source/tail steps may rotate their generation before archiving.
        let generation = timeline::archived_generation(&db).await?;
        assert!(!generation.is_empty());
        db.close().await?;
        let db = connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(timeline::archived_generation(&db).await?, generation);
        db.close().await?;
        Ok(())
    }

    async fn source_facts(db: &impl ConnectionTrait) -> Result<Vec<Vec<u8>>> {
        db.query_all_raw(statement(
            "SELECT metadata FROM conversation_atom_facts ORDER BY atom_id,phase",
            vec![],
        ))
        .await?
        .into_iter()
        .map(|row| Ok(row.try_get("", "metadata")?))
        .collect()
    }
}
