//! Dynamic workflow tools own decoding and rendering; core sees only versioned extension mutations.
use super::WorkflowBinding;
use super::machine::{
    EmptyInput, RestartInput, TransitionInput, WorkflowMachine, WorkflowOperation,
};
use super::state::validate_session_state_size;
use crate::thread_assembler::ThreadAssemblyError;
use crate::thread_mode_id::MODE_EXTENSION;
use crate::tool_json::{JsonToolInput, json_output, put_extension};
use crate::workflow_tool::WorkflowSessionState;
use pl_agent_tool::{Tool, ToolDefinition, ToolHandle};
use pl_core::{
    context::OpaquePayload,
    model::ToolPresentationContract,
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use pl_model::completion::ToolCallPolicy;
use pl_tool::binding::prepare_registration;

/// Product-owned extension namespace; it is not a core schema or a database table.
pub const WORKFLOW_EXTENSION: &str = "studio.workflow";
const FORMAT: &str = "pl.studio.workflow";

#[derive(Debug, thiserror::Error)]
enum WorkflowPayloadError {
    #[error("workflow state is not initialized")]
    Missing,
    #[error("unsupported workflow payload {format} version {version}")]
    Unsupported { format: String, version: u32 },
    #[error("workflow graph differs from the saved run; an explicit product upgrade is required")]
    GraphMismatch,
}

/// Encodes a product state without exposing its structure to core.
///
/// # Errors
/// Returns invalid state size or encoding errors.
pub fn encode_workflow_state(state: &WorkflowSessionState) -> Result<OpaquePayload, ToolError> {
    validate_session_state_size(state).map_err(ToolError::new)?;
    OpaquePayload::new(
        FORMAT,
        1,
        serde_json::to_string(state).map_err(ToolError::new)?,
    )
    .map_err(ToolError::new)
}

/// Decodes an explicitly supported product format; unknown versions are never defaulted.
///
/// # Errors
/// Rejects unknown formats, invalid state JSON and excessive state size.
pub fn decode_workflow_state(payload: &OpaquePayload) -> Result<WorkflowSessionState, ToolError> {
    if payload.format() != FORMAT || payload.version() != 1 {
        return Err(ToolError::new(WorkflowPayloadError::Unsupported {
            format: payload.format().into(),
            version: payload.version(),
        }));
    }
    let state = serde_json::from_str(payload.content()).map_err(ToolError::new)?;
    validate_session_state_size(&state).map_err(ToolError::new)?;
    Ok(state)
}

#[derive(Debug, Clone, Copy)]
pub(crate) enum WorkflowOperationKind {
    Current,
    Next,
    Graph,
    History,
    Transition,
    Restart,
}
impl WorkflowOperationKind {
    pub(crate) fn definition(self) -> Result<ToolDefinition, pl_agent_tool::DefinitionError> {
        let (name, description, schema) = match self {
            Self::Current => (
                super::TOOL_WORKFLOW_CURRENT,
                "Read the current workflow run, state and CAS revision.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::Next => (
                super::TOOL_WORKFLOW_NEXT,
                "Read direct next workflow transitions and their guards.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::Graph => (
                super::TOOL_WORKFLOW_GRAPH,
                "Read the frozen workflow graph used by this Thread's tools.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::History => (
                super::TOOL_WORKFLOW_HISTORY,
                "Read saved workflow transitions and archive receipts.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::Transition => (
                super::TOOL_WORKFLOW_TRANSITION,
                "Complete the current workflow state and transition along a valid edge (or set force=true to jump to any valid state ID in the graph). Call this tool alone.",
                pl_agent_tool::typed::input_schema_for::<TransitionInput>(),
            ),
            Self::Restart => (
                super::TOOL_WORKFLOW_RESTART,
                "Archive the current run and begin a new lineage using run, revision and state CAS. Call this tool alone.",
                pl_agent_tool::typed::input_schema_for::<RestartInput>(),
            ),
        };
        ToolDefinition::json(name, description, schema)
    }
    fn id(self) -> &'static str {
        match self {
            Self::Current => super::TOOL_WORKFLOW_CURRENT,
            Self::Next => super::TOOL_WORKFLOW_NEXT,
            Self::Graph => super::TOOL_WORKFLOW_GRAPH,
            Self::History => super::TOOL_WORKFLOW_HISTORY,
            Self::Transition => super::TOOL_WORKFLOW_TRANSITION,
            Self::Restart => super::TOOL_WORKFLOW_RESTART,
        }
    }
}

#[derive(Debug)]
struct ThreadWorkflowTool {
    definition: ToolDefinition,
    kind: WorkflowOperationKind,
    resolve_workflow: ResolveWorkflow,
}

type ResolveWorkflow = fn(&OpaquePayload) -> Result<Option<WorkflowBinding>, crate::PureError>;
impl Tool for ThreadWorkflowTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let input = JsonToolInput::new(&input)?;
        let saved = context
            .extensions
            .get(WORKFLOW_EXTENSION)
            .ok_or_else(|| ToolError::new(WorkflowPayloadError::Missing))?;
        let previous = decode_workflow_state(&saved.payload)?;
        let mode_record = context
            .extensions
            .get(MODE_EXTENSION)
            .ok_or_else(|| ToolError::new(WorkflowPayloadError::Missing))?;
        let binding = (self.resolve_workflow)(&mode_record.payload)
            .map_err(ToolError::new)?
            .ok_or_else(|| ToolError::new(WorkflowPayloadError::Missing))?;
        if let Some(run) = &previous.current_run
            && (run.mode_id != binding.mode_id || run.graph_hash != binding.graph.graph_hash())
        {
            return Err(ToolError::new(WorkflowPayloadError::GraphMismatch));
        }
        let mut machine = WorkflowMachine::new(binding, previous.clone());
        let identity = WorkflowOperation {
            turn_id: context.turn_id,
            call_id: context.call_id,
        };
        let hash = input.argument_hash();
        let response = match self.kind {
            WorkflowOperationKind::Current
            | WorkflowOperationKind::Next
            | WorkflowOperationKind::Graph
            | WorkflowOperationKind::History => {
                let _: EmptyInput = input.decode()?;
                match self.kind {
                    WorkflowOperationKind::Current => machine.current_snapshot(),
                    WorkflowOperationKind::Next => machine.next_snapshot(),
                    WorkflowOperationKind::Graph => machine.graph_snapshot(),
                    WorkflowOperationKind::History => machine.history_snapshot(),
                    WorkflowOperationKind::Transition | WorkflowOperationKind::Restart => {
                        return Err(ToolError::new(WorkflowPayloadError::GraphMismatch));
                    }
                }
            }
            WorkflowOperationKind::Transition => serde_json::to_value(
                machine
                    .apply_transition(
                        input.decode()?,
                        &identity,
                        hash,
                        crate::studio::unix_seconds(),
                    )
                    .map_err(ToolError::new)?,
            )
            .map_err(ToolError::new)?,
            WorkflowOperationKind::Restart => serde_json::to_value(
                machine
                    .apply_restart(
                        input.decode()?,
                        &identity,
                        hash,
                        crate::studio::unix_seconds(),
                    )
                    .map_err(ToolError::new)?,
            )
            .map_err(ToolError::new)?,
        };
        let mut output = json_output("pl.studio.workflow-result", &response)?;
        let next = machine.state();
        if next != &previous {
            output = put_extension(
                output,
                WORKFLOW_EXTENSION,
                Some(saved.revision),
                encode_workflow_state(next)?,
            );
        }
        Ok(output)
    }
}

/// Creates ToolDefinitions for all built-in workflow operations.
pub(crate) fn workflow_tool_definitions()
-> Result<Vec<(WorkflowOperationKind, ToolDefinition)>, pl_agent_tool::DefinitionError> {
    [
        WorkflowOperationKind::Current,
        WorkflowOperationKind::Next,
        WorkflowOperationKind::Graph,
        WorkflowOperationKind::History,
        WorkflowOperationKind::Transition,
        WorkflowOperationKind::Restart,
    ]
    .into_iter()
    .map(|kind| Ok((kind, kind.definition()?)))
    .collect()
}

/// Creates Thread-owned workflow operations from a frozen product Mode.
///
/// # Errors
/// Returns model declaration or registration failures.
pub(crate) fn workflow_registrations(
    resolve_workflow: ResolveWorkflow,
) -> Result<Vec<Registration>, ThreadAssemblyError> {
    [
        WorkflowOperationKind::Current,
        WorkflowOperationKind::Next,
        WorkflowOperationKind::Graph,
        WorkflowOperationKind::History,
        WorkflowOperationKind::Transition,
        WorkflowOperationKind::Restart,
    ]
    .into_iter()
    .map(|kind| {
        let definition = kind.definition()?;
        let prepared = prepare_registration(kind.id(), &definition, ToolCallPolicy::DirectOnly)?;
        let contract = match kind {
            WorkflowOperationKind::Current => "builtin.workflow_current@1",
            WorkflowOperationKind::Next => "builtin.workflow_next@1",
            WorkflowOperationKind::Graph => "builtin.workflow_graph@1",
            WorkflowOperationKind::History => "builtin.workflow_history@1",
            WorkflowOperationKind::Transition => "builtin.workflow_transition@1",
            WorkflowOperationKind::Restart => "builtin.workflow_restart@1",
        };
        let registration = prepared
            .attach(ToolHandle::new(ThreadWorkflowTool {
                definition,
                kind,
                resolve_workflow,
            }))
            .with_presentation_contract(ToolPresentationContract::new(contract));
        Ok(match kind {
            WorkflowOperationKind::Transition | WorkflowOperationKind::Restart => {
                registration.with_extension_updates()
            }
            WorkflowOperationKind::Current
            | WorkflowOperationKind::Next
            | WorkflowOperationKind::Graph
            | WorkflowOperationKind::History => registration,
        })
    })
    .collect()
}
