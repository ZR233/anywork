use super::super::{Session, replies};
use super::{delivery, requests, send_text, wait_idle, write_json};
use crate::{http, sqlite};
use anyhow::{Context, Result, ensure};
use pl_protocol::studio::{BotSendStage, BotSendStatus, BotSendStopReason};
use pl_provider_fixture::{
    bots_observe as model,
    feishu::{
        DIRECT_CHAT_ID, MessageSendOutcome, SendDisposition,
        media::{UploadDisposition, UploadOutcome},
    },
};
use std::time::Duration;

/// Each run owns a fresh peer and three file operations; upload and message
/// faults never share a script queue or infer each other's phase from an ACK.
pub(super) async fn run(
    session: &mut Session,
    upload_faults: bool,
    evidence: &mut Vec<String>,
) -> Result<String> {
    let (bot_id, _) = session.ensure_trusted_direct().await?;
    session.wait_connected(&bot_id).await?;
    send_text(session, "om_fault_seed", model::SOURCE_WRITE).await?;
    session
        .wait_inbound_completed(&bot_id, "om_fault_seed")
        .await?;
    let thread_id = replies::wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;
    wait_idle(session, &thread_id).await?;
    let mut public_results = Vec::new();
    if upload_faults {
        session
            .control()?
            .set_upload_script(vec![
                UploadDisposition::Reject {
                    code: 234_007,
                    msg: "upload permission rejected by fixture".into(),
                },
                UploadDisposition::AcceptThenDrop,
                UploadDisposition::Hang,
            ])
            .await?;
    } else {
        session
            .control()?
            .set_send_script(vec![
                SendDisposition::Reject {
                    code: 230_020,
                    msg: "message rejected by fixture".into(),
                },
                SendDisposition::AcceptThenDrop,
                SendDisposition::Hang,
            ])
            .await;
    }
    for (index, prompt) in model::FAULT_PROMPTS.into_iter().enumerate() {
        let message_id = format!("om_fault_{index}");
        send_text(session, &message_id, prompt).await?;
        http::wait_until(http::PREDICATE_TIMEOUT, || async {
            let facts = session.control()?.snapshot_report().await;
            Ok(if upload_faults {
                facts.uploads.len() == index + 1
                    && matches!(
                        facts.uploads[index].outcome,
                        UploadOutcome::Rejected
                            | UploadOutcome::StoredResponseDropped
                            | UploadOutcome::Waiting
                    )
            } else {
                facts.message_sends.len() == index + 1
                    && matches!(
                        facts.message_sends[index].outcome,
                        MessageSendOutcome::Rejected
                            | MessageSendOutcome::StoredResponseDropped
                            | MessageSendOutcome::Waiting
                    )
            })
        })
        .await
        .with_context(|| {
            format!("fault stage {index} was not reached on the real platform request")
        })?;
        if index < 2 {
            wait_idle(session, &thread_id).await?;
            requests::wait_executions(session, 4 + index * 2).await?;
            let public = requests::send_result(session, &format!("fault-submit-{index}")).await?;
            ensure!(
                public.bot_id == bot_id
                    && public.chat_id == DIRECT_CHAT_ID
                    && public.segments.len() == 1,
                "public fault result changed its bot/chat/segment identity"
            );
            let status = if index == 0 {
                BotSendStatus::Rejected
            } else {
                BotSendStatus::Unknown
            };
            let stage = if index == 0 {
                BotSendStage::Rejected
            } else {
                BotSendStage::Unknown
            };
            ensure!(
                public.status == status,
                "public operation aggregate does not match its observed stage"
            );
            delivery::public_segment(
                &public,
                0,
                status,
                Some(if upload_faults {
                    stage
                } else {
                    BotSendStage::Accepted
                }),
                if upload_faults {
                    BotSendStage::NotStarted
                } else {
                    stage
                },
                None,
            )?;
            if index == 0 {
                let code = if upload_faults { "234007" } else { "230020" };
                ensure!(
                    public.segments[0]
                        .diagnostic
                        .as_ref()
                        .is_some_and(|diagnostic| diagnostic.platform_code.as_deref() == Some(code)),
                    "platform Rejected stage lost its actual platform diagnostic"
                );
            }
            evidence.push(format!(
                "public operation={} status={:?} upload={:?} message={:?} stop={:?}",
                public.operation_id,
                public.status,
                public.segments[0].upload_stage,
                public.segments[0].message_stage,
                public.segments[0].stop_reason
            ));
            public_results.push(public);
        } else {
            let turn = session
                .http()?
                .thread(&thread_id)
                .await?
                .active_turn
                .context("held network operation has no active Turn")?;
            let stopped = session.http()?.interrupt(&thread_id, &turn.id).await?;
            ensure!(
                stopped.interrupted && stopped.turn_id == turn.id,
                "public cancel did not interrupt the exact active Turn"
            );
            wait_idle(session, &thread_id).await?;
            evidence.push(format!(
                "held {} operation cancelled over public interrupt; Turn={}",
                if upload_faults { "upload" } else { "message" },
                turn.id
            ));
        }
        http::wait_until(http::PREDICATE_TIMEOUT, || async {
            let rows = sqlite::send_details(&session.home, &bot_id).await?;
            Ok(rows.len() == index + 1
                && rows
                    .iter()
                    .all(|row| row.status == "rejected" || row.status == "unknown")
                && (index < 2
                    || rows.iter().any(|row| {
                        delivery::segments(row).is_ok_and(|segments| {
                            segments.iter().any(|segment| {
                                segment.stop_reason == Some(BotSendStopReason::Cancelled)
                            })
                        })
                    })))
        })
        .await?;
    }
    let facts = session.control()?.snapshot_report().await;
    ensure!(
        facts.uploads.len() == 3 && facts.message_sends.len() == if upload_faults { 0 } else { 3 },
        "fault handling retried or skipped a platform POST"
    );
    for upload in &facts.uploads {
        ensure!(
            upload.byte_len == Some(model::SOURCE_BYTES.len())
                && upload.sha256.as_deref() == Some(&model::sha256(model::SOURCE_BYTES.as_bytes())),
            "file-fault upload did not carry exact model-written original bytes"
        );
    }
    let mut rows = sqlite::send_details(&session.home, &bot_id).await?;
    rows.sort_by(|left, right| left.operation_id.cmp(&right.operation_id));
    ensure!(
        rows.iter().filter(|row| row.status == "rejected").count() == 1
            && rows.iter().filter(|row| row.status == "unknown").count() == 2,
        "expected one rejected and two unknown operations: {rows:?}"
    );
    for row in &rows {
        let segments = delivery::segments(row)?;
        ensure!(
            segments.len() == 1 && row.platform_message_ids.is_empty(),
            "failed/unknown file operations must not claim a confirmed platform message"
        );
        let segment = &segments[0];
        ensure!(
            segment.status == row.status && segment.platform_message_id.is_none(),
            "segment disagrees with durable overall outcome"
        );
        if segment.stop_reason == Some(BotSendStopReason::Cancelled) {
            ensure!(
                row.status == "unknown" && segment.message_stage.as_deref() != Some("rejected"),
                "local cancellation was incorrectly classified as platform message rejection"
            );
            evidence.push(format!("local cancellation preserves unknown network result rather than platform Rejected: operation={} upload={:?} message={:?} stop={:?}; no public tool continuation exists after this interrupted call", row.operation_id, segment.upload, segment.message_stage, segment.stop_reason));
        }
        if upload_faults {
            ensure!(
                segment.message_stage.as_deref() == Some("notStarted"),
                "file message started without confirmed upload"
            );
            ensure!(
                matches!(
                    segment.upload,
                    Some(
                        delivery::Upload::Rejected
                            | delivery::Upload::Unknown
                            | delivery::Upload::InFlight
                    )
                ),
                "upload outcome did not preserve the exact failed/uncertain phase"
            );
        } else {
            let Some(delivery::Upload::Accepted { file_key }) = &segment.upload else {
                anyhow::bail!("message fault lost its successful upload key");
            };
            let send = facts
                .message_sends
                .iter()
                .find(|send| send.uuid.as_deref() == Some(&segment.uuid))
                .context("message-fault ledger UUID does not identify the real POST")?;
            let upload = facts
                .uploads
                .iter()
                .find(|upload| upload.file_key.as_deref() == Some(file_key))
                .context("accepted key missing from upload facts")?;
            ensure!(
                upload.call_index < send.call_index,
                "message POST preceded the accepted upload"
            );
            ensure!(
                matches!(
                    segment.message_stage.as_deref(),
                    Some("rejected" | "unknown" | "inFlight")
                ),
                "message fault phase was lost"
            );
        }
        evidence.push(format!(
            "durable operation={} status={} upload={:?} messageStage={:?} confirmedIds={}",
            row.operation_id,
            row.status,
            segment.upload,
            segment.message_stage,
            row.platform_message_ids
        ));
    }
    write_json(
        session,
        "fault-ledgers-before.json",
        &rows
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
    write_json(session, "public-file-outcomes.json", &public_results)?;
    let counts = (
        facts.uploads.len(),
        facts.message_sends.len(),
        session.model_executions(),
    );
    evidence.push(session.restart_studio_server().await?);
    session.wait_connected(&bot_id).await?;
    // Recovery has no public sweep-completed marker. Assert the invariant at
    // every sample of this explicitly reported finite quiet interval, rather
    // than sleeping and treating absence of an error as proof of recovery.
    let until = std::time::Instant::now() + Duration::from_secs(12);
    loop {
        let facts = session.control()?.snapshot_report().await;
        ensure!(
            (
                facts.uploads.len(),
                facts.message_sends.len(),
                session.model_executions()
            ) == counts,
            "cancel/restart reissued an upload, message POST or model request"
        );
        if std::time::Instant::now() >= until {
            break;
        }
        tokio::time::sleep(http::POLL).await;
    }
    let mut after = sqlite::send_details(&session.home, &bot_id).await?;
    after.sort_by(|left, right| left.operation_id.cmp(&right.operation_id));
    ensure!(
        after == rows,
        "cold restart rewrote or lost unknown/rejected typed ledger identities"
    );
    write_json(
        session,
        "fault-ledgers-after.json",
        &after
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
    evidence.push("12-second sampled restart quiet interval: no extra upload/send/model requests; precise recovery-sweep/claim boundary remains unproven".into());
    Ok(format!(
        "real {} Reject, AcceptThenDrop and Hang/cancel produced phase-correct rejected/unknown durable facts; file messages never preceded accepted uploads; a real same-home server restart preserved those facts without automatic POST/model replay",
        if upload_faults {
            "upload"
        } else {
            "file-message"
        }
    ))
}
