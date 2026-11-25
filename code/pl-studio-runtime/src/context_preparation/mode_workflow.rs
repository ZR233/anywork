//! Freezes mode and workflow inputs together for one turn.
use pl_core::thread::{
    context_preparation::ContextPreparationRequest, extensions::ExtensionMutation,
};

use super::compaction::receipt_error;

/// Capture once at initiating root input admission. Repeated preparation, retries and all tools
/// consume the same self-contained snapshot even when the catalog changes during the Turn.
pub(super) struct ModePreparation {
    pub(super) mode: Option<std::sync::Arc<crate::mode::RegisteredThreadMode>>,
    pub(super) mutations: Vec<ExtensionMutation>,
    pub(super) new_turn: bool,
}

pub(super) fn freeze_mode_for_turn(
    request: &mut ContextPreparationRequest,
    modes: &crate::mode::ThreadModeManager,
) -> Result<ModePreparation, pl_core::model::ModelError> {
    if request
        .extensions
        .contains_key(crate::studio::model_route::AGENT_PROFILE_EXTENSION)
    {
        return Ok(ModePreparation {
            mode: None,
            mutations: Vec::new(),
            new_turn: false,
        });
    }
    let record = request
        .extensions
        .get(crate::mode::MODE_EXTENSION)
        .ok_or_else(|| {
            receipt_error(std::io::Error::other(
                "root Thread has no saved Mode snapshot",
            ))
        })?;
    let previous = crate::mode::decode_mode_snapshot(&record.payload).map_err(receipt_error)?;
    let root_prompt = request
        .turn_input
        .as_ref()
        .filter(|input| input.payload.format() == "pl.studio.prompt");
    if root_prompt.is_some_and(|input| input.payload.version() != 1) {
        return Err(receipt_error(std::io::Error::other(
            "unsupported root prompt payload",
        )));
    }
    let new_turn = root_prompt.is_some()
        && previous.frozen_turn_id.as_deref() != Some(request.model.turn_id.as_str());
    let next = if new_turn {
        let mode = modes
            .snapshot()
            .mode(&previous.definition.id)
            .unwrap_or(previous.registered().map_err(receipt_error)?);
        previous
            .updated_for_turn(&mode, request.model.turn_id.clone())
            .map_err(receipt_error)?
    } else {
        previous
    };
    let mode = next.registered().map_err(receipt_error)?;
    let payload = crate::mode::encode_mode_snapshot(&next).map_err(receipt_error)?;
    if record.payload == payload {
        return Ok(ModePreparation {
            mode: Some(mode),
            mutations: Vec::new(),
            new_turn,
        });
    }
    let expected_revision = record.revision;
    std::sync::Arc::make_mut(&mut request.extensions).insert(
        crate::mode::MODE_EXTENSION.into(),
        pl_core::thread::extensions::ExtensionRecord {
            revision: expected_revision,
            payload: payload.clone(),
        },
    );
    Ok(ModePreparation {
        mode: Some(mode),
        mutations: vec![ExtensionMutation::Put {
            id: crate::mode::MODE_EXTENSION.into(),
            expected_revision: Some(expected_revision),
            payload,
        }],
        new_turn,
    })
}

/// Start only from a pending root prompt, or repair an already active graph during execution.
/// The local preview feeds projection; core commits its mutation and facts together by CAS.
pub(super) fn prepare_workflow(
    request: &mut ContextPreparationRequest,
    mode: &crate::mode::RegisteredThreadMode,
) -> Result<Option<ExtensionMutation>, pl_core::model::ModelError> {
    let record = request
        .extensions
        .get(crate::workflow_tool::WORKFLOW_EXTENSION);
    let state = record
        .map(|record| crate::workflow_tool::decode_workflow_state(&record.payload))
        .transpose()
        .map_err(receipt_error)?;
    let run = state.as_ref().and_then(|state| state.current_run.as_ref());
    if run.is_some_and(|run| {
        run.mode_id == mode.descriptor().id
            && run.lifecycle == crate::workflow_tool::WorkflowRunLifecycle::Active
            && mode
                .workflow()
                .is_some_and(|graph| run.graph_hash == graph.graph_hash())
    }) {
        return Ok(None);
    }
    let expected_revision = record.map(|record| record.revision);
    let Some(state) = crate::workflow_tool::reconcile_workflow_for_turn(
        state,
        &mode.descriptor().id,
        mode.workflow_binding(),
        &request.model.thread_id,
        crate::studio::unix_seconds(),
    )
    .map_err(receipt_error)?
    else {
        return Ok(None);
    };
    let payload = crate::workflow_tool::encode_workflow_state(&state).map_err(receipt_error)?;
    if record.is_some_and(|record| record.payload == payload) {
        return Ok(None);
    }
    std::sync::Arc::make_mut(&mut request.extensions).insert(
        crate::workflow_tool::WORKFLOW_EXTENSION.into(),
        pl_core::thread::extensions::ExtensionRecord {
            revision: expected_revision.unwrap_or(0),
            payload: payload.clone(),
        },
    );
    Ok(Some(ExtensionMutation::Put {
        id: crate::workflow_tool::WORKFLOW_EXTENSION.into(),
        expected_revision,
        payload,
    }))
}
