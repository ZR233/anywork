use super::super::{Session, replies};
use super::{delivery, requests, send_text, write_json};
use crate::{http, sqlite};
use anyhow::{Context, Result, ensure};
use pl_protocol::studio::{BotSendStage, BotSendStatus, SendBotMessageRequest};
use pl_provider_fixture::{
    bots_observe as model,
    feishu::{DIRECT_CHAT_ID, MessageContentObservation, PostElement, SendDisposition},
};

pub(super) async fn run(session: &mut Session, evidence: &mut Vec<String>) -> Result<String> {
    let (bot_id, _) = session.ensure_trusted_direct().await?;
    session.wait_connected(&bot_id).await?;
    send_text(session, "om_markdown_small", model::MARKDOWN_SMALL_PROMPT).await?;
    session
        .wait_inbound_completed(&bot_id, "om_markdown_small")
        .await?;
    let facts = session.control()?.snapshot_report().await;
    ensure!(
        facts.message_sends.len() == 1 && facts.uploads.is_empty(),
        "small Markdown must be one post, not a file or split messages"
    );
    let post = &facts.message_sends[0];
    let post_message_id = delivery::stored_message_id(post)?;
    let MessageContentObservation::Post(content) = &post.content else {
        anyhow::bail!("small Markdown was flattened to text");
    };
    ensure!(
        content.zh_cn.content
            == vec![vec![PostElement::Markdown {
                text: model::MARKDOWN_SMALL.into()
            }]],
        "title/code/table/list/link Markdown original was rewritten"
    );
    ensure!(
        post.request_body_bytes <= 30_000
            && post.receive_id == DIRECT_CHAT_ID
            && post.uuid.as_ref().is_some_and(|uuid| !uuid.is_empty()),
        "small post full encoded JSON or target/UUID is invalid"
    );
    evidence.push(format!("small post complete original, full HTTP JSON={} bytes including escape/target/uuid; message={} uuid={:?}", post.request_body_bytes, post_message_id, post.uuid));
    let small_ledger = sqlite::send_details(&session.home, &bot_id).await?;
    ensure!(
        small_ledger.len() == 1,
        "small post has extra ledger operations"
    );
    let segments = delivery::segments(&small_ledger[0])?;
    ensure!(
        matches!(segments[0].content.as_ref(), Some(delivery::Content::Markdown { text }) if text == model::MARKDOWN_SMALL),
        "small post durable original is not Markdown"
    );

    send_text(session, "om_markdown_long", model::MARKDOWN_LONG_PROMPT).await?;
    session
        .wait_inbound_completed(&bot_id, "om_markdown_long")
        .await?;
    requests::wait_executions(session, 2).await?;
    let long = model::long_markdown();
    let facts = session.control()?.snapshot_report().await;
    let file_sends = facts
        .message_sends
        .iter()
        .filter(|send| matches!(&send.content, MessageContentObservation::File(_)))
        .collect::<Vec<_>>();
    ensure!(
        file_sends.len() == 1 && facts.message_sends.len() == 3 && facts.uploads.len() == 1,
        "long Markdown must be one complete .md file plus one short notice, not truncation or arbitrary splits"
    );
    let file = file_sends[0];
    let file_message_id = delivery::stored_message_id(file)?;
    let MessageContentObservation::File(resource) = &file.content else {
        anyhow::bail!("selected Markdown transfer changed from file content");
    };
    ensure!(
        resource.file_name.ends_with(".md"),
        "long Markdown has no downloadable .md extension"
    );
    delivery::file_roundtrip(session, file, long.as_bytes(), evidence).await?;
    let notice = facts
        .message_sends
        .iter()
        .filter(|send| send.call_index > file.call_index)
        .collect::<Vec<_>>();
    ensure!(
        notice.len() == 1
            && notice[0].request_body_bytes <= 30_000
            && matches!(&notice[0].content, MessageContentObservation::Post(_)),
        "long Markdown short notice is missing or precedes the file"
    );
    let hint = delivery::markdown_notice(notice[0], file)?;
    evidence.push(format!(
        "accepted complete .md download notice identifies actual file {:?}: {hint}",
        resource.file_name
    ));
    let rows = sqlite::send_details(&session.home, &bot_id).await?;
    let row = rows
        .iter()
        .find(|row| {
            delivery::segments(row).is_ok_and(|segments| {
                segments
                    .iter()
                    .any(|fact| fact.platform_message_id.as_deref() == Some(file_message_id))
            })
        })
        .context("long Markdown durable operation missing")?;
    delivery::verify_file_ledger(row, file, long.as_bytes())?;
    ensure!(
        delivery::segments(row)?.len() == 2,
        "long Markdown ledger must account for file and notice separately"
    );
    ensure!(
        long.ends_with("D2-long-tail-never-truncate\n"),
        "expected original lacks its complete tail"
    );

    // Same public operation + same intent must read its original ledger, while
    // an altered original is a conflict before upload/send. Includes JSON-heavy
    // input whose UTF-8 text fits, but complete encoded post JSON does not.
    let escaped = format!("# Escapes\n{}\nD2-escaped-tail", "\"\\\n".repeat(4_500));
    ensure!(
        escaped.len() < 30_000,
        "boundary stimulus must be below the raw-text ceiling"
    );
    let request = SendBotMessageRequest {
        operation_id: "op-markdown-escaped-boundary".into(),
        bot_id: bot_id.clone(),
        chat_id: DIRECT_CHAT_ID.into(),
        text: escaped.clone(),
    };
    let first = session.http()?.send_message(&request).await?;
    ensure!(
        first.status == BotSendStatus::Succeeded && first.segments.len() == 2,
        "full-JSON escape overhead did not select .md + notice"
    );
    delivery::public_segment(
        &first,
        0,
        BotSendStatus::Succeeded,
        Some(BotSendStage::Accepted),
        BotSendStage::Accepted,
        None,
    )?;
    delivery::public_segment(
        &first,
        1,
        BotSendStatus::Succeeded,
        None,
        BotSendStage::Accepted,
        None,
    )?;
    let before_replay = session.control()?.snapshot_report().await;
    let second = session.http()?.send_message(&request).await?;
    ensure!(
        second.status == first.status && second.segments == first.segments,
        "same-operation same-intent changed its delivery ledger"
    );
    let mut conflict = request.clone();
    conflict.text.push_str(" changed");
    ensure!(
        session
            .http()?
            .send_message_result(&conflict)
            .await?
            .is_err(),
        "same operation with different Markdown was not rejected"
    );
    let after_replay = session.control()?.snapshot_report().await;
    ensure!(
        before_replay.uploads.len() == after_replay.uploads.len()
            && before_replay.message_sends.len() == after_replay.message_sends.len(),
        "replay or conflict repeated a platform POST"
    );
    let escaped_send = before_replay
        .message_sends
        .iter()
        .rev()
        .find(|send| matches!(&send.content, MessageContentObservation::File(_)))
        .context("encoded-boundary .md send missing")?;
    delivery::file_roundtrip(session, escaped_send, escaped.as_bytes(), evidence).await?;
    let escaped_notice_id = first.segments[1]
        .platform_message_id
        .as_deref()
        .filter(|id| !id.is_empty())
        .context("accepted JSON-overhead notice has no platform identity")?;
    let escaped_notice = before_replay
        .message_sends
        .iter()
        .find(|send| send.message_id.as_deref() == Some(escaped_notice_id))
        .context("JSON-overhead short notice missing from its public message identity")?;
    ensure!(
        delivery::stored_message_id(escaped_notice)? == escaped_notice_id,
        "accepted JSON-overhead notice identity changed"
    );
    delivery::markdown_notice(escaped_notice, escaped_send)?;
    evidence.push(format!("raw escaped text {} bytes selected full .md transfer; same-operation replay and different-intent rejection added zero upload/send POSTs", escaped.len()));
    partial_restart(session, &bot_id, evidence).await?;
    let thread_id = replies::wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;
    super::wait_idle(session, &thread_id).await?;
    write_json(
        session,
        "markdown-send-ledgers.json",
        &sqlite::send_details(&session.home, &bot_id)
            .await?
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
    Ok("small Markdown was sent verbatim as post.md; long/JSON-escaped content used complete downloadable .md + short notice, independently downloaded with exact bytes and tail; real rejected-notice Partial survived restart without replay; ledger order and idempotent/conflicting public operation semantics were checked".into())
}

async fn partial_restart(
    session: &mut Session,
    bot_id: &str,
    evidence: &mut Vec<String>,
) -> Result<()> {
    let message_id = "om_markdown_partial";
    let operation_id = format!("botreply:{bot_id}:{DIRECT_CHAT_ID}:{message_id}");
    ensure!(
        sqlite::send_details(&session.home, bot_id)
            .await?
            .iter()
            .all(|row| row.operation_id != operation_id),
        "partial reply operation already existed before its input: {operation_id}"
    );
    // The whole original is confirmed before rejecting only its short notice.
    session
        .control()?
        .set_send_script(vec![
            SendDisposition::Succeed,
            SendDisposition::Reject {
                code: 230_020,
                msg: "notice rejected after complete .md delivery".into(),
            },
        ])
        .await;
    send_text(session, message_id, model::MARKDOWN_PARTIAL_PROMPT).await?;
    let partial = partial_terminal_record(session, bot_id, message_id, &operation_id).await?;
    requests::wait_executions(session, 3).await?;
    let segments = delivery::segments(&partial)?;
    ensure!(
        segments.len() == 2
            && segments[0].status == "succeeded"
            && segments[1].status == "rejected",
        "partial original/notice stages were lost"
    );
    let facts = session.control()?.snapshot_report().await;
    let file_message_id = segments[0]
        .platform_message_id
        .as_deref()
        .context("partial confirmed file has no platform identity")?;
    let file = facts
        .message_sends
        .iter()
        .find(|send| {
            send.message_id.as_deref() == Some(file_message_id)
                && send.uuid.as_deref() == Some(&segments[0].uuid)
        })
        .context("partial confirmed file identity missing")?;
    let stored_file_id = delivery::stored_message_id(file)?;
    delivery::file_roundtrip(session, file, model::long_markdown().as_bytes(), evidence).await?;
    ensure!(
        facts
            .message_sends
            .iter()
            .any(|send| send.uuid.as_deref() == Some(&segments[1].uuid)),
        "rejected notice was never actually posted"
    );
    let notice = facts
        .message_sends
        .iter()
        .find(|send| send.uuid.as_deref() == Some(&segments[1].uuid))
        .context("partial rejected notice body missing")?;
    let hint = delivery::markdown_notice(notice, file)?;
    evidence.push(format!("rejected short notice still names the accepted complete .md file and download semantics: {hint}"));
    let public = session
        .http()?
        .send_message(&SendBotMessageRequest {
            operation_id: partial.operation_id.clone(),
            bot_id: bot_id.into(),
            chat_id: DIRECT_CHAT_ID.into(),
            text: model::long_markdown(),
        })
        .await?;
    ensure!(
        public.operation_id == operation_id
            && public.bot_id == bot_id
            && public.chat_id == DIRECT_CHAT_ID
            && public.status == BotSendStatus::Partial
            && public.segments.len() == 2,
        "public replay did not preserve the file/notice partial result"
    );
    delivery::public_segment(
        &public,
        0,
        BotSendStatus::Succeeded,
        Some(BotSendStage::Accepted),
        BotSendStage::Accepted,
        None,
    )?;
    delivery::public_segment(
        &public,
        1,
        BotSendStatus::Rejected,
        None,
        BotSendStage::Rejected,
        None,
    )?;
    ensure!(
        public.segments[1]
            .diagnostic
            .as_ref()
            .is_some_and(|diagnostic| diagnostic.platform_code.as_deref() == Some("230020")),
        "exact partial notice lost its real platform rejection code"
    );
    write_json(session, "markdown-partial-public.json", &public)?;
    write_json(
        session,
        "markdown-partial-terminal.json",
        &serde_json::json!({
            "operationId": partial.operation_id, "status": partial.status,
            "platformMessageIds": partial.platform_message_ids, "segmentFacts": partial.segment_facts,
            "fileMessageId": stored_file_id, "fileUuid": segments[0].uuid, "noticeUuid": segments[1].uuid,
            "inboundMessageId": message_id, "inboundStatus": "needs_attention",
        }),
    )?;
    evidence.push(format!("exact operation={operation_id} reached durable file Accepted + notice Rejected(code230020) and inbound needs_attention; bound file message={} uuid={:?}; aggregate Partial alone was not used as completion", stored_file_id, file.uuid));
    let before = (
        facts.uploads.len(),
        facts.message_sends.len(),
        session.model_executions(),
    );
    let mut rows = sqlite::send_details(&session.home, bot_id).await?;
    ensure!(
        rows.iter().find(|row| row.operation_id == operation_id) == Some(&partial),
        "exact terminal partial record changed before restart"
    );
    rows.sort_by(|left, right| left.operation_id.cmp(&right.operation_id));
    let restart = session.restart_studio_server().await?;
    ensure!(
        restart.stopped_sigints == 1
            && restart.stopped_graceful
            && restart.stopped_exit_code == Some(0),
        "Markdown restart did not prove a single graceful stop: {restart}"
    );
    evidence.push(restart.to_string());
    session.wait_connected(bot_id).await?;
    let until = std::time::Instant::now() + std::time::Duration::from_secs(12);
    loop {
        let facts = session.control()?.snapshot_report().await;
        ensure!(
            (
                facts.uploads.len(),
                facts.message_sends.len(),
                session.model_executions()
            ) == before,
            "partial file/notice replayed after restart"
        );
        if std::time::Instant::now() >= until {
            break;
        }
        tokio::time::sleep(http::POLL).await;
    }
    let mut after = sqlite::send_details(&session.home, bot_id).await?;
    after.sort_by(|left, right| left.operation_id.cmp(&right.operation_id));
    ensure!(
        rows == after,
        "partial ledger identity changed after cold restart"
    );
    evidence.push("complete .md delivered then short notice rejected: durable partial survived real restart; 12s sampled interval added zero platform/model POSTs".into());
    Ok(())
}

async fn partial_terminal_record(
    session: &Session,
    bot_id: &str,
    message_id: &str,
    operation_id: &str,
) -> Result<sqlite::SendDetailRow> {
    let wait = async {
        loop {
            let rows = sqlite::send_details(&session.home, bot_id).await?;
            if let Some(row) = rows
                .into_iter()
                .find(|row| row.operation_id == operation_id)
            {
                let segments = delivery::segments(&row)?;
                ensure!(
                    segments.len() == 2 && segments[0].index == 0 && segments[1].index == 1,
                    "exact partial operation has an invalid segment plan: {operation_id}"
                );
                let file = &segments[0];
                let notice = &segments[1];
                ensure!(
                    file.stop_reason.is_none() && notice.stop_reason.is_none(),
                    "exact partial operation stopped locally: {segments:?}"
                );
                ensure!(
                    matches!(
                        &file.upload,
                        Some(
                            delivery::Upload::NotStarted
                                | delivery::Upload::InFlight
                                | delivery::Upload::Accepted { .. }
                        )
                    ) && notice.upload.is_none(),
                    "exact partial operation has a failed or missing upload phase: {segments:?}"
                );
                match file.message_stage.as_deref() {
                    Some("notStarted" | "inFlight") => ensure!(
                        file.status == "unknown" && row.status == "unknown",
                        "pending file stage contradicts its durable status: {row:?}"
                    ),
                    Some("accepted") => {
                        ensure!(
                            file.status == "succeeded"
                                && row.status == "partial"
                                && matches!(&file.upload, Some(delivery::Upload::Accepted { .. }))
                                && file
                                    .platform_message_id
                                    .as_deref()
                                    .is_some_and(|id| !id.is_empty()),
                            "accepted file lost its durable upload/message facts: {row:?}"
                        );
                        match notice.message_stage.as_deref() {
                            Some("notStarted" | "inFlight") => ensure!(
                                notice.status == "unknown",
                                "pending notice contradicts its durable status: {row:?}"
                            ),
                            Some("rejected") => {
                                ensure!(
                                    notice.status == "rejected",
                                    "rejected notice lost its durable status: {row:?}"
                                );
                                let inbound = sqlite::inbound(&session.home, bot_id).await?;
                                let input = inbound
                                    .iter()
                                    .find(|input| input.message_id == message_id)
                                    .context("exact partial reply input disappeared")?;
                                match input.status.as_str() {
                                    "needs_attention" => return Ok(row),
                                    "pending" | "claimed" | "failed" => {}
                                    "completed" => anyhow::bail!(
                                        "partial reply input was incorrectly completed: {input:?}"
                                    ),
                                    unknown => anyhow::bail!(
                                        "exact partial operation {operation_id} input {message_id} has an unknown status: {unknown:?}"
                                    ),
                                }
                            }
                            _ => anyhow::bail!(
                                "exact partial notice reached an unexpected or missing message outcome: {notice:?}"
                            ),
                        }
                    }
                    _ => anyhow::bail!(
                        "exact partial file reached an unexpected or missing message outcome: {file:?}"
                    ),
                }
            }
            // Poll observable progress only; IO/decode/wrong-outcome errors
            // above return immediately rather than being retried as pending.
            tokio::time::sleep(http::POLL).await;
        }
    };
    tokio::time::timeout(http::PREDICATE_TIMEOUT, wait)
        .await
        .with_context(|| {
            format!("exact partial operation {operation_id} did not settle within its budget")
        })?
        .with_context(|| format!("exact partial operation {operation_id} synchronization failed"))
}
