//! Restores frozen instructions and route bindings from persisted state.
use pl_core::thread::{
    context_preparation::ContextPreparationRequest,
    extensions::{ExtensionMutation, ExtensionRecord, InstructionRevisionBinding},
};
use pl_model::{config::ResolvedModelRoute, runtime::ThreadModel};

use super::compaction::receipt_error;

/// Rewind and old checkpoints may carry obsolete instructions. The current extension is the
/// host authority; normalize obsolete text or route bindings without rescanning files.
#[derive(Default)]
pub(super) struct InstructionRepair {
    pub(super) binding: Option<InstructionRevisionBinding>,
    pub(super) replacement: Option<pl_core::thread::ReplaceContext>,
    pub(super) mutations: Vec<ExtensionMutation>,
}
#[derive(Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct InstructionBinding {
    pub(crate) route_identity: String,
    pub(crate) append_snapshots: bool,
}

pub(crate) fn instruction_binding(
    route: &ResolvedModelRoute,
    model: &ThreadModel,
) -> InstructionBinding {
    InstructionBinding {
        route_identity: model.route_identity(),
        append_snapshots: route.endpoint.instruction_update_strategy(&route.model)
            == pl_model::protocol::InstructionUpdateStrategy::AppendFullSnapshot,
    }
}

pub(crate) fn decode_instruction_binding(
    record: &ExtensionRecord,
) -> std::io::Result<InstructionBinding> {
    if record.payload.format() != "pl.studio.instruction-binding"
        || record.payload.version() != 1
        || record.revision == 0
    {
        return Err(std::io::Error::other("invalid instruction route binding"));
    }
    let binding: InstructionBinding =
        serde_json::from_str(record.payload.content()).map_err(std::io::Error::other)?;
    if binding.route_identity.is_empty() {
        return Err(std::io::Error::other("empty instruction route binding"));
    }
    Ok(binding)
}
pub(super) fn restore_current_instructions(
    request: &mut ContextPreparationRequest,
    base_instructions: &str,
    binding: &InstructionBinding,
    mode: Option<&crate::mode::RegisteredThreadMode>,
    mut mutations: Vec<ExtensionMutation>,
) -> Result<InstructionRepair, pl_core::model::ModelError> {
    use pl_core::context::{ContextContent, ContextRecord, ContextSource};
    let Some(mut record) = request
        .extensions
        .get(crate::instruction::INSTRUCTIONS_EXTENSION)
        .cloned()
    else {
        return Ok(InstructionRepair {
            mutations,
            ..Default::default()
        });
    };
    if record.revision == 0 {
        return Err(receipt_error(std::io::Error::other(
            "invalid current instruction snapshot authority",
        )));
    }
    // Only the Mode-owned instruction source is refreshed here. The frozen Agent definition and
    // its identity stay untouched, so context preparation can never rewrite the session's role.
    let mut snapshot =
        crate::instruction::decode_snapshot(&record.payload).map_err(receipt_error)?;
    let profile_changed = match mode {
        Some(mode) => snapshot
            .set_mode_instruction(&mode.descriptor().display_name, mode.prompt())
            .map_err(receipt_error)?,
        None => false,
    };
    let previous_binding = request.extensions.get("studio.instructions.binding");
    let binding_changed = previous_binding
        .map(decode_instruction_binding)
        .transpose()
        .map_err(receipt_error)?
        .is_none_or(|previous| previous != *binding);
    if binding_changed {
        mutations.push(ExtensionMutation::Put {
            id: "studio.instructions.binding".into(),
            expected_revision: previous_binding.map(|record| record.revision),
            payload: pl_core::context::OpaquePayload::new(
                "pl.studio.instruction-binding",
                1,
                serde_json::to_string(binding).map_err(receipt_error)?,
            )
            .map_err(receipt_error)?,
        });
    }
    let changed_instruction = snapshot.rebind_model_base(base_instructions) | profile_changed;
    if changed_instruction {
        let expected_revision = record.revision;
        record.payload = crate::instruction::encode_snapshot(&snapshot).map_err(receipt_error)?;
        mutations.push(ExtensionMutation::Put {
            id: crate::instruction::INSTRUCTIONS_EXTENSION.into(),
            expected_revision: Some(expected_revision),
            payload: record.payload.clone(),
        });
        std::sync::Arc::make_mut(&mut request.extensions).insert(
            crate::instruction::INSTRUCTIONS_EXTENSION.into(),
            record.clone(),
        );
    }
    let complete = snapshot.trusted_text();
    let hash = snapshot.trusted_content_hash();
    let current =
        crate::instruction::current_instruction_context(&request.committed_context.records);
    let latest = current.latest_snapshot();
    if current.is_canonical_for(&complete) && (!binding_changed || latest.is_none()) {
        return Ok(InstructionRepair {
            binding: None,
            replacement: None,
            mutations,
        });
    }
    let replaces = latest.and_then(|record| match &record.source {
        ContextSource::InstructionSnapshot {
            content_hash,
            replaces,
            ..
        } => {
            if current.body() == complete {
                replaces.clone()
            } else {
                Some(content_hash.clone())
            }
        }
        _ => None,
    });
    let record_id = format!(
        "instruction:{}:{}",
        request.model.thread_id,
        uuid::Uuid::new_v4()
    );
    let instruction_binding = Some(InstructionRevisionBinding {
        record_id: record_id.clone(),
        extension_id: crate::instruction::INSTRUCTIONS_EXTENSION.into(),
    });
    let canonical = ContextRecord {
        tool_data: Default::default(),
        id: record_id,
        turn_id: None,
        source: ContextSource::InstructionSnapshot {
            revision: record.revision,
            content_hash: hash,
            replaces,
        },
        content: vec![ContextContent::Text {
            text: complete.into(),
        }],
        tool_calls: Vec::new(),
    };
    let normalize = |records: &[ContextRecord]| {
        if binding.append_snapshots && !binding_changed {
            let mut next = records.to_vec();
            next.push(canonical.clone());
            return next;
        }
        std::iter::once(canonical.clone())
            .chain(
                records
                    .iter()
                    .filter(|record| {
                        !matches!(
                            record.source,
                            ContextSource::Instruction | ContextSource::InstructionSnapshot { .. }
                        )
                    })
                    .cloned(),
            )
            .collect::<Vec<_>>()
    };
    request.model.context.records = normalize(&request.model.context.records).into();
    // Rebuilding the observed prefix invalidates its measurement even when the record count
    // happens to remain equal. The model validates any remaining candidate against final input.
    request.previous_usage = None;
    let records = normalize(&request.committed_context.records);
    request.committed_context.records = records.clone().into();
    Ok(InstructionRepair {
        binding: instruction_binding,
        replacement: Some(pl_core::thread::ReplaceContext {
            expected_revision: request.committed_context.revision,
            reason: pl_core::thread::ContextReplacementReason::Rebuild,
            records,
        }),
        mutations,
    })
}
