//! Plan tool frontends over core's opaque extension and interaction transactions.
use super::AgentSessionPlanOptions;
use super::{
    common::EmptyInput,
    restart::PlanRestartInput,
    submit::{PlanSubmitInput, confirmation_question},
};
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
use pl_protocol::AgentSessionPlanState;
use pl_studio_workflow::plan::{
    AgentSessionPlanMachine, AgentSessionPlanRestartCommand, AgentSessionPlanSubmitCommand,
};
use pl_tool::binding::prepare_registration;
use std::sync::Arc;

pub const PLAN_EXTENSION: &str = "studio.plan";

#[derive(Debug, thiserror::Error)]
enum PlanPayloadError {
    #[error("plan state is not initialized")]
    Missing,
    #[error("unsupported plan payload {format} version {version}")]
    Unsupported { format: String, version: u32 },
    #[error("invalid plan: {0}")]
    InvalidPlan(String),
}

/// Encodes the complete product state for a generic Thread extension.
///
/// # Errors
/// Rejects invalid or excessive plan state and encoding errors.
pub fn encode_plan_state(state: &AgentSessionPlanState) -> Result<OpaquePayload, ToolError> {
    state.encode()
}

/// Decodes only an explicitly supported plan format; core history never calls this function.
///
/// # Errors
/// Rejects unknown payload formats, corrupt plan state and excessive content.
pub fn decode_plan_state(payload: &OpaquePayload) -> Result<AgentSessionPlanState, ToolError> {
    AgentSessionPlanState::decode(payload)
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct PlanConfirmationPrompt {
    pub question: pl_protocol::UserQuestion,
    pub expected_plan_revision: u64,
    pub plan_hash: String,
    /// 保存于确认请求自身；读取历史不查询当前 Plan。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub document_version: Option<u64>,
    pub created_at: i64,
    pub presentation: pl_protocol::MessagePresentation,
}

#[derive(Debug, Clone, Copy)]
enum PlanOperation {
    Current,
    Next,
    History,
    Submit,
    Restart,
}
impl PlanOperation {
    fn name(self) -> &'static str {
        match self {
            Self::Current => "plan_current",
            Self::Next => "plan_next",
            Self::History => "plan_history",
            Self::Submit => "plan_submit",
            Self::Restart => "plan_restart",
        }
    }
    fn definition(self) -> Result<ToolDefinition, pl_agent_tool::DefinitionError> {
        let (description, schema) = match self {
            Self::Current => (
                "Read the current Plan, state and CAS revision.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::Next => (
                "Read permitted operations in the current fixed Plan state.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::History => (
                "Read saved Plan transitions and archive receipts.",
                pl_agent_tool::typed::input_schema_for::<EmptyInput>(),
            ),
            Self::Submit => (
                "Submit a complete Markdown Plan for user approval or revision. This is the only tool for asking the user to approve implementation of a complete Plan; do not first ask whether to implement through request_user_input or final text. Requires revision CAS; call this tool alone.",
                pl_agent_tool::typed::input_schema_for::<PlanSubmitInput>(),
            ),
            Self::Restart => (
                "Restart an approved or revision-requested Plan using revision CAS and a reason. Call this tool alone.",
                pl_agent_tool::typed::input_schema_for::<PlanRestartInput>(),
            ),
        };
        ToolDefinition::json(self.name(), description, schema)
    }
}

#[derive(Debug)]
struct ThreadPlanTool {
    definition: ToolDefinition,
    kind: PlanOperation,
    options: AgentSessionPlanOptions,
}
impl Tool for ThreadPlanTool {
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
            return Err(ToolError::new(PlanPayloadError::Unsupported {
                format: input.format().into(),
                version: input.version(),
            }));
        }
        let saved = context
            .extensions
            .get(PLAN_EXTENSION)
            .ok_or_else(|| ToolError::new(PlanPayloadError::Missing))?;
        let previous = decode_plan_state(&saved.payload)?;
        let mut machine = AgentSessionPlanMachine::new(previous.clone()).map_err(ToolError::new)?;
        let operation_id = format!(
            "{}/{}/{}",
            context.thread_id, context.turn_id, context.call_id
        );
        let argument_hash = pl_core::context::content_hash(input.content().as_bytes());
        let now = crate::studio::unix_seconds();
        let mut interaction = None;
        let result = match self.kind {
            PlanOperation::Current => {
                let _: EmptyInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                serde_json::to_value(machine.snapshot()).map_err(ToolError::new)?
            }
            PlanOperation::Next => {
                let _: EmptyInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                serde_json::json!({"revision": machine.state().revision, "state": machine.state().state, "transitions": machine.available_transitions()})
            }
            PlanOperation::History => {
                let _: EmptyInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                serde_json::json!({"revision":previous.revision,"state":previous.state,"history":previous.history_tail,"archivedTransitionCount":previous.archived_transition_count,"archivedTransitionDigest":previous.archived_transition_digest})
            }
            PlanOperation::Submit => {
                let args: PlanSubmitInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                pl_studio_workflow::plan::validate_plan(&args.plan)
                    .map_err(|error| ToolError::new(PlanPayloadError::InvalidPlan(error)))?;
                let question = confirmation_question(args.plan.clone());
                let plan_hash = pl_core::context::content_hash(args.plan.as_bytes());
                let result = machine.submit(AgentSessionPlanSubmitCommand {
                    expected_revision: args.expected_revision,
                    plan: args.plan,
                    interaction_id: context.interaction_id(),
                    operation_id,
                    argument_hash,
                    submitted_at: now,
                });
                if result.accepted && machine.state() != &previous {
                    let prompt = PlanConfirmationPrompt {
                        question,
                        expected_plan_revision: machine.state().revision,
                        plan_hash,
                        document_version: machine.state().document.as_ref().map(|doc| doc.version),
                        created_at: now,
                        presentation: self.options.submitted_plan_presentation(),
                    };
                    interaction = Some(
                        OpaquePayload::new(
                            super::PLAN_CONFIRMATION_FORMAT,
                            1,
                            serde_json::to_string(&prompt).map_err(ToolError::new)?,
                        )
                        .map_err(ToolError::new)?,
                    );
                }
                serde_json::to_value(result).map_err(ToolError::new)?
            }
            PlanOperation::Restart => {
                let args: PlanRestartInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                serde_json::to_value(machine.restart(AgentSessionPlanRestartCommand {
                    expected_revision: args.expected_revision,
                    reason: args.reason,
                    operation_id,
                    argument_hash,
                    restarted_at: now,
                }))
                .map_err(ToolError::new)?
            }
        };
        let text = serde_json::to_string(&result).map_err(ToolError::new)?;
        let mut output = ToolOutput::new(
            OpaquePayload::new("pl.studio.plan-result", 1, text.clone()).map_err(ToolError::new)?,
            vec![ContextContent::Text {
                text: Arc::from(text),
            }],
        );
        if machine.state() != &previous {
            output = output.with_extension_mutations(vec![ExtensionMutation::Put {
                id: PLAN_EXTENSION.into(),
                expected_revision: Some(saved.revision),
                payload: encode_plan_state(machine.state())?,
            }]);
        }
        if let Some(prompt) = interaction {
            output = output.with_interaction(prompt);
        }
        Ok(output)
    }
}

/// Registers independent Plan tools without a mutable product session handle.
///
/// # Errors
/// Returns model declaration or core registration failures.
pub fn plan_registrations(
    options: AgentSessionPlanOptions,
) -> Result<Vec<Registration>, ThreadAssemblyError> {
    [
        PlanOperation::Current,
        PlanOperation::Next,
        PlanOperation::History,
        PlanOperation::Submit,
        PlanOperation::Restart,
    ]
    .into_iter()
    .map(|kind| {
        let definition = kind.definition()?;
        let prepared = prepare_registration(kind.name(), &definition, ToolCallPolicy::DirectOnly)?;
        let contract = match kind {
            PlanOperation::Current => "builtin.plan_current@1",
            PlanOperation::Next => "builtin.plan_next@1",
            PlanOperation::History => "builtin.plan_history@1",
            PlanOperation::Submit => "builtin.plan_submit@1",
            PlanOperation::Restart => "builtin.plan_restart@1",
        };
        let registration = prepared
            .attach(ToolHandle::new(ThreadPlanTool {
                definition,
                kind,
                options,
            }))
            .with_presentation_contract(ToolPresentationContract::new(contract));
        Ok(match kind {
            PlanOperation::Submit => registration.with_extension_updates().with_interactions(),
            PlanOperation::Restart => registration.with_extension_updates(),
            PlanOperation::Current | PlanOperation::Next | PlanOperation::History => registration,
        })
    })
    .collect()
}

#[cfg(test)]
mod argument_tests {
    use super::*;
    use pl_agent_tool::typed::{ArgumentError, JsonError};
    use pl_core::thread::extensions::ExtensionRecord;

    #[tokio::test]
    async fn plan_adapter_retains_argument_paths_and_trailing_source() {
        let tool = ThreadPlanTool {
            definition: PlanOperation::Submit.definition().unwrap(),
            kind: PlanOperation::Submit,
            options: Default::default(),
        };
        let extensions = Arc::new(std::collections::BTreeMap::from([(
            PLAN_EXTENSION.into(),
            ExtensionRecord {
                revision: 0,
                payload: encode_plan_state(&Default::default()).unwrap(),
            },
        )]));
        let context = CallContext {
            thread_id: "argument-thread".into(),
            turn_id: "argument-turn".into(),
            call_id: "argument-call".into(),
            cancellation: Default::default(),
            extensions: extensions.clone(),
            catalog: Arc::from([]),
            extension_sequence: 0,
            grant: Default::default(),
            context: Default::default(),
            history_fence: 0,
            model_projection: None,
            tasks: None,
        };
        for (raw, expected_path) in [
            (
                r##"{"expectedRevision":null,"plan":"# Plan"}"##,
                Some("expectedRevision"),
            ),
            (r#"{"expectedRevision":0,"plan":7}"#, Some("plan")),
            (r##"{"expectedRevision":0,"plan":"# Plan"} true"##, None),
        ] {
            let error = tool
                .execute(
                    OpaquePayload::new("application/json", 1, raw).unwrap(),
                    context.clone(),
                )
                .await
                .unwrap_err();
            let argument = error
                .source
                .downcast_ref::<ArgumentError>()
                .expect("product adapter must retain ArgumentError identity");
            match (argument, expected_path) {
                (ArgumentError::Decode { path, source }, Some(expected)) => {
                    assert_eq!(path, expected);
                    assert!(source.is_data());
                }
                (ArgumentError::Trailing { source }, None) => assert!(source.is_syntax()),
                _ => panic!("unexpected argument error classification: {argument:?}"),
            }
            assert!(
                std::error::Error::source(argument)
                    .unwrap()
                    .is::<JsonError>()
            );
            assert_eq!(
                decode_plan_state(&extensions[PLAN_EXTENSION].payload).unwrap(),
                Default::default()
            );
        }
        tool.close().await.unwrap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::plan_tool::TOOL_PLAN_SUBMIT;
    use pl_core::{
        context::{ContextContent, OpaquePayload},
        model::{
            DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput,
            ModelToolCall, ModelTurnAction, PreparedModelCall,
        },
        thread::{
            ModelStepLimit, ThreadHandle, TurnInput, TurnOutcome, extensions::ExtensionMutation,
            interactions::InteractionState,
        },
    };
    use std::sync::Arc;

    struct PlanningModel {
        requests: usize,
    }

    impl ModelSession for PlanningModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            self.requests += 1;
            let step = self.requests;
            assert!(step <= 2, "plan submission must suspend for confirmation");
            let calls = if step == 1 {
                Vec::new()
            } else {
                assert!(request.context.records.iter().any(|record| {
                    record.content.contains(&ContextContent::Text {
                        text: Arc::from("调查完成，接下来提交计划。"),
                    })
                }));
                vec![ModelToolCall {
                call_id: "submit-plan".into(),
                tool_id: TOOL_PLAN_SUBMIT.into(),
                arguments: OpaquePayload::new(
                    "application/json", 1,
                    serde_json::json!({"expectedRevision":0,"plan":"# 修复计划\n\n确认根因、实施修复并验证。"}).to_string(),
                ).unwrap(),
                presentation_contract: None,
                rejection: None,
            }]
            };
            Ok(PreparedModelCall::new(async move {
                Ok(ModelStepOutput {
                    turn_action: ModelTurnAction::Continue,
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: if step == 1 {
                        vec![ContextContent::Text {
                            text: Arc::from("调查完成，接下来提交计划。"),
                        }]
                    } else {
                        Vec::new()
                    },
                    tool_calls: calls,
                    private_context: None,
                    usage: Default::default(),
                })
            }))
        }

        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    #[tokio::test]
    async fn planning_progress_continues_to_real_plan_confirmation() {
        let thread = ThreadHandle::start(
            "planning-thread".into(),
            DynModelSession::new(PlanningModel { requests: 0 }),
        )
        .unwrap();
        thread
            .register_tools(plan_registrations(Default::default()).unwrap())
            .await
            .unwrap();
        thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: PLAN_EXTENSION.into(),
                expected_revision: None,
                payload: encode_plan_state(&Default::default()).unwrap(),
            }])
            .await
            .unwrap();
        let completion = thread
            .run_turn(TurnInput {
                turn_id: "planning-turn".into(),
                attempt_prefix: "planning-attempt".into(),
                content: vec![ContextContent::Text {
                    text: Arc::from("修复并提 PR"),
                }],
                max_model_steps: ModelStepLimit::Limited(3.try_into().unwrap()),
                cancellation: Default::default(),
            })
            .await
            .unwrap();
        assert_eq!(completion.model_steps, 2);
        assert_eq!(completion.outcome, TurnOutcome::WaitingInteraction);
        let snapshot = thread.snapshot();
        let plan = decode_plan_state(&snapshot.extensions[PLAN_EXTENSION].payload).unwrap();
        assert_eq!(
            plan.state,
            pl_protocol::AgentSessionPlanPhase::AwaitingConfirmation
        );
        let pending = &snapshot.interactions[plan.pending_interaction_id.as_ref().unwrap()];
        assert_eq!(pending.state, InteractionState::Pending);
        assert_eq!(pending.request.turn_id, "planning-turn");
        assert!(plan.document.unwrap().markdown.starts_with("# 修复计划"));
        thread.close().await.unwrap();
    }
}
