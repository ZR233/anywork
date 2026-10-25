//! Self-contained execution snapshots. Only explicit recovery decodes the old ID-only format.
use super::{RegisteredThreadMode, ThreadModeManager};
use pl_core::{context::OpaquePayload, thread::ThreadSnapshot};
use pl_protocol::{PureError, ThreadModeDefinition, ThreadModeId};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

const FORMAT: &str = "pl.studio.mode";
const VERSION: u32 = 2;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct SavedThreadMode {
    pub definition: ThreadModeDefinition,
    pub graph_revision: u64,
    pub frozen_turn_id: Option<String>,
}
impl SavedThreadMode {
    pub fn capture(mode: &RegisteredThreadMode, turn_id: Option<String>) -> Self {
        Self {
            definition: mode.definition(),
            graph_revision: mode.graph_revision(),
            frozen_turn_id: turn_id,
        }
    }
    /// Catalog revisions belong to a process incarnation. An unchanged graph keeps the
    /// recovered session's graph revision so Prompt-only updates cannot relabel its run.
    pub fn updated_for_turn(
        &self,
        mode: &RegisteredThreadMode,
        turn_id: String,
    ) -> Result<Self, PureError> {
        let mut next = Self::capture(mode, Some(turn_id));
        if mode.graph_hash() == self.registered()?.graph_hash() {
            next.graph_revision = self.graph_revision;
        }
        Ok(next)
    }

    pub fn registered(&self) -> Result<Arc<RegisteredThreadMode>, PureError> {
        RegisteredThreadMode::from_definition(self.definition.clone(), self.graph_revision)
            .map_err(|error| PureError::ConfigError(error.to_string()))
    }
}
pub(crate) fn encode_mode_snapshot(snapshot: &SavedThreadMode) -> Result<OpaquePayload, PureError> {
    OpaquePayload::new(FORMAT, VERSION, serde_json::to_string(snapshot)?)
        .map_err(|error| PureError::ConfigError(error.to_string()))
}
pub(crate) fn decode_mode_snapshot(payload: &OpaquePayload) -> Result<SavedThreadMode, PureError> {
    if payload.format() != FORMAT || payload.version() != VERSION {
        return Err(PureError::ConfigError(
            "unsupported saved Mode; explicit recovery migration required".into(),
        ));
    }
    Ok(serde_json::from_str(payload.content())?)
}
pub(crate) fn decode_saved_mode(payload: &OpaquePayload) -> Result<ThreadModeId, PureError> {
    Ok(decode_mode_snapshot(payload)?.definition.id)
}
pub(crate) fn saved_registered_mode(
    state: &ThreadSnapshot,
) -> Result<Option<Arc<RegisteredThreadMode>>, PureError> {
    state
        .extensions
        .get("studio.mode")
        .map(|record| decode_mode_snapshot(&record.payload)?.registered())
        .transpose()
}

/// Computes the recovery candidate; the history writer commits it before activation.
/// Missing definitions or graph mismatches fail without altering the original saved data.
pub(crate) fn migrate_mode_snapshot(
    state: &mut ThreadSnapshot,
    modes: &ThreadModeManager,
) -> Result<(), PureError> {
    let Some(record) = state.extensions.get("studio.mode") else {
        if let Some(record) = state
            .extensions
            .get(crate::workflow_tool::WORKFLOW_EXTENSION)
        {
            let workflow = crate::workflow_tool::decode_workflow_state(&record.payload)
                .map_err(|error| PureError::ConfigError(error.to_string()))?;
            if workflow.current_run.is_some() {
                return Err(PureError::ConfigError("cannot recover workflow without its saved Mode identity; checkpoint and history preserved".into()));
            }
        }
        return Ok(());
    };
    if record.payload.format() != FORMAT || record.payload.version() != 1 {
        decode_mode_snapshot(&record.payload)?.registered()?;
        return Ok(());
    }
    let id: ThreadModeId = serde_json::from_str(record.payload.content())?;
    let registered = modes.snapshot().mode(&id).ok_or_else(|| {
        PureError::ConfigError(format!(
            "cannot recover saved Mode {id}: definition unavailable; original checkpoint preserved"
        ))
    })?;
    let mut saved = SavedThreadMode::capture(&registered, None);
    let mut recovered_prompt = false;
    if let Some(record) = state.extensions.get("studio.instructions") {
        // Mode recovery reads the saved Mode text through the instruction migration boundary, so
        // both the legacy mixed source and the current Mode source are understood here.
        if let Some((label, content)) = crate::instruction::saved_mode_instruction(&record.payload)
            .map_err(|error| PureError::ConfigError(error.to_string()))?
        {
            recovered_prompt = true;
            saved.definition.prompt = content;
            saved.definition.display_name = label;
        }
    }
    if !recovered_prompt {
        return Err(PureError::ConfigError(format!(
            "cannot recover saved Mode {id}: original Mode Prompt unavailable; checkpoint and history preserved"
        )));
    }
    if let Some(record) = state
        .extensions
        .get(crate::workflow_tool::WORKFLOW_EXTENSION)
    {
        let workflow = crate::workflow_tool::decode_workflow_state(&record.payload)
            .map_err(|error| PureError::ConfigError(error.to_string()))?;
        if let Some(run) = workflow.current_run {
            if run.mode_id != id || Some(run.graph_hash.as_str()) != registered.graph_hash() {
                return Err(PureError::ConfigError(format!(
                    "cannot recover saved Mode {id}: original workflow definition unavailable; checkpoint and history preserved"
                )));
            }
            saved.graph_revision = run.graph_revision;
        }
    }
    let payload = encode_mode_snapshot(&saved)?;
    state
        .extensions
        .get_mut("studio.mode")
        .expect("checked saved Mode")
        .payload = payload;
    Ok(())
}
