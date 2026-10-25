//! Ordinary question projection and atomic user-answer continuation.
use super::StudioThreadAssembler;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::{
        input::ThreadInput,
        interactions::{
            InteractionRecord, InteractionResolution as CoreResolution, InteractionResponse,
            InteractionState,
        },
    },
};
use pl_protocol::{
    InteractionCommand, InteractionRequest, InteractionScope, ResolveUserInput, UserInputResolution,
};
use std::collections::BTreeMap;

#[derive(Debug, thiserror::Error)]
pub enum UserInteractionError {
    #[error(transparent)]
    Key(#[from] super::InteractionKeyError),
    #[error("unsupported user interaction payload {format} version {version}")]
    Unsupported { format: String, version: u32 },
    #[error("user interaction question id {id} is reserved for plan confirmation")]
    ReservedQuestion { id: String },
    #[error("user interaction payload is invalid")]
    Decode(#[from] serde_json::Error),
    #[error("user interaction identity or revision does not match")]
    Identity,
    #[error("user answer validation failed")]
    Projection(#[from] pl_protocol::InteractionTransitionError),
    #[error("user answer could not be frozen")]
    Payload(#[from] pl_core::context::PayloadError),
    #[error("Thread rejected user answer")]
    Thread(#[from] pl_core::thread::ThreadError),
    #[error("user answer continuation model is unavailable")]
    Admission(#[from] super::ThreadAssemblyError),
}
fn decode<T: serde::de::DeserializeOwned>(
    payload: &OpaquePayload,
    format: &str,
) -> Result<T, UserInteractionError> {
    if payload.format() != format || payload.version() != 1 {
        return Err(UserInteractionError::Unsupported {
            format: payload.format().into(),
            version: payload.version(),
        });
    }
    Ok(serde_json::from_str(payload.content())?)
}

/// Projects the original tool questions and saved user response into the existing product DTO.
///
/// # Errors
/// Rejects unknown encodings, invalid responses and contradictory record revisions.
pub fn project_user_input(
    thread_id: &str,
    record: &InteractionRecord,
) -> Result<InteractionRequest, UserInteractionError> {
    let questions: Vec<pl_protocol::UserQuestion> =
        decode(&record.request.payload, "pl.tool.user-input")?;
    // 计划确认的问题身份是保留标识：普通提问不得占用它。否则界面无法仅凭该身份把子会话的
    // 计划诊断与普通问题区分开，普通问题也会被误当作诊断事实隐藏。
    if let Some(reserved) = questions
        .iter()
        .find(|question| question.id == pl_protocol::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID)
    {
        return Err(UserInteractionError::ReservedQuestion {
            id: reserved.id.clone(),
        });
    }
    let wire_id = super::interaction_key::encode(thread_id, &record.request.id);
    let mut projected = InteractionRequest::user_input(
        wire_id.clone(),
        InteractionScope {
            thread_id: thread_id.into(),
            turn_id: record.request.turn_id.clone(),
            item_id: None,
            tool_id: None,
            agent_path: Some(thread_id.into()),
            purpose: Default::default(),
        },
        questions,
        record.created_at,
    )
    .with_continuation(pl_protocol::InteractionContinuationPreset::resolution(
        pl_protocol::MessagePresentation::Hidden,
    ));
    projected.revision = 1;
    let command = match &record.state {
        InteractionState::Pending => None,
        InteractionState::Resolved(response) => {
            let response: UserInputResolution = decode(&response.payload, "pl.studio.user-answer")?;
            Some(InteractionCommand::ResolveUserInput(ResolveUserInput {
                interaction_id: wire_id.clone(),
                expected_revision: 1,
                operation_id: format!("resolve:{wire_id}"),
                resolved_at: record.updated_at,
                answers: response.answers,
            }))
        }
        InteractionState::Cancelled => {
            Some(InteractionCommand::Cancel(pl_protocol::CancelInteraction {
                interaction_id: wire_id.clone(),
                expected_revision: 1,
                operation_id: format!("cancel:{wire_id}"),
                reason: "User input was cancelled.".into(),
                cancelled_at: record.updated_at,
            }))
        }
    };
    if let Some(command) = command {
        let decision = projected.decide(command)?;
        projected.apply(decision, record.updated_at);
    }
    if projected.revision != record.revision {
        return Err(UserInteractionError::Identity);
    }
    Ok(projected)
}

fn prepare_resolution(
    thread_id: &str,
    record: &InteractionRecord,
    resolution: ResolveUserInput,
) -> Result<CoreResolution, UserInteractionError> {
    if record.request.id != resolution.interaction_id
        || record.revision != resolution.expected_revision
        || !matches!(record.state, InteractionState::Pending)
    {
        return Err(UserInteractionError::Identity);
    }
    let projected = project_user_input(thread_id, record)?;
    let mut validation = resolution.clone();
    validation.interaction_id = projected.interaction_id.clone();
    projected.decide(InteractionCommand::ResolveUserInput(validation))?;
    let answers = resolution
        .answers
        .iter()
        .map(|(id, answer)| (id.as_str(), answer))
        .collect::<BTreeMap<_, _>>();
    // The operation identity is part of the frozen decision, so the same operation is answered from
    // this record and a different one under the same id is visibly a conflict.
    let encoded = serde_json::to_string(
        &serde_json::json!({"answers":answers,"operationId":resolution.operation_id}),
    )?;
    let payload = OpaquePayload::new("pl.studio.user-answer", 1, encoded.clone())?;
    let continuation_metadata = OpaquePayload::new(
        "pl.studio.interaction-continuation",
        1,
        serde_json::to_string(
            &serde_json::json!({"interactionId":record.request.id,"presentation":pl_protocol::MessagePresentation::Hidden}),
        )?,
    )?;
    Ok(CoreResolution {
        id: record.request.id.clone(),
        expected_revision: record.revision,
        mutations: Vec::new(),
        response: InteractionResponse {
            payload,
            context: vec![ContextContent::Text {
                text: "User response received.".into(),
            }],
        },
        continuation: Some(ThreadInput {
            purpose: pl_core::thread::input::InputPurpose::Message,
            id: format!("interaction:{}:continuation", record.request.id),
            payload: continuation_metadata,
            context: vec![ContextContent::Text {
                text: encoded.into(),
            }],
        }),
    })
}

impl StudioThreadAssembler {
    /// Validates an answer and commits it with its continuation.
    ///
    /// Only the main session resumes its own queue: the answer is a user decision, so its own work
    /// continues exactly like before. A child answer is a decision fact for its parent to act on, so
    /// the child keeps the decision and its pending continuation input and is not started here; the
    /// parent agent decides whether and how to schedule that member again.
    ///
    /// # Errors
    /// Rejects unknown owners, stale questions, invalid answers and failed core admission.
    pub async fn resolve_user_input(
        &self,
        mut resolution: ResolveUserInput,
    ) -> Result<InteractionRequest, UserInteractionError> {
        let (thread_id, local_id) = super::decode_interaction_key(&resolution.interaction_id)?;
        let thread_id = thread_id.to_owned();
        resolution.interaction_id = local_id.to_owned();
        let _operation = self.agent_operation(&thread_id).await;
        let (thread, execution, is_root) = {
            self.0.state().entries.get(&thread_id).map(|entry| {
                (
                    entry.thread.clone(),
                    entry.execution,
                    entry.parent_id.is_none(),
                )
            })
        }
        .ok_or(UserInteractionError::Identity)?;
        let snapshot = thread.snapshot();
        let current = snapshot
            .interactions
            .get(&resolution.interaction_id)
            .ok_or(UserInteractionError::Identity)?;
        if let InteractionState::Resolved(saved) = &current.state {
            let answer: UserInputResolution = decode(&saved.payload, "pl.studio.user-answer")?;
            if resolution.expected_revision.checked_add(1) == Some(current.revision)
                && answer.answers == resolution.answers
            {
                return project_user_input(&thread_id, current);
            }
            return Err(UserInteractionError::Identity);
        }
        self.prepare_input_admission(&thread_id, &thread).await?;
        let committed = thread
            .resolve_interaction(prepare_resolution(&thread_id, current, resolution)?)
            .await?;
        if is_root {
            thread.resume_inputs(execution).await?;
        }
        project_user_input(&thread_id, &committed)
    }
}
