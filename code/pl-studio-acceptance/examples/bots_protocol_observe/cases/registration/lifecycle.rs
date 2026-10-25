//! Sequential registration-lifecycle stages. Only the last success publishes a bot.

use super::super::Session;
use super::CASE_LIFECYCLE;
use super::observe::{
    LIFECYCLE_BUDGET, POSITIVE_NONCE, POSITIVE_PATH, SLOWDOWN_EARLY, addons_encoding,
    assert_no_bot, assert_no_side_effects, assert_positive_url, begin_count, begin_options,
    cancel_ok, cancel_result, classify_command, current_status, ensure_attempt,
    ensure_committing_then_completed, ensure_registered_app, ensure_reply_attempt,
    ensure_usable_credential, loopback_port, poll_deltas, poll_observations, remaining, start_ok,
    start_result, status_interval, wait_connected_event, wait_status, wait_until, waiting_url,
};
use crate::http;
use crate::report::{self, CaseResult};
use crate::topic::{self, BotsTopicWatch};
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::{
    BotRegistrationAttempt, BotRegistrationStatus, CommandDisposition, StartBotRegistrationRequest,
    StudioErrorCode,
};
use pl_provider_fixture::feishu::{
    CallKind, REGISTERED_APP_ID, RegistrationPollScript, RegistrationTenantBrand,
    TRUSTED_USER_OPEN_ID,
};
use std::time::Instant;

pub(super) async fn run(session: &mut Session) -> Result<CaseResult> {
    let deadline = Instant::now() + LIFECYCLE_BUDGET;
    super::observe::run_within_deadline(deadline, CASE_LIFECYCLE, run_inner(session, deadline))
        .await
}

async fn run_inner(session: &mut Session, deadline: Instant) -> Result<CaseResult> {
    let mut evidence = Vec::new();
    let project_id = session
        .http()?
        .open_project(&session.project.to_string_lossy())
        .await?
        .id;
    let mut watch = BotsTopicWatch::connect(session.http()?.origin()).await?;
    let baseline = watch
        .wait_snapshot_baseline(super::observe::phase_budget(remaining(deadline)?))
        .await
        .context("registration baseline before first start")?;
    ensure!(
        baseline.bots.is_empty() && baseline.registration.is_none(),
        "fresh registration runtime must start empty"
    );

    evidence.push(stage_reuse_and_replace(session, &mut watch, &project_id, deadline).await?);
    evidence.push(stage_begin_hang_cancel(session, &mut watch, &project_id, deadline).await?);
    evidence.push(stage_poll_hang_cancel(session, &mut watch, &project_id, deadline).await?);
    evidence.push(stage_expire_inflight_poll(session, &mut watch, &project_id, deadline).await?);
    evidence.push(stage_denied(session, &mut watch, &project_id, deadline).await?);
    evidence.push(stage_remote_expired(session, &mut watch, &project_id, deadline).await?);
    evidence.push(stage_slow_down(session, &mut watch, &project_id, deadline).await?);
    evidence.push(stage_url_policy(session, &mut watch, &project_id, deadline).await?);
    evidence.push(stage_lark_brand(session, &mut watch, &project_id, deadline).await?);
    evidence.push(stage_success_with_user(session, &mut watch, &project_id, deadline).await?);

    drop(watch);
    Ok(report::CaseResult {
        name: CASE_LIFECYCLE,
        verdict: report::Verdict::Passed,
        detail: "registration lifecycle observed through public HTTP/SSE".into(),
        evidence,
    })
}

async fn stage_reuse_and_replace(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    project_id: &str,
    deadline: Instant,
) -> Result<String> {
    let reuse_name = "observe-reg-reuse";
    let reuse_op = "op-reg-reuse";
    session
        .control()?
        .set_registration_begin_options(begin_options(None, 1, 120))
        .await;
    session
        .control()?
        .set_registration_script(vec![RegistrationPollScript::Pending])
        .await;
    let begin_before = begin_count(session).await?;
    let first = start_ok(
        session,
        reuse_op,
        reuse_name,
        project_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(
        !first.receipt.durable,
        "start receipt.durable must be false"
    );
    ensure!(first.receipt.operation_id == reuse_op);
    let waiting = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| matches!(attempt.status, BotRegistrationStatus::Waiting { .. }),
        "A waiting",
    )
    .await?;
    let first_attempt = waiting.attempt_id.clone();
    ensure!(
        begin_count(session).await? == begin_before + 1,
        "first Waiting must record exactly one RegistrationBegin"
    );
    let reused = start_ok(
        session,
        reuse_op,
        reuse_name,
        project_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!reused.receipt.durable);
    ensure!(
        reused
            .registration
            .as_ref()
            .is_some_and(|attempt| attempt.attempt_id == first_attempt),
        "same operationId/name/project must reuse the attempt"
    );
    ensure!(
        begin_count(session).await? == begin_before + 1,
        "reused start must not call platform begin again"
    );
    let conflict = start_result(
        session,
        reuse_op,
        "observe-reg-conflict",
        project_id,
        remaining(deadline)?,
    )
    .await?;
    match conflict {
        Err(error) if error.code == StudioErrorCode::Conflict => {}
        other => bail!(
            "changing name/project under the same operationId must be typed Conflict, got {}",
            classify_command(other.as_ref())
        ),
    }

    let replace_start = start_ok(
        session,
        "op-reg-replace",
        "observe-reg-replace",
        project_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!replace_start.receipt.durable);
    let replaced = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| {
            attempt.attempt_id != first_attempt
                && matches!(
                    attempt.status,
                    BotRegistrationStatus::Preparing { .. } | BotRegistrationStatus::Waiting { .. }
                )
        },
        "A replace preparing/waiting",
    )
    .await?;
    let second_attempt = replaced.attempt_id.clone();
    ensure!(second_attempt != first_attempt);
    if !matches!(replaced.status, BotRegistrationStatus::Waiting { .. }) {
        wait_status(
            watch,
            remaining(deadline)?,
            |attempt| {
                attempt.attempt_id == second_attempt
                    && matches!(attempt.status, BotRegistrationStatus::Waiting { .. })
            },
            "A replace waiting",
        )
        .await?;
    }
    ensure!(
        begin_count(session).await? == begin_before + 2,
        "replacement start must record a second RegistrationBegin"
    );
    let stale_cancel = cancel_result(
        session,
        "op-reg-cancel-stale",
        &first_attempt,
        remaining(deadline)?,
    )
    .await?;
    match stale_cancel {
        Ok(reply) => {
            ensure!(
                reply.receipt.disposition == CommandDisposition::NoChange,
                "stale cancel of a replaced attempt must be NoChange if accepted"
            );
            ensure_reply_attempt(
                reply.registration.as_ref(),
                &first_attempt,
                |attempt| {
                    matches!(
                        attempt.status,
                        BotRegistrationStatus::Preparing { .. }
                            | BotRegistrationStatus::Waiting { .. }
                    )
                },
                "stale cancel must target the original attempt, not retire the replacement",
            )?;
            ensure!(
                reply.bot.is_none(),
                "stale cancel must not publish a configured bot"
            );
        }
        Err(error) if error.code == StudioErrorCode::NotFound => {}
        other => bail!(
            "cancel of replaced attemptId must be NotFound or NoChange, got {}",
            classify_command(other.as_ref())
        ),
    }
    ensure_attempt(
        &session.http()?.read_bots().await?,
        &second_attempt,
        |attempt| matches!(attempt.status, BotRegistrationStatus::Waiting { .. }),
        "replacement must remain Waiting after stale cancel",
    )?;
    let cancel_replace = cancel_ok(
        session,
        "op-reg-cancel-replace",
        &second_attempt,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!cancel_replace.receipt.durable);
    wait_status(
        watch,
        remaining(deadline)?,
        |attempt| {
            attempt.attempt_id == second_attempt
                && matches!(attempt.status, BotRegistrationStatus::Cancelled { .. })
        },
        "A replace cancelled",
    )
    .await?;
    assert_no_bot(session).await?;
    Ok(format!(
        "A reuse/replace old={first_attempt} new={second_attempt} beginDelta=2"
    ))
}

async fn stage_begin_hang_cancel(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    project_id: &str,
    deadline: Instant,
) -> Result<String> {
    let op = "op-reg-begin-hang";
    session
        .control()?
        .set_registration_begin_options(begin_options(None, 1, 120))
        .await;
    session
        .control()?
        .set_registration_script(vec![RegistrationPollScript::Pending])
        .await;
    session.control()?.hang_registration_begin().await;
    let start_http = session.http()?.clone();
    let start_request = StartBotRegistrationRequest {
        operation_id: op.into(),
        name: "observe-reg-begin-hang".into(),
        project_id: project_id.to_owned(),
    };
    let start_fut = start_http.start_registration_result(&start_request);
    let control_fut = async {
        wait_until(remaining(deadline)?, || async {
            Ok(session.control()?.begin_in_flight().await == 1)
        })
        .await
        .context("begin_in_flight never reached 1")?;
        let preparing = wait_status(
            watch,
            remaining(deadline)?,
            |attempt| matches!(attempt.status, BotRegistrationStatus::Preparing { .. }),
            "B preparing",
        )
        .await?;
        let cancel = cancel_ok(
            session,
            "op-reg-cancel-begin-hang",
            &preparing.attempt_id,
            remaining(deadline)?,
        )
        .await?;
        ensure!(!cancel.receipt.durable);
        wait_status(
            watch,
            remaining(deadline)?,
            |attempt| {
                attempt.attempt_id == preparing.attempt_id
                    && matches!(attempt.status, BotRegistrationStatus::Cancelled { .. })
            },
            "B cancelled",
        )
        .await?;
        session.control()?.release_registration_begin().await;
        wait_until(remaining(deadline)?, || async {
            Ok(session.control()?.begin_in_flight().await == 0)
        })
        .await
        .context("begin_in_flight did not return to 0")?;
        assert_no_bot(session).await?;
        Ok::<_, anyhow::Error>(preparing.attempt_id)
    };
    let (start_result, control) = tokio::join!(start_fut, control_fut);
    let attempt_id = control?;
    match start_result {
        Ok(Ok(reply)) => {
            ensure!(!reply.receipt.durable);
            ensure!(reply.receipt.operation_id == op);
        }
        Ok(Err(error)) => {
            ensure!(
                matches!(
                    error.code,
                    StudioErrorCode::Cancelled | StudioErrorCode::NotFound | StudioErrorCode::Busy
                ),
                "begin-hang start error must stay a fixed category, got {:?}",
                error.code
            );
        }
        Err(error) => {
            return Err(error.context("begin-hang start HTTP transport or decode failed"));
        }
    }
    http::hold_for(http::ACK_BUDGET.min(remaining(deadline)?)).await;
    ensure!(
        !matches!(
            current_status(session).await?,
            Some(BotRegistrationStatus::Waiting { .. })
                | Some(BotRegistrationStatus::Committing { .. })
        ),
        "begin-hang cancel must not land Waiting/Committing"
    );
    Ok(format!("B beginHang cancel attempt={attempt_id}"))
}

async fn stage_poll_hang_cancel(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    project_id: &str,
    deadline: Instant,
) -> Result<String> {
    session
        .control()?
        .set_registration_begin_options(begin_options(None, 1, 120))
        .await;
    session.control()?.hang_registration().await;
    let started = start_ok(
        session,
        "op-reg-poll-hang",
        "observe-reg-poll-hang",
        project_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!started.receipt.durable);
    let waiting = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| matches!(attempt.status, BotRegistrationStatus::Waiting { .. }),
        "C waiting",
    )
    .await?;
    wait_until(remaining(deadline)?, || async {
        Ok(session.control()?.poll_in_flight().await == 1)
    })
    .await
    .context("poll_in_flight never reached 1")?;
    session
        .control()?
        .set_registration_script(vec![RegistrationPollScript::Completed {
            include_open_id: true,
        }])
        .await;
    let cancel = cancel_ok(
        session,
        "op-reg-cancel-poll-hang",
        &waiting.attempt_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!cancel.receipt.durable);
    wait_status(
        watch,
        remaining(deadline)?,
        |attempt| {
            attempt.attempt_id == waiting.attempt_id
                && matches!(attempt.status, BotRegistrationStatus::Cancelled { .. })
        },
        "C cancelled",
    )
    .await?;
    let polls_before_release = session.control()?.snapshot_report().await.polls.len();
    session.control()?.release_registration().await;
    http::hold_for(http::ACK_BUDGET).await;
    let report = session.control()?.snapshot_report().await;
    let late = report.polls.len() > polls_before_release
        && report.polls.iter().any(|poll| {
            matches!(
                poll.script,
                RegistrationPollScript::Completed {
                    include_open_id: true
                }
            )
        });
    let branch = if late {
        "peerEmittedNotProofOfConsumption"
    } else {
        "requestDropped"
    };
    ensure!(
        matches!(
            current_status(session).await?,
            Some(BotRegistrationStatus::Cancelled { .. })
        ),
        "late Completed must not revive a cancelled attempt"
    );
    assert_no_bot(session).await?;
    assert_no_side_effects(session, CallKind::TenantToken).await?;
    assert_no_side_effects(session, CallKind::BotInfo).await?;
    Ok(format!(
        "C pollHang cancel attempt={} branch={branch}",
        waiting.attempt_id
    ))
}

async fn stage_expire_inflight_poll(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    project_id: &str,
    deadline: Instant,
) -> Result<String> {
    session
        .control()?
        .set_registration_begin_options(begin_options(None, 1, 2))
        .await;
    session.control()?.hang_registration().await;
    let started = start_ok(
        session,
        "op-reg-expire-inflight",
        "observe-reg-expire-inflight",
        project_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!started.receipt.durable);
    let waiting = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| matches!(attempt.status, BotRegistrationStatus::Waiting { .. }),
        "D waiting",
    )
    .await?;
    wait_until(remaining(deadline)?, || async {
        Ok(session.control()?.poll_in_flight().await == 1)
    })
    .await
    .ok();
    wait_status(
        watch,
        remaining(deadline)?,
        |attempt| {
            attempt.attempt_id == waiting.attempt_id
                && matches!(attempt.status, BotRegistrationStatus::Expired { .. })
        },
        "D expired",
    )
    .await?;
    session
        .control()?
        .set_registration_script(vec![RegistrationPollScript::Completed {
            include_open_id: true,
        }])
        .await;
    let inflight_before_release = session.control()?.poll_in_flight().await;
    session.control()?.release_registration().await;
    http::hold_for(http::ACK_BUDGET).await;
    ensure!(
        matches!(
            current_status(session).await?,
            Some(BotRegistrationStatus::Expired { .. })
        ),
        "late Completed after expiry must not complete registration"
    );
    assert_no_bot(session).await?;
    Ok(format!(
        "D expire inflight attempt={} pollInFlightBeforeRelease={inflight_before_release}",
        waiting.attempt_id
    ))
}

async fn stage_denied(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    project_id: &str,
    deadline: Instant,
) -> Result<String> {
    observe_terminal(
        session,
        watch,
        TerminalScript {
            project_id,
            operation_id: "op-reg-denied",
            name: "observe-reg-denied",
            script: RegistrationPollScript::Denied,
            phase: "E denied",
            deadline,
        },
        |attempt| matches!(attempt.status, BotRegistrationStatus::Denied { .. }),
    )
    .await
}

async fn stage_remote_expired(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    project_id: &str,
    deadline: Instant,
) -> Result<String> {
    observe_terminal(
        session,
        watch,
        TerminalScript {
            project_id,
            operation_id: "op-reg-remote-expired",
            name: "observe-reg-remote-expired",
            script: RegistrationPollScript::Expired,
            phase: "E remoteExpired",
            deadline,
        },
        |attempt| matches!(attempt.status, BotRegistrationStatus::Expired { .. }),
    )
    .await
}

struct TerminalScript<'a> {
    project_id: &'a str,
    operation_id: &'a str,
    name: &'a str,
    script: RegistrationPollScript,
    phase: &'static str,
    deadline: Instant,
}

async fn observe_terminal(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    script: TerminalScript<'_>,
    predicate: impl Fn(&BotRegistrationAttempt) -> bool,
) -> Result<String> {
    let begins = begin_count(session).await?;
    session
        .control()?
        .set_registration_begin_options(begin_options(None, 1, 30))
        .await;
    session
        .control()?
        .set_registration_script(vec![script.script])
        .await;
    let started = start_ok(
        session,
        script.operation_id,
        script.name,
        script.project_id,
        remaining(script.deadline)?,
    )
    .await?;
    ensure!(!started.receipt.durable);
    let terminal = wait_status(watch, remaining(script.deadline)?, predicate, script.phase).await?;
    ensure!(begin_count(session).await? == begins + 1);
    assert_no_bot(session).await?;
    Ok(format!(
        "{} attempt={} kind={}",
        script.phase,
        terminal.attempt_id,
        topic::registration_kind(&terminal.status)
    ))
}

async fn stage_slow_down(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    project_id: &str,
    deadline: Instant,
) -> Result<String> {
    session
        .control()?
        .set_registration_begin_options(begin_options(None, 1, 90))
        .await;
    session
        .control()?
        .set_registration_script(vec![
            RegistrationPollScript::SlowDown,
            RegistrationPollScript::SlowDown,
            RegistrationPollScript::Pending,
        ])
        .await;
    let started = start_ok(
        session,
        "op-reg-slowdown",
        "observe-reg-slowdown",
        project_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!started.receipt.durable);
    let waiting = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| matches!(attempt.status, BotRegistrationStatus::Waiting { .. }),
        "F waiting",
    )
    .await?;
    let polls_at_waiting = poll_observations(session).await?.len();
    let first_slow = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| match &attempt.status {
            BotRegistrationStatus::SlowDown {
                attempt_id,
                interval_seconds,
                ..
            } => attempt_id == &waiting.attempt_id && *interval_seconds == 6,
            _ => false,
        },
        "F slowDown 6",
    )
    .await?;
    let second_slow = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| match &attempt.status {
            BotRegistrationStatus::SlowDown {
                attempt_id,
                interval_seconds,
                ..
            } => attempt_id == &waiting.attempt_id && *interval_seconds == 11,
            _ => false,
        },
        "F slowDown 11",
    )
    .await?;
    wait_until(remaining(deadline)?, || async {
        Ok(poll_observations(session).await?.len() >= polls_at_waiting + 3)
    })
    .await
    .context("slowDown did not record three poll observations")?;
    let polls = poll_observations(session).await?;
    let stage_polls = &polls[polls_at_waiting.min(polls.len())..];
    let deltas = poll_deltas(stage_polls)?;
    ensure!(
        deltas.len() >= 2,
        "slowDown needs at least two poll intervals"
    );
    ensure!(
        deltas[0] + SLOWDOWN_EARLY >= std::time::Duration::from_secs(6),
        "first post-slowDown interval must be at least ~6s, got {}ms",
        deltas[0].as_millis()
    );
    ensure!(
        deltas[1] + SLOWDOWN_EARLY >= std::time::Duration::from_secs(11),
        "second post-slowDown interval must be at least ~11s, got {}ms",
        deltas[1].as_millis()
    );
    let cancel = cancel_ok(
        session,
        "op-reg-cancel-slowdown",
        &waiting.attempt_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!cancel.receipt.durable);
    wait_status(
        watch,
        remaining(deadline)?,
        |attempt| {
            attempt.attempt_id == waiting.attempt_id
                && matches!(attempt.status, BotRegistrationStatus::Cancelled { .. })
        },
        "F cancelled",
    )
    .await?;
    Ok(format!(
        "F slowDown attempt={} interval6@{} interval11@{} d0ms={} d1ms={}",
        waiting.attempt_id,
        status_interval(&first_slow).unwrap_or(0),
        status_interval(&second_slow).unwrap_or(0),
        deltas[0].as_millis(),
        deltas[1].as_millis()
    ))
}

async fn stage_url_policy(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    project_id: &str,
    deadline: Instant,
) -> Result<String> {
    let origin = session.control()?.origin().await;
    let nonce = POSITIVE_NONCE;
    session.remember_marker(nonce);
    let positive = format!("{origin}{POSITIVE_PATH}?user_code=ANYWORK&nonce={nonce}");
    session
        .control()?
        .set_registration_begin_options(begin_options(Some(positive), 1, 30))
        .await;
    session
        .control()?
        .set_registration_script(vec![RegistrationPollScript::Pending])
        .await;
    let started = start_ok(
        session,
        "op-reg-url-positive",
        "observe-reg-url-positive",
        project_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!started.receipt.durable);
    let waiting = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| matches!(attempt.status, BotRegistrationStatus::Waiting { .. }),
        "G positive waiting",
    )
    .await?;
    let url = waiting_url(&waiting.status).context("positive Waiting URL")?;
    assert_positive_url(url, &origin, nonce)?;
    session
        .control()?
        .validate_addons_encoding(&addons_encoding(url)?)
        .context("addons encoding")?;
    let cancel = cancel_ok(
        session,
        "op-reg-cancel-url-positive",
        &waiting.attempt_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!cancel.receipt.durable);
    wait_status(
        watch,
        remaining(deadline)?,
        |attempt| {
            attempt.attempt_id == waiting.attempt_id
                && matches!(attempt.status, BotRegistrationStatus::Cancelled { .. })
        },
        "G positive cancelled",
    )
    .await?;

    let peer_port = loopback_port(&origin)?;
    let other_port = if peer_port == 18080 { 18081 } else { 18080 };
    let negatives = [
        format!("http://127.0.0.1:{other_port}{POSITIVE_PATH}?user_code=ANYWORK&nonce={nonce}"),
        format!("http://user:pass@127.0.0.1:{peer_port}{POSITIVE_PATH}?user_code=ANYWORK"),
        format!("{origin}{POSITIVE_PATH}?user_code=ANYWORK#frag"),
        format!("http://example.test{POSITIVE_PATH}?user_code=ANYWORK&nonce={nonce}"),
        format!("https://accounts.feishu.cn{POSITIVE_PATH}?user_code=ANYWORK&nonce={nonce}"),
        format!("https://open.feishu.cn{POSITIVE_PATH}?user_code=ANYWORK&nonce={nonce}"),
        format!("https://accounts.larksuite.com{POSITIVE_PATH}?user_code=ANYWORK"),
    ];
    let mut rejected = 0usize;
    for (index, candidate) in negatives.into_iter().enumerate() {
        session
            .control()?
            .set_registration_begin_options(begin_options(Some(candidate), 1, 20))
            .await;
        session
            .control()?
            .set_registration_script(vec![RegistrationPollScript::Pending])
            .await;
        let op = format!("op-reg-url-neg-{index}");
        let started = start_ok(
            session,
            &op,
            &format!("observe-reg-url-neg-{index}"),
            project_id,
            remaining(deadline)?,
        )
        .await?;
        ensure!(!started.receipt.durable);
        let failed = wait_status(
            watch,
            remaining(deadline)?,
            |attempt| matches!(attempt.status, BotRegistrationStatus::Failed { .. }),
            "G negative failed",
        )
        .await;
        match failed {
            Ok(attempt) => {
                ensure!(
                    matches!(attempt.status, BotRegistrationStatus::Failed { .. }),
                    "rejected URL must not land Waiting"
                );
                rejected += 1;
            }
            Err(_) => match current_status(session).await? {
                Some(BotRegistrationStatus::Failed { .. }) => rejected += 1,
                Some(BotRegistrationStatus::Waiting { .. }) => {
                    bail!("fixture URL negative control landed Waiting")
                }
                other => bail!(
                    "fixture URL negative control did not fail safely: {:?}",
                    other.map(|status| topic::registration_kind(&status))
                ),
            },
        }
        assert_no_bot(session).await?;
    }
    Ok(format!(
        "G urlPolicy positiveAttempt={} negativesRejected={rejected}",
        waiting.attempt_id
    ))
}

async fn stage_lark_brand(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    project_id: &str,
    deadline: Instant,
) -> Result<String> {
    let mut attempts = Vec::new();
    for (index, include_open_id) in [true, false].into_iter().enumerate() {
        session
            .control()?
            .set_registration_begin_options(begin_options(None, 1, 30))
            .await;
        session
            .control()?
            .set_registration_tenant_brand(Some(RegistrationTenantBrand::Lark))
            .await;
        session
            .control()?
            .set_registration_script(vec![RegistrationPollScript::Completed { include_open_id }])
            .await;
        let started = start_ok(
            session,
            &format!("op-reg-lark-{index}"),
            &format!("observe-reg-lark-{index}"),
            project_id,
            remaining(deadline)?,
        )
        .await?;
        ensure!(!started.receipt.durable);
        let failed = wait_status(
            watch,
            remaining(deadline)?,
            |attempt| matches!(attempt.status, BotRegistrationStatus::Failed { .. }),
            "H lark failed",
        )
        .await?;
        attempts.push(failed.attempt_id.clone());
        assert_no_bot(session).await?;
        assert_no_side_effects(session, CallKind::TenantToken).await?;
    }
    session.control()?.set_registration_tenant_brand(None).await;
    Ok(format!("H larkFailed attempts={}", attempts.join(",")))
}

async fn stage_success_with_user(
    session: &mut Session,
    watch: &mut BotsTopicWatch,
    project_id: &str,
    deadline: Instant,
) -> Result<String> {
    session
        .control()?
        .set_registration_begin_options(begin_options(None, 1, 60))
        .await;
    session
        .control()?
        .set_registration_tenant_brand(Some(RegistrationTenantBrand::Feishu))
        .await;
    session
        .control()?
        .set_registration_script(vec![RegistrationPollScript::Completed {
            include_open_id: true,
        }])
        .await;
    let started = start_ok(
        session,
        "op-reg-success",
        "observe-reg-success",
        project_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!started.receipt.durable);
    let committing = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| match &attempt.status {
            BotRegistrationStatus::Committing { attempt_id, bot_id } => {
                attempt_id == &attempt.attempt_id
                    && !bot_id.is_empty()
                    && attempt.completed_bot_id.is_none()
            }
            _ => false,
        },
        "I committing",
    )
    .await?;
    let completed = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| {
            matches!(attempt.status, BotRegistrationStatus::Completed { .. })
                && attempt.completed_bot_id.is_some()
        },
        "I completed",
    )
    .await?;
    let bot_id = completed
        .completed_bot_id
        .clone()
        .context("success completedBotId")?;
    ensure_committing_then_completed(&committing, &completed, &bot_id)?;
    let snapshot = session.http()?.read_bots().await?;
    let bot = snapshot
        .bots
        .iter()
        .find(|bot| bot.id == bot_id)
        .context("success bot missing")?;
    ensure_registered_app(&bot.app_id)?;
    ensure!(bot.trusted_open_ids.as_slice() == [TRUSTED_USER_OPEN_ID]);
    ensure_usable_credential(bot.credential)?;
    wait_connected_event(watch, &bot_id, remaining(deadline)?).await?;
    let after_complete = cancel_result(
        session,
        "op-reg-cancel-completed",
        &completed.attempt_id,
        remaining(deadline)?,
    )
    .await?;
    match after_complete {
        Ok(reply) => {
            ensure!(reply.receipt.disposition == CommandDisposition::NoChange);
            ensure_reply_attempt(
                reply.registration.as_ref(),
                &completed.attempt_id,
                |attempt| matches!(attempt.status, BotRegistrationStatus::Completed { .. }),
                "cancel after Completed must stay Completed",
            )?;
        }
        Err(error) if error.code == StudioErrorCode::Busy => {}
        other => bail!(
            "cancel after Completed must be Busy or NoChange, got {}",
            classify_command(other.as_ref())
        ),
    }
    session
        .control()?
        .set_registration_script(vec![RegistrationPollScript::Pending])
        .await;
    let second = start_ok(
        session,
        "op-reg-second",
        "observe-reg-second",
        project_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!second.receipt.durable);
    let second_attempt = wait_status(
        watch,
        remaining(deadline)?,
        |attempt| {
            attempt.attempt_id != completed.attempt_id
                && matches!(
                    attempt.status,
                    BotRegistrationStatus::Preparing { .. } | BotRegistrationStatus::Waiting { .. }
                )
        },
        "I second preparing/waiting",
    )
    .await?;
    let cancel_second = cancel_ok(
        session,
        "op-reg-cancel-second",
        &second_attempt.attempt_id,
        remaining(deadline)?,
    )
    .await?;
    ensure!(!cancel_second.receipt.durable);
    wait_status(
        watch,
        remaining(deadline)?,
        |attempt| {
            attempt.attempt_id == second_attempt.attempt_id
                && matches!(attempt.status, BotRegistrationStatus::Cancelled { .. })
        },
        "I second cancelled",
    )
    .await?;
    let kept = session
        .http()?
        .read_bots()
        .await?
        .bots
        .into_iter()
        .find(|bot| bot.id == bot_id)
        .context("saved bot must survive a later first-config attempt")?;
    ensure!(kept.app_id == REGISTERED_APP_ID);
    Ok(format!(
        "I success bot={bot_id} attempt={} second={}",
        completed.attempt_id, second_attempt.attempt_id
    ))
}
