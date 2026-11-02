//! Schema 13 → 14: immutable lightweight atom metadata and actual source lifecycle only.
//! Published payloads are decoded here, never by normal storage reads or a current tool renderer.
use super::super::conversation::{self, sources};
use super::*;
use anyhow::Result;
use pl_core::chat::ChatKey;
use pl_protocol::*;
use serde_json::{Value as Json, json};
use std::collections::{BTreeMap, BTreeSet};

pub(super) struct AtomMetadata;
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
    let member_id = if transferred {
        call.map(|call| format!("tool:{}:{call}", call.len()))
            .unwrap_or_else(|| id.into())
    } else {
        id.into()
    };
    let known = execution(db, &member_id).await?;
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
        if target.pointer("/target/kind").and_then(Json::as_str) == Some("inbox")
            && let Some(message_id) = target
                .pointer("/target/value/messageId")
                .and_then(Json::as_str)
        {
            source = ChatSourceId::BackgroundResult {
                message_id: message_id.into(),
            };
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
        completion_seq: None,
        source_state: None,
        source,
        source_order: known.map(|(ordinal, _)| ordinal),
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
    conversation::current::validate_database(&current, &database)?;
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
mod tests;
