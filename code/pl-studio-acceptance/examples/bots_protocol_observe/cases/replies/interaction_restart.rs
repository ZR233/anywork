//! `reply-interaction-restart`: real question continuation, one local hint per
//! pending interaction, and a formal reply that survives a same-home restart.
//!
//! The model really calls `request_user_input` (q1) and then `plan_submit`
//! (the Plan confirmation interaction), so the only path to the final formal
//! reply is: discover the wire interaction IDs over the public thread SSE,
//! resolve them over the public HTTP endpoint across a real server restart,
//! and let the recovered watcher continue the original inbound work. On a
//! server that keeps the inbound claim for its full lease (or looks the
//! continuation up under the wrong identity) the second hint and the formal
//! reply never arrive, so the case fails instead of degrading.

use super::super::Session;
use super::{CASE_BUDGET, answers_json, ensure_bound_row, optional_title_step};
use crate::http;
use crate::report::{self, CaseResult};
use crate::thread_watch::{ThreadWatch, interaction_line};
use anyhow::{Context, Result, ensure};
use pl_protocol::studio::ResolveInteractionRequest;
use pl_protocol::{
    AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, InteractionContent, InteractionRequest,
    InteractionResolution, InteractionStatus, UserInputAnswer, UserInputResolution,
};
use pl_provider_fixture::feishu::{
    CallKind, ChatType, DIRECT_CHAT_ID, SenderKind, TRUSTED_USER_OPEN_ID, text_event,
};
use pl_provider_fixture::{
    Protocol, RealtimeToolCall, Reply, Step, responses_text, responses_tool_calls,
};
use std::collections::HashMap;

pub(super) const CASE: &str = "reply-interaction-restart";

const MESSAGE_ID: &str = "om_restart_interact";
const PROMPT: &str = "Bots restart interaction fixture: confirm the release wording";
const Q1_ID: &str = "wording";
const Q1_ANSWER: &str = "lightweight receipt";
const PLAN_MD: &str = "# Bots restart reply plan\n\n- Ask the operator for the wording once.\n- Confirm the plan in the local Studio app.\n- Send exactly one final confirmation reply.";
const FINAL_TEXT: &str =
    "Bots restart final reply: lightweight receipt wording confirmed after plan approval.";
const FINAL_MARKER: &str = "Bots restart final reply";
const RESTART_SETTLE: std::time::Duration = std::time::Duration::from_secs(8);

pub(crate) async fn interaction_restart(session: &mut Session) -> Result<CaseResult> {
    let mut evidence = Vec::new();
    let outcome = tokio::time::timeout(
        CASE_BUDGET,
        interaction_restart_inner(session, &mut evidence),
    )
    .await;
    match outcome {
        Ok(Ok(result)) => Ok(result),
        Ok(Err(error)) => {
            let mut result = report::failed(CASE, format!("{error:#}"));
            result.evidence = evidence;
            Ok(result)
        }
        Err(_) => {
            let mut result = report::failed(
                CASE,
                "reply-interaction-restart exceeded its absolute observe budget",
            );
            result.evidence = evidence;
            Ok(result)
        }
    }
}

async fn interaction_restart_inner(
    session: &mut Session,
    evidence: &mut Vec<String>,
) -> Result<CaseResult> {
    let (bot_id, _) = session.ensure_trusted_direct().await?;
    session.wait_connected(&bot_id).await?;

    session
        .control()?
        .send_event(text_event(
            MESSAGE_ID,
            DIRECT_CHAT_ID,
            ChatType::P2p,
            SenderKind::User,
            TRUSTED_USER_OPEN_ID,
            PROMPT,
            Vec::new(),
        ))
        .await?;
    let thread_id = super::wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;
    evidence.push(format!("thread={thread_id} bound for DM {DIRECT_CHAT_ID}"));

    // Phase 1: the first model call must really ask the operator.
    let mut watch = ThreadWatch::connect(session.http()?.origin(), &thread_id).await?;
    let snapshot = watch.wait_snapshot(http::PREDICATE_TIMEOUT).await?;
    evidence.push(format!(
        "snapshot revision={} interactions={}",
        snapshot.revision,
        snapshot.interactions.len()
    ));
    let q1 = watch.interaction(http::PREDICATE_TIMEOUT, Q1_ID).await?;
    ensure!(
        q1.scope.thread_id == thread_id && !q1.scope.turn_id.is_empty(),
        "q1 interaction scope must stay on the bound Thread"
    );
    evidence.push(format!("q1 {}", interaction_line(&q1)));

    wait_hint_count(session, 1).await?;
    let model_after_step0 = session.model_executions();
    ensure!(
        model_after_step0 == 1,
        "the first inbound must consume exactly one model execution before the restart, got {model_after_step0}"
    );

    // Phase 2: stop the server, really wait for its exit, relaunch the same
    // binary against the same home/manifest/keyring store. The Feishu peer and
    // the model fixture stay alive for the whole case.
    let restart = session.restart_studio_server().await?;
    evidence.push(restart);
    session.wait_connected(&bot_id).await?;
    http::hold_for(RESTART_SETTLE).await;
    let model_after_restart = session.model_executions();
    ensure!(
        model_after_restart == model_after_step0,
        "restart must not re-execute the original inbound input (model {model_after_step0} -> {model_after_restart})"
    );

    // Phase 3: canonical pending rebuild, then resolve q1 over public HTTP.
    let mut watch2 = ThreadWatch::connect(session.http()?.origin(), &thread_id).await?;
    let rebuilt = watch2.wait_snapshot(http::PREDICATE_TIMEOUT).await?;
    let rebuilt_q1 = rebuilt
        .interactions
        .iter()
        .find(|item| is_user_input_question(item, Q1_ID))
        .context("the pending question must be canonically rebuilt after the restart")?;
    ensure!(
        rebuilt_q1.interaction_id == q1.interaction_id
            && rebuilt_q1.status() == InteractionStatus::Pending
            && rebuilt_q1.scope == q1.scope,
        "the rebuilt pending interaction changed identity, scope, or status: {} -> {}",
        interaction_line(&q1),
        interaction_line(rebuilt_q1)
    );
    session
        .http()?
        .resolve_interaction(
            &q1.interaction_id,
            &ResolveInteractionRequest {
                operation_id: "op-bots-restart-q1".into(),
                resolution: InteractionResolution::UserInput(UserInputResolution {
                    answers: HashMap::from([(
                        Q1_ID.to_string(),
                        UserInputAnswer {
                            answers: vec![Q1_ANSWER.to_string()],
                        },
                    )]),
                }),
            },
        )
        .await
        .context("resolving the first question over public HTTP failed")?;

    // Phase 4: the continuation must drive the model into a real Plan
    // confirmation interaction, discovered as a typed SSE increment.
    let plan = watch2
        .wait_interaction(
            http::PREDICATE_TIMEOUT,
            |item| {
                is_user_input_question(item, AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID)
                    && item.status() == InteractionStatus::Pending
            },
            "plan confirmation after q1 resolution",
        )
        .await?;
    ensure!(
        plan.scope.thread_id == thread_id,
        "plan confirmation must stay on the bound Thread"
    );
    evidence.push(format!("plan {}", interaction_line(&plan)));

    wait_hint_count(session, 2).await?;

    session
        .http()?
        .resolve_interaction(
            &plan.interaction_id,
            &ResolveInteractionRequest {
                operation_id: "op-bots-restart-plan".into(),
                resolution: InteractionResolution::UserInput(UserInputResolution {
                    answers: HashMap::from([(
                        AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.to_string(),
                        UserInputAnswer {
                            answers: vec!["Approve".to_string()],
                        },
                    )]),
                }),
            },
        )
        .await
        .context("approving the plan over public HTTP failed")?;

    // Phase 5: exactly one complete formal reply.
    session.wait_send_text_count(FINAL_MARKER, 1).await?;
    let facts_final = reply_send_facts(session).await?;
    ensure!(
        facts_final.final_bodies == 1,
        "the formal reply must be sent exactly once and complete, got {}",
        facts_final.final_bodies
    );
    ensure!(
        facts_final.total == 3,
        "two hints plus one formal reply must be the whole send history, got {}",
        facts_final.total
    );
    let final_body = session
        .send_bodies()
        .await?
        .into_iter()
        .find(|body| body.to_string().contains(FINAL_MARKER))
        .context("final send body missing")?;
    ensure!(
        body_has_complete_final(&final_body),
        "the sent formal reply must carry the complete final text"
    );

    session.wait_inbound_completed(&bot_id, MESSAGE_ID).await?;
    let model_total = session.model_executions();
    ensure!(
        model_total == 3,
        "the whole journey must consume exactly three model executions, got {model_total}"
    );

    let sends = crate::sqlite::send_details(&session.home, &bot_id).await?;
    ensure!(
        sends.len() == 3 && sends.iter().all(|row| row.status == "succeeded"),
        "two hints plus one formal reply must be the durable send ledger, got {:?}",
        sends
            .iter()
            .map(|row| (row.operation_id.as_str(), row.status.as_str()))
            .collect::<Vec<_>>()
    );
    let bindings = crate::sqlite::thread_bindings(&session.home, &bot_id).await?;
    let dm = bindings
        .iter()
        .filter(|row| row.chat_id == DIRECT_CHAT_ID)
        .collect::<Vec<_>>();
    ensure!(
        dm.len() == 1,
        "the original DM must keep exactly one Thread binding, got {}",
        dm.len()
    );
    ensure_bound_row(dm[0])?;
    ensure!(
        dm[0].thread_id == thread_id,
        "the DM must stay bound to the original Thread {}",
        thread_id
    );

    let mut result = report::passed(
        CASE,
        format!(
            "one hint per pending interaction, canonical pending rebuild after a same-home restart, public resolutions continued the original Thread into a real Plan confirmation, and the formal reply was sent exactly once (thread={thread_id}, model executions={model_total})"
        ),
    );
    result.evidence = evidence.clone();
    Ok(result)
}

struct ReplySendFacts {
    total: usize,
    final_bodies: usize,
}

/// Counts accepted Feishu message sends, splitting the formal reply (body
/// carries the final marker) from every other send (the per-interaction local
/// hint), so unexpected sends cannot hide inside the hint count.
async fn reply_send_facts(session: &Session) -> Result<ReplySendFacts> {
    let report = session.control()?.snapshot_report().await;
    let mut total = 0usize;
    let mut final_bodies = 0usize;
    for call in report
        .calls
        .iter()
        .filter(|call| call.kind == Some(CallKind::MessageSend) && call.accepted)
    {
        total += 1;
        if call
            .send_body
            .as_ref()
            .is_some_and(|body| body.to_string().contains(FINAL_MARKER))
        {
            final_bodies += 1;
        }
    }
    Ok(ReplySendFacts {
        total,
        final_bodies,
    })
}

/// Waits (bounded) until exactly `expected` non-final sends have happened and
/// no formal reply has leaked early, then leaves the strict count assertions
/// to the caller's next facts read.
async fn wait_hint_count(session: &Session, expected: usize) -> Result<()> {
    http::wait_until(http::PREDICATE_TIMEOUT, || async {
        let facts = reply_send_facts(session).await?;
        Ok(facts.total == expected && facts.final_bodies == 0)
    })
    .await
    .with_context(|| {
        format!("local-processing hints did not reach exactly {expected} before the next phase")
    })
}

fn body_has_complete_final(body: &serde_json::Value) -> bool {
    let rendered = body.to_string();
    rendered.contains(FINAL_MARKER) && rendered.contains("plan approval.")
}

fn is_user_input_question(item: &InteractionRequest, question_id: &str) -> bool {
    matches!(&item.content, InteractionContent::UserInput(value)
        if value.questions().iter().any(|question| question.id == question_id))
}

impl ThreadWatch {
    /// Waits for one pending user-input question by question id.
    async fn interaction(
        &mut self,
        budget: std::time::Duration,
        question_id: &'static str,
    ) -> Result<InteractionRequest> {
        self.wait_interaction(
            budget,
            |item| {
                is_user_input_question(item, question_id)
                    && item.status() == InteractionStatus::Pending
            },
            "first question after the inbound prompt",
        )
        .await
    }
}

pub(crate) fn interaction_restart_model_steps() -> Vec<Step> {
    let continuation = answers_json(&[(Q1_ID, Q1_ANSWER)]);
    vec![
        optional_title_step(0, PROMPT),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT,
            1,
            Reply::Sse(responses_tool_calls(
                "bots-restart-q1",
                "fixture-model",
                &[RealtimeToolCall {
                    item_id: "bots-restart-q1-item",
                    call_id: "bots-restart-q1-call",
                    name: "request_user_input",
                    arguments: q1_arguments(),
                }],
            )),
        ),
        optional_title_step(2, &continuation),
        Step::prompt(
            Protocol::ResponsesHttp,
            continuation,
            3,
            Reply::Sse(responses_tool_calls(
                "bots-restart-plan",
                "fixture-model",
                &[RealtimeToolCall {
                    item_id: "bots-restart-plan-item",
                    call_id: "bots-restart-plan-call",
                    name: "plan_submit",
                    arguments: serde_json::json!({
                        "expectedRevision": 0,
                        "plan": PLAN_MD,
                    })
                    .to_string(),
                }],
            )),
        ),
        optional_title_step(4, PLAN_MD),
        Step::prompt(
            Protocol::ResponsesHttp,
            PLAN_MD,
            5,
            Reply::Sse(responses_text(
                FINAL_TEXT,
                "bots-restart-final",
                "fixture-model",
            )),
        ),
    ]
}

fn q1_arguments() -> String {
    serde_json::json!({
        "questions": [
            {
                "id": Q1_ID,
                "header": "Wording",
                "question": "Which receipt wording should the final reply use?",
                "isOther": true,
                "isSecret": false,
                "options": [
                    {
                        "label": Q1_ANSWER,
                        "description": "Only status, count, and the answer, folded by default.",
                    }
                ]
            }
        ]
    })
    .to_string()
}
