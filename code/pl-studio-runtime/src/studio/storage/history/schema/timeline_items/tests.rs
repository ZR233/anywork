use super::super::super::HistoryStore;
use super::*;
use crate::studio::storage::history::conversation;
use crate::studio::storage::history::schema::legacy_timeline_types::{
    ChatEntry, CurrentProjection, TimelineItem, TimelineItemKind,
};
use anyhow::{Context, Result, ensure};
use pl_core::{
    chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor},
    context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
    thread::{ThreadCheckpoint, ThreadSnapshot},
};
use pl_protocol::*;
use sea_orm::DatabaseConnection;
use serde_json::json;
use std::sync::Arc;

const THREAD: &str = "timeline-items-migration";

struct Published13;
impl MigratorTraitSelf for Published13 {
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
            )
        })
        .filter(|step| !matches!(step.name(), ATOM_METADATA | TIMELINE_ITEMS))
        .collect()
    }
}

struct Published14;
impl MigratorTraitSelf for Published14 {
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
            )
        })
        .filter(|step| !matches!(step.name(), TIMELINE_ITEMS))
        .collect()
    }
}

/// Freeze the released member step's schema-16 input and official ledger.
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
                TIMELINE_BACKGROUND_TAIL
                    | COMPLETION_BOUNDARY
                    | IMMUTABLE_COMPLETION_RUNS
                    | WORK_SNAPSHOTS
            )
        })
        .collect()
    }
}
async fn prepare_published16(db: &DatabaseConnection) -> Result<()> {
    let count = Published16
        .get_pending_migrations_read_only(db)
        .await?
        .iter()
        .take_while(|step| !is_lifecycle_migration(step.name()))
        .count();
    Published16.up(db, Some(u32::try_from(count)?)).await?;
    Ok(())
}

async fn database_id(db: &impl ConnectionTrait) -> Result<String> {
    Ok(db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("history identity")?
        .try_get("", "database_id")?)
}

async fn seed_schema13(path: &std::path::Path, db: &DatabaseConnection) -> Result<()> {
    use crate::studio::storage::history::schema::legacy_current::{
        CurrentContentWrite, CurrentEntryChange, CurrentEntryWrite, LegacyCurrent,
    };

    let identity = database_id(db).await?;
    let store = HistoryStore::open(path, THREAD).await?;
    for part in 1..=2_u64 {
        let member = ThreadItem::new(
            format!("sealed-member-{part}"),
            THREAD.into(),
            "sealed-turn".into(),
            part,
            1,
            1,
            2,
            ThreadItemState::Thinking(ThreadThinkingItem::new(
                vec![],
                vec![format!("历史成员正文 {part} 🦀")],
                ThreadContentLifecycle::completed(2),
            )),
        );
        store.upsert_item(db, 4, member.clone()).await?;
        let completion = pl_core::chat::ChatItem::complete(
            crate::studio::runtime::chat_item::completion_draft(&member, 4, &identity)?,
            part,
            None,
        );
        conversation::migration::append_published(db, &completion).await?;
    }
    let sealed = ThreadItem::new(
        "sealed-text".into(),
        THREAD.into(),
        "sealed-turn".into(),
        3,
        1,
        1,
        3,
        ThreadItemState::Text(ThreadTextItem::new(
            ThreadTextChannel::Final,
            "封口正文 retained 🦀".into(),
            vec![],
            ThreadContentLifecycle::completed(3),
        )),
    );
    store.upsert_item(db, 4, sealed.clone()).await?;
    let completion = pl_core::chat::ChatItem::complete(
        crate::studio::runtime::chat_item::completion_draft(&sealed, 4, &identity)?,
        3,
        None,
    );
    conversation::migration::append_published(db, &completion).await?;

    let mut current = CurrentProjection::empty(4, ThreadStatus::Running);
    current.collections.push(CurrentCollectionRef {
        database_id: identity.clone(),
        collection: "members".into(),
        revision: 4,
    });
    let mut contents = Vec::new();
    let mut changes = Vec::new();
    for part in 1..=3_i64 {
        let id = format!("live-{part}");
        let text = format!("活动正文 {part} 🦀");
        store
            .upsert_item(
                db,
                4,
                ThreadItem::new(
                    id.clone(),
                    THREAD.into(),
                    "active-turn".into(),
                    u64::try_from(part + 3)?,
                    1,
                    1,
                    2,
                    ThreadItemState::Thinking(ThreadThinkingItem::new(
                        vec![],
                        vec![text.clone()],
                        ThreadContentLifecycle::streaming(),
                    )),
                ),
            )
            .await?;
        let key = "part.reasoningText.0".to_owned();
        let bytes: Arc<[u8]> = text.into_bytes().into();
        let reference = ContentRef {
            database_id: identity.clone(),
            target: ContentTarget::Body {
                owner: ContentOwner::Item {
                    item_id: id.clone(),
                },
                key: key.clone(),
            },
        };
        let body = json!([{
            "reference": reference.clone(),
            "byteLength": bytes.len(),
            "generation": 1
        }]);
        current.previews.push(CurrentContentPreview {
            id: id.clone(),
            role: CurrentContentRole::Reasoning,
            text_channel: None,
            text: format!("preview-{part}"),
            reference: reference.clone(),
        });
        contents.push(CurrentContentWrite {
            content: Arc::new(ChatContent {
                descriptor: ContentDescriptor {
                    key: ChatContentKey {
                        owner: pl_core::chat::ChatKey::new("item", &id)?,
                        key,
                    },
                    byte_length: bytes.len() as u64,
                    generation: 1,
                    media_type: None,
                },
                data: ContentData::Bytes(bytes),
            }),
            sealed: false,
        });
        changes.push(CurrentEntryChange::Put(CurrentEntryWrite {
            collection: "members".into(),
            position: part,
            entry_id: id,
            payload: serde_json::to_vec(&body)?.into(),
        }));
    }
    crate::studio::storage::history::schema::legacy_current::apply(
        db,
        4,
        &LegacyCurrent::new(
            crate::studio::storage::history::schema::legacy_timeline_types::FrozenCurrentProjection::new(current),
            changes.into(),
            contents.into(),
        ),
    )
    .await?;
    db.execute_unprepared("UPDATE history_meta SET applied_write_seq=4")
        .await?;
    Ok(())
}

async fn source_bytes(db: &impl ConnectionTrait) -> Result<Vec<String>> {
    let completed = completion_boundary::applied(db).await?;
    let mut facts = Vec::new();
    // This byte oracle does not decode/re-encode source rows through the migration or fold.
    // Only schema_version and the derived current.items are expected to change on success.
    for query in [
        "SELECT json_array(database_id,thread_id,applied_write_seq,model_route_json,model_route_hash) AS fact
         FROM history_meta ORDER BY id",
        "SELECT json_array(id,revision,context_revision,context_count,hex(payload),payload_hash,legacy_cleanup) AS fact
         FROM session_checkpoint ORDER BY id",
        "SELECT json_array(ordinal,record_id,hex(payload),payload_hash) AS fact
         FROM current_context ORDER BY ordinal",
        "SELECT json_array(ordinal,item_id,turn_id,kind,revision,lifecycle,created_at,updated_at,hex(payload),last_write_seq) AS fact
         FROM history_items ORDER BY ordinal",
        "SELECT json_array(seq,item_id,query_class,parent_id,hex(payload),hex(metadata)) AS fact
         FROM conversation_items ORDER BY seq",
        "SELECT json_array(owner_key,content_key,hex(payload)) AS fact
         FROM conversation_contents ORDER BY owner_key,content_key",
        "SELECT json_array(owner_key,content_key,byte_offset,hex(data)) AS fact
         FROM conversation_content_chunks ORDER BY owner_key,content_key,byte_offset",
        if completed {
            "SELECT json_array(collection,position,entry_id,hex(payload)) AS fact
             FROM completion_boundary_archive_view_entries ORDER BY collection,position"
        } else {
            "SELECT json_array(collection,position,entry_id,hex(payload)) AS fact
             FROM conversation_view_entries ORDER BY collection,position"
        },
        "SELECT json_array(source_key,started_effect,started_suborder,ended_effect,ended_suborder,
                           active_observed,ended_observed,outcome) AS fact
         FROM conversation_sources ORDER BY source_key",
    ] {
        let query = if completed {
            query.replace("FROM conversation_contents ORDER BY", "FROM (SELECT * FROM conversation_contents UNION ALL SELECT * FROM completion_boundary_archive_contents) ORDER BY")
                .replace("FROM conversation_content_chunks ORDER BY", "FROM (SELECT * FROM conversation_content_chunks UNION ALL SELECT * FROM completion_boundary_archive_content_chunks) ORDER BY")
        } else { query.to_owned() };
        for row in db.query_all_raw(statement(&query, vec![])).await? {
            facts.push(row.try_get("", "fact")?);
        }
    }
    Ok(facts)
}

async fn migration_records(db: &impl ConnectionTrait) -> Result<Vec<String>> {
    db.query_all_raw(statement(
        "SELECT json_array(version,applied_at) AS record FROM seaql_migrations ORDER BY version",
        vec![],
    ))
    .await?
    .into_iter()
    .map(|row| row.try_get("", "record").map_err(Into::into))
    .collect()
}

async fn derived_bytes(db: &impl ConnectionTrait) -> Result<Vec<String>> {
    let completed = completion_boundary::applied(db).await?;
    let mut facts = Vec::new();
    for query in [
        "SELECT json_array(item_id,kind,location,position,commit_seq,hex(metadata),projection_version) AS fact
         FROM timeline_items ORDER BY location,position,item_id",
        "SELECT json_array(item_id,member_order,member_id,completion_item_id,admitted_effect,hex(metadata)) AS fact
         FROM timeline_item_members ORDER BY item_id,member_order",
        "SELECT json_array(projection_version,next_position,source_effect_seq,projection_generation,hex(recovery)) AS fact
         FROM timeline_projection_state ORDER BY singleton_id",
        "SELECT json_array(effect_seq,suborder,atom_id,phase,fact_order,hex(metadata)) AS fact
         FROM conversation_atom_facts ORDER BY effect_seq,suborder,fact_order,atom_id,phase",
    ] {
        let query = if completed {
            query.replace("FROM timeline_items ", "FROM completion_boundary_archive_timeline_items ")
                .replace("FROM timeline_item_members ", "FROM completion_boundary_archive_timeline_members ")
                .replace("FROM timeline_projection_state ", "FROM completion_boundary_archive_projection_state ")
        } else {query.to_owned()};
        for row in db.query_all_raw(statement(&query, vec![])).await? {
            facts.push(row.try_get("", "fact")?);
        }
    }
    Ok(facts)
}

async fn schema14() -> Result<(tempfile::TempDir, std::path::PathBuf, Vec<String>, Vec<u8>)> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let db =
        super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::Create).await?;
    let steps = Published13
        .migrations()
        .iter()
        .take_while(|step| !is_lifecycle_migration(step.name()))
        .count();
    Published13.up(&db, Some(u32::try_from(steps)?)).await?;
    assert_eq!(version(&db).await?, 13);
    seed_schema13(&path, &db).await?;
    let steps = Published14
        .get_pending_migrations_read_only(&db)
        .await?
        .iter()
        .take_while(|step| !is_lifecycle_migration(step.name()))
        .count();
    assert_eq!(steps, 1, "fixture advances only the real AtomMetadata step");
    Published14.up(&db, Some(u32::try_from(steps)?)).await?;
    assert_eq!(version(&db).await?, 14);
    // These steps precede TimelineItems in the official sequence and each owns
    // its own transaction. Freeze their completed boundary for the backfill story.
    Migrator {
        thread_id: THREAD.into(),
        execution_identity: None,
        bot_root: None,
    }
    .up(&db, Some(2))
    .await?;
    validate_source(&db).await?;
    checkpoint::write(
        &db,
        &ThreadCheckpoint::capture(
            THREAD.into(),
            4,
            ThreadSnapshot {
                commit_sequence: 4,
                context: ContextSnapshot {
                    revision: 1,
                    records: vec![ContextRecord {
                        id: "original-context".into(),
                        turn_id: None,
                        source: ContextSource::Instruction,
                        content: vec![ContextContent::Text {
                            text: Arc::from("原始恢复上下文 🦀"),
                        }],
                        tool_calls: vec![],
                    }]
                    .into(),
                },
                ..Default::default()
            },
        )?,
        None,
        None,
    )
    .await?;
    let cut = crate::studio::storage::history::schema::legacy_current::read(&db).await?;
    assert_eq!(cut.atoms.len(), 3);
    assert!(
        cut.items.is_empty(),
        "schema 14 has no Timeline projection yet"
    );
    let source = source_bytes(&db).await?;
    let current = db
        .query_one_raw(statement(
            "SELECT payload FROM conversation_view_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
        .context("schema-14 current")?
        .try_get("", "payload")?;
    db.close().await?;
    Ok((directory, path, source, current))
}

async fn install_output_rejections(db: &impl ConnectionTrait) -> Result<()> {
    let completed = completion_boundary::applied(db).await?;
    let current_table = if completed {
        "completion_boundary_archive_view_state"
    } else {
        "conversation_view_state"
    };
    let item_table = if completed {
        "completion_boundary_archive_timeline_items"
    } else {
        "timeline_items"
    };
    let member_table = if completed {
        "completion_boundary_archive_timeline_members"
    } else {
        "timeline_item_members"
    };
    let state_table = if completed {
        "completion_boundary_archive_projection_state"
    } else {
        "timeline_projection_state"
    };
    db.execute_unprepared(
        &format!("CREATE TRIGGER reject_atom_insert BEFORE INSERT ON conversation_atom_facts
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote atom facts'); END;
         CREATE TRIGGER reject_atom_update BEFORE UPDATE ON conversation_atom_facts
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote atom facts'); END;
         CREATE TRIGGER reject_atom_delete BEFORE DELETE ON conversation_atom_facts
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote atom facts'); END;
         CREATE TRIGGER reject_item_insert BEFORE INSERT ON {item_table}
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote items'); END;
         CREATE TRIGGER reject_item_update BEFORE UPDATE ON {item_table}
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote items'); END;
         CREATE TRIGGER reject_item_delete BEFORE DELETE ON {item_table}
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote items'); END;
         CREATE TRIGGER reject_member_insert BEFORE INSERT ON {member_table}
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote members'); END;
         CREATE TRIGGER reject_member_update BEFORE UPDATE ON {member_table}
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote members'); END;
         CREATE TRIGGER reject_member_delete BEFORE DELETE ON {member_table}
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote members'); END;
         CREATE TRIGGER reject_state_insert BEFORE INSERT ON {state_table}
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote recovery'); END;
         CREATE TRIGGER reject_state_update BEFORE UPDATE ON {state_table}
           WHEN NOT EXISTS(SELECT 1 FROM sqlite_schema WHERE name='completion_boundary_archive_view_state')
             OR EXISTS(SELECT 1 FROM seaql_migrations WHERE version='m20261109_000001_history_completion_boundary')
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote recovery'); END;
         CREATE TRIGGER reject_state_delete BEFORE DELETE ON {state_table}
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote recovery'); END;
         CREATE TRIGGER reject_current_update BEFORE UPDATE ON {current_table}
           BEGIN SELECT RAISE(ABORT,'Applied migration rewrote current'); END;"),
    )
    .await?;
    Ok(())
}

async fn group_members(
    db: &impl ConnectionTrait,
    database: &str,
    group: &TimelineItem,
) -> Result<Vec<ChatAtom>> {
    let expected = group
        .summary
        .as_ref()
        .context("archived group summary")?
        .member_count as usize;
    let rows = db.query_all_raw(statement(
        "SELECT member_order,metadata,payload_bytes FROM completion_boundary_archive_timeline_members
         WHERE item_id=? ORDER BY member_order LIMIT ?",
        vec![group.id.clone().into(),integer(expected+1)?.into()],
    )).await?;
    assert_eq!(rows.len(), expected);
    rows.into_iter()
        .map(|row| {
            let mut atom: ChatAtom =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            if matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }) {
                atom.contents.clear();
            }
            if let Some(id) = &atom.completion_item_id {
                atom.payload = Some(PayloadData::Deferred {
                    reference: ContentRef {
                        database_id: database.into(),
                        target: ContentTarget::ItemPayload {
                            item_id: id.clone(),
                        },
                    },
                    byte_length: u64::try_from(row.try_get::<i64>("", "payload_bytes")?)?,
                });
            }
            Ok(atom)
        })
        .collect()
}

async fn assert_body(
    db: &impl ConnectionTrait,
    reference: &ContentRef,
    id: &str,
    key: &str,
    expected: &[u8],
) -> Result<()> {
    assert_eq!(
        reference.target,
        ContentTarget::Body {
            owner: ContentOwner::Item { item_id: id.into() },
            key: key.into(),
        }
    );
    assert_eq!(reference.database_id, database_id(db).await?);
    let contents = conversation::read_contents(db, id).await?;
    let content = contents
        .values()
        .find(|content| content.descriptor.key.key == key)
        .context("original body remains readable")?;
    assert_eq!(
        content.descriptor.byte_length,
        u64::try_from(expected.len())?
    );
    assert_eq!(content.data.range(0, expected.len())?.as_bytes(), expected);
    Ok(())
}

async fn assert_migrated_content(
    store: &HistoryStore,
) -> Result<(CurrentProjection, Vec<ChatAtom>)> {
    let db = &store.writer().await?.db;
    let database = database_id(db).await?;
    let current = super::super::legacy_current::read_archived(db).await?;
    assert_eq!(current.source_effect_seq, 4);
    assert_eq!(current.items.len(), 1);
    let group = &current.items[0];
    assert_eq!(group.kind, TimelineItemKind::WorkGroup);
    let summary = group.summary.as_ref().context("active group summary")?;
    assert_eq!((summary.member_count, summary.active_count), (3, 3));
    let members = group_members(db, &database, group).await?;
    assert_eq!(
        members
            .iter()
            .map(|atom| atom.id.as_str())
            .collect::<Vec<_>>(),
        ["live-1", "live-2", "live-3"]
    );
    for (index, atom) in members.iter().enumerate() {
        assert_eq!(atom.source_order, Some(u64::try_from(index)? + 4));
        assert!(atom.completion_item_id.is_none());
        assert!(matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }));
        assert!(
            atom.contents.is_empty(),
            "cold reads never activate old previews"
        );
        // Archive-only inspection: these references are not normal reader authority.
        let row = db.query_one_raw(statement(
            "SELECT metadata FROM completion_boundary_archive_timeline_members WHERE member_id=?",
            vec![atom.id.clone().into()],
        )).await?.context("archived member")?;
        let archived: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        assert_eq!(archived.contents.len(), 1);
        assert_eq!(archived.id, atom.id);
        let expected = format!("活动正文 {} 🦀", index + 1);
        assert_eq!(
            archived.contents[0].reference.target,
            ContentTarget::Body {
                owner: ContentOwner::Item {
                    item_id: atom.id.clone()
                },
                key: "part.reasoningText.0".into(),
            }
        );
        let chunks = db
            .query_all_raw(statement(
                "SELECT byte_offset,data FROM completion_boundary_archive_content_chunks
             WHERE owner_key=? AND content_key='part.reasoningText.0' ORDER BY byte_offset",
                vec![
                    pl_core::chat::ChatKey::new("item", &atom.id)?
                        .as_str()
                        .into(),
                ],
            ))
            .await?;
        let mut bytes = Vec::new();
        for chunk in chunks {
            assert_eq!(
                chunk.try_get::<i64>("", "byte_offset")?,
                i64::try_from(bytes.len())?
            );
            bytes.extend(chunk.try_get::<Vec<u8>>("", "data")?);
        }
        assert_eq!(bytes, expected.as_bytes());
    }

    let mut history = timeline::archived_page(db).await?;
    history.reverse();
    assert_eq!(history.len(), 2);
    let mut items = Vec::new();
    for (expected, (position, entry)) in history.into_iter().enumerate() {
        assert_eq!(position, u64::try_from(expected)?);
        let ChatEntry::Item(item) = entry else {
            anyhow::bail!("Main returned an ungrouped atom");
        };
        items.push(*item);
    }
    assert_eq!(items[0].kind, TimelineItemKind::WorkGroup);
    let summary = items[0]
        .summary
        .as_ref()
        .context("historical group summary")?;
    assert_eq!((summary.member_count, summary.active_count), (2, 0));
    let historical = group_members(db, &database, &items[0]).await?;
    assert_eq!(
        historical
            .iter()
            .map(|atom| atom.id.as_str())
            .collect::<Vec<_>>(),
        ["sealed-member-1", "sealed-member-2"]
    );
    for (index, atom) in historical.iter().enumerate() {
        assert_eq!(atom.source_order, Some(u64::try_from(index)? + 1));
        assert_eq!(atom.completion_item_id.as_deref(), Some(atom.id.as_str()));
        assert_eq!(atom.completion_seq, Some(u64::try_from(index)? + 1));
        assert!(matches!(
            atom.lifecycle,
            ChatAtomLifecycle::Terminal {
                outcome: ChatTerminalOutcome::Completed,
                ..
            }
        ));
        assert!(matches!(atom.payload, Some(PayloadData::Deferred { .. })));
        assert_eq!(atom.contents.len(), 1);
        assert_body(
            db,
            &atom.contents[0].reference,
            &atom.id,
            "part.reasoningText.0",
            format!("历史成员正文 {} 🦀", index + 1).as_bytes(),
        )
        .await?;
    }
    let sealed = &items[1];
    assert_eq!(sealed.kind, TimelineItemKind::Text);
    assert_eq!(sealed.content_item_id.as_deref(), Some("sealed-text"));
    assert_eq!(sealed.contents.len(), 1);
    assert_body(
        db,
        &sealed.contents[0].reference,
        "sealed-text",
        "body",
        "封口正文 retained 🦀".as_bytes(),
    )
    .await?;
    Ok((current, members))
}

#[tokio::test]
async fn failed_backfill_rolls_back_then_fresh_retry_applies_once_and_restores_recovery()
-> Result<()> {
    // One deadline bounds the entire scenario; it is not a migration latency requirement.
    tokio::time::timeout(
        crate::runtime_test_support::integration_test_deadline()?,
        formal_migration_round_trip(),
    )
    .await
    .context("Timeline migration regression exceeded its watchdog")?
}

async fn published_members(old_columns: bool) -> Result<(tempfile::TempDir, std::path::PathBuf)> {
    let (directory, path, _, _) = schema14().await?;
    let db = super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
        .await?;
    prepare_published16(&db).await?;
    assert_eq!(version(&db).await?, 16);
    db.execute_raw(statement(
        "DELETE FROM seaql_migrations WHERE version=?",
        vec![MEMBER_READ_METADATA.into()],
    ))
    .await?;
    if old_columns {
        db.execute_unprepared(
            "ALTER TABLE timeline_item_members DROP COLUMN updated_effect;
            ALTER TABLE timeline_item_members DROP COLUMN payload_bytes;",
        )
        .await?;
    }
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM seaql_migrations WHERE version=?",
            vec![BACKGROUND_RESULTS.into()]
        ))
        .await?
        .is_some()
    );
    db.close().await?;
    Ok((directory, path))
}

#[tokio::test]
async fn applied_background_migration_and_both_published_member_layouts_reopen_without_rebuild()
-> Result<()> {
    for old_columns in [true, false] {
        let (_directory, path) = published_members(old_columns).await?;
        let db =
            super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
                .await?;
        let source = source_bytes(&db).await?;
        let derived = derived_bytes(&db).await?;
        let ledger = migration_records(&db).await?;
        install_output_rejections(&db).await?;
        if old_columns {
            db.execute_unprepared("DROP TRIGGER reject_member_update;
                CREATE TRIGGER reject_member_update BEFORE UPDATE OF item_id,member_order,member_id,completion_item_id,admitted_effect,metadata ON timeline_item_members
                BEGIN SELECT RAISE(ABORT,'member metadata upgrade rewrote original members'); END;").await?;
        }
        db.close().await?;

        let db =
            super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
                .await?;
        prepare_published16(&db).await?;
        assert_eq!(source_bytes(&db).await?, source);
        assert_eq!(derived_bytes(&db).await?, derived);
        let upgraded_ledger = migration_records(&db).await?;
        assert_eq!(upgraded_ledger.len(), ledger.len() + 1);
        assert!(ledger.iter().all(|record| upgraded_ledger.contains(record)));
        let invalid = db.query_one_raw(statement("SELECT 1 FROM timeline_item_members m
            LEFT JOIN conversation_items c ON c.item_id=m.completion_item_id
            WHERE m.updated_effect>4 OR m.updated_effect<m.admitted_effect
              OR (m.completion_item_id IS NOT NULL AND m.payload_bytes IS NOT length(c.payload)) LIMIT 1", vec![])).await?;
        assert!(invalid.is_none());
        prepare_published16(&db).await?;
        assert_eq!(migration_records(&db).await?, upgraded_ledger);
        assert_eq!(derived_bytes(&db).await?, derived);
        // The later named tail migration deliberately rebuilds derived data.
        // Only this fixture owns these rejection triggers.
        for row in db
            .query_all_raw(statement(
                "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'reject_%'",
                vec![],
            ))
            .await?
        {
            let name: String = row.try_get("", "name")?;
            db.execute_unprepared(&format!("DROP TRIGGER \"{}\"", name.replace('"', "\"\"")))
                .await?;
        }
        db.close().await?;
        let store = HistoryStore::open(&path, THREAD).await?;
        store.prepare_conversation_read().await?;
        assert_migrated_content(&store).await?;
        let latest = migration_records(&store.writer().await?.db).await?;
        let appended_steps = [
            TIMELINE_BACKGROUND_TAIL,
            COMPLETION_BOUNDARY,
            IMMUTABLE_COMPLETION_RUNS,
            WORK_SNAPSHOTS,
        ];
        assert_eq!(latest.len(), upgraded_ledger.len() + appended_steps.len());
        for step in appended_steps {
            assert!(latest.iter().any(|record| record.contains(step)));
        }
        assert!(upgraded_ledger.iter().all(|record| latest.contains(record)));
        store.close_for_deletion().await?;
    }
    Ok(())
}

#[tokio::test]
async fn member_metadata_ddl_and_receipt_roll_back_then_retry_preserves_the_original_cut()
-> Result<()> {
    let (_directory, path) = published_members(true).await?;
    let db = super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
        .await?;
    let source = source_bytes(&db).await?;
    let derived = derived_bytes(&db).await?;
    let ledger = migration_records(&db).await?;
    db.execute_unprepared(&format!("CREATE TRIGGER reject_member_metadata BEFORE INSERT ON seaql_migrations
        WHEN NEW.version='{MEMBER_READ_METADATA}' BEGIN SELECT RAISE(ABORT,'member metadata commit fault'); END;")).await?;
    db.close().await?;
    let store = HistoryStore::open(&path, THREAD).await?;
    let failure = {
        let db =
            super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
                .await?;
        let result = prepare_published16(&db).await;
        db.close().await?;
        result
    }
    .expect_err("the Applied record is in the migration transaction");
    assert!(
        format!("{failure:#}").contains("member metadata commit fault"),
        "{failure:#}"
    );
    store.close_for_deletion().await?;
    let db = super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
        .await?;
    assert!(!member_read_metadata::validate_source(&db).await?);
    assert_eq!(source_bytes(&db).await?, source);
    assert_eq!(derived_bytes(&db).await?, derived);
    assert_eq!(migration_records(&db).await?, ledger);
    db.execute_unprepared("DROP TRIGGER reject_member_metadata")
        .await?;
    prepare_published16(&db).await?;
    assert_eq!(source_bytes(&db).await?, source);
    assert_eq!(derived_bytes(&db).await?, derived);
    db.close().await?;
    let store = HistoryStore::open(&path, THREAD).await?;
    store.prepare_conversation_read().await?;
    assert_migrated_content(&store).await?;
    store.close_for_deletion().await?;
    Ok(())
}

#[tokio::test]
async fn applied_member_metadata_with_missing_columns_is_corruption_and_never_repaired_on_read()
-> Result<()> {
    let (_directory, path) = published_members(true).await?;
    let db = super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
        .await?;
    db.execute_raw(statement(
        "INSERT INTO seaql_migrations(version,applied_at) VALUES(?,1)",
        vec![MEMBER_READ_METADATA.into()],
    ))
    .await?;
    let source = source_bytes(&db).await?;
    let derived = derived_bytes(&db).await?;
    let ledger = migration_records(&db).await?;
    db.close().await?;
    let store = HistoryStore::open(&path, THREAD).await?;
    assert!(store.prepare_conversation_read().await.is_err());
    store.close_for_deletion().await?;
    let db = super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
        .await?;
    assert!(!member_read_metadata::validate_source(&db).await?);
    assert_eq!(source_bytes(&db).await?, source);
    assert_eq!(derived_bytes(&db).await?, derived);
    assert_eq!(migration_records(&db).await?, ledger);
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn member_metadata_rejects_incomplete_layout_or_missing_completion_without_changing_the_source()
-> Result<()> {
    for corruption in [
        "ALTER TABLE timeline_item_members ADD COLUMN updated_effect INTEGER NOT NULL DEFAULT 0",
        "DELETE FROM conversation_items WHERE item_id='sealed-member-1'",
    ] {
        let (_directory, path) = published_members(true).await?;
        let db =
            super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
                .await?;
        db.execute_unprepared(corruption).await?;
        let source = source_bytes(&db).await?;
        let derived = derived_bytes(&db).await?;
        let ledger = migration_records(&db).await?;
        let columns = db
            .query_all_raw(statement(
                "SELECT name FROM pragma_table_info('timeline_item_members') ORDER BY cid",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "name"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        db.close().await?;
        let store = HistoryStore::open(&path, THREAD).await?;
        assert!(store.prepare_conversation_read().await.is_err());
        store.close_for_deletion().await?;
        let db =
            super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
                .await?;
        assert_eq!(source_bytes(&db).await?, source);
        assert_eq!(derived_bytes(&db).await?, derived);
        assert_eq!(migration_records(&db).await?, ledger);
        let after = db
            .query_all_raw(statement(
                "SELECT name FROM pragma_table_info('timeline_item_members') ORDER BY cid",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "name"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(after, columns);
        db.close().await?;
    }
    Ok(())
}

async fn formal_migration_round_trip() -> Result<()> {
    let (_directory, path, original_source, original_current) = schema14().await?;
    let fault =
        super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
            .await?;
    let original_ledger = migration_records(&fault).await?;
    fault
        .execute_unprepared(
            "CREATE TRIGGER reject_timeline_finish BEFORE UPDATE OF schema_version ON history_meta
             WHEN NEW.schema_version=15
             BEGIN
               SELECT CASE WHEN
                 (SELECT COUNT(*) FROM timeline_item_members)=5
                 AND (SELECT COUNT(*) FROM timeline_items WHERE location='history')=2
                 AND EXISTS(SELECT 1 FROM conversation_atom_facts)
                 AND EXISTS(SELECT 1 FROM timeline_projection_state
                   WHERE source_effect_seq=4 AND next_position=2
                     AND projection_generation<>'' AND length(recovery)>0)
                 AND (SELECT json_array_length(payload,'$.items')
                      FROM conversation_view_state WHERE singleton_id=1)=1
               THEN RAISE(ABORT,'controlled timeline finish failure')
               ELSE RAISE(ABORT,'timeline finish reached without complete backfill') END;
             END",
        )
        .await?;
    fault.close().await?;

    let failed = HistoryStore::open(&path, THREAD).await?;
    let error = failed
        .prepare_history_access()
        .await
        .expect_err("final migration write must fail");
    assert!(
        format!("{error:#}").contains("controlled timeline finish failure"),
        "{error:#}"
    );
    assert!(failed.state.writer.get().is_none());
    failed.close_for_deletion().await?;
    drop(failed);

    let inspect = super::super::super::connect_read_only(&path).await?;
    assert_eq!(version(&inspect).await?, 14);
    validate_source(&inspect).await?;
    assert!(
        inspect
            .query_all_raw(statement(
                "SELECT name FROM sqlite_schema
                 WHERE name IN ('conversation_atom_facts_by_admission',
                   'conversation_sources_by_timeline_end','timeline_items_by_commit',
                   'timeline_items_by_location_position')",
                vec![],
            ))
            .await?
            .is_empty(),
        "the migration's output indexes must roll back with its tables and head"
    );
    assert_eq!(source_bytes(&inspect).await?, original_source);
    assert_eq!(migration_records(&inspect).await?, original_ledger);
    assert_eq!(
        inspect
            .query_one_raw(statement(
                "SELECT payload FROM conversation_view_state WHERE singleton_id=1",
                vec![],
            ))
            .await?
            .context("rolled-back current")?
            .try_get::<Vec<u8>>("", "payload")?,
        original_current,
        "rebuilt current must roll back with DDL, recovery and generation"
    );
    assert!(
        inspect
            .query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![TIMELINE_ITEMS.into()],
            ))
            .await?
            .is_none(),
        "failed transaction must not publish the Applied record"
    );
    inspect.close().await?;

    let repair =
        super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
            .await?;
    repair
        .execute_unprepared("DROP TRIGGER reject_timeline_finish")
        .await?;
    repair.close().await?;

    let migrated = HistoryStore::open(&path, THREAD).await?;
    migrated.prepare_history_access().await?;
    let db = &migrated.writer().await?.db;
    assert_eq!(version(db).await?, HISTORY_SCHEMA_VERSION);
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM seaql_migrations WHERE version=?",
            vec![TIMELINE_ITEMS.into()],
        ))
        .await?
        .is_some()
    );
    assert_eq!(source_bytes(db).await?, original_source);
    let applied_ledger = migration_records(db).await?;
    assert_eq!(
        applied_ledger.len(),
        original_ledger.len() + 7,
        "content preparation appends the seven named content/display upgrades, not lifecycle migrations"
    );
    let new_steps = db
        .query_all_raw(statement(
            "SELECT version FROM seaql_migrations WHERE version IN (?,?,?,?,?,?,?) ORDER BY version",
            vec![
                TIMELINE_ITEMS.into(),
                TIMELINE_THINKING_SUMMARY.into(),
                SOURCE_CLASSIFICATION.into(),
                COMPLETION_BOUNDARY.into(),
                TIMELINE_BACKGROUND_TAIL.into(),
                IMMUTABLE_COMPLETION_RUNS.into(),
                WORK_SNAPSHOTS.into(),
            ],
        ))
        .await?
        .into_iter()
        .map(|row| row.try_get::<String>("", "version"))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    assert_eq!(
        new_steps,
        [
            TIMELINE_ITEMS,
            SOURCE_CLASSIFICATION,
            TIMELINE_THINKING_SUMMARY,
            COMPLETION_BOUNDARY,
            TIMELINE_BACKGROUND_TAIL,
            IMMUTABLE_COMPLETION_RUNS,
            WORK_SNAPSHOTS
        ]
    );
    for record in &original_ledger {
        assert!(
            applied_ledger.contains(record),
            "an earlier Applied record changed"
        );
    }
    let migrator = Migrator {
        thread_id: THREAD.into(),
        execution_identity: None,
        bot_root: None,
    };
    let pending = migrator.get_pending_migrations_read_only(db).await?;
    assert!(
        pending
            .iter()
            .all(|step| is_lifecycle_migration(step.name()))
    );
    assert!(pending.iter().any(|step| step.name() == MODEL_ACCESS));
    assert!(pending.iter().any(|step| step.name() == EXECUTION_IDENTITY));
    let (current, members) = assert_migrated_content(&migrated).await?;
    let original_cut: CurrentProjection = serde_json::from_slice(&original_current)?;
    let mut expected_current = original_cut;
    let archived_current: CurrentProjection = serde_json::from_slice(
        &db.query_one_raw(statement(
            "SELECT payload FROM completion_boundary_archive_view_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
        .context("archived current")?
        .try_get::<Vec<u8>>("", "payload")?,
    )?;
    expected_current.items = archived_current.items.clone();
    assert_eq!(
        archived_current, expected_current,
        "migration archives the legacy cut without rewriting its non-Timeline material"
    );

    let database_identity = migrated.conversation_database_id().await?;
    assert!(
        migrated
            .cold_current_state()
            .await?
            .context("cold state")?
            .projection()
            .atoms
            .is_empty(),
        "ordinary cold browsing cannot restore the legacy active group"
    );
    let derived = derived_bytes(db).await?;
    migrated.close_for_deletion().await?;
    drop(migrated);

    let guard =
        super::super::super::connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite)
            .await?;
    install_output_rejections(&guard).await?;
    guard.close().await?;

    let reopened = HistoryStore::open(&path, THREAD).await?;
    reopened.prepare_history_access().await?;
    assert_eq!(
        reopened.conversation_database_id().await?,
        database_identity
    );
    assert_eq!(
        source_bytes(&reopened.writer().await?.db).await?,
        original_source
    );
    assert_eq!(derived_bytes(&reopened.writer().await?.db).await?, derived);
    assert_eq!(
        migration_records(&reopened.writer().await?.db).await?,
        applied_ledger
    );
    let (reopened_current, reopened_members) = assert_migrated_content(&reopened).await?;
    ensure!(
        reopened_current == current && reopened_members == members,
        "ordinary reopen changed the migrated current"
    );
    reopened.close_for_deletion().await?;
    Ok(())
}
