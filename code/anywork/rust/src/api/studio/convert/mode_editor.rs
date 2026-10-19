use anyhow::Result;
use pl_protocol::{
    ThreadModeDefinition, ThreadModeDefinitionCommandReply, ThreadModeDefinitionSnapshot,
    ThreadModeDocument, ThreadModeEditorLayout, ThreadModeId, ThreadModeValidationIssue,
    ThreadModeValidationResult, WorkflowDefinition, WorkflowNodePosition, WorkflowPreviewRequest,
    WorkflowPreviewSnapshot, WorkflowState, WorkflowStateKind, WorkflowTransition,
};

use crate::api::studio::types::{
    BridgeThreadModeDefinition, BridgeThreadModeDefinitionCommandReply,
    BridgeThreadModeDefinitionSnapshot, BridgeThreadModeDocument, BridgeThreadModeEditorLayout,
    BridgeThreadModeValidationIssue, BridgeThreadModeValidationResult, BridgeWorkflowDefinition,
    BridgeWorkflowNodePosition, BridgeWorkflowPreviewRequest, BridgeWorkflowPreviewSnapshot,
    BridgeWorkflowState, BridgeWorkflowStateKind, BridgeWorkflowTransition,
};

use super::commands::command_receipt;
use super::runtime::bridge_thread_mode_catalog;

fn thread_mode_id(value: &str) -> Result<ThreadModeId> {
    ThreadModeId::new(value).map_err(|error| {
        pl_protocol::studio::StudioError::invalid_argument(format!(
            "invalid Thread Mode id: {error}"
        ))
        .into()
    })
}

impl TryFrom<BridgeThreadModeDefinition> for ThreadModeDefinition {
    type Error = anyhow::Error;

    fn try_from(value: BridgeThreadModeDefinition) -> Result<Self> {
        Ok(Self {
            id: thread_mode_id(&value.id)?,
            display_name: value.display_name,
            description: value.description,
            order: value.order,
            prompt: value.prompt,
            workflow: value.workflow.map(Into::into),
        })
    }
}

impl From<BridgeWorkflowDefinition> for WorkflowDefinition {
    fn from(value: BridgeWorkflowDefinition) -> Self {
        Self {
            title: value.title,
            goal: value.goal,
            initial_state_id: value.initial_state_id,
            states: value.states.into_iter().map(Into::into).collect(),
            transitions: value.transitions.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<BridgeWorkflowState> for WorkflowState {
    fn from(value: BridgeWorkflowState) -> Self {
        Self {
            id: value.id,
            title: value.title,
            instructions: value.instructions,
            completion_criteria: value.completion_criteria,
            kind: match value.kind {
                BridgeWorkflowStateKind::Atomic => WorkflowStateKind::Atomic,
                BridgeWorkflowStateKind::FinalState => WorkflowStateKind::Final,
            },
        }
    }
}

impl From<BridgeWorkflowTransition> for WorkflowTransition {
    fn from(value: BridgeWorkflowTransition) -> Self {
        Self {
            source_state_id: value.source_state_id,
            target_state_id: value.target_state_id,
            guard: value.guard,
        }
    }
}

impl TryFrom<BridgeThreadModeDocument> for ThreadModeDocument {
    type Error = anyhow::Error;

    fn try_from(value: BridgeThreadModeDocument) -> Result<Self> {
        Ok(Self {
            definition: value.definition.try_into()?,
            editor: value.editor.into(),
        })
    }
}

impl From<BridgeThreadModeEditorLayout> for ThreadModeEditorLayout {
    fn from(value: BridgeThreadModeEditorLayout) -> Self {
        Self {
            nodes: value.nodes.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<BridgeWorkflowNodePosition> for WorkflowNodePosition {
    fn from(value: BridgeWorkflowNodePosition) -> Self {
        Self {
            state_id: value.state_id,
            x: value.x,
            y: value.y,
        }
    }
}

impl TryFrom<BridgeWorkflowPreviewRequest> for WorkflowPreviewRequest {
    type Error = anyhow::Error;

    fn try_from(value: BridgeWorkflowPreviewRequest) -> Result<Self> {
        Ok(Self {
            document: value.document.try_into()?,
            path: value.path,
            target_state_id: value.target_state_id,
            reason: value.reason,
        })
    }
}

pub(crate) fn bridge_thread_mode_document(value: ThreadModeDocument) -> BridgeThreadModeDocument {
    BridgeThreadModeDocument {
        definition: bridge_thread_mode_definition(value.definition),
        editor: bridge_thread_mode_editor_layout(value.editor),
    }
}

pub(crate) fn bridge_thread_mode_definition(
    value: ThreadModeDefinition,
) -> BridgeThreadModeDefinition {
    BridgeThreadModeDefinition {
        id: value.id.to_string(),
        display_name: value.display_name,
        description: value.description,
        order: value.order,
        prompt: value.prompt,
        workflow: value.workflow.map(bridge_workflow_definition),
    }
}

fn bridge_thread_mode_editor_layout(value: ThreadModeEditorLayout) -> BridgeThreadModeEditorLayout {
    BridgeThreadModeEditorLayout {
        nodes: value
            .nodes
            .into_iter()
            .map(|node| BridgeWorkflowNodePosition {
                state_id: node.state_id,
                x: node.x,
                y: node.y,
            })
            .collect(),
    }
}

fn bridge_workflow_definition(value: WorkflowDefinition) -> BridgeWorkflowDefinition {
    BridgeWorkflowDefinition {
        title: value.title,
        goal: value.goal,
        initial_state_id: value.initial_state_id,
        states: value
            .states
            .into_iter()
            .map(bridge_workflow_state)
            .collect(),
        transitions: value
            .transitions
            .into_iter()
            .map(bridge_workflow_transition)
            .collect(),
    }
}

pub(crate) fn bridge_workflow_state(value: WorkflowState) -> BridgeWorkflowState {
    BridgeWorkflowState {
        id: value.id,
        title: value.title,
        instructions: value.instructions,
        completion_criteria: value.completion_criteria,
        kind: match value.kind {
            WorkflowStateKind::Atomic => BridgeWorkflowStateKind::Atomic,
            WorkflowStateKind::Final => BridgeWorkflowStateKind::FinalState,
        },
    }
}

pub(crate) fn bridge_workflow_transition(value: WorkflowTransition) -> BridgeWorkflowTransition {
    BridgeWorkflowTransition {
        source_state_id: value.source_state_id,
        target_state_id: value.target_state_id,
        guard: value.guard,
    }
}

pub(crate) fn bridge_thread_mode_definition_snapshot(
    value: ThreadModeDefinitionSnapshot,
) -> BridgeThreadModeDefinitionSnapshot {
    BridgeThreadModeDefinitionSnapshot {
        revision: value.revision,
        document: bridge_thread_mode_document(value.document),
        read_only: value.read_only,
    }
}

fn bridge_thread_mode_validation_issue(
    value: ThreadModeValidationIssue,
) -> BridgeThreadModeValidationIssue {
    BridgeThreadModeValidationIssue {
        code: value.code,
        path: value.path,
        message: value.message,
    }
}

pub(crate) fn bridge_thread_mode_validation_result(
    value: ThreadModeValidationResult,
) -> BridgeThreadModeValidationResult {
    BridgeThreadModeValidationResult {
        document: value.document.map(bridge_thread_mode_document),
        issues: value
            .issues
            .into_iter()
            .map(bridge_thread_mode_validation_issue)
            .collect(),
    }
}

pub(crate) fn bridge_thread_mode_command_reply(
    value: ThreadModeDefinitionCommandReply,
) -> BridgeThreadModeDefinitionCommandReply {
    BridgeThreadModeDefinitionCommandReply {
        catalog: bridge_thread_mode_catalog(value.catalog),
        definition: value.definition.map(bridge_thread_mode_definition_snapshot),
        receipt: command_receipt(value.receipt),
    }
}

pub(crate) fn bridge_workflow_preview_snapshot(
    value: WorkflowPreviewSnapshot,
) -> BridgeWorkflowPreviewSnapshot {
    BridgeWorkflowPreviewSnapshot {
        accepted: value.accepted,
        message: value.message,
        current_state: value.current_state.map(bridge_workflow_state),
        transitions: value
            .transitions
            .into_iter()
            .map(bridge_workflow_transition)
            .collect(),
        path: value.path,
        terminal: value.terminal,
    }
}
