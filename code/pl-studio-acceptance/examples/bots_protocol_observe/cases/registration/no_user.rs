//! Isolated empty-trust registration. Completion without open_id must not
//! auto-admin the first inbound sender.

use super::super::Session;
use super::CASE_NO_USER;
use super::observe::{
    NO_USER_BUDGET, begin_options, ensure_committing_then_completed, ensure_registered_app,
    remaining, start_ok, wait_connected_event, wait_status,
};
use crate::http;
use crate::report::{self, CaseResult};
use crate::sqlite;
use crate::topic::BotsTopicWatch;
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::BotRegistrationStatus;
use pl_provider_fixture::feishu::{
    ChatType, DIRECT_CHAT_ID, RegistrationPollScript, SenderKind, UNKNOWN_USER_OPEN_ID, text_event,
};
use pl_studio_runtime::StudioThreadDirectoryPage;
use std::time::Instant;

const UNKNOWN_DM_ID: &str = "om_reg_nouser_unknown";
const UNKNOWN_DM_DUP_ID: &str = "om_reg_nouser_unknown_dup";

pub(super) async fn run(session: &mut Session) -> Result<CaseResult> {
    let deadline = Instant::now() + NO_USER_BUDGET;
    super::observe::run_within_deadline(deadline, CASE_NO_USER, run_inner(session, deadline)).await
}

async fn run_inner(session: &mut Session, deadline: Instant) -> Result<CaseResult> {
    let workspace_id = session
        .http()?
        .open_project(&session.project.to_string_lossy())
        .await?
        .id;
    let mut watch = BotsTopicWatch::connect(session.http()?.origin()).await?;
    watch
        .wait_snapshot_baseline(super::observe::phase_budget(remaining(deadline)?))
        .await
        .context("no-user baseline")?;
    session
        .control()?
        .set_registration_begin_options(begin_options(None, 1, 120))
        .await;
    session.control()?.set_registration_tenant_brand(None).await;
    session
        .control()?
        .set_registration_script(vec![RegistrationPollScript::Completed {
            include_open_id: false,
        }])
        .await;
    let started = start_ok(
        session,
        "op-reg-nouser",
        "observe-reg-nouser",
        &workspace_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!started.receipt.durable);
    let committing = wait_status(
        &mut watch,
        remaining(deadline)?,
        |attempt| match &attempt.status {
            BotRegistrationStatus::Committing { attempt_id, bot_id } => {
                attempt_id == &attempt.attempt_id
                    && !bot_id.is_empty()
                    && attempt.completed_bot_id.is_none()
            }
            _ => false,
        },
        "no-user committing",
    )
    .await?;
    let completed = wait_status(
        &mut watch,
        remaining(deadline)?,
        |attempt| {
            matches!(attempt.status, BotRegistrationStatus::Completed { .. })
                && attempt.completed_bot_id.is_some()
        },
        "no-user completed",
    )
    .await?;
    let bot_id = completed
        .completed_bot_id
        .clone()
        .context("no-user completedBotId")?;
    ensure_committing_then_completed(&committing, &completed, &bot_id)?;
    let snapshot = session.http()?.read_bots().await?;
    let bot = snapshot
        .bots
        .iter()
        .find(|bot| bot.id == bot_id)
        .context("no-user bot missing from GET /api/v1/bots")?;
    ensure_registered_app(&bot.app_id)?;
    ensure!(bot.trusted_open_ids.is_empty());
    match bot.credential {
        pl_protocol::studio::BotCredentialAvailability::Stored
        | pl_protocol::studio::BotCredentialAvailability::SessionOnly => {}
        pl_protocol::studio::BotCredentialAvailability::Missing => {
            bail!("no-user credential Missing")
        }
        pl_protocol::studio::BotCredentialAvailability::Unavailable => {
            bail!("no-user credential Unavailable")
        }
    }
    wait_connected_event(&mut watch, &bot_id, remaining(deadline)?).await?;
    let before_model = session.model_executions();
    let before_send = session.send_count().await?;
    let before_ack = session.ack_count().await?;
    let threads_before = list_all_thread_ids(session).await?;
    session
        .control()?
        .send_event(text_event(
            UNKNOWN_DM_ID,
            DIRECT_CHAT_ID,
            ChatType::P2p,
            SenderKind::User,
            UNKNOWN_USER_OPEN_ID,
            "unknown after empty trust",
            Vec::new(),
        ))
        .await?;
    session.wait_ack_count(before_ack + 1).await?;
    watch
        .wait_bot(
            &bot_id,
            remaining(deadline)?
                .min(http::ACK_BUDGET)
                .min(http::PREDICATE_TIMEOUT),
            |bot| {
                bot.pairing
                    .iter()
                    .any(|request| request.open_id == UNKNOWN_USER_OPEN_ID)
            },
            "no-user pairing",
        )
        .await
        .context("unknown DM pairing must arrive on bots topic SSE")?;
    session
        .control()?
        .send_event(text_event(
            UNKNOWN_DM_DUP_ID,
            DIRECT_CHAT_ID,
            ChatType::P2p,
            SenderKind::User,
            UNKNOWN_USER_OPEN_ID,
            "unknown after empty trust again",
            Vec::new(),
        ))
        .await?;
    session.wait_ack_count(before_ack + 2).await?;
    ensure!(
        session.model_executions() == before_model,
        "empty trusted list must not execute a model request"
    );
    ensure!(
        session.send_count().await? == before_send,
        "empty trusted list must not send a formal reply"
    );
    let threads_after = list_all_thread_ids(session).await?;
    ensure!(
        threads_after == threads_before,
        "unknown DM must not create a canonical Thread"
    );
    let bindings = sqlite::bindings(&session.home, &bot_id)
        .await
        .context("no-user thread_bindings read failed")?;
    ensure!(
        bindings.is_empty(),
        "no-user unknown DM must not bind a Thread"
    );
    let inbound = sqlite::inbound(&session.home, &bot_id)
        .await
        .context("no-user inbound_work read failed")?;
    ensure!(
        inbound.iter().all(|row| row.status != "completed"
            || (row.message_id != UNKNOWN_DM_ID && row.message_id != UNKNOWN_DM_DUP_ID)),
        "unknown DM must not complete inbound execution"
    );
    drop(watch);
    Ok(report::passed(
        CASE_NO_USER,
        format!(
            "Completed without open_id; trusted empty; ACK observed; model={} send={}",
            session.model_executions() - before_model,
            session.send_count().await? - before_send
        ),
    ))
}

async fn list_all_thread_ids(session: &Session) -> Result<Vec<String>> {
    let mut ids = Vec::new();
    let mut cursor = None;
    loop {
        let page: StudioThreadDirectoryPage = session
            .http()?
            .list_threads_page(cursor.as_deref(), 50)
            .await
            .context("GET /api/v1/threads failed")?;
        let data = page
            .state
            .value()
            .context("thread directory page had no canonical value")?;
        for thread in &data.threads {
            ids.push(thread.id.clone());
        }
        match &data.next_cursor {
            Some(next) => cursor = Some(next.clone()),
            None => break,
        }
        ensure!(
            ids.len() <= 200,
            "thread directory exceeded observe page budget"
        );
    }
    ids.sort();
    Ok(ids)
}
