//! Dynamic workflow tools own decoding and rendering; core sees only versioned extension mutations.
use crate::extension_payload::ExtensionState;
use crate::thread_assembler::ThreadAssemblyError;
use pl_agent_tool::{Tool, ToolDefinition, ToolHandle};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    model::ToolPresentationContract,
    thread::extensions::ExtensionMutation,
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use pl_model::completion::ToolCallPolicy;
use pl_protocol::WorkflowSessionState;
use pl_studio_workflow::mode::{
    EmptyInput, RestartInput, TransitionInput, WorkflowMachine, WorkflowOperation,
};
use pl_tool::binding::prepare_registration;
use std::sync::Arc;

/// Product-owned extension namespace; it is not a core schema or a database table.
pub const WORKFLOW_EXTENSION: &str = "studio.workflow";

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
    state.encode()
}

/// Decodes an explicitly supported product format; unknown versions are never defaulted.
///
/// # Errors
/// Rejects unknown formats, invalid state JSON and excessive state size.
pub fn decode_workflow_state(payload: &OpaquePayload) -> Result<WorkflowSessionState, ToolError> {
    WorkflowSessionState::decode(payload)
}

#[derive(Debug, Clone, Copy)]
enum WorkflowOperationKind {
    Current,
    Next,
    Graph,
    History,
    Transition,
    Restart,
}
impl WorkflowOperationKind {
    fn definition(self) -> Result<ToolDefinition, pl_agent_tool::DefinitionError> {
        let (name, description, schema) = match self {
            Self::Current => (
                "workflow_current",
                "Read the current workflow run, state and CAS revision.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::Next => (
                "workflow_next",
                "Read direct next workflow transitions and their guards.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::Graph => (
                "workflow_graph",
                "Read the frozen workflow graph used by this Thread's tools.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::History => (
                "workflow_history",
                "Read saved workflow transitions and archive receipts.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::Transition => (
                "workflow_transition",
                "Complete the current workflow state and cross one direct edge using run, revision and state CAS. Call this tool alone.",
                pl_agent_tool::typed::input_schema_for::<TransitionInput>(),
            ),
            Self::Restart => (
                "workflow_restart",
                "Archive the current run and begin a new lineage using run, revision and state CAS. Call this tool alone.",
                pl_agent_tool::typed::input_schema_for::<RestartInput>(),
            ),
        };
        ToolDefinition::json(name, description, schema)
    }
    fn id(self) -> &'static str {
        match self {
            Self::Current => "workflow_current",
            Self::Next => "workflow_next",
            Self::Graph => "workflow_graph",
            Self::History => "workflow_history",
            Self::Transition => "workflow_transition",
            Self::Restart => "workflow_restart",
        }
    }
}

#[derive(Debug)]
struct ThreadWorkflowTool {
    definition: ToolDefinition,
    kind: WorkflowOperationKind,
}
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
        if input.format() != "application/json" || input.version() != 1 {
            return Err(ToolError::new(WorkflowPayloadError::Unsupported {
                format: input.format().into(),
                version: input.version(),
            }));
        }
        let saved = context
            .extensions
            .get(WORKFLOW_EXTENSION)
            .ok_or_else(|| ToolError::new(WorkflowPayloadError::Missing))?;
        let previous = decode_workflow_state(&saved.payload)?;
        let mode_record = context
            .extensions
            .get("studio.mode")
            .ok_or_else(|| ToolError::new(WorkflowPayloadError::Missing))?;
        let mode = crate::mode_snapshot::decode_mode_snapshot(&mode_record.payload)
            .and_then(|snapshot| snapshot.registered())
            .map_err(ToolError::new)?;
        if mode.workflow().is_none() {
            return Err(ToolError::new(WorkflowPayloadError::Missing));
        }
        let mut machine =
            WorkflowMachine::new(mode.clone(), previous.clone()).map_err(ToolError::new)?;
        if let Some(run) = &previous.current_run
            && (run.mode_id != mode.descriptor().id
                || run.graph_hash != machine.graph().graph_hash())
        {
            return Err(ToolError::new(WorkflowPayloadError::GraphMismatch));
        }
        let identity = WorkflowOperation {
            turn_id: context.turn_id,
            call_id: context.call_id,
            occurred_at: crate::studio::unix_seconds(),
        };
        let hash = pl_core::context::content_hash(input.content().as_bytes());
        let response = match self.kind {
            WorkflowOperationKind::Current
            | WorkflowOperationKind::Next
            | WorkflowOperationKind::Graph
            | WorkflowOperationKind::History => {
                let _: EmptyInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                match self.kind {
                    WorkflowOperationKind::Current => machine.current_snapshot(&previous),
                    WorkflowOperationKind::Next => machine.next_snapshot(&previous),
                    WorkflowOperationKind::Graph => machine.graph_snapshot(&previous),
                    WorkflowOperationKind::History => machine.history_snapshot(&previous),
                    WorkflowOperationKind::Transition | WorkflowOperationKind::Restart => {
                        return Err(ToolError::new(WorkflowPayloadError::GraphMismatch));
                    }
                }
            }
            WorkflowOperationKind::Transition => serde_json::to_value(
                machine
                    .apply_transition(
                        pl_agent_tool::typed::decode_json(input.content())
                            .map_err(ToolError::new)?,
                        &identity,
                        hash,
                    )
                    .map_err(ToolError::new)?,
            )
            .map_err(ToolError::new)?,
            WorkflowOperationKind::Restart => serde_json::to_value(
                machine
                    .apply_restart(
                        pl_agent_tool::typed::decode_json(input.content())
                            .map_err(ToolError::new)?,
                        &identity,
                        hash,
                    )
                    .map_err(ToolError::new)?,
            )
            .map_err(ToolError::new)?,
        };
        let text = serde_json::to_string(&response).map_err(ToolError::new)?;
        let mut output = ToolOutput::new(
            OpaquePayload::new("pl.studio.workflow-result", 1, text.clone())
                .map_err(ToolError::new)?,
            vec![ContextContent::Text {
                text: Arc::from(text),
            }],
        );
        let next = machine.state();
        if next != &previous {
            output = output.with_extension_mutations(vec![ExtensionMutation::Put {
                id: WORKFLOW_EXTENSION.into(),
                expected_revision: Some(saved.revision),
                payload: encode_workflow_state(next)?,
            }]);
        }
        Ok(output)
    }
}

/// Creates Thread-owned workflow operations from a frozen product Mode.
///
/// # Errors
/// Returns model declaration or registration failures.
pub fn workflow_registrations() -> Result<Vec<Registration>, ThreadAssemblyError> {
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
            .attach(ToolHandle::new(ThreadWorkflowTool { definition, kind }))
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
