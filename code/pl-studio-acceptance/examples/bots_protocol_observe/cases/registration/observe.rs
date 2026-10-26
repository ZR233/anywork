//! Shared bounded observation helpers for registration cases.

use super::super::Session;
use crate::http;
use crate::report::CaseResult;
use crate::topic::{self, BotsTopicWatch};
use anyhow::{Context, Result, anyhow, bail, ensure};
use pl_protocol::studio::{
    BotConnectionState, BotCredentialAvailability, BotCredentialOperation, BotRegistrationAttempt,
    BotRegistrationStatus, BotsCommandReply, BotsStateSnapshot, CancelBotRegistrationRequest,
    StartBotRegistrationRequest, StudioError,
};
use pl_provider_fixture::feishu::{CallKind, PollObservation, REGISTERED_APP_ID};
use reqwest::Url;
use std::time::{Duration, Instant};

pub(super) const LIFECYCLE_BUDGET: Duration = Duration::from_secs(180);
pub(super) const NO_USER_BUDGET: Duration = Duration::from_secs(75);
pub(super) const SLOWDOWN_EARLY: Duration = Duration::from_millis(250);
pub(super) const POSITIVE_NONCE: &str = "anyworkObserveNonceA1b2";
pub(super) const POSITIVE_PATH: &str = "/observe-verify";

pub(super) async fn start_ok(
    session: &Session,
    operation_id: &str,
    name: &str,
    project_id: &str,
    budget: Duration,
) -> Result<BotsCommandReply> {
    match start_result(session, operation_id, name, project_id, budget).await? {
        Ok(reply) => {
            ensure!(reply.receipt.operation_id == operation_id);
            ensure!(!reply.receipt.durable);
            Ok(reply)
        }
        Err(error) => Err(anyhow!(
            "start {operation_id} failed as {:?} without raw body",
            error.code
        )),
    }
}

pub(super) async fn start_result(
    session: &Session,
    operation_id: &str,
    name: &str,
    project_id: &str,
    budget: Duration,
) -> Result<std::result::Result<BotsCommandReply, StudioError>> {
    let http = session.http()?.clone();
    let request = StartBotRegistrationRequest {
        operation_id: operation_id.to_owned(),
        name: name.to_owned(),
        project_id: project_id.to_owned(),
    };
    tokio::time::timeout(budget, http.start_registration_result(&request))
        .await
        .map_err(|_| anyhow!("start {operation_id} timed out"))?
}

pub(super) async fn cancel_ok(
    session: &Session,
    operation_id: &str,
    attempt_id: &str,
    budget: Duration,
) -> Result<BotsCommandReply> {
    match cancel_result(session, operation_id, attempt_id, budget).await? {
        Ok(reply) => {
            ensure!(reply.receipt.operation_id == operation_id);
            ensure!(!reply.receipt.durable);
            Ok(reply)
        }
        Err(error) => Err(anyhow!(
            "cancel {operation_id} failed as {:?} without raw body",
            error.code
        )),
    }
}

pub(super) async fn cancel_result(
    session: &Session,
    operation_id: &str,
    attempt_id: &str,
    budget: Duration,
) -> Result<std::result::Result<BotsCommandReply, StudioError>> {
    let http = session.http()?.clone();
    let request = CancelBotRegistrationRequest {
        operation_id: operation_id.to_owned(),
        attempt_id: attempt_id.to_owned(),
    };
    tokio::time::timeout(budget, http.cancel_registration_result(&request))
        .await
        .map_err(|_| anyhow!("cancel {operation_id} timed out"))?
}

pub(super) async fn wait_status(
    watch: &mut BotsTopicWatch,
    budget: Duration,
    predicate: impl Fn(&BotRegistrationAttempt) -> bool,
    phase: &'static str,
) -> Result<BotRegistrationAttempt> {
    let snapshot = watch
        .wait_snapshot(
            phase_budget(budget),
            |snapshot| snapshot.registration.as_ref().is_some_and(&predicate),
            phase,
        )
        .await?;
    snapshot
        .registration
        .context("registration snapshot missing after predicate")
}

pub(super) async fn wait_connected_event(
    watch: &mut BotsTopicWatch,
    bot_id: &str,
    budget: Duration,
) -> Result<()> {
    watch
        .wait_bot(
            bot_id,
            phase_budget(budget),
            |bot| matches!(bot.connection, BotConnectionState::Connected),
            "connected",
        )
        .await?;
    Ok(())
}

pub(super) async fn current_status(session: &Session) -> Result<Option<BotRegistrationStatus>> {
    Ok(session
        .http()?
        .read_bots()
        .await?
        .registration
        .map(|attempt| attempt.status))
}

pub(super) async fn assert_no_bot(session: &Session) -> Result<()> {
    let snapshot = session.http()?.read_bots().await?;
    ensure!(
        snapshot.bots.is_empty(),
        "registration path must not publish a bot yet"
    );
    ensure!(
        snapshot
            .pending_credential_operations
            .iter()
            .all(|pending| {
                !matches!(
                    pending.credential_operation,
                    BotCredentialOperation::Preparing { .. }
                        | BotCredentialOperation::CommitUncertain { .. }
                )
            }),
        "registration path must not leave credential pending"
    );
    Ok(())
}

pub(super) async fn assert_no_side_effects(session: &Session, kind: CallKind) -> Result<()> {
    let report = session.control()?.snapshot_report().await;
    ensure!(
        report
            .calls
            .iter()
            .all(|call| call.kind != Some(kind) || !call.accepted),
        "{kind:?} must not run during this registration stage"
    );
    Ok(())
}

pub(super) async fn begin_count(session: &Session) -> Result<usize> {
    let report = session.control()?.snapshot_report().await;
    Ok(report
        .calls
        .iter()
        .filter(|call| call.kind == Some(CallKind::RegistrationBegin) && call.accepted)
        .count())
}

pub(super) async fn poll_observations(session: &Session) -> Result<Vec<PollObservation>> {
    Ok(session.control()?.snapshot_report().await.polls)
}

pub(super) fn poll_deltas(polls: &[PollObservation]) -> Result<Vec<Duration>> {
    let mut deltas = Vec::new();
    for window in polls.windows(2) {
        let earlier = window[0].unix_millis;
        let later = window[1].unix_millis;
        if later < earlier {
            bail!("peer unix_millis jumped backward; environment/clock precision, not product");
        }
        deltas.push(Duration::from_millis(later - earlier));
    }
    Ok(deltas)
}

pub(super) fn ensure_attempt(
    snapshot: &BotsStateSnapshot,
    attempt_id: &str,
    predicate: impl Fn(&BotRegistrationAttempt) -> bool,
    message: &str,
) -> Result<()> {
    let attempt = snapshot
        .registration
        .as_ref()
        .context("registration snapshot missing")?;
    ensure!(attempt.attempt_id == attempt_id, "{message}");
    ensure!(predicate(attempt), "{message}");
    Ok(())
}

/// 命令回执只携带该命令精确针对的 registration attempt（不是聚合快照）。
pub(super) fn ensure_reply_attempt(
    registration: Option<&BotRegistrationAttempt>,
    attempt_id: &str,
    predicate: impl Fn(&BotRegistrationAttempt) -> bool,
    message: &str,
) -> Result<()> {
    let attempt = registration.context("command reply registration missing")?;
    ensure!(attempt.attempt_id == attempt_id, "{message}");
    ensure!(predicate(attempt), "{message}");
    Ok(())
}

pub(super) fn ensure_committing_then_completed(
    committing: &BotRegistrationAttempt,
    completed: &BotRegistrationAttempt,
    bot_id: &str,
) -> Result<()> {
    match &committing.status {
        BotRegistrationStatus::Committing {
            attempt_id,
            bot_id: inner,
        } => {
            ensure!(attempt_id == &committing.attempt_id);
            ensure!(inner == bot_id);
            ensure!(committing.completed_bot_id.is_none());
        }
        other => bail!(
            "expected Committing, got {}",
            topic::registration_kind(other)
        ),
    }
    match &completed.status {
        BotRegistrationStatus::Completed { attempt_id } => {
            ensure!(attempt_id == &completed.attempt_id);
            ensure!(completed.completed_bot_id.as_deref() == Some(bot_id));
        }
        other => bail!(
            "expected Completed, got {}",
            topic::registration_kind(other)
        ),
    }
    Ok(())
}

pub(super) fn waiting_url(status: &BotRegistrationStatus) -> Option<&str> {
    match status {
        BotRegistrationStatus::Waiting {
            verification_url, ..
        }
        | BotRegistrationStatus::SlowDown {
            verification_url, ..
        } => Some(verification_url.as_str()),
        _ => None,
    }
}

pub(super) fn assert_positive_url(raw: &str, origin: &str, nonce: &str) -> Result<()> {
    let url = parse_http_url(raw)?;
    let expected = parse_http_url(origin)?;
    ensure!(
        same_origin(&url, &expected),
        "positive verification URL origin/path policy failed"
    );
    ensure!(
        url.path() == POSITIVE_PATH,
        "positive verification URL origin/path policy failed"
    );
    ensure!(
        url.username().is_empty() && url.password().is_none() && url.fragment().is_none(),
        "positive verification URL origin/path policy failed"
    );
    ensure!(
        query_value(&url, "user_code").as_deref() == Some("ANYWORK")
            && query_value(&url, "nonce").as_deref() == Some(nonce)
            && query_value(&url, "from").as_deref() == Some("sdk")
            && query_value(&url, "source").as_deref() == Some("anywork")
            && query_value(&url, "tp").as_deref() == Some("sdk")
            && query_value(&url, "createOnly").as_deref() == Some("true")
            && query_value(&url, "addons").is_some(),
        "positive verification URL query policy failed"
    );
    Ok(())
}

pub(super) fn addons_encoding(raw: &str) -> Result<String> {
    query_value(&parse_http_url(raw)?, "addons").context("missing addons")
}

pub(super) fn loopback_port(origin: &str) -> Result<u16> {
    parse_http_url(origin)?
        .port()
        .context("peer origin missing port")
}

pub(super) fn classify_command(result: Result<&BotsCommandReply, &StudioError>) -> String {
    match result {
        Ok(reply) => format!("ok disposition={:?}", reply.receipt.disposition),
        Err(error) => format!("error {:?}", error.code),
    }
}

pub(super) fn remaining(deadline: Instant) -> Result<Duration> {
    let left = deadline.saturating_duration_since(Instant::now());
    ensure!(!left.is_zero(), "registration observe budget exhausted");
    Ok(left)
}

pub(super) fn phase_budget(remaining: Duration) -> Duration {
    remaining.min(http::PREDICATE_TIMEOUT)
}

pub(super) async fn run_within_deadline<Fut>(
    deadline: Instant,
    name: &'static str,
    work: Fut,
) -> Result<CaseResult>
where
    Fut: std::future::Future<Output = Result<CaseResult>>,
{
    match tokio::time::timeout(remaining(deadline)?, work).await {
        Ok(result) => result,
        Err(_) => Err(anyhow!("{name} exceeded its absolute observe budget")),
    }
}

pub(super) async fn wait_until<F, Fut>(timeout: Duration, predicate: F) -> Result<()>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<bool>>,
{
    http::wait_until(timeout, predicate).await
}

pub(super) fn status_interval(attempt: &BotRegistrationAttempt) -> Option<u32> {
    match attempt.status {
        BotRegistrationStatus::Waiting {
            interval_seconds, ..
        }
        | BotRegistrationStatus::SlowDown {
            interval_seconds, ..
        } => Some(interval_seconds),
        _ => None,
    }
}

pub(super) fn ensure_usable_credential(availability: BotCredentialAvailability) -> Result<()> {
    match availability {
        BotCredentialAvailability::Stored | BotCredentialAvailability::SessionOnly => Ok(()),
        BotCredentialAvailability::Missing => bail!("credential Missing"),
        BotCredentialAvailability::Unavailable => bail!("credential Unavailable"),
    }
}

pub(super) fn ensure_registered_app(app_id: &str) -> Result<()> {
    ensure!(app_id == REGISTERED_APP_ID);
    Ok(())
}

fn parse_http_url(raw: &str) -> Result<Url> {
    Url::parse(raw).map_err(|_| anyhow!("verification URL was not a valid HTTP URL"))
}

fn same_origin(left: &Url, right: &Url) -> bool {
    left.scheme() == right.scheme()
        && left.host_str() == right.host_str()
        && left.port_or_known_default() == right.port_or_known_default()
}

fn query_value(url: &Url, key: &str) -> Option<String> {
    url.query_pairs()
        .find(|(name, _)| name == key)
        .map(|(_, value)| value.into_owned())
}

pub(super) fn begin_options(
    verification_url: Option<String>,
    interval_seconds: u32,
    expires_in_seconds: u32,
) -> pl_provider_fixture::feishu::RegistrationBeginOptions {
    pl_provider_fixture::feishu::RegistrationBeginOptions {
        verification_url,
        interval_seconds,
        expires_in_seconds,
    }
}
