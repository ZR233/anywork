use super::super::{Session, replies};
use super::{delivery, input, requests, send_text, wait_idle, write_json};
use crate::{
    http, sqlite,
    thread_watch::{ThreadWatch, interaction_line},
};
use anyhow::{Context, Result, ensure};
use pl_protocol::{
    InteractionContent, InteractionResolution, InteractionStatus, UserInputAnswer,
    UserInputResolution,
    studio::{BotSendStage, BotSendStatus, ResolveInteractionRequest, SetBotTrustedUserRequest},
};
use pl_provider_fixture::{
    bots_observe as model,
    feishu::{DIRECT_CHAT_ID, MessageContentObservation, TRUSTED_USER_OPEN_ID},
};
use std::{collections::HashMap, path::PathBuf};

pub(super) async fn run(session: &mut Session, evidence: &mut Vec<String>) -> Result<String> {
    let (bot_id, _) = session.ensure_trusted_direct().await?;
    session.wait_connected(&bot_id).await?;
    ensure!(
        !session.bot(&bot_id).await?.tools_enabled,
        "case must retain toolsEnabled=false"
    );
    send_text(session, "om_source_write", model::SOURCE_WRITE).await?;
    session
        .wait_inbound_completed(&bot_id, "om_source_write")
        .await?;
    let thread_id = replies::wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;
    wait_idle(session, &thread_id).await?;
    let workspace = PathBuf::from(session.bot(&bot_id).await?.workspace_path);
    ensure!(
        workspace == session.home.join("v2/bots").join(&bot_id).join("workspace"),
        "file source escaped its managed bot execution root"
    );
    let root_fact = format!("Current execution workspace root: {}.", workspace.display());
    ensure!(
        requests::execution_requests(session)
            .first()
            .map(requests::user_texts)
            .transpose()?
            .is_some_and(|texts| texts.iter().any(|text| text.contains(&root_fact))),
        "actual source-writing model request did not identify the public bot execution root"
    );
    let actual = std::fs::read(workspace.join(model::SOURCE_FILE))?;
    ensure!(
        actual == model::SOURCE_BYTES.as_bytes(),
        "model write_file did not write the exact original in the real workspace"
    );
    let facts = session.control()?.snapshot_report().await;
    let current = facts
        .message_sends
        .iter()
        .find(|send| matches!(&send.content, MessageContentObservation::File(_)))
        .context("current inbound file message missing")?;
    delivery::file_roundtrip(session, current, model::SOURCE_BYTES.as_bytes(), evidence).await?;
    let rows = sqlite::send_details(&session.home, &bot_id).await?;
    ensure!(
        rows.len() == 1,
        "blank Final after file delivery must not add a formal message"
    );
    delivery::verify_file_ledger(&rows[0], current, model::SOURCE_BYTES.as_bytes())?;
    let public = requests::send_result(session, "source-send-current").await?;
    delivery::public_segment(
        &public,
        0,
        BotSendStatus::Succeeded,
        Some(BotSendStage::Accepted),
        BotSendStage::Accepted,
        None,
    )?;
    ensure!(
        public.segments[0].platform_message_id.as_deref() == Some(current.message_id.as_str()),
        "public file result refers to another delivered message"
    );
    evidence.push(format!("toolsEnabled=false; model write_file -> submit_bot_file succeeded on current inbound; thread={thread_id}"));

    // Discover and resolve the canonical interaction over product HTTP/SSE. No
    // continuation ID or source grant is constructed by the observer.
    send_text(session, "om_source_question", model::SOURCE_QUESTION).await?;
    let question = pending_question(session, &thread_id).await?;
    evidence.push(format!(
        "canonical continuation {}",
        interaction_line(&question)
    ));
    resolve(session, &question.interaction_id, "source-resolve-public").await?;
    session
        .wait_inbound_completed(&bot_id, "om_source_question")
        .await?;
    wait_idle(session, &thread_id).await?;
    let facts = session.control()?.snapshot_report().await;
    let sends = facts
        .message_sends
        .iter()
        .filter(|send| matches!(&send.content, MessageContentObservation::File(_)))
        .collect::<Vec<_>>();
    ensure!(
        sends.len() == 2 && facts.uploads.len() == 2,
        "canonical continuation did not deliver exactly one additional file"
    );
    delivery::file_roundtrip(session, sends[1], model::SOURCE_BYTES.as_bytes(), evidence).await?;
    let continuation = requests::send_result(session, "source-send-continuation").await?;
    delivery::public_segment(
        &continuation,
        0,
        BotSendStatus::Succeeded,
        Some(BotSendStage::Accepted),
        BotSendStage::Accepted,
        None,
    )?;
    let baseline = (facts.uploads.len(), facts.message_sends.len());

    session
        .http()?
        .submit(&thread_id, input("source-local-input", model::SOURCE_LOCAL))
        .await?;
    let actual = requests::wait_output(session, "source-send-local").await?;
    wait_idle(session, &thread_id).await?;
    assert_no_external_posts(session, baseline).await?;
    ensure!(
        requests::tool_output(&actual, "source-send-local")?.contains("requires this Turn"),
        "ordinary local input borrowed the bot Thread's previous authority"
    );
    evidence.push("ordinary local input on the same bot-bound Thread: actual submit_bot_file rejection and zero additional upload/send POSTs".into());

    // This one is trusted inbound, but JSON cannot choose a different target.
    send_text(session, "om_source_target", model::SOURCE_TARGET).await?;
    session
        .wait_inbound_completed(&bot_id, "om_source_target")
        .await?;
    wait_idle(session, &thread_id).await?;
    // Its text Final is a legitimate formal reply; only uploads must stay fixed.
    let facts = session.control()?.snapshot_report().await;
    ensure!(
        facts.uploads.len() == baseline.0
            && facts
                .message_sends
                .iter()
                .all(|send| send.receive_id == DIRECT_CHAT_ID),
        "tool JSON selected a target or caused a file POST"
    );
    let target = requests::wait_output(session, "source-send-target").await?;
    ensure!(
        requests::tool_output(&target, "source-send-target")?.contains("unknown field"),
        "tool accepted a caller-provided chatId"
    );
    let empty = requests::wait_output(session, "source-send-empty").await?;
    ensure!(
        requests::tool_output(&empty, "source-send-empty")?.contains("empty files")
            && std::fs::metadata(workspace.join("empty-source.txt"))?.len() == 0,
        "real empty model-written file was not rejected before upload"
    );
    evidence.push("current authorized source wrote a real empty file, then submit_bot_file rejected it with no upload; target-selecting JSON also rejected".into());

    send_text(session, "om_source_steering", model::SOURCE_STEERING).await?;
    requests::wait_prompt(session, model::SOURCE_STEERING).await?;
    let running = session
        .http()?
        .thread(&thread_id)
        .await?
        .active_turn
        .context("stream barrier has no active Turn")?;
    let posts = session.control()?.snapshot_report().await;
    let posts = (posts.uploads.len(), posts.message_sends.len());
    session
        .http()?
        .submit(
            &thread_id,
            input("source-running-local", model::SOURCE_STEER_LOCAL),
        )
        .await?;
    let request = requests::wait_output(session, "source-send-steering").await?;
    wait_idle(session, &thread_id).await?;
    assert_no_external_posts(session, posts).await?;
    ensure!(
        requests::tool_output(&request, "source-send-steering")?.contains("requires this Turn"),
        "input submitted during bot execution borrowed its authority"
    );
    evidence.push(format!("local public prompt interrupted running Turn {} and its actual file call was denied; public prompt is fresh-Turn continuation, NOT proof of same-Turn steering", running.id));

    send_text(session, "om_source_revoked", model::SOURCE_REVOKED).await?;
    let revoked = pending_question(session, &thread_id).await?;
    let bot = session.bot(&bot_id).await?;
    session
        .http()?
        .set_trusted_user(&SetBotTrustedUserRequest {
            operation_id: "source-revoke-original-user".into(),
            bot_id: bot_id.clone(),
            expected_config_revision: bot.config_revision,
            open_id: TRUSTED_USER_OPEN_ID.into(),
            trusted: false,
        })
        .await?;
    let facts = session.control()?.snapshot_report().await;
    let baseline = (facts.uploads.len(), facts.message_sends.len());
    resolve(
        session,
        &revoked.interaction_id,
        "source-resolve-after-revocation",
    )
    .await?;
    let actual = requests::wait_output(session, "source-send-revoked").await?;
    wait_idle(session, &thread_id).await?;
    assert_no_external_posts(session, baseline).await?;
    ensure!(
        requests::tool_output(&actual, "source-send-revoked")?.contains("revoked"),
        "revoked trust remained a usable current-source grant"
    );
    evidence.push("public trust revocation before canonical interaction resolution: continuation still executed locally but file delivery was denied before every platform POST".into());
    let ledgers = sqlite::send_details(&session.home, &bot_id).await?;
    write_json(
        session,
        "source-file-ledgers.json",
        &ledgers
            .iter()
            .map(|row| {
                (
                    &row.operation_id,
                    &row.status,
                    &row.platform_message_ids,
                    &row.segment_facts,
                )
            })
            .collect::<Vec<_>>(),
    )?;
    Ok("actual model write_file/submit_bot_file delivered exact bytes from current trusted inbound and canonical public interaction continuation with toolsEnabled=false; ordinary/running-turn local input, caller-selected target and revoked source were rejected without unauthorized upload/send effects (same-Turn steering remains separately unproven)".into())
}

async fn pending_question(
    session: &Session,
    thread_id: &str,
) -> Result<pl_protocol::InteractionRequest> {
    let mut watch = ThreadWatch::connect(session.http()?.origin(), thread_id).await?;
    watch.wait_snapshot(http::PREDICATE_TIMEOUT).await?;
    watch.wait_interaction(http::PREDICATE_TIMEOUT, |interaction| interaction.status() == InteractionStatus::Pending && matches!(&interaction.content, InteractionContent::UserInput(input) if input.questions().iter().any(|question| question.id == model::QUESTION_ID)), "file source canonical pending question").await
}

async fn resolve(session: &Session, interaction_id: &str, operation: &str) -> Result<()> {
    session
        .http()?
        .resolve_interaction(
            interaction_id,
            &ResolveInteractionRequest {
                operation_id: operation.into(),
                resolution: InteractionResolution::UserInput(UserInputResolution {
                    answers: HashMap::from([(
                        model::QUESTION_ID.into(),
                        UserInputAnswer {
                            answers: vec![model::QUESTION_ANSWER.into()],
                        },
                    )]),
                }),
            },
        )
        .await
}

async fn assert_no_external_posts(session: &Session, before: (usize, usize)) -> Result<()> {
    let facts = session.control()?.snapshot_report().await;
    ensure!(
        (facts.uploads.len(), facts.message_sends.len()) == before,
        "rejected source changed platform upload/send counters: {before:?} -> {:?}",
        (facts.uploads.len(), facts.message_sends.len())
    );
    Ok(())
}
