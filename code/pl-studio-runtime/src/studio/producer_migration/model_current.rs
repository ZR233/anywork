//! Model identity conversion at the explicit Current recovery/import boundaries.
use crate::studio::session_data_error::SessionDataError;
use anyhow::{Context, Result, ensure};
use pl_core::{
    context::{ContextContent, ContextSource, OpaquePayload},
    model::ModelToolCall,
    thread::{
        ToolDeliveryTarget,
        current::{SavedModelPhase, ThreadCurrent},
        extensions::ExtensionMutation,
    },
    tool::opaque::{interaction_tool_call_id, tool_interaction_id},
};
use std::{collections::BTreeMap, sync::Arc};

struct CallMove {
    old: ModelToolCall,
    current: String,
    turn: Option<String>,
}

pub(super) fn prepare(current: &mut ThreadCurrent) -> Result<()> {
    // Build one staged Current; none of the caller's source can change on a failed conversion.
    let mut next = current.clone();
    let mut moves = BTreeMap::new();
    for record in Arc::make_mut(&mut next.state.context.records) {
        let original = record.tool_calls.clone();
        let changed = pl_model::runtime::migration::upgrade_saved_assistant_record(record)
            .with_context(|| format!("migrate saved model output {}", record.id))?;
        for old in original {
            if let Some(id) = changed.get(&old.call_id) {
                let key = old.call_id.clone();
                ensure!(
                    moves
                        .insert(
                            key,
                            CallMove {
                                old,
                                current: id.clone(),
                                turn: record.turn_id.clone(),
                            }
                        )
                        .is_none(),
                    "ambiguous saved tool call identity"
                );
            }
        }
        for content in &mut record.content {
            if let ContextContent::Opaque { payload } = content
                && payload.format() == "pl.model.compaction"
                && let Some(upgraded) = pl_model::runtime::migration::migrate_payload(payload)?
            {
                *payload = upgraded;
            }
        }
    }
    if let Some(call) = next.model_call.as_mut() {
        if let Some(payload) = call.prepared_parameters.as_mut() {
            let migrated =
                pl_model::runtime::migration::migrate_payload(payload).map_err(|source| {
                    SessionDataError::PreparedRequest {
                        revision: payload.version(),
                        source,
                    }
                })?;
            if let Some(upgraded) = migrated {
                *payload = upgraded;
            }
        }
        if let SavedModelPhase::Streaming { stream } = &mut call.phase {
            ensure!(
                stream.format() == pl_model::completion::MODEL_STREAM_CURRENT_FORMAT,
                "unsupported saved model stream format: {}",
                stream.format(),
            );
            if let Some(upgraded) = pl_model::runtime::migration::migrate_payload(stream)
                .context("migrate saved model stream observation")?
            {
                *stream = upgraded;
            }
        }
    }
    if !moves.is_empty() {
        relocate_calls(&mut next, &moves)?;
    }
    next.validate(&current.thread_id)?;
    *current = next;
    Ok(())
}

fn relocate_calls(current: &mut ThreadCurrent, moves: &BTreeMap<String, CallMove>) -> Result<()> {
    let state = &mut current.state;
    for record in Arc::make_mut(&mut state.context.records) {
        if let ContextSource::ToolResult { call_id, tool_id } = &mut record.source
            && let Some(binding) = moves.get(call_id)
        {
            ensure!(
                binding.old.tool_id == *tool_id
                    && compatible_turn(binding, record.turn_id.as_deref()),
                "saved tool result conflicts with its assistant call"
            );
            call_id.clone_from(&binding.current);
        }
    }
    for task in state.tasks.values_mut() {
        if let Some(binding) = moves.get(&task.call_id) {
            ensure!(
                task.tool_id == binding.old.tool_id
                    && compatible_turn(binding, Some(&task.turn_id)),
                "saved task conflicts with its assistant call"
            );
            if let Some(invocation) = task.invocation.as_mut() {
                ensure!(
                    *invocation == binding.old,
                    "saved task invocation conflicts with its assistant call"
                );
                invocation.call_id.clone_from(&binding.current);
            }
            // The old task ID still owns its original messages, permission and archive body.
            task.call_id.clone_from(&binding.current);
        }
        if let Some(parent) = task.parent_call_id.as_mut() {
            replace_call(parent, moves);
        }
    }
    for delivery in Arc::make_mut(&mut state.deliveries) {
        if let Some(binding) = moves.get(&delivery.call_id) {
            ensure!(
                delivery.tool_id == binding.old.tool_id,
                "saved delivery conflicts with its assistant call"
            );
            delivery.call_id.clone_from(&binding.current);
        }
        if let ToolDeliveryTarget::Nested { parent_call_id } = &mut delivery.target {
            replace_call(parent_call_id, moves);
        }
    }
    for permission in state.permissions.values_mut() {
        if let Some(binding) = moves.get(&permission.call_id) {
            ensure!(
                permission.tool_id == binding.old.tool_id
                    && compatible_turn(binding, Some(&permission.turn_id)),
                "saved permission conflicts with its assistant call"
            );
            permission.call_id.clone_from(&binding.current);
        }
    }
    for (mut id, preview) in std::mem::take(&mut state.tool_previews) {
        replace_call(&mut id, moves);
        ensure!(
            state.tool_previews.insert(id, preview).is_none(),
            "conflicting saved tool preview identity"
        );
    }
    relocate_interactions(state, moves)
}

fn compatible_turn(binding: &CallMove, turn: Option<&str>) -> bool {
    binding
        .turn
        .as_deref()
        .zip(turn)
        .is_none_or(|(left, right)| left == right)
}

fn replace_call(id: &mut String, moves: &BTreeMap<String, CallMove>) {
    if let Some(binding) = moves.get(id) {
        id.clone_from(&binding.current);
    }
}

fn relocate_interactions(
    state: &mut pl_core::thread::current::ThreadCurrentState,
    moves: &BTreeMap<String, CallMove>,
) -> Result<()> {
    let mut interactions = BTreeMap::new();
    for (id, mut record) in std::mem::take(&mut state.interactions) {
        let mut key = id;
        if let Some(binding) =
            interaction_tool_call_id(&record.request.id).and_then(|call| moves.get(call))
        {
            ensure!(
                key == record.request.id && compatible_turn(binding, Some(&record.request.turn_id)),
                "saved interaction conflicts with its assistant call"
            );
            ensure!(
                matches!(
                    record.request.payload.format(),
                    "pl.tool.user-input" | crate::plan_tool::PLAN_CONFIRMATION_FORMAT
                ),
                "unknown saved tool interaction cannot be safely re-associated"
            );
            key = tool_interaction_id(&binding.current);
            interactions.insert(
                std::mem::replace(&mut record.request.id, key.clone()),
                key.clone(),
            );
        }
        ensure!(
            state.interactions.insert(key, record).is_none(),
            "conflicting saved interaction identity"
        );
    }
    if let Some(plan) = state.extensions.get_mut(crate::plan_tool::PLAN_EXTENSION) {
        relocate_plan(&mut plan.payload, &interactions)?;
    }
    for record in state.interactions.values_mut() {
        for change in &mut record.extension_mutations {
            if let ExtensionMutation::Put { payload, .. } = change
                && payload.format() == "pl.studio.plan"
            {
                relocate_plan(payload, &interactions)?;
            }
        }
    }
    Ok(())
}

fn relocate_plan(
    payload: &mut OpaquePayload,
    interactions: &BTreeMap<String, String>,
) -> Result<()> {
    if interactions.is_empty() {
        return Ok(());
    }
    if let Some(upgraded) = crate::plan_tool::migrate_plan_payload(payload)? {
        *payload = upgraded;
    }
    let mut plan: super::RawObject = serde_json::from_str(payload.content())?;
    if let Some(field) = plan.get("pendingInteractionId")
        && let Some(old) = serde_json::from_str::<Option<String>>(field.get())?
        && let Some(current) = interactions.get(&old)
    {
        plan.insert(
            "pendingInteractionId".into(),
            serde_json::value::to_raw_value(current)?,
        );
        *payload = OpaquePayload::new(
            payload.format(),
            payload.version(),
            serde_json::to_string(&plan)?,
        )?;
    }
    Ok(())
}
