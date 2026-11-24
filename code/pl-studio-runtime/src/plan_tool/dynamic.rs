//! Studio adapter bridging the standalone `pl-tool-plan` tool family onto `CallContext`.

use super::types::{
    AgentSessionPlanState, LegacyAgentSessionPlanState, Plan, PlanActor, PlanHistoryArgs,
    PlanHistoryResponse, PlanNextResponse, PlanSnapshot, PlanState, PlanTransitionArgs,
    PlanTransitionCommand, PlanTransitionOutcome,
};
use crate::plan_tool::state::AgentSessionPlanOptions;
use crate::thread_assembler::ThreadAssemblyError;
use crate::{AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, UserQuestion, UserQuestionOption};
use pl_agent_tool::typed::TypedTool;
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
use pl_tool::binding::prepare_registration;
use pl_tool_plan::{PlanCurrentTool, PlanHistoryTool, PlanHost, PlanNextTool, PlanTransitionTool};
use std::sync::{Arc, Mutex};

pub const PLAN_EXTENSION: &str = "studio.plan";
const FORMAT: &str = "pl.studio.plan";

#[derive(Debug, thiserror::Error)]
enum PlanPayloadError {
    #[error("unsupported plan payload {format} version {version}")]
    Unsupported { format: String, version: u32 },
    #[error("invalid plan host context")]
    Context,
}

/// Encodes the complete product state for a generic Thread extension.
///
/// # Errors
/// Rejects invalid or excessive plan state and encoding errors.
pub fn encode_plan_state(state: &AgentSessionPlanState) -> Result<OpaquePayload, ToolError> {
    crate::plan_tool::state::validate_session_state_size(state).map_err(ToolError::new)?;
    OpaquePayload::new(
        FORMAT,
        1,
        serde_json::to_string(state).map_err(ToolError::new)?,
    )
    .map_err(ToolError::new)
}

/// Decodes either the current `pl-tool-plan` envelope or pre-unification v1 `studio.plan` JSON.
///
/// # Errors
/// Rejects unknown payload formats, corrupt plan state, and excessive content.
pub fn decode_plan_state(payload: &OpaquePayload) -> Result<AgentSessionPlanState, ToolError> {
    if payload.format() != FORMAT || payload.version() != 1 {
        return Err(ToolError::new(PlanPayloadError::Unsupported {
            format: payload.format().into(),
            version: payload.version(),
        }));
    }
    let state: AgentSessionPlanState = if let Ok(value) =
        serde_json::from_str::<serde_json::Value>(payload.content())
        && value.get("plan").is_none()
        && (value.get("state").is_some()
            || value.get("revision").is_some()
            || value.get("historyTail").is_some())
    {
        let legacy: LegacyAgentSessionPlanState =
            serde_json::from_value(value).map_err(ToolError::new)?;
        legacy.into()
    } else {
        serde_json::from_str(payload.content()).map_err(ToolError::new)?
    };
    crate::plan_tool::state::validate_session_state_size(&state).map_err(ToolError::new)?;
    Ok(state)
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct PlanConfirmationPrompt {
    pub question: crate::UserQuestion,
    pub expected_plan_revision: u64,
    pub plan_hash: String,
    /// Preserved inside the confirmation prompt itself so history reads remain self-contained.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub document_version: Option<u64>,
    pub created_at: i64,
    pub presentation: crate::MessagePresentation,
}

pub(crate) fn confirmation_question(plan: String) -> UserQuestion {
    UserQuestion {
        id: AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.to_string(),
        header: "Plan".to_string(),
        question: plan,
        is_other: true,
        is_secret: false,
        options: Some(vec![
            UserQuestionOption {
                label: "Approve".to_string(),
                description: "Approve this exact Plan and allow the task to proceed.".to_string(),
            },
            UserQuestionOption {
                label: "Revise".to_string(),
                description: "Request a revised Plan and optionally describe the changes."
                    .to_string(),
            },
        ]),
    }
}

struct StudioPlanCallState {
    previous: AgentSessionPlanState,
    next: AgentSessionPlanState,
    operation_id: String,
    argument_hash: String,
    interaction_id: String,
    now_secs: i64,
    options: AgentSessionPlanOptions,
    interaction: Option<OpaquePayload>,
}

struct StudioPlanCallContext(Arc<Mutex<StudioPlanCallState>>);

#[derive(Debug, Default)]
struct StudioPlanHost;

impl PlanHost for StudioPlanHost {
    type Context = StudioPlanCallContext;
    type Error = ToolError;

    async fn current(&self, context: Self::Context) -> Result<PlanSnapshot, Self::Error> {
        let guard = context
            .0
            .lock()
            .map_err(|_| ToolError::new(PlanPayloadError::Context))?;
        let plan = Plan::from_record(guard.previous.plan.clone()).map_err(ToolError::new)?;
        Ok(plan.snapshot())
    }

    async fn next(&self, context: Self::Context) -> Result<PlanNextResponse, Self::Error> {
        let guard = context
            .0
            .lock()
            .map_err(|_| ToolError::new(PlanPayloadError::Context))?;
        let plan = Plan::from_record(guard.previous.plan.clone()).map_err(ToolError::new)?;
        Ok(plan.next())
    }

    async fn history(
        &self,
        args: PlanHistoryArgs,
        context: Self::Context,
    ) -> Result<PlanHistoryResponse, Self::Error> {
        let guard = context
            .0
            .lock()
            .map_err(|_| ToolError::new(PlanPayloadError::Context))?;
        let plan = Plan::from_record(guard.previous.plan.clone()).map_err(ToolError::new)?;
        Ok(plan.history(args.limit))
    }

    async fn transition(
        &self,
        args: PlanTransitionArgs,
        context: Self::Context,
    ) -> Result<PlanTransitionOutcome, Self::Error> {
        let mut guard = context
            .0
            .lock()
            .map_err(|_| ToolError::new(PlanPayloadError::Context))?;
        let mut plan = Plan::from_record(guard.previous.plan.clone()).map_err(ToolError::new)?;
        let force = args.force;
        let idempotency_key = args
            .idempotency_key
            .clone()
            .or_else(|| Some(guard.operation_id.clone()));
        let command = PlanTransitionCommand {
            target_state: args.target_state,
            content: args.content,
            feedback: args.feedback,
            reason: args.reason,
            force,
            expected_revision: args.expected_revision,
            idempotency_key,
            argument_hash: Some(guard.argument_hash.clone()),
            actor: PlanActor::Agent,
            timestamp_ms: guard.now_secs.saturating_mul(1000),
        };
        let outcome = plan.transition(command);
        if outcome.accepted && !outcome.replayed {
            let mut next_state = AgentSessionPlanState {
                plan: plan.into_record(),
                pending_interaction_id: None,
            };
            if outcome.awaiting_confirmation
                && guard.options.allow_confirmation_interaction()
                && !force
                && let Some(doc) = &next_state.plan.document
            {
                let interaction_id = guard.interaction_id.clone();
                let prompt = PlanConfirmationPrompt {
                    question: confirmation_question(doc.content.clone()),
                    expected_plan_revision: next_state.plan.revision,
                    plan_hash: doc.hash.clone(),
                    document_version: Some(doc.revision),
                    created_at: guard.now_secs,
                    presentation: guard.options.submitted_plan_presentation(),
                };
                next_state.pending_interaction_id = Some(interaction_id);
                guard.interaction = Some(
                    OpaquePayload::new(
                        super::PLAN_CONFIRMATION_FORMAT,
                        1,
                        serde_json::to_string(&prompt).map_err(ToolError::new)?,
                    )
                    .map_err(ToolError::new)?,
                );
            }
            guard.next = next_state;
        } else if outcome.snapshot.state != PlanState::AwaitingConfirmation {
            guard.next.pending_interaction_id = None;
        }
        Ok(outcome)
    }
}

struct ThreadPlanTool<T> {
    tool: T,
    definition: ToolDefinition,
    options: AgentSessionPlanOptions,
}

impl<T> ThreadPlanTool<T>
where
    T: TypedTool<Context = StudioPlanCallContext, Error = ToolError>,
    T::Output: serde::Serialize,
{
    fn build(
        tool: T,
        options: AgentSessionPlanOptions,
    ) -> Result<Self, pl_agent_tool::DefinitionError> {
        let definition = ToolDefinition::json(
            T::NAME,
            T::DESCRIPTION,
            pl_agent_tool::typed::input_schema_for::<T::Args>(),
        )?;
        Ok(Self {
            tool,
            definition,
            options,
        })
    }
}

impl<T> Tool for ThreadPlanTool<T>
where
    T: TypedTool<Context = StudioPlanCallContext, Error = ToolError>,
    T::Output: serde::Serialize,
{
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
        let args: T::Args =
            pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
        let saved = context.extensions.get(PLAN_EXTENSION);
        let expected_extension_revision = saved.map(|record| record.revision);
        let previous = match saved {
            Some(record) => decode_plan_state(&record.payload)?,
            None => AgentSessionPlanState::default(),
        };
        let operation_id = format!(
            "{}/{}/{}",
            context.thread_id, context.turn_id, context.call_id
        );
        let argument_hash = pl_core::context::content_hash(input.content().as_bytes());
        let interaction_id = context.interaction_id();
        let now_secs = crate::studio::unix_seconds();

        let shared = Arc::new(Mutex::new(StudioPlanCallState {
            previous: previous.clone(),
            next: previous.clone(),
            operation_id,
            argument_hash,
            interaction_id,
            now_secs,
            options: self.options,
            interaction: None,
        }));
        let result = self
            .tool
            .execute(args, StudioPlanCallContext(Arc::clone(&shared)))
            .await?;
        let text = serde_json::to_string(&result).map_err(ToolError::new)?;
        let mut output = ToolOutput::new(
            OpaquePayload::new("pl.studio.plan-result", 1, text.clone()).map_err(ToolError::new)?,
            vec![ContextContent::Text {
                text: Arc::from(text),
            }],
        );
        let mut guard = shared
            .lock()
            .map_err(|_| ToolError::new(PlanPayloadError::Context))?;
        if guard.next != previous {
            output = output.with_extension_mutations(vec![ExtensionMutation::Put {
                id: PLAN_EXTENSION.into(),
                expected_revision: expected_extension_revision,
                payload: encode_plan_state(&guard.next)?,
            }]);
        }
        if let Some(prompt) = guard.interaction.take() {
            output = output.with_interaction(prompt);
        }
        Ok(output)
    }
}

/// Registers the standalone per-agent Plan tools (`plan_current`, `plan_next`, `plan_history`,
/// `plan_transition`) without binding them to a mutable product session handle or workflow.
///
/// # Errors
/// Returns model declaration or core registration failures.
pub fn plan_registrations(
    options: AgentSessionPlanOptions,
) -> Result<Vec<Registration>, ThreadAssemblyError> {
    let host = Arc::new(StudioPlanHost);
    let r_current = register_one(
        ThreadPlanTool::build(PlanCurrentTool::new(Arc::clone(&host)), options)?,
        "builtin.plan_current@1",
        false,
        false,
    )?;
    let r_next = register_one(
        ThreadPlanTool::build(PlanNextTool::new(Arc::clone(&host)), options)?,
        "builtin.plan_next@1",
        false,
        false,
    )?;
    let r_history = register_one(
        ThreadPlanTool::build(PlanHistoryTool::new(Arc::clone(&host)), options)?,
        "builtin.plan_history@1",
        false,
        false,
    )?;
    let r_transition = register_one(
        ThreadPlanTool::build(PlanTransitionTool::new(host), options)?,
        "builtin.plan_transition@1",
        true,
        true,
    )?;
    Ok(vec![r_current, r_next, r_history, r_transition])
}

fn register_one<T>(
    adapter: ThreadPlanTool<T>,
    contract: &'static str,
    extension_updates: bool,
    interactions: bool,
) -> Result<Registration, ThreadAssemblyError>
where
    T: TypedTool<Context = StudioPlanCallContext, Error = ToolError>,
    T::Output: serde::Serialize,
{
    let definition = adapter.definition().clone();
    let prepared = prepare_registration(T::NAME, &definition, ToolCallPolicy::DirectOnly)?;
    let mut registration = prepared
        .attach(ToolHandle::new(adapter))
        .with_presentation_contract(ToolPresentationContract::new(contract));
    if extension_updates {
        registration = registration.with_extension_updates();
    }
    if interactions {
        registration = registration.with_interactions();
    }
    Ok(registration)
}

#[cfg(test)]
mod argument_tests {
    use super::*;
    use pl_agent_tool::typed::{ArgumentError, JsonError};
    use pl_core::thread::extensions::ExtensionRecord;

    #[tokio::test]
    async fn plan_adapter_retains_argument_paths_and_trailing_source() {
        let host = Arc::new(StudioPlanHost);
        let tool = ThreadPlanTool::build(
            PlanTransitionTool::new(host),
            AgentSessionPlanOptions::default().with_confirmation_interaction(true),
        )
        .unwrap();
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
                r##"{"targetState":"awaitingConfirmation","expectedRevision":"bad","content":"# Plan"}"##,
                Some("expectedRevision"),
            ),
            (
                r#"{"targetState":"awaitingConfirmation","content":7}"#,
                Some("content"),
            ),
            (
                r##"{"targetState":"awaitingConfirmation","content":"# Plan"} true"##,
                None,
            ),
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
