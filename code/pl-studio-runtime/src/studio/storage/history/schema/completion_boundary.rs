//! Named completion-boundary upgrade. Unique legacy material stays in managed archive tables.
use super::super::conversation;
use super::legacy_timeline_store as timeline;
use super::*;

pub(super) struct CompletionBoundary;
impl MigrationName for CompletionBoundary {
    fn name(&self) -> &str {
        COMPLETION_BOUNDARY
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CompletionBoundary {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        async {
            let db = manager.get_connection();
            ensure!(version(db).await? == 17, "completion boundary requires schema 17");
            // This step runs after the published TimelineBackgroundTail step. Its layout and
            // recovery decoding are validated before moving any original material.
            demand_conversation::validate_tables(db).await?;
            timeline::validate_tables(db).await?;
            validate_saved_heads(db).await?;
            let row = db.query_one_raw(statement(
                "SELECT database_id,applied_write_seq FROM history_meta WHERE id=1",vec![],
            )).await?.context("completion boundary has no history identity")?;
            db.execute_unprepared("
                ALTER TABLE conversation_view_state RENAME TO completion_boundary_archive_view_state;
                ALTER TABLE conversation_view_entries RENAME TO completion_boundary_archive_view_entries;
                ALTER TABLE timeline_items RENAME TO completion_boundary_archive_timeline_items;
                ALTER TABLE timeline_item_members RENAME TO completion_boundary_archive_timeline_members;
                CREATE TABLE completion_boundary_archive_projection_state AS SELECT * FROM timeline_projection_state;
                DROP INDEX timeline_items_by_commit;
                DROP INDEX timeline_items_by_location_position;
                DROP INDEX timeline_members_by_member;
            ").await?;
            archive_unfinished_contents(db).await?;
            db.execute_unprepared(timeline::complete::CREATE).await?;
            timeline::complete::rebuild(db,
                &row.try_get::<String>("","database_id")?,
                uuid::Uuid::new_v4().to_string(),
                u64::try_from(row.try_get::<i64>("","applied_write_seq")?)?,
            ).await?;
            timeline::complete::validate(db).await?;
            let head = timeline::read_state(db).await?.context("completion boundary has no recovery cut")?;
            timeline::complete::restore(db, &row.try_get::<String>("","database_id")?, &head).await?;
            super::legacy_current::validate_cold_domains(db).await?;
            Ok::<_, anyhow::Error>(())
        }.await.map_err(conversion)
    }
}

pub(in crate::studio::storage::history) async fn applied(
    db: &impl ConnectionTrait,
) -> Result<bool> {
    Ok(Migrator {
        thread_id: String::new(),
        bot_root: None,
        execution_identity: None,
    }
    .get_applied_migrations_read_only(db)
    .await?
    .iter()
    .any(|step| step.name() == COMPLETION_BOUNDARY))
}

pub(super) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 17,
        "completion boundary requires schema 17"
    );
    validate_preserved(db).await?;
    timeline::complete::validate(db).await
}

pub(super) async fn validate_preserved(db: &impl ConnectionTrait) -> Result<()> {
    super::validate_tables(db).await?;
    for sql in [
        "SELECT seq,item_id,query_class,parent_id,payload,metadata FROM conversation_items LIMIT 0",
        "SELECT owner_key,content_key,payload FROM conversation_contents LIMIT 0",
        "SELECT owner_key,content_key,byte_offset,data FROM conversation_content_chunks LIMIT 0",
        "SELECT singleton_id,payload FROM completion_boundary_archive_view_state LIMIT 0",
        "SELECT collection,position,entry_id,payload FROM completion_boundary_archive_view_entries LIMIT 0",
        "SELECT item_id,metadata FROM completion_boundary_archive_timeline_items LIMIT 0",
        "SELECT item_id,member_order,member_id,metadata FROM completion_boundary_archive_timeline_members LIMIT 0",
        "SELECT projection_generation,recovery FROM completion_boundary_archive_projection_state LIMIT 0",
        "SELECT owner_key,content_key,payload FROM completion_boundary_archive_contents LIMIT 0",
        "SELECT owner_key,content_key,byte_offset,data FROM completion_boundary_archive_content_chunks LIMIT 0",
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
            "completion_boundary_archive_contents",
            &["owner_key", "content_key"][..],
            false,
            &[][..],
        ),
        (
            "completion_boundary_archive_content_chunks",
            &["owner_key", "content_key", "byte_offset"][..],
            false,
            &[][..],
        ),
        (
            "completion_boundary_archive_view_entries",
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
        "completion_boundary_archive_view_entries",
        &["collection", "entry_id"],
        false,
    )
    .await?;
    model_route_head::validate_tables(db).await?;
    atom_metadata::validate_tables(db).await?;
    checkpoint::read_model_route_head(db).await?;
    Ok(())
}

/// Migration-only relocation. No normal writer can take over an unfinished body.
async fn archive_unfinished_contents(db: &impl ConnectionTrait) -> Result<()> {
    use conversation::content;
    use pl_core::chat::ChatKey;
    use pl_protocol::{ChatAtom, ContentTarget};

    db.execute_unprepared(
        "
        CREATE TABLE completion_boundary_archive_contents (
            owner_key TEXT NOT NULL, content_key TEXT NOT NULL, payload BLOB NOT NULL,
            PRIMARY KEY(owner_key,content_key)) WITHOUT ROWID;
        CREATE TABLE completion_boundary_archive_content_chunks (
            owner_key TEXT NOT NULL, content_key TEXT NOT NULL,
            byte_offset INTEGER NOT NULL, data BLOB NOT NULL,
            PRIMARY KEY(owner_key,content_key,byte_offset)) WITHOUT ROWID;
    ",
    )
    .await?;
    let mut after = (String::new(), String::new());
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT owner_key,content_key,payload FROM conversation_contents
             WHERE (owner_key,content_key)>(?,?) ORDER BY owner_key,content_key LIMIT 32",
                vec![after.0.clone().into(), after.1.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let owner: String = row.try_get("", "owner_key")?;
            let key: String = row.try_get("", "content_key")?;
            after = (owner.clone(), key.clone());
            let payload: Vec<u8> = row.try_get("", "payload")?;
            let manifest = content::manifest(&payload)?;
            if manifest.sealed {
                continue;
            }
            let identity = ChatKey::from_encoded(owner.clone())?;
            ensure!(!key.is_empty(), "unfinished content has no key");
            if let Some(id) = owner.strip_prefix("4:item") {
                ensure!(
                    ChatKey::new("item", id)? == identity,
                    "invalid unfinished item owner"
                );
                ensure!(
                    db.query_one_raw(statement(
                        "SELECT 1 FROM conversation_items WHERE item_id=?",
                        vec![id.into()],
                    ))
                    .await?
                    .is_none(),
                    "unfinished content belongs to a completed item"
                );
                ensure!(
                    db.query_one_raw(statement(
                        "SELECT 1 FROM history_items WHERE item_id=?
                     UNION ALL SELECT 1 FROM conversation_atom_facts WHERE atom_id=? LIMIT 1",
                        vec![id.into(), id.into()],
                    ))
                    .await?
                    .is_some(),
                    "unfinished content has no original owner"
                );
            } else if let Some(encoded) = owner.strip_prefix("7:current") {
                let (domain, id, revision): (String, String, u64) = serde_json::from_str(encoded)?;
                ensure!(
                    crate::studio::conversation_identity::content_owner_key(
                        &pl_protocol::ContentOwner::Current {
                            domain,
                            id,
                            revision
                        },
                    )? == identity,
                    "invalid unfinished current owner"
                );
                let row = db.query_one_raw(statement(
                    "SELECT payload FROM completion_boundary_archive_view_state WHERE singleton_id=1",vec![],
                )).await?.context("unfinished current has no archived owner")?;
                let original: super::legacy_timeline_types::CurrentProjection =
                    serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
                let referenced = super::legacy_current::references(&original).any(|reference| {
                    matches!(&reference.target, ContentTarget::Body {owner: candidate,key: candidate_key}
                        if crate::studio::conversation_identity::content_owner_key(candidate).as_ref().ok()==Some(&identity)
                            && candidate_key==&key)
                });
                let entry = db
                    .query_one_raw(statement(
                        "SELECT 1 FROM completion_boundary_archive_view_entries
                     WHERE json_extract(CAST(payload AS TEXT),'$.owner')=?
                       AND json_extract(CAST(payload AS TEXT),'$.key')=? LIMIT 1",
                        vec![owner.clone().into(), key.clone().into()],
                    ))
                    .await?;
                ensure!(
                    referenced || entry.is_some(),
                    "unfinished current content has no original owner reference"
                );
            } else {
                anyhow::bail!("unfinished content has an unknown owner domain");
            }
            // Frozen references can name another owner. Check all completion envelopes in
            // bounded pages, rather than assuming the owning item's absence proves non-use.
            let mut seq = 0i64;
            loop {
                let records = db.query_all_raw(statement(
                    "SELECT seq,metadata FROM conversation_items WHERE seq>? ORDER BY seq LIMIT 128",
                    vec![seq.into()],
                )).await?;
                if records.is_empty() {
                    break;
                }
                for record in records {
                    seq = record.try_get("", "seq")?;
                    let atom: ChatAtom =
                        serde_json::from_slice(&record.try_get::<Vec<u8>>("", "metadata")?)?;
                    for body in atom.contents {
                        if let ContentTarget::Body {
                            owner: referenced,
                            key: referenced_key,
                        } = body.reference.target
                        {
                            ensure!(
                                crate::studio::conversation_identity::content_owner_key(
                                    &referenced
                                )? != identity
                                    || referenced_key != key,
                                "unfinished content is referenced by a completion"
                            );
                        }
                    }
                }
            }
            // Validate the entire old body before relocation; preserve the original payload
            // and every chunk byte/offset, not a re-encoded manifest or a sealed prefix.
            let mut offset = 0u64;
            let mut last_chunk = -1i64;
            ensure!(db.query_one_raw(statement(
                "SELECT 1 FROM conversation_content_chunks WHERE owner_key=? AND content_key=? AND byte_offset<0 LIMIT 1",
                vec![owner.clone().into(),key.clone().into()],
            )).await?.is_none(), "unfinished content has a negative chunk offset");
            loop {
                let chunks = db
                    .query_all_raw(statement(
                        "SELECT byte_offset,length(data) AS size FROM conversation_content_chunks
                     WHERE owner_key=? AND content_key=? AND byte_offset>?
                     ORDER BY byte_offset LIMIT 32",
                        vec![owner.clone().into(), key.clone().into(), last_chunk.into()],
                    ))
                    .await?;
                if chunks.is_empty() {
                    break;
                }
                for chunk in chunks {
                    last_chunk = chunk.try_get("", "byte_offset")?;
                    ensure!(
                        last_chunk == integer(offset)?,
                        "unfinished content chunks have a gap or overlap"
                    );
                    let size = u64::try_from(chunk.try_get::<i64>("", "size")?)?;
                    ensure!(size > 0, "unfinished content has an empty chunk");
                    offset = offset
                        .checked_add(size)
                        .context("unfinished content size overflow")?;
                }
            }
            ensure!(
                offset == manifest.byte_length,
                "unfinished content byte length differs"
            );
            for sql in [
                "INSERT INTO completion_boundary_archive_contents SELECT * FROM conversation_contents WHERE owner_key=? AND content_key=?",
                "INSERT INTO completion_boundary_archive_content_chunks SELECT * FROM conversation_content_chunks WHERE owner_key=? AND content_key=?",
                "DELETE FROM conversation_content_chunks WHERE owner_key=? AND content_key=?",
                "DELETE FROM conversation_contents WHERE owner_key=? AND content_key=?",
            ] {
                db.execute_raw(statement(
                    sql,
                    vec![owner.clone().into(), key.clone().into()],
                ))
                .await?;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::storage::history::{connect, conversation};
    use anyhow::Result;
    use pl_core::{
        chat::{ChatContent, ChatContentKey, ChatItem, ContentData, ContentDescriptor},
        context::OpaquePayload,
        thread::{
            ThreadCheckpoint, ThreadSnapshot,
            extensions::ExtensionRecord,
            interactions::{InteractionRecord, InteractionRequest, InteractionState},
        },
    };
    use pl_protocol::*;
    use std::sync::Arc;

    const THREAD: &str = "completion-boundary-migration";

    struct Published16;
    impl MigratorTraitSelf for Published16 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            Migrator {
                thread_id: THREAD.into(),
                bot_root: None,
                execution_identity: None,
            }
            .migrations()
            .into_iter()
            .filter(|step| !work_snapshots::is_legacy_marker(step.name()))
            .take_while(|step| !is_lifecycle_migration(step.name()))
            .filter(|step| {
                !matches!(
                    step.name(),
                    COMPLETION_BOUNDARY | IMMUTABLE_COMPLETION_RUNS | WORK_SNAPSHOTS
                )
            })
            .collect()
        }
    }

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

    fn at(effect_seq: u64) -> ChatFactPosition {
        ChatFactPosition {
            effect_seq,
            suborder: 0,
        }
    }

    async fn seed(db: &impl ConnectionTrait) -> Result<(String, ChatAtom)> {
        use super::super::legacy_current::{CurrentContentWrite, LegacyCurrent};
        let database: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("database")?
            .try_get("", "database_id")?;
        let item = ThreadItem::new(
            "A".into(),
            THREAD.into(),
            "turn".into(),
            1,
            1,
            1,
            2,
            ThreadItemState::Thinking(ThreadThinkingItem::new(
                vec!["完整摘要".into()],
                vec!["完整正文".into()],
                ThreadContentLifecycle::completed(2),
            )),
        );
        let mut draft = crate::studio::runtime::chat_item::completion_draft(&item, 2, &database)?;
        let mut a: ChatAtom = serde_json::from_slice(&draft.metadata)?;
        a.attempt_id = Some("attempt".into());
        a.source_order = Some(1);
        a.lifecycle = ChatAtomLifecycle::Terminal {
            started: Some(at(1)),
            ended: Some(at(2)),
            outcome: ChatTerminalOutcome::Completed,
        };
        a.completion_seq = Some(1);
        draft.metadata = serde_json::to_vec(&a)?.into();
        let record = ChatItem::complete(draft, 1, None);
        timeline::append_fixture(db, &record).await?;
        let mut start = a.clone();
        start.lifecycle = ChatAtomLifecycle::Active {
            started: Some(at(1)),
            status: ChatActiveStatus::Running,
        };
        start.completion_item_id = None;
        start.completion_seq = None;
        start.finished_at = None;
        start.contents.clear();
        start.content_present = None;
        let mut b = start.clone();
        b.id = "B".into();
        b.source_order = Some(2);
        b.lifecycle = ChatAtomLifecycle::Active {
            started: Some(at(3)),
            status: ChatActiveStatus::Running,
        };
        for (atom, phase, effect) in [(&start, "start", 1), (&a, "terminal", 2), (&b, "start", 3)] {
            db.execute_raw(statement(
            "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata) VALUES(?,0,?,?,?,?)",
            vec![effect.into(),atom.id.clone().into(),phase.into(),integer(atom.source_order.unwrap())?.into(),
                serde_json::to_vec(atom)?.into()],
        )).await?;
        }
        conversation::sources::apply(
            db,
            1,
            &[ChatSourceState {
                source: a.source.clone(),
                lifecycle: ChatSourceLifecycle::Active,
                started: Some(at(1)),
                ended: None,
            }],
        )
        .await?;
        let mut state = ThreadSnapshot {
            commit_sequence: 3,
            ..Default::default()
        };
        let mut plan = crate::plan_tool::state::AgentSessionPlanMachine::new(Default::default())?;
        plan.submit(crate::plan_tool::state::AgentSessionPlanSubmitCommand {
            expected_revision: 0,
            plan: "# 完整计划\n\n- 保全旧记录".into(),
            interaction_id: "plan-confirmation".into(),
            operation_id: "submit".into(),
            argument_hash: "plan-hash".into(),
            submitted_at: 1,
        });
        let plan = plan.into_state();
        state.extensions.insert(
            crate::plan_tool::PLAN_EXTENSION.into(),
            ExtensionRecord {
                revision: 1,
                payload: crate::plan_tool::encode_plan_state(&plan)?,
            },
        );
        let interaction = pl_core::tool::opaque::tool_interaction_id("question");
        state.interactions.insert(
            interaction.clone(),
            InteractionRecord {
                created_at: 1,
                updated_at: 1,
                continuation_id: None,
                revision: 1,
                state: InteractionState::Pending,
                extension_mutations: vec![],
                request: InteractionRequest {
                    id: interaction,
                    turn_id: "turn".into(),
                    payload: OpaquePayload::new(
                        "pl.tool.user-input",
                        1,
                        serde_json::to_string(&vec![UserQuestion {
                            id: "choice".into(),
                            header: "选择".into(),
                            question: "保留吗？".into(),
                            is_other: true,
                            is_secret: false,
                            options: None,
                        }])?,
                    )?,
                },
            },
        );
        let checkpoint = ThreadCheckpoint::capture(THREAD.into(), 3, state)?;
        checkpoint::write(db, &checkpoint, None, None).await?;
        db.execute_unprepared("UPDATE history_meta SET applied_write_seq=3 WHERE id=1")
            .await?;
        super::super::seed_current(db, THREAD).await?;
        let mut current = super::super::legacy_current::read(db).await?;
        let owner = ContentOwner::Item {
            item_id: "B".into(),
        };
        let reference = ContentRef {
            database_id: database.clone(),
            target: ContentTarget::Body {
                owner: owner.clone(),
                key: "body".into(),
            },
        };
        b.contents = vec![ChatAtomContent {
            role: ChatContentRole::ReasoningSummary,
            reference: reference.clone(),
        }];
        current.atoms = vec![b];
        current.previews = vec![CurrentContentPreview {
            id: "B".into(),
            role: CurrentContentRole::Reasoning,
            text_channel: None,
            text: "旧活动前缀".into(),
            reference,
        }];
        let bytes: Arc<[u8]> = Arc::from("旧活动前缀".repeat(4096).into_bytes());
        super::super::legacy_current::apply(
        db,
        3,
        &LegacyCurrent::new(
            crate::studio::storage::history::schema::legacy_timeline_types::FrozenCurrentProjection::new(current),
            Arc::from([]),
            vec![CurrentContentWrite {
                sealed: false,
                content: Arc::new(ChatContent {
                    descriptor: ContentDescriptor {
                        key: ChatContentKey {
                            owner: crate::studio::conversation_identity::content_owner_key(&owner)?,
                            key: "body".into(),
                        },
                        byte_length: bytes.len() as u64,
                        generation: 1,
                        media_type: Some("text/plain".into()),
                    },
                    data: ContentData::Bytes(bytes),
                }),
            }]
            .into(),
        ),
    )
    .await?;
        crate::studio::storage::history::schema::legacy_timeline_store::rebuild(db, &database)
            .await?;
        Ok((database, a))
    }

    async fn rows(db: &impl ConnectionTrait, sql: &str) -> Result<Vec<String>> {
        db.query_all_raw(statement(sql, vec![]))
            .await?
            .into_iter()
            .map(|row| row.try_get("", "value").map_err(Into::into))
            .collect()
    }

    async fn originals(db: &impl ConnectionTrait) -> Result<Vec<Vec<String>>> {
        let completed = applied(db).await?;
        let mut values = vec![];
        for sql in [
            "SELECT json_array(seq,item_id,query_class,parent_id,hex(payload),hex(metadata)) AS value FROM conversation_items ORDER BY seq",
            "SELECT json_array(owner_key,content_key,hex(payload)) AS value FROM conversation_contents ORDER BY owner_key,content_key",
            "SELECT json_array(owner_key,content_key,byte_offset,hex(data)) AS value FROM conversation_content_chunks ORDER BY owner_key,content_key,byte_offset",
            "SELECT json_array(effect_seq,suborder,atom_id,phase,fact_order,hex(metadata)) AS value FROM conversation_atom_facts ORDER BY effect_seq,suborder,atom_id,phase",
            "SELECT json_array(source_key,started_effect,started_suborder,ended_effect,ended_suborder,active_observed,ended_observed,outcome) AS value FROM conversation_sources ORDER BY source_key",
            "SELECT json_array(revision,context_revision,context_count,payload,payload_hash) AS value FROM session_checkpoint",
            "SELECT json_array(ordinal,record_id,payload,payload_hash) AS value FROM current_context ORDER BY ordinal",
            "SELECT json_array(thread_id,database_id,applied_write_seq) AS value FROM history_meta",
        ] {
            let sql = if completed {
                sql.replace("FROM conversation_contents ORDER BY", "FROM (SELECT * FROM conversation_contents UNION ALL SELECT * FROM completion_boundary_archive_contents) ORDER BY")
                .replace("FROM conversation_content_chunks ORDER BY", "FROM (SELECT * FROM conversation_content_chunks UNION ALL SELECT * FROM completion_boundary_archive_content_chunks) ORDER BY")
            } else {
                sql.to_owned()
            };
            values.push(rows(db, &sql).await?);
        }
        Ok(values)
    }

    #[tokio::test]
    async fn nonempty_legacy_archive_rebuild_rollback_and_reopen_preserve_originals() -> Result<()>
    {
        let dir = tempfile::tempdir()?;
        let path = dir.path().join("history.sqlite");
        let db = connect(&path, crate::studio::paths::SqliteFileMode::Create).await?;
        Published16.up(&db, None).await?;
        let (database, a) = seed(&db).await?;
        let before = originals(&db).await?;
        let old_head = timeline::read_state(&db).await?.context("old head")?;
        let old_current = super::super::legacy_current::read(&db).await?;
        let old_group = old_current
            .items
            .iter()
            .find(|item| item.is_work_group())
            .context("old open group")?;
        let old_reference = old_group.members.as_ref().context("old members")?.clone();
        let old_view = rows(
            &db,
            "SELECT hex(payload) AS value FROM conversation_view_state",
        )
        .await?;
        let old_entries=rows(&db,"SELECT json_array(collection,position,entry_id,hex(payload)) AS value FROM conversation_view_entries ORDER BY collection,position,entry_id").await?;
        let old_members=rows(&db,"SELECT json_array(item_id,member_order,member_id,completion_item_id,hex(metadata)) AS value FROM timeline_item_members ORDER BY item_id,member_order").await?;
        // Failure occurs after archive DDL, while replay resolves a completion owner.
        let mut damaged = a.clone();
        damaged.completion_item_id = Some("missing".into());
        db.execute_raw(statement(
            "UPDATE conversation_atom_facts SET metadata=? WHERE atom_id='A' AND phase='terminal'",
            vec![serde_json::to_vec(&damaged)?.into()],
        ))
        .await?;
        let broken = originals(&db).await?;
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert!(!applied(&db).await?);
        assert_eq!(originals(&db).await?, broken);
        assert_eq!(
            rows(
                &db,
                "SELECT hex(payload) AS value FROM conversation_view_state"
            )
            .await?,
            old_view
        );
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE name='completion_boundary_archive_view_state'",
                vec![]
            ))
            .await?
            .is_none()
        );
        db.execute_raw(statement(
            "UPDATE conversation_atom_facts SET metadata=? WHERE atom_id='A' AND phase='terminal'",
            vec![serde_json::to_vec(&a)?.into()],
        ))
        .await?;
        Published17.up(&db, None).await?;
        assert!(applied(&db).await?);
        assert_eq!(originals(&db).await?, before);
        assert_eq!(
            rows(
                &db,
                "SELECT hex(payload) AS value FROM completion_boundary_archive_view_state"
            )
            .await?,
            old_view
        );
        assert_eq!(rows(&db,"SELECT json_array(collection,position,entry_id,hex(payload)) AS value FROM completion_boundary_archive_view_entries ORDER BY collection,position,entry_id").await?,old_entries);
        assert_eq!(rows(&db,"SELECT json_array(item_id,member_order,member_id,completion_item_id,hex(metadata)) AS value FROM completion_boundary_archive_timeline_members ORDER BY item_id,member_order").await?,old_members);
        let head = timeline::read_state(&db).await?.context("new head")?;
        assert_ne!(head.generation, old_head.generation);
        let cut: serde_json::Value = serde_json::from_slice(&head.recovery)?;
        assert!(cut.is_array());
        assert!(!String::from_utf8(head.recovery.clone())?.contains("旧活动前缀"));
        assert_ne!(head.generation, old_reference.projection_generation);
        assert!(
            rows(&db, "SELECT item_id AS value FROM timeline_items")
                .await?
                .is_empty()
        );
        assert!(
            rows(&db, "SELECT member_id AS value FROM timeline_item_members")
                .await?
                .is_empty()
        );
        let cold = conversation::completed::cold(&db).await?;
        assert!(cold.projection().previews.is_empty());
        assert!(!cold.projection().execution_present);
        assert_eq!(cold.interactions().len(), 1);
        assert!(
            cold.projection()
                .plan
                .as_ref()
                .and_then(|plan| plan.document.as_ref())
                .is_some()
        );
        assert!(
            cold.projection().atoms.is_empty(),
            "cold browsing does not restore legacy work groups"
        );
        // Ordinary reopen must neither rotate generation nor populate an open group.
        db.close().await?;
        let db = connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(
            timeline::archived_generation(&db).await?,
            old_head.generation
        );
        assert_eq!(originals(&db).await?, before);
        assert!(
        rows(&db, "SELECT name AS value FROM sqlite_schema WHERE name IN ('timeline_items','timeline_item_members','timeline_projection_state')")
            .await?
            .is_empty()
    );
        assert_eq!(
            database,
            rows(&db, "SELECT database_id AS value FROM history_meta").await?[0]
        );
        db.execute_unprepared("DROP TABLE completion_boundary_archive_timeline_members")
            .await?;
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE name='completion_boundary_archive_timeline_members'",
            vec![]
        ))
        .await?
        .is_none()
    );
        assert!(applied(&db).await?);
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn unfinished_completion_reference_or_incomplete_chunks_roll_back_relocation()
    -> Result<()> {
        for damage in [
            "UPDATE conversation_contents SET payload=CAST(json_set(CAST(payload AS TEXT),'$.sealed',json('false')) AS BLOB) WHERE owner_key='4:itemA'",
            "DELETE FROM conversation_content_chunks WHERE owner_key='4:itemB' AND byte_offset=0",
        ] {
            let dir = tempfile::tempdir()?;
            let db = connect(
                &dir.path().join("history.sqlite"),
                crate::studio::paths::SqliteFileMode::Create,
            )
            .await?;
            Published16.up(&db, None).await?;
            seed(&db).await?;
            db.execute_unprepared(damage).await?;
            let before = originals(&db).await?;
            assert!(
                prepare(&db, THREAD, Preparation::Schema, None)
                    .await
                    .is_err()
            );
            assert!(!applied(&db).await?);
            assert_eq!(originals(&db).await?, before);
            assert!(
                db.query_one_raw(statement(
                    "SELECT 1 FROM sqlite_schema WHERE name='completion_boundary_archive_contents'",
                    vec![],
                ))
                .await?
                .is_none()
            );
            db.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn cancelling_named_step_transaction_restores_original_keys_and_ddl() -> Result<()> {
        use sea_orm::TransactionTrait;
        let dir = tempfile::tempdir()?;
        let db = connect(
            &dir.path().join("history.sqlite"),
            crate::studio::paths::SqliteFileMode::Create,
        )
        .await?;
        Published16.up(&db, None).await?;
        seed(&db).await?;
        let before = originals(&db).await?;
        let (reached, observed) = tokio::sync::oneshot::channel();
        // Run the actual named step in its outer transaction, then cancel before the
        // framework could record Applied/commit. Dropping the transaction must undo
        // both key relocation and all DDL, not merely roll back the final index.
        {
            let work = async {
                let tx = db.begin().await?;
                CompletionBoundary.up(&SchemaManager::new(&tx)).await?;
                assert!(
                    !rows(
                        &tx,
                        "SELECT owner_key AS value FROM completion_boundary_archive_contents"
                    )
                    .await?
                    .is_empty()
                );
                reached
                    .send(())
                    .map_err(|_| anyhow::anyhow!("cancel observer gone"))?;
                std::future::pending::<()>().await;
                tx.commit().await?;
                Ok::<_, anyhow::Error>(())
            };
            tokio::pin!(work);
            tokio::select! {
                result=&mut work => { result?; anyhow::bail!("migration unexpectedly committed"); },
                result=observed => { result?; },
            }
        }
        assert!(!applied(&db).await?);
        assert_eq!(originals(&db).await?, before);
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE name='completion_boundary_archive_contents'",
                vec![],
            ))
            .await?
            .is_none()
        );
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert!(applied(&db).await?);
        db.close().await?;
        Ok(())
    }

    mod tool_restart {
        use super::*;
        use crate::studio::{
            storage::{
                history::{EffectCommit, HistoryStore},
                thread_writer::HistoryChannel,
            },
            thread_projection::LiveProjection,
        };
        use pl_core::{
            chat::{ChatHistory, ContentReadRequest, TimelineEpoch},
            context::{ContextRecord, ContextSnapshot, ContextSource},
            model::ModelToolCall,
            thread::{ThreadHandle, ToolOutcome},
        };

        #[tokio::test]
        async fn archived_tool_arguments_allow_actual_core_recovery_terminal_to_commit()
        -> Result<()> {
            eprintln!("tool recovery: creating runtime fixture");
            let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
            eprintln!("tool recovery: runtime fixture ready");
            let result = async {
        let mut thread = pl_protocol::Thread::from(env.runtime.create_thread(
            &env.project.id, "migrated interrupted tool",
        ).await?);
        thread.id = THREAD.into();
        let path = env._temp.path().join("legacy-tool.sqlite");
        let db = connect(&path, crate::studio::paths::SqliteFileMode::Create).await?;
        Published16.up(&db, None).await?;
        let (database, _) = seed(&db).await?;
        let store = HistoryStore::open(&path, THREAD).await?;
        let arguments = format!("{{\"value\":\"{}\"}}", "工具参数".repeat(30_000));
        let id = crate::studio::thread_projection::order::tool_id("old-call");
        let item = ThreadItem::new(id.clone(),THREAD.into(),"tool-turn".into(),2,1,3,3,
            ThreadItemState::Tool(ThreadToolItem::new(
                ThreadToolInvocation::new("old-call".into(),"side_effect".into(),arguments.clone()),
                ThreadToolState::Running(RunningThreadTool::new(String::new())),
            )),
        );
        store.upsert_item(&db,3,item.clone()).await?;
        let old_key = ChatContentKey {
            owner: pl_core::chat::ChatKey::new("item",&id)?,
            key:"tool.arguments".into(),
        };
        super::super::super::legacy_content::write_content(&db,&ChatContent {
            descriptor: ContentDescriptor {key:old_key.clone(),byte_length:arguments.len() as u64,
                generation:7,media_type:None},
            data:ContentData::Bytes(Arc::from(arguments.clone().into_bytes())),
        },false).await?;
        let mut checkpoint = *checkpoint::read(&db,THREAD).await?.context("checkpoint")?;
        checkpoint.state.context = ContextSnapshot {revision:1,records:vec![ContextRecord {
            id:"call-record".into(),turn_id:Some("tool-turn".into()),source:ContextSource::Assistant,
            content:vec![],tool_calls:vec![ModelToolCall {
                call_id:"old-call".into(),tool_id:"side_effect".into(),
                arguments:OpaquePayload::new("tool.arguments",1,arguments.clone())?,
                presentation_contract:None,rejection:None,
            }],
        }].into()};
        checkpoint::write(&db,&checkpoint,None,None).await?;
        let before = originals(&db).await?;
        let original_manifest = rows(&db, "SELECT json_array(owner_key,content_key,hex(payload)) AS value FROM conversation_contents WHERE content_key='tool.arguments'").await?;
        let original_chunks = rows(&db, "SELECT json_array(owner_key,content_key,byte_offset,hex(data)) AS value FROM conversation_content_chunks WHERE content_key='tool.arguments' ORDER BY byte_offset").await?;
        prepare(&db,THREAD,Preparation::Schema,None).await?;
        eprintln!("tool recovery: migration committed");
        assert_eq!(originals(&db).await?,before);
        assert_eq!(rows(&db,"SELECT json_array(owner_key,content_key,hex(payload)) AS value FROM completion_boundary_archive_contents WHERE content_key='tool.arguments'").await?,original_manifest);
        assert_eq!(rows(&db,"SELECT json_array(owner_key,content_key,byte_offset,hex(data)) AS value FROM completion_boundary_archive_content_chunks WHERE content_key='tool.arguments' ORDER BY byte_offset").await?,original_chunks);
        assert!(rows(&db,"SELECT owner_key AS value FROM conversation_contents WHERE content_key='tool.arguments'").await?.is_empty());
        db.close().await?;

        // This is the real Core recovery reducer, not a hand-constructed terminal delivery.
        let owner = ThreadHandle::resume_without_model(THREAD.into(),Some(checkpoint))?;
        let mut settled = owner.snapshot();
        let effects = owner.effect_page(3,std::num::NonZeroUsize::new(32).unwrap()).await?;
        assert!(!effects.is_empty());
        let delivery = effects.iter().flat_map(|effect| effect.deliveries.iter())
            .find(|delivery| delivery.call_id=="old-call").context("Core recovery delivery")?;
        assert!(matches!(delivery.outcome,ToolOutcome::Interrupted));
        let channel=HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let chat=pl_core::chat::Session::new(store.clone(),TimelineEpoch::new("tool-recovery")?);
        let mut projection=LiveProjection::new();
        projection.bind_execution_history(channel.order_index(),store.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        projection.seed(vec![item],Default::default());
        projection.restore_current(&chat,&thread,&settled).await?;
        eprintln!("tool recovery: current restored");
        for effect in &effects {
            // Reattach the original effect's transfer facts, which live snapshots prune.
            settled.deliveries = effect.deliveries.clone();
            let (_,mut prepared)=projection.prepare(&thread,effect,&settled,false).await?;
            projection.publish_prepared(&chat,&mut prepared).await?;
            store.commit_effect(effect.sequence,EffectCommit {
                items:&prepared.items,completions:&prepared.completions,current:&prepared.current,
                rolled_back_turns:&Default::default(),identities:&[],messages:&[],receipts:&[],
                tasks:&[],deliveries:&[],delivery_repairs:&[],attempt:effect.attempt.as_ref(),
            }).await?;
        }
        assert!(store.watermark().await?>3);
        let saved=store.read_chat_item(&id).await?.context("completed interrupted tool")?;
        let body=saved.contents.get(&old_key).context("full arguments")?;
        assert_eq!(body.data.range(0,arguments.len())?.as_bytes(),arguments.as_bytes());
        owner.close().await?;
        drop(projection);
        drop(chat);
        store.close_for_deletion().await?;
        eprintln!("tool recovery: history closed");
        let store=HistoryStore::open(&path,THREAD).await?;
        let mut recovered = Vec::new();
        while recovered.len() < arguments.len() {
            let body=ChatHistory::read_content(&store,&ContentReadRequest {
                epoch:TimelineEpoch::new("cold-tool")?,
                reference:pl_core::chat::ContentRef::Body(old_key.clone()),
                offset:recovered.len() as u64,max_bytes:64*1024,generation:None,
            }).await?;
            assert!(body.sealed);
            assert!(!body.bytes.as_bytes().is_empty());
            recovered.extend_from_slice(body.bytes.as_bytes());
        }
        assert_eq!(recovered,arguments.as_bytes());
        {
            let connection = store.writer().await?;
            let db = &connection.db;
            assert_eq!(rows(db,"SELECT json_array(owner_key,content_key,hex(payload)) AS value FROM completion_boundary_archive_contents WHERE content_key='tool.arguments'").await?,original_manifest);
            assert_eq!(rows(db,"SELECT json_array(owner_key,content_key,byte_offset,hex(data)) AS value FROM completion_boundary_archive_content_chunks WHERE content_key='tool.arguments' ORDER BY byte_offset").await?,original_chunks);
            assert_eq!(originals(db).await?[0][0],before[0][0],"unrelated completed A is unchanged");
        }
        store.close_for_deletion().await?;
        Ok::<_,anyhow::Error>(())
    }.await;
            eprintln!("tool recovery: result before runtime shutdown: {result:?}");
            env.finish(result).await
        }
    }
}
