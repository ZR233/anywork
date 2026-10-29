//! Typed user-input history projected from the one canonical interaction fact.
//!
//! The asking tool's own result is only `Waiting for the user's response.`, so the questions and the
//! accepted answer can never be read from the tool outcome. They live in the interaction record of
//! the same commit — an ordinary `pl.tool.user-input` question or the Plan confirmation the
//! `plan_submit` call raised — and this module is the one decode boundary that turns that record into
//! the typed history projection carried by the tool item. Plan facts keep their own payload decoder,
//! verification and safe public projection in the format owner; this module only maps the verified
//! question, the authoritative lifecycle and the accepted answers onto the shared typed structure.
//! The private receipt keeps its original payload; only the public projection is redacted.
use std::collections::HashMap;

use pl_core::{
    context::OpaquePayload,
    thread::interactions::{InteractionRecord, InteractionState},
};

use pl_protocol::{
    InteractionContent, InteractionResolution, InteractionStatus, ResolvedThreadToolUserInput,
    ThreadItem, ThreadItemState, ThreadToolUserInput, ThreadToolUserInputAnswer,
    ThreadToolUserInputState, UserInputAnswer, UserQuestion,
};

use super::ProjectionError;

/// Producer-owned payload format of the ordinary question tool.
pub(in crate::studio) const USER_INPUT_FORMAT: &str = "pl.tool.user-input";
/// Producer-owned payload format of the accepted answer receipt.
pub(in crate::studio) const USER_ANSWER_FORMAT: &str = "pl.studio.user-answer";

/// Decoded `{"answers": {questionId: {answers: [..]}}}` receipt body.
#[derive(serde::Deserialize)]
struct AcceptedAnswers {
    answers: HashMap<String, UserInputAnswer>,
}

/// Projects one interaction record into the tool item's typed user-input history.
///
/// Returns `None` for every interaction that is not a user-input request, so this module never
/// reinterprets another product fact. A Plan confirmation keeps its own payload owner and only
/// shares the typed structure returned here.
///
/// # Errors
/// Rejects unknown payload versions, undecodable questions, answers naming a question the request
/// never asked, and Plan confirmation facts the Plan owner cannot verify: a broken fact fails
/// explicitly instead of publishing a fabricated answer or decision.
pub(in crate::studio) fn project_user_input(
    thread_id: &str,
    record: &InteractionRecord,
) -> Result<Option<ThreadToolUserInput>, ProjectionError> {
    match record.request.payload.format() {
        USER_INPUT_FORMAT => project_questions(record).map(Some),
        crate::plan_tool::PLAN_CONFIRMATION_FORMAT => project_plan(thread_id, record).map(Some),
        _ => Ok(None),
    }
}

/// Projects one ordinary question request from its own producer payload and answer receipt.
fn project_questions(record: &InteractionRecord) -> Result<ThreadToolUserInput, ProjectionError> {
    let questions: Vec<UserQuestion> = decode(&record.request.payload, USER_INPUT_FORMAT)?;
    let state = match &record.state {
        InteractionState::Pending => ThreadToolUserInputState::Pending,
        InteractionState::Cancelled => ThreadToolUserInputState::Cancelled,
        InteractionState::Resolved(response) => {
            let accepted: AcceptedAnswers = decode(&response.payload, USER_ANSWER_FORMAT)?;
            ThreadToolUserInputState::Resolved(ResolvedThreadToolUserInput::new(answers(
                &questions,
                &accepted.answers,
            )?))
        }
    };
    Ok(ThreadToolUserInput::new(
        record.request.id.clone(),
        questions,
        state,
    ))
}

/// Projects one Plan confirmation onto the same typed structure.
///
/// The question origin, the Plan text hash, the interaction revision domain and the accepted answer
/// are all verified by the Plan owner's own public projection, so this function never reinterprets a
/// Plan payload or grows a second Plan state machine. Only the verified facts are mapped.
///
/// # Errors
/// Rejects a Plan fact the format owner cannot verify, a lifecycle this product never writes, and a
/// resolved confirmation whose decision the Plan kernel itself rejects: an undecidable answer is
/// never read as approved.
fn project_plan(
    thread_id: &str,
    record: &InteractionRecord,
) -> Result<ThreadToolUserInput, ProjectionError> {
    let projected =
        crate::thread_assembler::project_plan_confirmation(thread_id, record).map_err(|error| {
            ProjectionError::UserInput(format!(
                "saved Plan confirmation cannot be projected: {error}"
            ))
        })?;
    let InteractionContent::UserInput(content) = &projected.content else {
        return Err(ProjectionError::UserInput(
            "saved Plan confirmation is not a user-input interaction".into(),
        ));
    };
    let questions = content.questions().to_vec();
    let identity =
        crate::thread_assembler::plan_confirmation_document_identity(record).map_err(|error| {
            ProjectionError::UserInput(format!(
                "saved Plan document identity cannot be projected: {error}"
            ))
        })?;
    let state = match projected.status() {
        InteractionStatus::Pending => ThreadToolUserInputState::Pending,
        InteractionStatus::Cancelled => ThreadToolUserInputState::Cancelled,
        InteractionStatus::Resolved => {
            let Some(InteractionResolution::UserInput(resolution)) = projected.resolution() else {
                return Err(ProjectionError::UserInput(
                    "resolved Plan confirmation carries no accepted answer".into(),
                ));
            };
            // 决定语义由 Plan 内核自己的判定验证（Approve / Revise / 纯反馈），这里不重新解析标记，
            // 也不收窄内核允许的输入；拒绝原因只描述事实，不回显用户正文或计划正文。
            crate::plan_tool::state::confirmation_decision(&resolution).map_err(|reason| {
                ProjectionError::UserInput(format!(
                    "saved Plan confirmation decision is invalid: {reason}"
                ))
            })?;
            let accepted = answers(&questions, &resolution.answers)?;
            ThreadToolUserInputState::Resolved(ResolvedThreadToolUserInput::new(accepted))
        }
        InteractionStatus::Expired => {
            return Err(ProjectionError::UserInput(
                "saved Plan confirmation has an unsupported lifecycle".into(),
            ));
        }
    };
    Ok(
        ThreadToolUserInput::new(record.request.id.clone(), questions, state)
            .with_plan_document(identity),
    )
}

/// Attaches one projected user-input history to the tool item that owns the interaction.
///
/// The tool item is the persisted owner of the fact: it keeps its identity, ordinal, creation time
/// and lifecycle, and only gains the Q&A body. The call named by the interaction identity has to be
/// exactly the item's own call, so no neighbouring row can ever receive another call's answer, and a
/// Plan confirmation can only ever land on the `plan_submit` call that raised it.
///
/// # Errors
/// Rejects a non-tool item or an identity that does not name the item's own call.
pub(in crate::studio) fn attach(
    item: &mut ThreadItem,
    user_input: ThreadToolUserInput,
) -> Result<(), ProjectionError> {
    let ThreadItemState::Tool(tool) = item.state() else {
        return Err(ProjectionError::UserInput(format!(
            "item `{}` is not a tool call and cannot own a user-input history",
            item.id
        )));
    };
    let owns = pl_core::tool::opaque::tool_interaction_id(tool.invocation().tool_call_id())
        == user_input.interaction_id();
    if !owns {
        return Err(ProjectionError::UserInput(format!(
            "item `{}` does not own the user-input history it was given",
            item.id
        )));
    }
    let state = ThreadItemState::Tool(
        tool.clone()
            .with_user_input(Some(user_input))
            .with_wait(tool.wait().cloned()),
    );
    *item = item.clone().with_state(state);
    Ok(())
}

/// Accepted answers in question order, with sensitive values kept private.
fn answers(
    questions: &[UserQuestion],
    accepted: &HashMap<String, UserInputAnswer>,
) -> Result<Vec<ThreadToolUserInputAnswer>, ProjectionError> {
    // 诊断只说明事实，不回显任何载荷内容：答案载荷可能含有用户私密输入。
    if accepted
        .keys()
        .any(|id| !questions.iter().any(|question| &question.id == id))
    {
        return Err(ProjectionError::UserInput(
            "accepted answers name a question the request never asked".into(),
        ));
    }
    let mut ordered = Vec::with_capacity(accepted.len());
    for question in questions {
        let Some(answer) = accepted.get(&question.id) else {
            continue;
        };
        // 空答案列表表示“这一题没有作答”，不是“已回答但被隐藏”：只有真正提供了值的敏感题才脱敏。
        // 采纳的私有回执与 resolution 允许的输入不变，历史投影不替用户伪造已提供。
        if answer.answers.is_empty() {
            continue;
        }
        ordered.push(if question.is_secret {
            ThreadToolUserInputAnswer::redacted(question.id.clone())
        } else {
            ThreadToolUserInputAnswer::new(question.id.clone(), answer.answers.clone())
        });
    }
    Ok(ordered)
}

/// Decodes one producer payload of the expected format and version.
fn decode<T: serde::de::DeserializeOwned>(
    payload: &OpaquePayload,
    format: &str,
) -> Result<T, ProjectionError> {
    if payload.format() != format || payload.version() != 1 {
        return Err(ProjectionError::UserInput(format!(
            "unsupported saved `{format}` payload version {}",
            payload.version()
        )));
    }
    // 解码失败只报事实：绝不把载荷正文或反序列化上下文带进诊断。
    serde_json::from_str(payload.content()).map_err(|_| {
        ProjectionError::UserInput(format!("saved `{format}` payload cannot be decoded"))
    })
}
