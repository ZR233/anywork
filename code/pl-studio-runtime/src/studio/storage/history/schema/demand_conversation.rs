//! The single schema-11 → schema-12 content transition. The manager supplies the real transaction;
//! no pool acquisition, live owner, tool decoder or execution activation occurs inside it.

use super::super::conversation::{
    self,
    current::{CurrentContentWrite, CurrentEntryChange, CurrentEntryWrite, PreparedCurrent},
};
use super::*;
use pl_core::chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor};
use pl_protocol::{
    ContentOwner, ContentRef, ContentTarget, CurrentCollectionRef, CurrentPlanHead,
    CurrentProjection, CurrentTurnHead, ThreadStatus,
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

#[cfg(test)]
mod tests;

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
    let mut prepared = PreparedCurrent {
        projection: CurrentProjection::empty(watermark, ThreadStatus::Idle),
        changes: Arc::from([]),
        contents: Arc::from([]),
    };
    let Some(checkpoint) = checkpoint::read(db, thread_id).await? else {
        // v2 imports can prepare their SQLite facts before importing the external checkpoint.
        // There is no persisted execution source yet; that explicit import reseeds this projection
        // in its checkpoint transaction before its preparation barrier is released.
        return conversation::current::apply(db, watermark, &prepared).await;
    };
    ensure!(
        checkpoint.history_fence == watermark,
        "current migration checkpoint fence differs"
    );
    let state = &checkpoint.state;
    prepared.projection.logical_status = crate::studio::thread_projection::status(state);
    if let Some(turn) = crate::studio::thread_projection::project_active_turn(thread_id, state, 0)?
        && let Some(phase) = turn.phase()
    {
        prepared.projection.active_turn = Some(CurrentTurnHead {
            children_parent_id: Some(
                pl_core::chat::ChatKey::new("turn", &turn.id)?
                    .as_str()
                    .to_owned(),
            ),
            id: turn.id,
            phase,
        });
    }
    let mut entries = Vec::new();
    let mut contents = Vec::new();
    if let Some(activity) =
        crate::studio::thread_projection::project_activity(thread_id, state, None)
    {
        prepared.projection.active = Some(pl_protocol::CurrentActivityHead {
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
        prepared.projection.collections.push(CurrentCollectionRef {
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
        prepared.projection.interactions = Some(CurrentCollectionRef {
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
        prepared.projection.plan = Some(CurrentPlanHead {
            revision: plan.revision,
            phase: plan.state,
            document,
        });
        if !plan.history_tail.is_empty() {
            prepared.projection.collections.push(CurrentCollectionRef {
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
    prepared.changes = Arc::from(entries);
    prepared.contents = Arc::from(contents);
    // Persisted running remains a logical fact; it does not reactivate the old execution.
    prepared.projection.execution_present = false;
    conversation::current::apply(db, watermark, &prepared).await
}
