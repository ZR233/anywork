//! Ordinary user Q&A history projected from the one canonical interaction fact.
//!
//! The question tool's own result is only `Waiting for the user's response.`, so the questions and
//! the accepted answer can never be read from the tool outcome. They live in the interaction record
//! of the same commit (`pl.tool.user-input` and `pl.studio.user-answer`), and this module is the one
//! decode boundary that turns that record into the typed history projection carried by the tool
//! item. The private receipt keeps its original payload; only the public projection is redacted.
use std::collections::BTreeMap;

use pl_core::{
    context::OpaquePayload,
    thread::interactions::{InteractionRecord, InteractionState},
};

use pl_protocol::{
    ResolvedThreadToolUserInput, ThreadItem, ThreadItemState, ThreadToolUserInput,
    ThreadToolUserInputAnswer, ThreadToolUserInputState, UserInputAnswer, UserQuestion,
};

use super::ProjectionError;

/// Producer-owned payload format of the ordinary question tool.
pub(in crate::studio) const USER_INPUT_FORMAT: &str = "pl.tool.user-input";
/// Producer-owned payload format of the accepted answer receipt.
pub(in crate::studio) const USER_ANSWER_FORMAT: &str = "pl.studio.user-answer";

/// Decoded `{"answers": {questionId: {answers: [..]}}}` receipt body.
#[derive(serde::Deserialize)]
struct AcceptedAnswers {
    answers: BTreeMap<String, UserInputAnswer>,
}

/// Projects one interaction record into the tool item's typed Q&A history.
///
/// Returns `None` for every interaction that is not an ordinary question request (a Plan
/// confirmation keeps its own projection) so this module never reinterprets another product fact.
///
/// # Errors
/// Rejects unknown payload versions, undecodable questions, and answers naming a question the
/// request never asked: a broken fact fails explicitly instead of publishing a fabricated answer.
pub(in crate::studio) fn project_user_input(
    record: &InteractionRecord,
) -> Result<Option<ThreadToolUserInput>, ProjectionError> {
    if record.request.payload.format() != USER_INPUT_FORMAT {
        return Ok(None);
    }
    let questions: Vec<UserQuestion> = decode(&record.request.payload, USER_INPUT_FORMAT)?;
    let state = match &record.state {
        InteractionState::Pending => ThreadToolUserInputState::Pending,
        InteractionState::Cancelled => ThreadToolUserInputState::Cancelled,
        InteractionState::Resolved(response) => {
            let accepted: AcceptedAnswers = decode(&response.payload, USER_ANSWER_FORMAT)?;
            ThreadToolUserInputState::Resolved(ResolvedThreadToolUserInput::new(answers(
                &questions,
                accepted.answers,
            )?))
        }
    };
    Ok(Some(ThreadToolUserInput::new(
        record.request.id.clone(),
        questions,
        state,
    )))
}

/// Attaches one projected Q&A history to the tool item that owns the interaction.
///
/// The tool item is the persisted owner of the fact: it keeps its identity, ordinal, creation time
/// and lifecycle, and only gains the Q&A body. The call named by the interaction identity has to be
/// exactly the item's own call, so no neighbouring row can ever receive another call's answer.
///
/// # Errors
/// Rejects a non-tool item or an identity that does not name the item's own call.
pub(in crate::studio) fn attach(
    item: &mut ThreadItem,
    user_input: ThreadToolUserInput,
) -> Result<(), ProjectionError> {
    let ThreadItemState::Tool(tool) = item.state() else {
        return Err(ProjectionError::UserInput(format!(
            "item `{}` is not a tool call and cannot own an ordinary user Q&A",
            item.id
        )));
    };
    let owns = pl_core::tool::opaque::tool_interaction_id(tool.invocation().tool_call_id())
        == user_input.interaction_id();
    if !owns {
        return Err(ProjectionError::UserInput(format!(
            "item `{}` does not own the ordinary user Q&A it was given",
            item.id
        )));
    }
    let state = ThreadItemState::Tool(tool.clone().with_user_input(Some(user_input)));
    *item = item.clone().with_state(state);
    Ok(())
}

/// Accepted answers in question order, with sensitive values kept private.
fn answers(
    questions: &[UserQuestion],
    accepted: BTreeMap<String, UserInputAnswer>,
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
