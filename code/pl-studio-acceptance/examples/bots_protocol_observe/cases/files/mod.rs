//! Explicit, session-exclusive product journeys. The model and Feishu peers
//! supply wire stimuli; only public Studio results and independent bytes/DB
//! observations decide each case. Not a CI test suite or a tenant/GUI verdict.

mod admission_limits;
mod compaction;
mod compaction_owner;
mod compaction_timeout;
pub(in crate::cases) mod delivery;
mod ingress;
mod isolation;
mod markdown;
mod notice;
mod outcomes;
mod requests;
mod source;
mod uploads;

use super::Session;
use crate::{
    env, http,
    report::{self, CaseResult},
};
use anyhow::{Context, Result, ensure};
pub(super) use compaction_owner::CompactionOwner;
use pl_protocol::studio::{BotModelRoute, BotSecretUpdate, SaveBotRequest, StudioPromptInput};
use pl_provider_fixture::{Step, bots_observe as model};
use serde::Serialize;
use std::time::Duration;
use tokio_util::sync::CancellationToken;

pub(super) const CASE_ISOLATION: &str = "chat-isolation";
pub(super) const CASE_INGRESS: &str = "chat-media-ingress";
pub(super) const CASE_SOURCE: &str = "public-artifact-source";
/// Historical policies remain compile-checked but are not runnable cases.
const STAGE_TWO_PENDING: &[&str] = &[
    "bot-markdown-transfer",
    "bot-upload-outcomes",
    "bot-file-send-outcomes",
];
pub(super) const CASE_COMPACTION: &str = "user-file-compaction";
pub(super) const CASE_COMPACTION_TIMEOUT: &str = "user-file-compaction-timeout";
pub(super) const CASE_ADMISSION_LIMITS: &str = "user-file-admission-limits";
pub(super) const CASES: &[&str] = &[
    CASE_ISOLATION,
    CASE_INGRESS,
    CASE_SOURCE,
    CASE_COMPACTION,
    CASE_COMPACTION_TIMEOUT,
    CASE_ADMISSION_LIMITS,
];

pub(super) fn reject_obsolete_policy(name: &str) -> Result<()> {
    // References keep the historical implementation and its independent
    // oracles type-checked. No future is created or polled, and no dispatch
    // table exposes either entry until its stage-two migration is reviewed.
    let _pending_implementations = (markdown::run, outcomes::run);
    ensure!(
        !STAGE_TWO_PENDING.contains(&name),
        "observe case {name} is stage-2 pending / obsolete policy; historical automatic Markdown-file/notice and file-tool journeys cannot run or supply current coverage"
    );
    Ok(())
}

pub(super) fn model_steps(name: &str) -> Vec<Step> {
    match name {
        CASE_ISOLATION => model::chat_isolation_script(),
        CASE_INGRESS => model::media_ingress_script(),
        CASE_SOURCE => source::model_steps(),
        CASE_COMPACTION => model::compaction_script(),
        CASE_COMPACTION_TIMEOUT => model::compaction_timeout_script(),
        _ => Vec::new(),
    }
}

pub(super) async fn run(session: &mut Session, name: &'static str) -> Result<CaseResult> {
    reject_obsolete_policy(name)?;
    let mut evidence = Vec::new();
    session
        .control()?
        .set_file_message_key_mode(
            pl_provider_fixture::feishu::media::FileMessageKeyMode::MessageScoped,
        )
        .await?;
    let probe_ready = CancellationToken::new();
    let deadline = async {
        if name == CASE_COMPACTION_TIMEOUT
            && tokio::time::timeout(Duration::from_secs(300), probe_ready.cancelled())
                .await
                .is_ok()
        {
            // This is the deliberately forced deadline under observation, not
            // a sleep used to infer that the provider reached a stage.
            tokio::time::sleep(Duration::from_millis(1)).await;
            true
        } else if name == CASE_COMPACTION_TIMEOUT {
            false
        } else {
            tokio::time::sleep(Duration::from_secs(300)).await;
            false
        }
    };
    let result = tokio::select! {
        result = async {
        match name {
            CASE_ISOLATION => isolation::run(session, &mut evidence).await,
            CASE_INGRESS => ingress::run(session, &mut evidence).await,
            CASE_SOURCE => source::run(session, &mut evidence).await,
            CASE_COMPACTION => compaction::run(session, &mut evidence).await,
            CASE_COMPACTION_TIMEOUT => compaction_timeout::run(session, &mut evidence, &probe_ready).await,
            CASE_ADMISSION_LIMITS => admission_limits::run(session, &mut evidence).await,
            _ => anyhow::bail!("unknown file observe case {name}"),
        }
        } => Ok(result),
        forced_probe = deadline => Err(forced_probe),
    };
    // The absolute timeout dropped only the borrowed case future. Session
    // still owns every runtime/task; close + join them before peer capture or
    // the outer runner can begin fixture/server cleanup.
    let cleanup = session.compaction_owner.close().await;
    write_json(
        session,
        "case-runtime-cleanup.json",
        &session.compaction_owner.evidence(),
    )?;
    // Preserve strict peer evidence even on a red phase. Fixture verification
    // still happens during Session shutdown; an unconsumed stage remains red.
    capture(session).await?;
    let mut report = match result {
        Ok(Ok(detail)) => report::passed(name, detail),
        Ok(Err(error)) => report::failed(name, format!("{error:#}")),
        Err(true)
            if cleanup.is_ok() && timeout_cleanup_proven(&session.compaction_owner.evidence()) =>
        {
            evidence.push("outer case future was dropped by its armed deadline; Session explicitly shut down the real runtime and joined the registered compact before any server/model/peer cleanup; no abort fallback".into());
            report::passed(
                name,
                "forced outer case timeout preserved runtime/task ownership and completed public shutdown + compact join before fixture cleanup",
            )
        }
        Err(_) => report::failed(
            name,
            "absolute observe budget exceeded or forced-timeout cleanup was not proven",
        ),
    };
    if let Err(error) = cleanup {
        report = report::failed(
            name,
            format!("{}; owned compact cleanup: {error:#}", report.detail),
        );
    }
    report.evidence = evidence;
    Ok(report)
}

fn timeout_cleanup_proven(cleanup: &compaction_owner::CleanupEvidence) -> bool {
    cleanup.runtime_closed
        && cleanup.compact_spawned
        && cleanup.compact_pending_before_shutdown
        && cleanup.compact_joined
        && !cleanup.compact_aborted
        && matches!(
            cleanup.compact_terminal.as_ref(),
            Some(compaction_owner::CompactTerminal::Failed { .. })
        )
}

async fn capture(session: &Session) -> Result<()> {
    if let Some(model) = session.model.as_ref() {
        write_json(session, "model-requests.json", &model.recorded())?;
        write_json(session, "model-status.json", &model.live_status())?;
    }
    write_json(
        session,
        "feishu-facts.json",
        &session.control()?.snapshot_report().await,
    )
}

pub(super) fn write_json(session: &Session, filename: &str, value: &impl Serialize) -> Result<()> {
    let text = serde_json::to_string_pretty(value)?;
    std::fs::write(session.output.join(filename), env::redact(&text))?;
    Ok(())
}

async fn route(session: &Session, bot_id: &str, model_id: &str, operation: &str) -> Result<()> {
    let bot = session.bot(bot_id).await?;
    let reply = session
        .http()?
        .save_bot(&SaveBotRequest {
            operation_id: operation.into(),
            bot_id: Some(bot.id),
            expected_config_revision: bot.config_revision,
            name: bot.name,
            project_id: bot.project_id,
            app_id: bot.app_id,
            secret: BotSecretUpdate::Preserve,
            enabled: bot.enabled,
            tools_enabled: bot.tools_enabled,
            model_route: Some(BotModelRoute {
                account_id: env::model_account_id(&session.home)?,
                model_id: model_id.into(),
                effort: None,
            }),
        })
        .await?;
    let updated = reply
        .snapshot
        .bots
        .iter()
        .find(|bot| bot.id == bot_id)
        .context("saved bot missing")?;
    ensure!(
        updated
            .model_route
            .as_ref()
            .is_some_and(|route| route.model_id == model_id),
        "bot model route did not change canonically"
    );
    session.wait_connected(bot_id).await
}

fn input(id: &str, prompt: &str) -> StudioPromptInput {
    StudioPromptInput {
        input_id: id.into(),
        text: prompt.into(),
        attachment_draft_ids: Vec::new(),
    }
}

async fn wait_idle(session: &Session, thread_id: &str) -> Result<()> {
    http::wait_until(http::PREDICATE_TIMEOUT, || async {
        Ok(session
            .http()?
            .thread(thread_id)
            .await?
            .active_turn
            .is_none())
    })
    .await
    .context("Thread did not return to idle")
}

async fn send_text(session: &Session, message_id: &str, prompt: &str) -> Result<()> {
    use pl_provider_fixture::feishu::{
        ChatType, DIRECT_CHAT_ID, SenderKind, TRUSTED_USER_OPEN_ID, text_event,
    };
    session
        .control()?
        .send_event(text_event(
            message_id,
            DIRECT_CHAT_ID,
            ChatType::P2p,
            SenderKind::User,
            TRUSTED_USER_OPEN_ID,
            prompt,
            Vec::new(),
        ))
        .await?;
    Ok(())
}
