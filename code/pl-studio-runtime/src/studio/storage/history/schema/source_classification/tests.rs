use super::*;
use crate::studio::paths::SqliteFileMode;
use crate::studio::storage::history::conversation;
use crate::studio::storage::history::schema::legacy_timeline_types::{
    ChatEntry, CurrentProjection, FrozenCurrentProjection, TimelineItemKind,
};
use crate::studio::storage::history::{HistoryStore, connect};
use anyhow::Result;
use pl_protocol::*;
use sea_orm::DatabaseConnection;
use std::path::{Path, PathBuf};

const THREAD: &str = "source-classification-upgrade";

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
            !matches!(
                step.name(),
                SOURCE_CLASSIFICATION
                    | TIMELINE_BACKGROUND_TAIL
                    | COMPLETION_BOUNDARY
                    | IMMUTABLE_COMPLETION_RUNS
                    | DISPLAY_SNAPSHOTS
                    | DISPLAY_OBSERVATIONS
                    | TOOL_WORK
                    | VISIBLE_TAIL_WORKGROUPS
            )
        })
        .collect()
    }
}

async fn rows(db: &impl ConnectionTrait, sql: &str) -> Result<Vec<String>> {
    let sql = if version(db).await? >= 18 {
        sql.replace(
            "FROM timeline_items ",
            "FROM completion_boundary_archive_timeline_items ",
        )
        .replace(
            "FROM timeline_item_members ",
            "FROM completion_boundary_archive_timeline_members ",
        )
        .replace(
            "FROM timeline_projection_state",
            "FROM completion_boundary_archive_projection_state",
        )
    } else {
        sql.to_owned()
    };
    db.query_all_raw(statement(&sql, vec![]))
        .await?
        .into_iter()
        .map(|row| row.try_get("", "value").map_err(Into::into))
        .collect()
}

async fn ledger(db: &impl ConnectionTrait) -> Result<Vec<String>> {
    rows(
        db,
        "SELECT json_array(version,applied_at) AS value FROM seaql_migrations ORDER BY version",
    )
    .await
}

async fn originals(db: &impl ConnectionTrait) -> Result<Vec<String>> {
    let mut result = Vec::new();
    for sql in [
        "SELECT json_array(seq,item_id,query_class,parent_id,hex(payload),json_remove(CAST(metadata AS TEXT),'$.kind')) AS value FROM conversation_items ORDER BY seq",
        "SELECT json_array(ordinal,item_id,turn_id,kind,revision,lifecycle,created_at,updated_at,hex(payload),last_write_seq) AS value FROM history_items ORDER BY ordinal",
        "SELECT json_array(owner_key,content_key,hex(payload)) AS value FROM conversation_contents ORDER BY owner_key,content_key",
        "SELECT json_array(owner_key,content_key,byte_offset,hex(data)) AS value FROM conversation_content_chunks ORDER BY owner_key,content_key,byte_offset",
        "SELECT json_array(effect_seq,suborder,atom_id,phase,fact_order,CASE WHEN phase='legacySourceEnd' THEN CAST(metadata AS TEXT) ELSE json_remove(CAST(metadata AS TEXT),'$.kind') END) AS value FROM conversation_atom_facts ORDER BY atom_id,phase",
    ] {
        result.extend(rows(db, sql).await?);
    }
    Ok(result)
}

async fn derived(db: &impl ConnectionTrait) -> Result<Vec<String>> {
    let completed = completion_boundary::applied(db).await?;
    let mut result = Vec::new();
    for sql in [
        if completed {
            "SELECT json_array(item_id,kind,'history',position,commit_seq,hex(metadata),projection_version) AS value FROM timeline_items ORDER BY item_id"
        } else {
            "SELECT json_array(item_id,kind,location,position,commit_seq,hex(metadata),projection_version) AS value FROM timeline_items ORDER BY item_id"
        },
        "SELECT json_array(item_id,member_order,member_id,completion_item_id,admitted_effect,updated_effect,payload_bytes,hex(metadata)) AS value FROM timeline_item_members ORDER BY item_id,member_order",
        "SELECT json_array(projection_version,next_position,source_effect_seq,projection_generation,hex(recovery)) AS value FROM timeline_projection_state",
        if completed {
            "SELECT hex(payload) AS value FROM completion_boundary_archive_view_state"
        } else {
            "SELECT hex(payload) AS value FROM conversation_view_state"
        },
        "SELECT hex(metadata) AS value FROM conversation_items ORDER BY seq",
        "SELECT hex(metadata) AS value FROM conversation_atom_facts ORDER BY atom_id,phase",
    ] {
        result.extend(rows(db, sql).await?);
    }
    Ok(result)
}

fn agent(active: bool) -> ThreadItemState {
    ThreadItemState::Agent(ThreadAgentItem::new(
        ThreadAgentIdentity::new(
            "child".into(),
            "root/child".into(),
            "worker".into(),
            "task".into(),
            1,
        ),
        if active {
            ThreadAgentState::Running(RunningThreadAgent)
        } else {
            ThreadAgentState::Succeeded(SucceededThreadAgent::new(2, "done".into()))
        },
    ))
}

async fn fixture() -> Result<(tempfile::TempDir, PathBuf)> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let db = connect(&path, SqliteFileMode::Create).await?;
    let steps = Published16
        .migrations()
        .iter()
        .take_while(|step| !is_lifecycle_migration(step.name()))
        .count();
    Published16.up(&db, Some(u32::try_from(steps)?)).await?;
    let database = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("database identity")?
        .try_get::<String>("", "database_id")?;
    let store = HistoryStore::open(&path, THREAD).await?;
    // More than one migration window, with real producer payloads and content chunks.
    for seq in 1..=133u64 {
        let state = match seq {
            1 | 3 | 5 => ThreadItemState::Thinking(ThreadThinkingItem::new(
                vec![format!("摘要 {seq}")],
                vec!["工作原文 🦀".into()],
                ThreadContentLifecycle::completed(2),
            )),
            4 => ThreadItemState::Inference(ThreadInferenceItem::new(
                "call".into(),
                "model".into(),
                ThreadInferenceState::Completed(CompletedThreadInference::new(
                    2,
                    Default::default(),
                )),
            )),
            6 => agent(false),
            _ => ThreadItemState::Raw(if seq % 2 == 0 {
                ThreadRawItem::runtime_control("framework control", 2)
            } else {
                ThreadRawItem::stored(
                    vec![ThreadRawPayload {
                        format: "opaque".into(),
                        version: 1,
                        content: "原件 preserved".repeat(500),
                    }],
                    "undecodable",
                    2,
                )
            }),
        };
        let item = ThreadItem::new(
            format!("atom-{seq}"),
            THREAD.into(),
            "turn".into(),
            seq,
            1,
            1,
            2,
            state,
        );
        if seq != 7 {
            store.upsert_item(&db, 9, item.clone()).await?;
        }
        let mut draft = crate::studio::runtime::chat_item::completion_draft(&item, 9, &database)?;
        let mut atom: ChatAtom = serde_json::from_slice(&draft.metadata)?;
        atom.completion_seq = Some(seq);
        atom.completion_item_id = Some(item.id.clone());
        if seq != 1 && seq != 3 && seq != 5 {
            atom.kind = if seq == 6 || (seq > 7 && seq % 2 == 0) {
                ChatAtomKind::Receipt
            } else {
                ChatAtomKind::Unknown
            };
        }
        if seq == 7 {
            draft.payload = std::sync::Arc::from(&b"unsupported original bytes"[..]);
        }
        draft.metadata = serde_json::to_vec(&atom)?.into();
        let completion = pl_core::chat::ChatItem::complete(draft, seq, None);
        conversation::migration::append_published(&db, &completion).await?;
        db.execute_raw(statement(
            "UPDATE conversation_items SET metadata=?,query_class=? WHERE seq=?",
            vec![
                completion.header.metadata.to_vec().into(),
                if seq == 4 {
                    "diagnostic"
                } else {
                    "conversation"
                }
                .into(),
                integer(seq)?.into(),
            ],
        ))
        .await?;
    }
    let item = ThreadItem::new(
        "active-agent".into(),
        THREAD.into(),
        "turn".into(),
        134,
        1,
        1,
        2,
        agent(true),
    );
    store.upsert_item(&db, 9, item.clone()).await?;
    let mut current = CurrentProjection::empty(9, ThreadStatus::Running);
    let mut atom = crate::studio::runtime::chat_item::atom(&item);
    atom.kind = ChatAtomKind::Unknown;
    current.atoms.push(atom);
    crate::studio::storage::history::schema::legacy_current::apply(
        &db,
        9,
        &crate::studio::storage::history::schema::legacy_current::LegacyCurrent::new(
            FrozenCurrentProjection::new(current),
            [].into(),
            [].into(),
        ),
    )
    .await?;
    db.execute_unprepared("UPDATE history_meta SET applied_write_seq=9")
        .await?;
    timeline::normalize_legacy(&db).await?;
    timeline::rebuild_published(&db, &database).await?;
    db.close().await?;
    Ok((directory, path))
}

async fn open(path: &Path) -> Result<DatabaseConnection> {
    connect(path, SqliteFileMode::ReadWrite).await
}

async fn cold_shape(store: &HistoryStore) -> Result<(CurrentProjection, Vec<(u64, ChatEntry)>)> {
    let reader = store.reader().await?.context("cold reader")?;
    let current = super::super::legacy_current::read_archived(&reader.db).await?;
    let page = timeline::archived_page(&reader.db).await?;
    assert!(!page.is_empty());
    Ok((current, page))
}

#[tokio::test]
async fn new_database_runs_source_step_before_lifecycle_and_records_it_once() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let db = connect(
        &directory.path().join("history.sqlite"),
        SqliteFileMode::Create,
    )
    .await?;
    initialize(&db, THREAD).await?;
    let old_ledger = ledger(&db).await?;
    assert!(
        old_ledger
            .iter()
            .any(|row| row.contains(SOURCE_CLASSIFICATION))
    );
    assert!(old_ledger.iter().any(|row| row.contains(TIMELINE_ITEMS)));
    assert!(!old_ledger.iter().any(|row| row.contains(MODEL_ACCESS)));
    assert!(!needs_content_preparation(&db, THREAD).await?);
    let generation = migration_generation(&db).await?;
    initialize(&db, THREAD).await?;
    assert_eq!(migration_generation(&db).await?, generation);
    assert_eq!(ledger(&db).await?, old_ledger);
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn named_source_upgrade_preserves_originals_and_is_stable_on_cold_reopen() -> Result<()> {
    let (_directory, path) = fixture().await?;
    let db = open(&path).await?;
    let original = originals(&db).await?;
    let old_ledger = ledger(&db).await?;
    assert_eq!(version(&db).await?, 16);
    assert!(
        old_ledger
            .iter()
            .any(|record| record.contains(TIMELINE_THINKING_SUMMARY))
    );
    assert!(
        old_ledger
            .iter()
            .all(|record| !record.contains(SOURCE_CLASSIFICATION))
    );
    let generation = migration_generation(&db).await?;
    db.close().await?;
    let store = HistoryStore::open(&path, THREAD).await?;
    store.prepare_conversation_read().await?;
    let db = &store.writer().await?.db;
    assert_eq!(originals(db).await?, original);
    let new_ledger = ledger(db).await?;
    let appended_steps = [
        SOURCE_CLASSIFICATION,
        TIMELINE_BACKGROUND_TAIL,
        COMPLETION_BOUNDARY,
        IMMUTABLE_COMPLETION_RUNS,
        DISPLAY_SNAPSHOTS,
        DISPLAY_OBSERVATIONS,
        TOOL_WORK,
        VISIBLE_TAIL_WORKGROUPS,
    ];
    assert_eq!(new_ledger.len(), old_ledger.len() + appended_steps.len());
    for step in appended_steps {
        assert!(new_ledger.iter().any(|record| record.contains(step)));
    }
    assert!(old_ledger.iter().all(|record| new_ledger.contains(record)));
    assert_ne!(migration_generation(db).await?, generation);
    assert_eq!(rows(db, "SELECT json_extract(metadata,'$.kind') AS value FROM conversation_items WHERE seq IN (2,4,6,7) ORDER BY seq").await?,
        ["raw", "inference", "agent", "unknown"]);
    assert_eq!(
        rows(
            db,
            "SELECT kind AS value FROM timeline_items ORDER BY position LIMIT 6"
        )
        .await?,
        [
            "status",
            "workGroup",
            "status",
            "workGroup",
            "status",
            "status"
        ]
    );
    assert_eq!(
        rows(
            db,
            "SELECT member_id AS value FROM timeline_item_members ORDER BY item_id,member_order"
        )
        .await?,
        ["atom-1", "atom-3", "atom-5"]
    );
    assert_eq!(
        rows(
            db,
            "SELECT json_extract(metadata,'$.summary.latestThinkingSummary') AS value
             FROM timeline_items WHERE kind='workGroup' ORDER BY position"
        )
        .await?,
        ["摘要 1", "摘要 5"]
    );
    let current = super::super::legacy_current::read_archived(db).await?;
    assert_eq!(current.atoms[0].kind, ChatAtomKind::Agent);
    assert_eq!(current.items[0].kind, TimelineItemKind::Status);
    assert_eq!(current.items[0].source, current.atoms[0].source);
    let shape = cold_shape(&store).await?;
    let frozen = derived(db).await?;
    db.execute_unprepared("CREATE TRIGGER reject_rebuild BEFORE DELETE ON completion_boundary_archive_timeline_items BEGIN SELECT RAISE(ABORT,'unexpected rebuild'); END;
        CREATE TRIGGER reject_reclassify BEFORE UPDATE OF metadata ON conversation_items BEGIN SELECT RAISE(ABORT,'unexpected reclassification'); END;").await?;
    store.close_for_deletion().await?;
    let store = HistoryStore::open(&path, THREAD).await?;
    store.prepare_conversation_read().await?;
    let db = &store.writer().await?.db;
    assert_eq!(derived(db).await?, frozen);
    assert_eq!(originals(db).await?, original);
    assert_eq!(ledger(db).await?, new_ledger);
    assert_eq!(cold_shape(&store).await?, shape);
    store.close_for_deletion().await?;
    Ok(())
}

#[tokio::test]
async fn source_upgrade_failure_rolls_back_metadata_generation_and_applied_receipt() -> Result<()> {
    let (_directory, path) = fixture().await?;
    let db = open(&path).await?;
    let original = originals(&db).await?;
    let frozen = derived(&db).await?;
    let old_ledger = ledger(&db).await?;
    db.execute_unprepared(&format!("CREATE TRIGGER reject_source_receipt BEFORE INSERT ON seaql_migrations
        WHEN NEW.version='{SOURCE_CLASSIFICATION}' BEGIN SELECT RAISE(ABORT,'source receipt fault'); END;")).await?;
    assert!(
        prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .unwrap_err()
            .to_string()
            .contains(SOURCE_CLASSIFICATION)
    );
    assert_eq!(originals(&db).await?, original);
    assert_eq!(derived(&db).await?, frozen);
    assert_eq!(ledger(&db).await?, old_ledger);
    db.execute_unprepared("DROP TRIGGER reject_source_receipt")
        .await?;
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    assert!(!needs_content_preparation(&db, THREAD).await?);
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn source_upgrade_rejects_conflicting_evidence_and_supported_malformed_envelopes()
-> Result<()> {
    for corruption in [
        "UPDATE history_items SET kind='agent' WHERE item_id='atom-2'",
        "UPDATE history_items SET payload=json_set(payload,'$.state.kind','agent') WHERE item_id='atom-2'",
        "UPDATE history_items SET payload=json_set(payload,'$.state',NULL) WHERE item_id='atom-2'",
        "UPDATE conversation_items SET metadata=CAST(json_set(CAST(metadata AS TEXT),'$.kind','text') AS BLOB) WHERE seq=2",
        "UPDATE conversation_items SET payload=CAST(json_set(CAST(payload AS TEXT),'$.type',42) AS BLOB) WHERE seq=2",
        "UPDATE conversation_items SET payload=CAST(json_set(CAST(payload AS TEXT),'$.data',NULL) AS BLOB) WHERE seq=2",
    ] {
        let (_directory, path) = fixture().await?;
        let db = open(&path).await?;
        db.execute_unprepared(corruption).await?;
        let original = originals(&db).await?;
        let frozen = derived(&db).await?;
        let old_ledger = ledger(&db).await?;
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err(),
            "{corruption}"
        );
        assert_eq!(originals(&db).await?, original);
        assert_eq!(derived(&db).await?, frozen);
        assert_eq!(ledger(&db).await?, old_ledger);
        db.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn applied_source_upgrade_does_not_repair_missing_tables_or_recovery() -> Result<()> {
    for corruption in [
        "DROP INDEX conversation_items_visible_seq",
        "DROP INDEX conversation_items_by_run_seq",
    ] {
        let (_directory, path) = fixture().await?;
        let db = open(&path).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        let old_ledger = ledger(&db).await?;
        db.execute_unprepared(corruption).await?;
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(ledger(&db).await?, old_ledger);
        db.close().await?;
    }
    Ok(())
}

async fn migration_generation(db: &impl ConnectionTrait) -> Result<String> {
    if version(db).await? >= 18 {
        timeline::archived_generation(db).await
    } else {
        timeline::generation(db).await
    }
}
