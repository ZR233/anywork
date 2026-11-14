//! Schema 13 → 14: immutable lightweight atom metadata and actual source lifecycle only.
//! Published payloads are decoded here, never by normal storage reads or a current tool renderer.
use super::super::conversation::{self, sources};
use super::legacy_timeline_types::CurrentProjection;
use super::*;
use anyhow::Result;
use pl_core::chat::ChatKey;
use pl_protocol::*;
use serde::Deserialize;
use serde_json::{Value as Json, json};
use std::collections::{BTreeMap, BTreeSet};

pub(super) struct AtomMetadata;
// Frozen legacy delivery encoding: rename_all applies to variants only.
#[derive(Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
enum PublishedTarget {
    CallResult,
    Inbox { message_id: String },
}
impl MigrationName for AtomMetadata {
    fn name(&self) -> &str {
        ATOM_METADATA
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for AtomMetadata {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let result: anyhow::Result<()> = async {
            let db = manager.get_connection();
            ensure!(
                version(db).await? == 13,
                "atom metadata migration requires schema 13"
            );
            validate_source(db).await?;
            db.execute_unprepared(
                "ALTER TABLE conversation_items ADD COLUMN metadata BLOB NOT NULL DEFAULT X''",
            )
            .await?;
            db.execute_unprepared(sources::CREATE_SCHEMA).await?;
            migrate(db).await?;
            validate_tables(db).await?;
            set_version(db, 14).await?;
            Ok(())
        }
        .await;
        result.map_err(conversion)
    }
}
pub(super) async fn validate_source(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM pragma_table_info('conversation_items') WHERE name='metadata'",
            vec![]
        ))
        .await?
        .is_none(),
        "pending atom metadata migration has pre-existing output column; original database preserved"
    );
    ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='conversation_sources'",
            vec![]
        ))
        .await?
        .is_none(),
        "pending atom metadata migration has pre-existing source table; original database preserved"
    );
    Ok(())
}
pub(super) async fn validate_tables(db: &impl ConnectionTrait) -> Result<()> {
    let row=db.query_one_raw(statement("SELECT type,\"notnull\" FROM pragma_table_info('conversation_items') WHERE name='metadata'",vec![])).await?.context("atom metadata column missing")?;
    ensure!(
        row.try_get::<String>("", "type")?
            .eq_ignore_ascii_case("BLOB")
            && row.try_get::<i64>("", "notnull")? == 1,
        "atom metadata must be a non-null BLOB"
    );
    db.query_all_raw(statement("SELECT source_key,started_effect,started_suborder,ended_effect,ended_suborder,active_observed,ended_observed,outcome FROM conversation_sources LIMIT 0",vec![])).await?;
    validate_keys(db, "conversation_sources", &["source_key"], false, &[]).await?;
    Ok(())
}
fn kind(value: Option<&str>, channel: Option<ThreadTextChannel>) -> ChatAtomKind {
    match value {
        Some("text")
            if matches!(
                channel,
                Some(ThreadTextChannel::User | ThreadTextChannel::ParentAgent)
            ) =>
        {
            ChatAtomKind::Input
        }
        Some("text") => ChatAtomKind::Text,
        Some("thinking") => ChatAtomKind::Reasoning,
        Some("tool") => ChatAtomKind::ToolCall,
        Some("file") => ChatAtomKind::FileChange,
        Some("skill") => ChatAtomKind::Skill,
        Some("plan") => ChatAtomKind::Plan,
        Some("contextCompaction") => ChatAtomKind::Compaction,
        Some("turn") => ChatAtomKind::TurnReceipt,
        Some("agent" | "raw") => ChatAtomKind::Receipt,
        _ => ChatAtomKind::Unknown,
    }
}
fn outcome(data: &Json) -> ChatTerminalOutcome {
    match data
        .pointer("/state/kind")
        .or_else(|| data.pointer("/lifecycle/kind"))
        .or_else(|| data.pointer("/outcome/kind"))
        .and_then(Json::as_str)
    {
        Some("failed" | "denied") => ChatTerminalOutcome::Failed,
        Some("cancelled" | "interrupted" | "budgetLimited") => ChatTerminalOutcome::Cancelled,
        Some("backgroundStarted") => ChatTerminalOutcome::Transferred,
        _ => ChatTerminalOutcome::Completed,
    }
}
async fn contents(
    db: &impl ConnectionTrait,
    id: &str,
    database: &str,
) -> Result<Vec<ChatAtomContent>> {
    let owner = ChatKey::new("item", id)?;
    let rows = db
        .query_all_raw(statement(
            "SELECT content_key FROM conversation_contents WHERE owner_key=? ORDER BY content_key",
            vec![owner.as_str().into()],
        ))
        .await?;
    rows.into_iter()
        .map(|row| {
            let key: String = row.try_get("", "content_key")?;
            let role = match key.as_str() {
                "tool.arguments" => ChatContentRole::ToolArguments,
                "tool.result" => ChatContentRole::ToolOutput,
                k if k.starts_with("part.summaryText.") => ChatContentRole::ReasoningSummary,
                _ => ChatContentRole::Body,
            };
            Ok(ChatAtomContent {
                role,
                reference: ContentRef {
                    database_id: database.into(),
                    target: ContentTarget::Body {
                        owner: ContentOwner::Item { item_id: id.into() },
                        key,
                    },
                },
            })
        })
        .collect()
}
async fn execution(db: &impl ConnectionTrait, id: &str) -> Result<Option<(u64, String)>> {
    db.query_one_raw(statement(
        "SELECT ordinal,turn_id FROM history_items WHERE item_id=?",
        vec![id.into()],
    ))
    .await?
    .map(|row| {
        Ok((
            u64::try_from(row.try_get::<i64>("", "ordinal")?)?,
            row.try_get("", "turn_id")?,
        ))
    })
    .transpose()
}
async fn completed_metadata(
    db: &impl ConnectionTrait,
    id: &str,
    payload: &[u8],
    database: &str,
) -> Result<(ChatAtom, bool)> {
    let value: Json = serde_json::from_slice(payload).unwrap_or(Json::Null);
    let supported = value.get("contract").and_then(Json::as_str) == Some("anywork.chat/1");
    let original_kind = if supported {
        value.get("type").and_then(Json::as_str)
    } else {
        None
    };
    let data = value.get("data").unwrap_or(&Json::Null);
    let channel = data
        .get("channel")
        .cloned()
        .and_then(|value| serde_json::from_value(value).ok());
    let atom_kind = kind(original_kind, channel);
    let turn_id = value
        .get("turnId")
        .and_then(Json::as_str)
        .filter(|turn| !turn.is_empty())
        .map(str::to_owned);
    let call = data
        .pointer("/invocation/toolCallId")
        .and_then(Json::as_str);
    let terminal = outcome(data);
    let transferred = terminal == ChatTerminalOutcome::Transferred;
    let mut member_id = if transferred {
        call.map(|call| format!("tool:{}:{call}", call.len()))
            .unwrap_or_else(|| id.into())
    } else {
        id.into()
    };
    let known = execution(db, &member_id).await?;
    let mut source_order = known.as_ref().map(|(ordinal, _)| *ordinal);
    if let (Some(turn), Some((_, owner))) = (&turn_id, &known) {
        ensure!(
            turn == owner,
            "legacy completion {id} conflicts with its canonical Turn; original database preserved"
        );
    }
    // The published envelope carries the original Turn, even when its full execution
    // item was not retained. Do not replace this explicit provenance with a UI parent
    // or manufacture an independent receipt merely because the ordinal is unavailable.
    let mut source = if atom_kind == ChatAtomKind::Input {
        ChatSourceId::Input {
            input_id: id.into(),
        }
    } else if let Some(turn) = &turn_id {
        ChatSourceId::ForegroundTurn {
            turn_id: turn.clone(),
        }
    } else {
        ChatSourceId::Receipt {
            receipt_id: id.into(),
        }
    };
    let mut delivery = if matches!(source, ChatSourceId::ForegroundTurn { .. }) {
        ChatDeliveryKind::Foreground
    } else {
        ChatDeliveryKind::Independent
    };
    if transferred {
        delivery = ChatDeliveryKind::BackgroundHandoff;
    }
    if !transferred
        && let Some(call) = call
        && let Some(row) = db
            .query_one_raw(statement(
                "SELECT delivery_payload FROM history_tool_tasks WHERE call_id=?",
                vec![call.into()],
            ))
            .await?
        && let Some(payload) = row.try_get::<Option<String>>("", "delivery_payload")?
    {
        let target: Json = serde_json::from_str(&payload)?;
        if let PublishedTarget::Inbox { message_id } = serde_json::from_value::<PublishedTarget>(
            target
                .get("target")
                .context("legacy tool delivery has no target")?
                .clone(),
        )? {
            ensure!(
                target.get("callId").and_then(Json::as_str) == Some(call),
                "background delivery differs from its saved tool call"
            );
            ensure!(
                !message_id.is_empty(),
                "background result has an empty saved message identity"
            );
            let identity = db
                .query_one_raw(statement(
                    "SELECT item_id,sequence FROM history_message_identities WHERE message_id=?",
                    vec![message_id.clone().into()],
                ))
                .await?
                .context(
                    "background result has no durable message identity; original data preserved",
                )?;
            let identity_id: String = identity.try_get("", "item_id")?;
            let sequence = u64::try_from(identity.try_get::<i64>("", "sequence")?)?;
            ensure!(
                identity_id == crate::studio::thread_projection::order::message_id(&message_id)
                    && sequence > 0,
                "background result has conflicting durable message identity"
            );
            member_id = identity_id;
            source_order = Some(sequence);
            source = ChatSourceId::BackgroundResult { message_id };
            delivery = ChatDeliveryKind::Independent;
        }
    }
    let tool = match (
        call,
        data.pointer("/invocation/name").and_then(Json::as_str),
    ) {
        (Some(call), Some(name)) => Some(ChatToolIdentity {
            call_id: call.into(),
            name: name.into(),
        }),
        _ => None,
    };
    let atom = ChatAtom {
        id: member_id,
        completion_item_id: Some(id.into()),
        content_present: None,
        completion_seq: None,
        source_state: None,
        source,
        source_order,
        kind: atom_kind,
        delivery,
        lifecycle: ChatAtomLifecycle::Terminal {
            started: None,
            ended: None,
            outcome: terminal,
        },
        turn_id,
        attempt_id: None,
        tool,
        wait: None,
        text_channel: channel,
        started_at: None,
        finished_at: value.get("sealedAt").and_then(Json::as_i64),
        contents: contents(db, id, database).await?,
        payload: None,
    };
    let diagnostic = original_kind == Some("inference")
        || db
            .query_one_raw(statement(
                "SELECT 1 FROM history_items WHERE item_id=? AND kind='inference'",
                vec![id.into()],
            ))
            .await?
            .is_some();
    Ok((atom, diagnostic))
}

fn retain_active_bytes(bytes: &mut usize, additional: usize) -> Result<()> {
    *bytes = bytes
        .checked_add(additional)
        .context("migrated current size overflow")?;
    ensure!(
        *bytes <= CHAT_BATCH_MAX_BYTES as usize,
        "migrated current exceeds product envelope budget"
    );
    Ok(())
}

fn retain_active_atom(
    atoms: &mut BTreeMap<String, ChatAtom>,
    bytes: &mut usize,
    atom: ChatAtom,
) -> Result<()> {
    retain_active_bytes(bytes, serde_json::to_vec(&atom)?.len())?;
    atoms.insert(atom.id.clone(), atom);
    Ok(())
}

async fn active_atoms(
    db: &impl ConnectionTrait,
    current: &CurrentProjection,
    checkpoint: Option<&pl_core::thread::ThreadCheckpoint>,
    database: &str,
) -> Result<Vec<ChatAtom>> {
    struct ActiveContent {
        id: String,
        role: CurrentContentRole,
        text_channel: Option<ThreadTextChannel>,
        reference: ContentRef,
    }
    let mut active_contents: Vec<_> = current
        .previews
        .iter()
        .map(|preview| ActiveContent {
            id: preview.id.clone(),
            role: preview.role,
            text_channel: preview.text_channel,
            reference: preview.reference.clone(),
        })
        .collect();
    let mut positions = BTreeMap::new();
    for member in conversation::migration::active_members(db, current).await? {
        positions.insert(member.id.clone(), member.source_order);
        for reference in member.contents {
            if active_contents
                .iter()
                .any(|content| content.id == member.id && content.reference == reference)
            {
                continue;
            }
            let ContentTarget::Body { key, .. } = &reference.target else {
                unreachable!()
            };
            let role = match key.as_str() {
                "tool.arguments" => CurrentContentRole::ToolArguments,
                "tool.result" => CurrentContentRole::ToolOutput,
                key if key.starts_with("part.reasoningText.")
                    || key.starts_with("part.summaryText.") =>
                {
                    CurrentContentRole::Reasoning
                }
                "body" => CurrentContentRole::Response,
                key if key.starts_with("part.outputText.") => CurrentContentRole::Response,
                _ => anyhow::bail!(
                    "legacy active member {} has an unclassifiable content key; original database preserved",
                    member.id
                ),
            };
            active_contents.push(ActiveContent {
                id: member.id.clone(),
                role,
                text_channel: None,
                reference,
            });
        }
    }
    let mut atoms = BTreeMap::<String, ChatAtom>::new();
    let mut atom_bytes = 0;
    for preview in &active_contents {
        if db
            .query_one_raw(statement(
                "SELECT 1 FROM conversation_items WHERE item_id=?",
                vec![preview.id.clone().into()],
            ))
            .await?
            .is_some()
        {
            continue;
        }
        let ContentTarget::Body {
            owner: ContentOwner::Item { item_id },
            ..
        } = &preview.reference.target
        else {
            anyhow::bail!(
                "legacy preview {} has no canonical item body owner",
                preview.id
            )
        };
        ensure!(
            *item_id == preview.id,
            "legacy preview {} differs from its owner",
            preview.id
        );
        let saved = execution(db, &preview.id).await?;
        let turn = if let Some((_, turn)) = &saved {
            turn.clone()
        } else {
            let state=&checkpoint.context("legacy active preview has no canonical checkpoint; original database preserved")?.state;
            let found: Vec<_> = state
                .attempt_ids
                .iter()
                .filter(|(attempt, _)| {
                    preview
                        .id
                        .starts_with(&format!("model:{}:{attempt}:", attempt.len()))
                })
                .collect();
            ensure!(
                found.len() == 1,
                "legacy preview {} cannot be associated with a canonical source; original database preserved",
                preview.id
            );
            found[0].1.clone()
        };
        ensure!(
            !turn.is_empty(),
            "legacy preview {} has no canonical Turn",
            preview.id
        );
        let atom_kind = match preview.role {
            CurrentContentRole::Reasoning => ChatAtomKind::Reasoning,
            CurrentContentRole::Response => ChatAtomKind::Text,
            _ => ChatAtomKind::ToolCall,
        };
        let role = match preview.role {
            CurrentContentRole::Reasoning => ChatContentRole::ReasoningSummary,
            CurrentContentRole::ToolArguments => ChatContentRole::ToolArguments,
            CurrentContentRole::ToolOutput => ChatContentRole::ToolOutput,
            _ => ChatContentRole::Body,
        };
        let content = ChatAtomContent {
            role,
            reference: preview.reference.clone(),
        };
        if let Some(atom) = atoms.get_mut(&preview.id) {
            ensure!(
                atom.kind == atom_kind,
                "legacy preview has conflicting canonical roles"
            );
            if !atom.contents.contains(&content) {
                retain_active_bytes(&mut atom_bytes, 1 + serde_json::to_vec(&content)?.len())?;
                atom.contents.push(content);
            }
            continue;
        }
        retain_active_atom(
            &mut atoms,
            &mut atom_bytes,
            ChatAtom {
                id: preview.id.clone(),
                completion_item_id: None,
                content_present: None,
                completion_seq: None,
                source_state: None,
                source: ChatSourceId::ForegroundTurn {
                    turn_id: turn.clone(),
                },
                source_order: saved
                    .map(|(ordinal, _)| ordinal)
                    .or_else(|| positions.get(&preview.id).copied().flatten()),
                kind: atom_kind,
                delivery: ChatDeliveryKind::Foreground,
                lifecycle: ChatAtomLifecycle::Active {
                    started: None,
                    status: ChatActiveStatus::Running,
                },
                turn_id: Some(turn),
                attempt_id: None,
                tool: None,
                wait: None,
                text_channel: preview.text_channel,
                started_at: None,
                finished_at: None,
                contents: vec![content],
                payload: None,
            },
        )?;
    }
    if let Some(checkpoint) = checkpoint {
        for task in checkpoint.state.tasks.values().filter(|task| {
            task.status == pl_core::thread::task::TaskStatus::Running
                && task.acknowledgement.is_none()
        }) {
            let id = format!("tool:{}:{}", task.call_id.len(), task.call_id);
            if db
                .query_one_raw(statement(
                    "SELECT 1 FROM conversation_items WHERE item_id=?",
                    vec![id.clone().into()],
                ))
                .await?
                .is_some()
            {
                continue;
            }
            let known = execution(db, &id).await?;
            ensure!(
                !task.turn_id.is_empty()
                    && known.as_ref().is_none_or(|(_, turn)| turn == &task.turn_id),
                "legacy task {} conflicts with its canonical Turn",
                task.id
            );
            if let Some(atom) = atoms.get_mut(&id) {
                let tool = Some(ChatToolIdentity {
                    call_id: task.call_id.clone(),
                    name: task.tool_id.clone(),
                });
                let old_size = serde_json::to_vec(&atom.tool)?.len();
                let new_size = serde_json::to_vec(&tool)?.len();
                retain_active_bytes(&mut atom_bytes, new_size.saturating_sub(old_size))?;
                atom.tool = tool;
                continue;
            }
            retain_active_atom(
                &mut atoms,
                &mut atom_bytes,
                ChatAtom {
                    id: id.clone(),
                    completion_item_id: None,
                    content_present: None,
                    completion_seq: None,
                    source_state: None,
                    source: ChatSourceId::ForegroundTurn {
                        turn_id: task.turn_id.clone(),
                    },
                    source_order: known.map(|(ordinal, _)| ordinal),
                    kind: ChatAtomKind::ToolCall,
                    delivery: ChatDeliveryKind::Foreground,
                    lifecycle: ChatAtomLifecycle::Active {
                        started: None,
                        status: ChatActiveStatus::Running,
                    },
                    turn_id: Some(task.turn_id.clone()),
                    attempt_id: None,
                    tool: Some(ChatToolIdentity {
                        call_id: task.call_id.clone(),
                        name: task.tool_id.clone(),
                    }),
                    wait: None,
                    text_channel: None,
                    started_at: None,
                    finished_at: None,
                    contents: contents(db, &id, database).await?,
                    payload: None,
                },
            )?;
        }
    }
    Ok(atoms.into_values().collect())
}
async fn migrate(db: &impl ConnectionTrait) -> Result<()> {
    let identity = db
        .query_one_raw(statement(
            "SELECT database_id,thread_id,applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("legacy history identity missing")?;
    let database: String = identity.try_get("", "database_id")?;
    let thread: String = identity.try_get("", "thread_id")?;
    let effect = u64::try_from(identity.try_get::<i64>("", "applied_write_seq")?)?;
    let mut old: Json = serde_json::from_slice(
        &db.query_one_raw(statement(
            "SELECT payload FROM conversation_view_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
        .context("legacy current missing")?
        .try_get::<Vec<u8>>("", "payload")?,
    )?;
    if let Some(turn) = old.get_mut("activeTurn").and_then(Json::as_object_mut) {
        turn.remove("childrenParentId");
    }
    let fields = old
        .as_object_mut()
        .context("legacy current is not an object")?;
    fields.insert("sources".into(), json!([]));
    fields.insert("atoms".into(), json!([]));
    let mut current: CurrentProjection = serde_json::from_value(old)?;
    super::legacy_current::validate_database(&current, &database)?;
    let checkpoint = checkpoint::read(db, &thread).await?;
    let mut after = 0i64;
    loop {
        let Some(row)=db.query_one_raw(statement("SELECT seq,item_id,payload,query_class FROM conversation_items WHERE seq>? ORDER BY seq LIMIT 1",vec![after.into()])).await? else {break};
        after = row.try_get("", "seq")?;
        let id: String = row.try_get("", "item_id")?;
        let (atom, diagnostic) =
            completed_metadata(db, &id, &row.try_get::<Vec<u8>>("", "payload")?, &database).await?;
        let class = if diagnostic {
            "diagnostic".into()
        } else if row.try_get::<String>("", "query_class")? == "activity" {
            "conversation".into()
        } else {
            row.try_get::<String>("", "query_class")?
        };
        db.execute_raw(statement(
            "UPDATE conversation_items SET metadata=?,query_class=? WHERE item_id=?",
            vec![serde_json::to_vec(&atom)?.into(), class.into(), id.into()],
        ))
        .await?;
        if atom.kind == ChatAtomKind::TurnReceipt
            && matches!(atom.source, ChatSourceId::ForegroundTurn { .. })
        {
            let original: Json = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
            if !matches!(
                original
                    .pointer("/data/outcome/kind")
                    .and_then(Json::as_str),
                Some("completed" | "failed" | "cancelled" | "budgetLimited")
            ) {
                continue;
            }
            let ChatAtomLifecycle::Terminal { outcome, .. } = atom.lifecycle else {
                unreachable!()
            };
            sources::apply(
                db,
                effect,
                &[ChatSourceState {
                    source: atom.source,
                    lifecycle: ChatSourceLifecycle::Ended { outcome },
                    started: None,
                    ended: None,
                }],
            )
            .await?;
        }
    }
    current.atoms = active_atoms(db, &current, checkpoint.as_deref(), &database).await?;
    let mut active_sources: BTreeSet<_> = current
        .atoms
        .iter()
        .map(|atom| atom.source.clone())
        .collect();
    if let (Some(active), Some(checkpoint)) = (&current.active_turn, &checkpoint)
        && checkpoint.state.turns.iter().any(|turn| {
            turn.turn_id == active.id && matches!(turn.state, pl_core::thread::TurnState::Running)
        })
    {
        active_sources.insert(ChatSourceId::ForegroundTurn {
            turn_id: active.id.clone(),
        });
    }
    for source in &active_sources {
        sources::apply(
            db,
            effect,
            &[ChatSourceState {
                source: source.clone(),
                lifecycle: ChatSourceLifecycle::Active,
                started: None,
                ended: None,
            }],
        )
        .await?;
    }
    current.sources =
        sources::read(db, &active_sources.into_iter().collect::<Vec<_>>(), effect).await?;
    let bytes = serde_json::to_vec(&current)?;
    ensure!(
        bytes.len() <= pl_protocol::CHAT_BATCH_MAX_BYTES as usize,
        "migrated current exceeds product envelope budget"
    );
    db.execute_raw(statement(
        "UPDATE conversation_view_state SET payload=? WHERE singleton_id=1",
        vec![bytes.into()],
    ))
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::storage::history::schema::legacy_timeline_types::CurrentProjection;
    use sea_orm::DatabaseConnection;

    const THREAD: &str = "atom-migration";

    // Inspect preserved migration material, never use it as a normal current source.
    async fn archived_current(db: &impl ConnectionTrait) -> Result<CurrentProjection> {
        if !completion_boundary::applied(db).await? {
            return super::super::legacy_current::read(db).await;
        }
        let row = db
            .query_one_raw(statement(
                "SELECT payload FROM completion_boundary_archive_view_state WHERE singleton_id=1",
                vec![],
            ))
            .await?
            .context("archived current")?;
        let mut current: CurrentProjection =
            serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
        current.execution_present = false;
        Ok(current)
    }

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
                        | DISPLAY_BLOCK_ORDER
                )
            })
            .filter(|step| !matches!(step.name(), ATOM_METADATA | TIMELINE_ITEMS))
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
        let steps = Published13
            .migrations()
            .iter()
            .take_while(|step| !is_lifecycle_migration(step.name()))
            .count();
        Published13.up(&db, Some(u32::try_from(steps)?)).await?;
        assert_eq!(version(&db).await?, 13);
        Ok((dir, db))
    }

    async fn insert(db: &DatabaseConnection, seq: i64, id: &str, kind: &str) -> Result<Vec<u8>> {
        let payload = if kind == "turn" {
            turn_payload(TurnState::Completed(CompletedTurnState::new(
                None,
                10,
                TurnCompletion::Normal,
            )))?
        } else {
            serde_json::to_vec(&json!({
                "contract":"anywork.chat/1","type":kind,"turnId":"turn",
                "data":{"invocation":{"toolCallId":"call","name":"shell"},
                    "state":{"kind":"completed"},"original":{"opaque":[0,255,37]}}
            }))?
        };
        db.execute_raw(statement(
            "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload)
         VALUES(?,?,'activity',?,?)",
            vec![
                seq.into(),
                id.into(),
                ChatKey::new("turn", "turn")?.as_str().into(),
                payload.clone().into(),
            ],
        ))
        .await?;
        Ok(payload)
    }

    fn turn_payload(state: TurnState) -> Result<Vec<u8>> {
        let item = ThreadItem::new(
            "turn-receipt".into(),
            THREAD.into(),
            "turn".into(),
            1,
            1,
            1,
            10,
            ThreadItemState::Turn(ThreadTurnItem::new(state)),
        );
        Ok(
            crate::studio::runtime::chat_item::completion_draft(&item, 5, "fixture")?
                .payload
                .to_vec(),
        )
    }

    async fn seed_active_members(db: &DatabaseConnection, turn: &str) -> Result<CurrentProjection> {
        use crate::studio::storage::history::schema::legacy_current::{
            CurrentContentWrite, CurrentEntryChange, CurrentEntryWrite, LegacyCurrent,
        };
        use pl_core::chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor};
        use std::sync::Arc;
        let database: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "database_id")?;
        let mut current = CurrentProjection::empty(0, ThreadStatus::Running);
        current.collections.push(CurrentCollectionRef {
            database_id: database.clone(),
            collection: "members".into(),
            revision: 0,
        });
        let mut contents = Vec::new();
        let mut changes = Vec::new();
        for part in 1..=5_i64 {
            let id = format!("live-{part}");
            db.execute_raw(statement(
                "INSERT INTO history_items VALUES(?,? ,?,'text',1,'active',1,2,'{}',0)",
                vec![part.into(), id.clone().into(), turn.into()],
            ))
            .await?;
            let mut bodies = Vec::new();
            for index in 0..if part == 5 { 2 } else { 1 } {
                let key = format!("part.outputText.{index}");
                let reference = ContentRef {
                    database_id: database.clone(),
                    target: ContentTarget::Body {
                        owner: ContentOwner::Item {
                            item_id: id.clone(),
                        },
                        key: key.clone(),
                    },
                };
                let bytes: Arc<[u8]> = format!("原始活动内容 {part}/{index} 🦀")
                    .into_bytes()
                    .into();
                bodies.push(json!({"reference":reference,"byteLength":bytes.len(),"generation":1}));
                if current.previews.len() < 4 {
                    current.previews.push(CurrentContentPreview {
                        id: id.clone(),
                        role: CurrentContentRole::Response,
                        text_channel: Some(ThreadTextChannel::Final),
                        text: "window".into(),
                        reference: reference.clone(),
                    });
                }
                contents.push(CurrentContentWrite {
                    content: Arc::new(ChatContent {
                        descriptor: ContentDescriptor {
                            key: ChatContentKey {
                                owner: ChatKey::new("item", &id)?,
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
            }
            changes.push(CurrentEntryChange::Put(CurrentEntryWrite {
                collection: "members".into(),
                position: part,
                entry_id: id,
                payload: serde_json::to_vec(&bodies)?.into(),
            }));
        }
        crate::studio::storage::history::schema::legacy_current::apply(
        db,
        0,
        &LegacyCurrent::new(
            crate::studio::storage::history::schema::legacy_timeline_types::FrozenCurrentProjection::new(current.clone()),
            changes.into(),
            contents.into(),
        ),
    )
    .await?;
        Ok(current)
    }

    async fn active_originals(db: &DatabaseConnection) -> Result<Vec<String>> {
        let entries = if completion_boundary::applied(db).await? {
            "completion_boundary_archive_view_entries"
        } else {
            "conversation_view_entries"
        };
        let manifests = if completion_boundary::applied(db).await? {
            "(SELECT * FROM conversation_contents UNION ALL SELECT * FROM completion_boundary_archive_contents)"
        } else {
            "conversation_contents"
        };
        let chunks = if completion_boundary::applied(db).await? {
            "(SELECT * FROM conversation_content_chunks UNION ALL SELECT * FROM completion_boundary_archive_content_chunks)"
        } else {
            "conversation_content_chunks"
        };
        db.query_all_raw(statement(
            &format!(
                "SELECT json_array(owner_key,content_key,hex(payload)) AS original FROM {manifests}
         UNION ALL SELECT json_array(owner_key,content_key,byte_offset,hex(data)) FROM {chunks}
         UNION ALL SELECT json_array(collection,position,entry_id,hex(payload)) FROM {entries}
         ORDER BY original"
            ),
            vec![],
        ))
        .await?
        .into_iter()
        .map(|row| row.try_get("", "original").map_err(Into::into))
        .collect()
    }

    #[tokio::test]
    async fn complete_member_directory_survives_four_preview_limit_and_rolls_back_over_budget()
    -> Result<()> {
        let (_dir, db) = source().await?;
        let old = seed_active_members(&db, "live-turn").await?;
        assert_eq!(old.previews.len(), 4);
        let originals = active_originals(&db).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        let migrated = archived_current(&db).await?;
        assert_eq!(migrated.atoms.len(), 5);
        for part in 1..=5 {
            let atom = migrated
                .atoms
                .iter()
                .find(|atom| atom.id == format!("live-{part}"))
                .unwrap();
            assert_eq!(
                atom.source,
                ChatSourceId::ForegroundTurn {
                    turn_id: "live-turn".into()
                }
            );
            assert_eq!(atom.source_order, Some(part));
            assert_eq!(atom.contents.len(), if part == 5 { 2 } else { 1 });
            for (index, content) in atom.contents.iter().enumerate() {
                assert_eq!(
                    content.reference.target,
                    ContentTarget::Body {
                        owner: ContentOwner::Item {
                            item_id: atom.id.clone()
                        },
                        key: format!("part.outputText.{index}")
                    }
                );
            }
        }
        assert_eq!(
            active_originals(&db).await?,
            originals,
            "all body bytes, manifests and legacy member directory remain intact"
        );

        let (_dir, db) = source().await?;
        let old = seed_active_members(&db, "live-turn").await?;
        db.execute_unprepared("DELETE FROM history_items WHERE item_id='live-5'")
            .await?;
        let originals = active_originals(&db).await?;
        let error = prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .unwrap_err();
        assert!(
            format!("{error:#}").contains("canonical checkpoint"),
            "{error:#}"
        );
        assert_eq!(version(&db).await?, 13);
        validate_source(&db).await?;
        assert_eq!(active_originals(&db).await?, originals);
        assert_eq!(archived_current(&db).await?, old);

        let (_dir, db) = source().await?;
        let old = seed_active_members(&db, &"t".repeat(CHAT_BATCH_MAX_BYTES as usize)).await?;
        let originals = active_originals(&db).await?;
        let error = prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .unwrap_err();
        assert!(format!("{error:#}").contains("budget"), "{error:#}");
        assert_eq!(version(&db).await?, 13);
        validate_source(&db).await?;
        assert_eq!(active_originals(&db).await?, originals);
        assert_eq!(archived_current(&db).await?, old);
        Ok(())
    }

    #[tokio::test]
    async fn real_turn_outcome_payloads_backfill_completed_failed_and_cancelled_sources()
    -> Result<()> {
        for (state, expected) in [
            (
                TurnState::Completed(CompletedTurnState::new(None, 10, TurnCompletion::Normal)),
                ChatTerminalOutcome::Completed,
            ),
            (
                TurnState::Failed(FailedTurnState::new(
                    None,
                    10,
                    TurnFailure::permanent(TurnFailureCategory::Internal, "original failure"),
                )),
                ChatTerminalOutcome::Failed,
            ),
            (
                TurnState::Cancelled(CancelledTurnState::new(
                    None,
                    9,
                    10,
                    TurnCancellationCause::UserRequested,
                )),
                ChatTerminalOutcome::Cancelled,
            ),
        ] {
            let (_dir, db) = source().await?;
            insert(&db, 1, "turn-receipt", "turn").await?;
            let payload = turn_payload(state)?;
            let frozen: Json = serde_json::from_slice(&payload)?;
            assert!(frozen.pointer("/data/state").is_none());
            assert!(frozen.pointer("/data/outcome/kind").is_some());
            db.execute_raw(statement(
                "UPDATE conversation_items SET payload=? WHERE item_id='turn-receipt'",
                vec![payload.clone().into()],
            ))
            .await?;
            db.execute_unprepared("UPDATE history_meta SET applied_write_seq=5")
                .await?;
            prepare(&db, THREAD, Preparation::Schema, None).await?;
            let source = ChatSourceId::ForegroundTurn {
                turn_id: "turn".into(),
            };
            assert_eq!(
                sources::read(&db, std::slice::from_ref(&source), 4).await?[0].lifecycle,
                ChatSourceLifecycle::Unknown
            );
            let state = sources::read(&db, &[source], 5).await?.remove(0);
            assert_eq!(
                state.lifecycle,
                ChatSourceLifecycle::Ended { outcome: expected }
            );
            assert_eq!((state.started, state.ended), (None, None));
            assert_eq!(
                db.query_one_raw(statement(
                    "SELECT payload FROM conversation_items WHERE item_id='turn-receipt'",
                    vec![]
                ))
                .await?
                .unwrap()
                .try_get::<Vec<u8>>("", "payload")?,
                payload
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn pending_timeline_fact_output_is_rejected_without_erasing_originals() -> Result<()> {
        let (_directory, db) = source().await?;
        let payload = insert(&db, 1, "original-tool", "tool").await?;
        // A table with the next step's output name is not proof of a completed migration.
        // Even an unrecognized shape with original bytes must be preserved, never adopted/dropped.
        db.execute_unprepared(
            "CREATE TABLE conversation_atom_facts(original BLOB NOT NULL);
         INSERT INTO conversation_atom_facts VALUES(X'00ff01')",
        )
        .await?;
        for _ in 0..2 {
            let failure = prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .expect_err("pending migration cannot adopt its pre-existing output");
            assert!(
            format!("{failure:#}").contains(
                "pending timeline migration has pre-existing output table conversation_atom_facts"
            ),
            "{failure:#}"
        );
            assert_eq!(version(&db).await?, 13);
            let original = db
                .query_one_raw(statement(
                    "SELECT original FROM conversation_atom_facts",
                    vec![],
                ))
                .await?
                .context("preserved conflicting output")?;
            assert_eq!(original.try_get::<Vec<u8>>("", "original")?, [0, 255, 1]);
            let completion = db
                .query_one_raw(statement(
                    "SELECT payload FROM conversation_items WHERE item_id='original-tool'",
                    vec![],
                ))
                .await?
                .context("preserved original completion")?;
            assert_eq!(completion.try_get::<Vec<u8>>("", "payload")?, payload);
            let boundary = db
                .query_one_raw(statement(
                    "SELECT
                   (SELECT COUNT(*) FROM pragma_table_info('conversation_items')
                    WHERE name='metadata') AS metadata_columns,
                   (SELECT COUNT(*) FROM seaql_migrations WHERE version IN (?,?)) AS completed",
                    vec![ATOM_METADATA.into(), TIMELINE_ITEMS.into()],
                ))
                .await?
                .context("unmodified migration boundary")?;
            assert_eq!(boundary.try_get::<i64>("", "metadata_columns")?, 0);
            assert_eq!(boundary.try_get::<i64>("", "completed")?, 0);
        }
        Ok(())
    }

    #[tokio::test]
    async fn migration_preserves_completion_bytes_seq_parent_and_content_owners() -> Result<()> {
        let (_dir, db) = source().await?;
        let payload = insert(&db, 1, "tool", "tool").await?;
        let inference = insert(&db, 2, "diagnostic", "inference").await?;
        // Independent original execution/attachment/tool bytes must not be normalized by this step.
        db.execute_unprepared(
        "INSERT INTO history_items VALUES(7,'tool','turn','tool',1,'terminal',1,2,'{\"opaque\":true}',0);
         INSERT INTO history_items VALUES(8,'diagnostic','turn','inference',1,'terminal',1,2,'{\"diagnostic\":\"original\"}',0);
         INSERT INTO history_tool_tasks VALUES('call',1,'{\"originalTask\":true}',NULL,0);"
    ).await?;
        let owner = ChatKey::new("item", "tool")?;
        let manifest =
        br#"{"byteLength":4,"generation":7,"mediaType":"application/octet-stream","sealed":true}"#
            .to_vec();
        let body = vec![0u8, 255, 128, 39];
        db.execute_raw(statement(
            "INSERT INTO conversation_contents VALUES(?,'tool.result',?)",
            vec![owner.as_str().into(), manifest.clone().into()],
        ))
        .await?;
        db.execute_raw(statement(
            "INSERT INTO conversation_content_chunks VALUES(?,'tool.result',0,?)",
            vec![owner.as_str().into(), body.clone().into()],
        ))
        .await?;

        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
        let tool = conversation::read_item(&db, "tool").await?;
        assert_eq!(
            tool.unwrap()
                .contents
                .values()
                .next()
                .unwrap()
                .data
                .range(0, 4)?
                .as_bytes(),
            body
        );
        for (id, seq, original, class) in [
            ("tool", 1_i64, payload, "conversation"),
            ("diagnostic", 2, inference, "diagnostic"),
        ] {
            let row = db.query_one_raw(statement(
            "SELECT seq,parent_id,payload,metadata,query_class FROM conversation_items WHERE item_id=?",
            vec![id.into()],
        )).await?.unwrap();
            assert_eq!(row.try_get::<i64>("", "seq")?, seq);
            assert_eq!(
                row.try_get::<String>("", "parent_id")?,
                ChatKey::new("turn", "turn")?.as_str()
            );
            assert_eq!(row.try_get::<Vec<u8>>("", "payload")?, original);
            assert_eq!(row.try_get::<String>("", "query_class")?, class);
            let atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            assert_eq!(atom.completion_item_id.as_deref(), Some(id));
            assert!(atom.source_state.is_none());
            assert!(
                serde_json::from_slice::<Json>(&row.try_get::<Vec<u8>>("", "metadata")?)?
                    .get("sourceState")
                    .is_none(),
                "read-cut annotation is not frozen into metadata"
            );
            assert_eq!(atom.completion_seq, None);
            assert!(atom.payload.is_none());
            assert_eq!(atom.source_order, Some(if id == "tool" { 7 } else { 8 }));
            assert!(matches!(
                atom.lifecycle,
                ChatAtomLifecycle::Terminal {
                    started: None,
                    ended: None,
                    ..
                }
            ));
            if id == "tool" {
                assert_eq!(
                    atom.contents[0].reference.target,
                    ContentTarget::Body {
                        owner: ContentOwner::Item { item_id: id.into() },
                        key: "tool.result".into()
                    }
                );
            }
        }
        let row = db
            .query_one_raw(statement(
                "SELECT payload FROM conversation_contents WHERE owner_key=?",
                vec![owner.as_str().into()],
            ))
            .await?
            .unwrap();
        assert_eq!(row.try_get::<Vec<u8>>("", "payload")?, manifest);
        let row = db
            .query_one_raw(statement(
                "SELECT data FROM conversation_content_chunks WHERE owner_key=?",
                vec![owner.as_str().into()],
            ))
            .await?
            .unwrap();
        assert_eq!(row.try_get::<Vec<u8>>("", "data")?, body);
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT payload FROM history_items WHERE item_id='diagnostic'",
                vec![]
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "payload")?,
            "{\"diagnostic\":\"original\"}"
        );
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT task_payload FROM history_tool_tasks WHERE call_id='call'",
                vec![]
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "task_payload")?,
            "{\"originalTask\":true}"
        );
        Ok(())
    }

    #[tokio::test]
    async fn unattributable_active_preview_rolls_back_ddl_data_marker_and_receipt() -> Result<()> {
        let (_dir, db) = source().await?;
        let original = insert(&db, 1, "old", "thinking").await?;
        let mut current = CurrentProjection::empty(0, ThreadStatus::Running);
        current.previews.push(CurrentContentPreview {
            id: "unattributable".into(),
            role: CurrentContentRole::Response,
            text_channel: None,
            reference: ContentRef {
                database_id: "unused".into(),
                target: ContentTarget::Body {
                    owner: ContentOwner::Item {
                        item_id: "unattributable".into(),
                    },
                    key: "body".into(),
                },
            },
            text: "bounded preview".into(),
        });
        let database: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "database_id")?;
        current.previews[0].reference.database_id = database;
        let current_bytes = serde_json::to_vec(&current)?;
        db.execute_raw(statement(
            "UPDATE conversation_view_state SET payload=? WHERE singleton_id=1",
            vec![current_bytes.clone().into()],
        ))
        .await?;
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(version(&db).await?, 13);
        validate_source(&db).await?;
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT payload FROM conversation_items WHERE item_id='old'",
                vec![]
            ))
            .await?
            .unwrap()
            .try_get::<Vec<u8>>("", "payload")?,
            original
        );
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT query_class FROM conversation_items WHERE item_id='old'",
                vec![]
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "query_class")?,
            "activity"
        );
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT payload FROM conversation_view_state WHERE singleton_id=1",
                vec![]
            ))
            .await?
            .unwrap()
            .try_get::<Vec<u8>>("", "payload")?,
            current_bytes
        );
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![ATOM_METADATA.into()]
            ))
            .await?
            .is_none()
        );
        Ok(())
    }

    #[tokio::test]
    async fn terminal_source_backfill_keeps_unknown_positions_and_requires_real_terminal_evidence()
    -> Result<()> {
        let (_dir, db) = source().await?;
        insert(&db, 1, "thought", "thinking").await?;
        let receipt = insert(&db, 2, "turn-receipt", "turn").await?;
        db.execute_unprepared("UPDATE conversation_items SET payload=CAST('{\"contract\":\"anywork.chat/1\",\"type\":\"thinking\",\"turnId\":\"turn\",\"data\":{\"lifecycle\":{\"kind\":\"failed\"}}}' AS BLOB) WHERE item_id='thought'").await?;
        // Observation of an ended Turn proves its lifecycle, not when it started/ended.
        db.execute_unprepared("UPDATE history_meta SET applied_write_seq=5")
            .await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        let origin = ChatSourceId::ForegroundTurn {
            turn_id: "turn".into(),
        };
        let at4 = sources::read(&db, std::slice::from_ref(&origin), 4).await?;
        assert_eq!(at4[0].lifecycle, ChatSourceLifecycle::Unknown);
        let at5 = sources::read(&db, &[origin], 5).await?;
        assert_eq!(
            at5[0].lifecycle,
            ChatSourceLifecycle::Ended {
                outcome: ChatTerminalOutcome::Completed
            }
        );
        assert_eq!((at5[0].started, at5[0].ended), (None, None));
        let row = db
            .query_one_raw(statement(
                "SELECT payload,metadata FROM conversation_items WHERE item_id='turn-receipt'",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(row.try_get::<Vec<u8>>("", "payload")?, receipt);
        let atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        assert_eq!(
            atom.source_order, None,
            "a completion seq is not source order evidence"
        );
        let row = db
            .query_one_raw(statement(
                "SELECT metadata FROM conversation_items WHERE item_id='thought'",
                vec![],
            ))
            .await?
            .unwrap();
        let atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        assert!(matches!(
            atom.lifecycle,
            ChatAtomLifecycle::Terminal {
                outcome: ChatTerminalOutcome::Failed,
                started: None,
                ended: None
            }
        ));

        let (_dir, db) = source().await?;
        insert(&db, 1, "unsupported-turn", "turn").await?;
        db.execute_unprepared("UPDATE conversation_items SET payload=CAST('{\"contract\":\"anywork.chat/1\",\"type\":\"turn\",\"turnId\":\"turn\",\"data\":{\"unsupported\":true}}' AS BLOB)").await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(
            sources::read(
                &db,
                &[ChatSourceId::ForegroundTurn {
                    turn_id: "turn".into()
                }],
                99
            )
            .await?[0]
                .lifecycle,
            ChatSourceLifecycle::Unknown
        );
        Ok(())
    }
}

#[cfg(test)]
mod background_tests {
    use super::*;
    use crate::studio::paths::SqliteFileMode;
    use crate::studio::storage::history::{HistoryStore, connect};
    use crate::studio::thread_projection::order;
    use anyhow::{Context, Result};
    use pl_core::thread::{ToolDelivery, ToolDeliveryTarget, ToolOutcome};
    use pl_core::tool::ToolOutput;
    use sea_orm::DatabaseConnection;
    use serde_json::json;

    const THREAD: &str = "synthetic-upgrade";
    const CALL: &str = "synthetic-call";
    const MESSAGE: &str = "task-result:synthetic";

    /// v6.36.0 (ae7951a8) wrote metering-only history 10. Published checkpoints
    /// 13 and 14 remain frozen inputs; the first timeline migration normalizes them.
    struct Published(i64);

    impl MigratorTraitSelf for Published {
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
                )
            })
            .filter(|step| !is_lifecycle_migration(step.name()))
            .filter(|step| match self.0 {
                10 => !matches!(
                    step.name(),
                    ATOMIC_TIMELINE
                        | COMBINED_CONTENT
                        | DEMAND_CONVERSATION
                        | MODEL_ROUTE_HEAD
                        | ATOM_METADATA
                        | TIMELINE_ITEMS
                ),
                13 => !matches!(step.name(), ATOM_METADATA | TIMELINE_ITEMS),
                14 => step.name() != TIMELINE_ITEMS,
                _ => unreachable!("only v6.36.0 and later published inputs"),
            })
            .collect()
        }
    }

    fn payload(background: bool) -> Result<Vec<u8>> {
        Ok(serde_json::to_vec(&json!({
            "contract":"anywork.chat/1","type":"tool","turnId":"synthetic-turn",
            "sealedAt":12,
            "data":{"invocation":{"toolCallId":CALL,"name":"exec"},
                "state":{"kind":if background {"backgroundStarted"} else {"completed"}},
                "opaque":{"original":[0,255,37],"text":"合成结果，保留原文"}}
        }))?)
    }

    async fn fixture(
        format: i64,
        handoff: bool,
    ) -> Result<(tempfile::TempDir, std::path::PathBuf)> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let db = connect(&path, SqliteFileMode::Create).await?;
        let initial = if format == 10 { 10 } else { 13 };
        Published(initial).up(&db, None).await?;
        assert_eq!(version(&db).await?, initial);
        let item = order::tool_id(CALL);
        if format == 10 {
            let store = HistoryStore::open(&path, THREAD).await?;
            store
                .upsert_item(
                    &db,
                    7,
                    ThreadItem::new(
                        item.clone(),
                        THREAD.into(),
                        "synthetic-turn".into(),
                        1,
                        1,
                        10,
                        12,
                        ThreadItemState::Tool(ThreadToolItem::new(
                            ThreadToolInvocation::new(CALL.into(), "exec".into(), "{}".into()),
                            ThreadToolState::Succeeded(SucceededThreadTool::new(
                                12,
                                ThreadToolOutput::new(
                                    "合成结果，保留原文".into(),
                                    vec![],
                                    vec![],
                                    Some(0),
                                ),
                            )),
                        )),
                    ),
                )
                .await?;
        } else {
            db.execute_raw(statement(
            "INSERT INTO history_items VALUES(1,?,'synthetic-turn','tool',1,'terminal',10,12,'{\"original\":true}',7)",
            vec![item.clone().into()],
        )).await?;
            for (seq, id, bytes) in if handoff {
                vec![
                    (
                        1_i64,
                        order::tool_background_started_id(CALL),
                        payload(true)?,
                    ),
                    (2, item.clone(), payload(false)?),
                ]
            } else {
                vec![(1_i64, item.clone(), payload(false)?)]
            } {
                db.execute_raw(statement(
                "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload) VALUES(?,?,'activity',NULL,?)",
                vec![seq.into(), id.into(), bytes.into()],
            )).await?;
            }
        }
        // Exercise the actual persisted enum shape: Inbox serializes message_id, not messageId.
        let delivery = ToolDelivery {
            target: ToolDeliveryTarget::Inbox {
                message_id: MESSAGE.into(),
            },
            call_id: CALL.into(),
            tool_id: "exec".into(),
            output: ToolOutput::new(
                pl_core::context::OpaquePayload::text("合成结果，保留原文"),
                vec![],
            ),
            delivered_context: vec![],
            outcome: ToolOutcome::Succeeded,
        };
        db.execute_raw(statement(
            "INSERT INTO history_tool_tasks VALUES(?,1,'{\"originalTask\":true}',?,7)",
            vec![CALL.into(), serde_json::to_string(&delivery)?.into()],
        ))
        .await?;
        db.execute_raw(statement(
        "INSERT INTO history_message_identities(message_id,item_id,sequence,digest,last_write_seq) VALUES(?,?,23,'original-digest',7)",
        vec![MESSAGE.into(), order::message_id(MESSAGE).into()],
    )).await?;
        if format > 13 {
            Published(format).up(&db, None).await?;
        }
        assert_eq!(version(&db).await?, format);
        db.close().await?;
        Ok((directory, path))
    }

    async fn originals(db: &DatabaseConnection, completions: bool) -> Result<Vec<String>> {
        let mut values = Vec::new();
        for sql in [
            "SELECT json_array(ordinal,item_id,payload,last_write_seq) AS original FROM history_items ORDER BY ordinal",
            "SELECT json_array(call_id,revision,task_payload,delivery_payload,last_write_seq) AS original FROM history_tool_tasks ORDER BY call_id",
            "SELECT json_array(message_id,item_id,sequence,digest,last_write_seq) AS original FROM history_message_identities ORDER BY message_id",
        ] {
            for row in db.query_all_raw(statement(sql, vec![])).await? {
                values.push(row.try_get("", "original")?);
            }
        }
        if completions {
            // query_class is derived and the published 13→14 step legitimately reclassifies it.
            for row in db.query_all_raw(statement(
            "SELECT json_array(seq,item_id,parent_id,hex(payload)) AS original FROM conversation_items ORDER BY seq",
            vec![],
        )).await? {
            values.push(row.try_get("", "original")?);
        }
        }
        Ok(values)
    }

    async fn metadata(db: &impl ConnectionTrait, id: &str) -> Result<ChatAtom> {
        let row = db
            .query_one_raw(statement(
                "SELECT metadata FROM conversation_items WHERE item_id=?",
                vec![id.into()],
            ))
            .await?
            .context("original completion")?;
        Ok(serde_json::from_slice(
            &row.try_get::<Vec<u8>>("", "metadata")?,
        )?)
    }

    #[tokio::test]
    async fn background_results_migrate_from_636_and_interrupted_13_14_without_losing_completions()
    -> Result<()> {
        for format in [10, 13, 14] {
            let (_directory, path) = fixture(format, format != 10).await?;
            let db = connect(&path, SqliteFileMode::ReadWrite).await?;
            let before = originals(&db, format >= 13).await?;
            db.close().await?;
            let store = HistoryStore::open(&path, THREAD).await?;
            store.prepare_conversation_read().await?;
            store.close_for_deletion().await?;
            let db = connect(&path, SqliteFileMode::ReadWrite).await?;
            assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
            assert!(!needs_content_preparation(&db, THREAD).await?);
            let result = metadata(&db, &order::tool_id(CALL)).await?;
            assert_eq!(result.id, order::message_id(MESSAGE));
            assert_eq!(
                result.source,
                ChatSourceId::BackgroundResult {
                    message_id: MESSAGE.into()
                }
            );
            assert_eq!(result.delivery, ChatDeliveryKind::Independent);
            assert_eq!(result.source_order, Some(23));
            assert_eq!(
                result.completion_item_id.as_deref(),
                Some(order::tool_id(CALL).as_str())
            );
            if format != 10 {
                let handoff = metadata(&db, &order::tool_background_started_id(CALL)).await?;
                assert_eq!(handoff.id, order::tool_id(CALL));
                assert_eq!(handoff.delivery, ChatDeliveryKind::BackgroundHandoff);
            }
            assert_eq!(originals(&db, format >= 13).await?, before);
            let run = db.query_one_raw(statement(
            "SELECT seq,display_run_start,display_run_ordinal FROM conversation_items WHERE item_id=?",
            vec![order::tool_id(CALL).into()],
        )).await?.context("background completion")?;
            assert_eq!(
                run.try_get::<i64>("", "display_run_start")?,
                run.try_get::<i64>("", "seq")?
            );
            assert_eq!(run.try_get::<i64>("", "display_run_ordinal")?, 1);
            db.close().await?;
        }
        Ok(())
    }
}
