//! `owner-binding-occupancy`: the first explicit owner conversation-Thread
//! creation, the stale-creation race during its pre-write directory
//! verification, and the occupancy projection — from one fresh environment
//! with no inbound traffic and no bindings.
//!
//! The bot is saved disabled by its first public command and stays disabled, so
//! no platform WebSocket is ever started: nothing later in this scenario can be
//! refreshed by a connection restart, and the observation depends only on local
//! owner commands plus the platform directory responses it triggers.
//!
//! Three ordered observations share the session; a failed or unreached later
//! observation keeps its coverage gap instead of being reported as passed:
//! A. The creation is suspended inside its pre-write directory verification with
//!    the existing peer chat-list control: the peer records the accepted
//!    directory request and *then* holds the response, so a growing accepted
//!    `ChatList` count while the same request future is still pending proves the
//!    creation entered that window (no sleep, no token trick, no derived task).
//!    A public project P -> Q save commits in the window. Releasing the
//!    directory response must leave the stale creation rejected as `Conflict`
//!    **before its first write**: no `thread_bindings` row, no
//!    `binding_operations` row, no Thread added to the public directory, the
//!    project stays mutable, and no model or send call happens. A bare 409 is
//!    not enough: the old implementation wrote `creating` and created the old
//!    project's Thread before its final Conflict.
//! B. With still no inbound/binding and `canChangeProject=true`, the first
//!    public creation binds a verified visible group conversation. The
//!    occupancy flip to `canChangeProject=false` must arrive as an active
//!    bots-topic publication (config revision unchanged, topic watermark
//!    advanced) on a subscription opened before the action. The strict topic
//!    path refuses a stale/resync read-back, so the capability change cannot be
//!    synthesized by `/api/v1/state/product`.
//! C. Retrying the same operationId reuses the same creation (`NoChange`, same
//!    Thread/binding revision/creation identity), including after a
//!    non-identity rename commit whose actual config revision is read from the
//!    reply snapshot; the canonical conversation page shows that binding.
//!
//! The model fixture script is intentionally empty: any model request in this
//! scenario is a product defect, and the strict fixture rejects it.

use super::Session;
use crate::http;
use crate::report::{self, CaseResult};
use crate::topic::BotsTopicWatch;
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::{
    BotConnectionState, BotConversationThreadReply, BotConversationThreadState,
    BotCredentialAvailability, BotSecretUpdate, BotSnapshot, BotsCommandReply, CommandDisposition,
    CreateBotConversationThreadRequest, ListBotConversationsRequest, SaveBotRequest, StudioError,
    StudioErrorCode,
};
use pl_provider_fixture::feishu::{
    CallKind, DEFAULT_APP_ID, DEFAULT_APP_SECRET, GROUP_CHAT_ID, RecordedCall,
};
use std::collections::BTreeSet;
use std::time::Duration;

pub(crate) const CASE: &str = "owner-binding-occupancy";

/// Absolute observe budget for this session-exclusive scenario. Phase waits
/// inside stay on the shared predicate budgets; this is only the outer bound.
const CASE_BUDGET: Duration = Duration::from_secs(240);
/// Bound for draining a suspended creation after a failed phase. It only has to
/// cover the released request reaching its verdict, and stays well inside
/// [`CASE_BUDGET`] so the cleanup is observed instead of the outer timeout.
const DRAIN_BUDGET: Duration = Duration::from_secs(30);

const CHAT_ID: &str = GROUP_CHAT_ID;
const CREATE_OPERATION: &str = "op-obo-create-first";
const SWITCH_OPERATION: &str = "op-obo-switch-project";
const RENAME_AFTER_CONFLICT: &str = "op-obo-rename-after-conflict";
const RENAME_AFTER_OCCUPANCY: &str = "op-obo-rename-after-occupancy";

/// Absolute monotonic deadline shared by the budget handler and the observation
/// body. Every business entry re-checks the same instant, and a completion is
/// only claimed while that instant still has time left, so a ready inner future
/// cannot win the biased select past the deadline.
struct Deadline {
    expires_at: tokio::time::Instant,
}

impl Deadline {
    fn new(budget: Duration) -> Self {
        Self {
            expires_at: tokio::time::Instant::now() + budget,
        }
    }

    fn expired(&self) -> bool {
        tokio::time::Instant::now() >= self.expires_at
    }

    /// Gate for anything that can cause a business side effect: a command, a
    /// project open, or a platform-facing creation. It checks the real absolute
    /// instant, not a timer callback.
    fn checkpoint(&self, before: &str) -> Result<()> {
        if self.expired() {
            bail!("owner-binding-occupancy was already past its absolute deadline before {before}");
        }
        Ok(())
    }
}

/// One finished observation: the verdict plus everything it had proven, so the
/// outer budget handler can report the evidence without sharing state with the
/// future it is draining.
struct Observation {
    result: Result<CaseResult>,
    evidence: Vec<String>,
}

pub(crate) async fn owner_binding_occupancy(session: &mut Session) -> Result<CaseResult> {
    // Cloned before the observation borrows the session, so the deadline branch
    // can release the suspended response while the same future is still alive.
    let control = session.control()?;
    let deadline = Deadline::new(CASE_BUDGET);
    let inner = owner_binding_occupancy_inner(session, &deadline);
    tokio::pin!(inner);
    // The budget only *borrows* the observation: the accepted request future
    // stays owned by it and can still be drained after the deadline. The timer
    // and the completion re-check share one monotonic instant.
    let finished = tokio::select! {
        biased;
        observation = &mut inner => Some(observation),
        _ = tokio::time::sleep_until(deadline.expires_at) => None,
    };
    match finished {
        Some(Observation { result, evidence }) => {
            // Completion claim linearization point: an inner future that is
            // ready at the same moment as the timer cannot win past the deadline,
            // so a both-ready race stays a deadline failure with its evidence.
            if deadline.expired() {
                let _ = control.release_chat_list().await;
                let cleanup = match result {
                    Ok(_) => {
                        "the observation completed only at the absolute deadline; the deadline verdict is retained".to_string()
            }
                    Err(error) => format!("the observation ended with {error:#}"),
                };
                let mut failed = report::failed(
                    CASE,
                    format!(
                        "owner-binding-occupancy exceeded its absolute observe budget; cleanup: {cleanup}"
                    ),
                );
                failed.evidence = evidence;
                return Ok(failed);
            }
            match result {
                Ok(result) => Ok(result),
                Err(error) => {
                    // A suspended directory response must not outlive the case
                    // even on failure; releasing an already released generation
                    // is a no-op.
                    let _ = control.release_chat_list().await;
                    let mut failed = report::failed(CASE, format!("{error:#}"));
                    failed.evidence = evidence;
                    Ok(failed)
                }
            }
        }
        None => {
            // Absolute deadline: every later business entry is refused by the
            // shared instant, the suspended response is released, and the *same*
            // observation future (and the request it owns) keeps being drained
            // within the separate bounds.
            let _ = control.release_chat_list().await;
            let drained = tokio::time::timeout(DRAIN_BUDGET, &mut inner).await;
            let (evidence, cleanup) = match drained {
                Ok(Observation { result, evidence }) => {
                    let cleanup = match result {
                        Ok(_) => {
                            "the observation finished after its deadline; the deadline verdict is retained"
                                .to_string()
                        }
                        Err(error) => format!("the observation ended with {error:#}"),
                    };
                    (evidence, cleanup)
                }
                Err(_) => (
                    Vec::new(),
                    format!(
                        "draining the observation after its absolute deadline exceeded {DRAIN_BUDGET:?}"
                    ),
                ),
            };
            let mut failed = report::failed(
                CASE,
                format!(
                    "owner-binding-occupancy exceeded its absolute observe budget; cleanup: {cleanup}"
                ),
            );
            failed.evidence = evidence;
            Ok(failed)
        }
    }
}

/// Wraps the body so its evidence always travels back with the verdict.
async fn owner_binding_occupancy_inner(session: &mut Session, deadline: &Deadline) -> Observation {
    let mut evidence = Vec::new();
    let result = owner_binding_body(session, &mut evidence, deadline).await;
    Observation { result, evidence }
}

async fn owner_binding_body(
    session: &mut Session,
    evidence: &mut Vec<String>,
    deadline: &Deadline,
) -> Result<CaseResult> {
    // Fresh environment: one disabled bot on project P. No connection starts,
    // so no platform traffic or occupancy publication happens in the background.
    let (bot_id, project_p) = save_disabled_bot(session, deadline).await?;
    let initial = session.bot(&bot_id).await?;
    let revision = initial.config_revision;
    ensure!(
        initial.can_change_project,
        "a fresh bot must allow project changes"
    );
    ensure!(
        !initial.enabled && matches!(initial.connection, BotConnectionState::Disabled),
        "the observation bot must stay disabled without a platform connection, got enabled={} connection={}",
        initial.enabled,
        crate::topic::redact_connection(&initial.connection)
    );
    let ws_connections = session.control()?.snapshot_report().await.ws_connections;
    ensure!(
        ws_connections == 0,
        "a disabled bot must not open a platform WebSocket, got {ws_connections} connections"
    );
    let project_q = open_second_project(session, deadline).await?;
    ensure!(
        project_p != project_q,
        "the second public project must get its own id, got the same id for P and Q"
    );
    evidence.push(format!(
        "fresh disabled bot on P={project_p} cfgrev={revision} canChangeProject=true; Q={project_q} with a distinct id"
    ));

    let baseline_threads = list_thread_facts(session).await?;
    assert_no_occupancy_facts(session, &bot_id, "baseline").await?;
    let baseline_chat_lists = accepted_calls(
        &session.control()?.snapshot_report().await.calls,
        CallKind::ChatList,
    );

    // --- A. stale creation during its pre-write directory verification ------
    deadline.checkpoint("the stale creation")?;
    evidence.push("A: suspending the creation's directory response".into());
    session.control()?.hang_chat_list().await;
    // Arming the peer also awaits, so the request itself is gated again right
    // before it is issued.
    deadline.checkpoint("issuing the stale creation")?;
    // The request future is owned by this case body (no derived task or
    // `JoinHandle`), so cancellation of the case future drops the request
    // instead of orphaning a detached task.
    let http = session.http()?.clone();
    let stale_request = CreateBotConversationThreadRequest {
        operation_id: "op-obo-create-stale".into(),
        bot_id: bot_id.clone(),
        chat_id: CHAT_ID.into(),
        expected_config_revision: revision,
        expected_binding_revision: 0,
    };
    let stale = http.create_conversation_thread(&stale_request);
    tokio::pin!(stale);
    // The peer records the accepted directory request *before* it holds the
    // response, so the wait arm proves the creation entered that window; the
    // request arm proves the same future did not settle early, which would
    // invalidate the race.
    let settled_early = tokio::select! {
        biased;
        settled = &mut stale => Some(settled),
        waited = http::wait_until(http::PREDICATE_TIMEOUT, || {
            chat_list_accepted(session, baseline_chat_lists)
        }) => {
            match waited {
                Ok(()) => None,
                Err(error) => {
                    let cleanup = release_and_drain(session, &mut stale).await;
                    return Err(drain_error(
                        error.context(
                            "the stale creation never entered its pending directory response",
                        ),
                        cleanup,
                    ));
                }
            }
        }
    };
    if let Some(settled) = settled_early {
        bail!(
            "the stale creation settled before its directory response was suspended: {}",
            describe_creation_outcome(&settled)
        );
    }
    let in_window = accepted_calls(
        &session.control()?.snapshot_report().await.calls,
        CallKind::ChatList,
    );
    ensure!(
        in_window > baseline_chat_lists,
        "the accepted directory request count must grow while the creation is pending"
    );
    evidence.push(format!(
        "A: stale creation is pending on its directory response (accepted chatList {baseline_chat_lists} -> {in_window}) with the same request future still unfinished"
    ));

    // The absolute deadline may have elapsed while this creation was suspended:
    // drain that same request to a terminal instead of starting the switch.
    if deadline.expired() {
        let cleanup = release_and_drain(session, &mut stale).await;
        return Err(drain_error(
            anyhow::anyhow!(
                "owner-binding-occupancy was already past its absolute deadline while the creation was suspended"
            ),
            cleanup,
        ));
    }

    // A legitimate owner save commits the project switch while the creation is
    // suspended; same app and secret, valid expected revision r -> r+1.
    let switched = match save_owned(
        session,
        deadline,
        SWITCH_OPERATION,
        &bot_id,
        revision,
        "observe-bot",
        &project_q,
    )
    .await
    {
        Ok(reply) => reply,
        Err(error) => {
            // The creation is still suspended: release the directory response
            // and drain the same request future before reporting, so no handler
            // is left waiting.
            let cleanup = release_and_drain(session, &mut stale).await;
            return Err(drain_error(
                error.context("the project switch failed while the creation was suspended"),
                cleanup,
            ));
        }
    };
    session.control()?.release_chat_list().await;
    let stale_outcome = (&mut stale).await;

    // The switch itself must be a real P -> Q commit at the next revision.
    let switched_bot = saved_bot(&switched, &bot_id, "project switch")?;
    ensure!(
        switched.receipt.operation_id == SWITCH_OPERATION
            && switched.receipt.disposition == CommandDisposition::Applied,
        "the project switch must be an applied command with its own operation id"
    );
    ensure!(
        switched_bot.project_id == project_q && switched_bot.config_revision == revision + 1,
        "the switch reply must show project Q at the next config revision, got project={} cfgrev={}",
        switched_bot.project_id,
        switched_bot.config_revision
    );
    let revision_q = switched_bot.config_revision;
    evidence.push(format!(
        "A: project switch committed P -> Q at cfgrev {revision} -> {revision_q} while the creation was suspended"
    ));

    let stale_error: StudioError = match stale_outcome {
        Ok(Ok(reply)) => bail!(
            "the stale creation must be rejected, not accepted (disposition={:?})",
            reply.receipt.disposition
        ),
        Ok(Err(error)) => error,
        Err(error) => {
            return Err(error.context("the stale creation request failed in transport"));
        }
    };
    ensure!(
        stale_error.code == StudioErrorCode::Conflict,
        "the stale creation must fail as Conflict, got {:?} {}",
        stale_error.code,
        crate::env::redact(&stale_error.message)
    );
    // The verdict category is a fixed product diagnostic; keep it so a rejection
    // from another stage stays visible.
    evidence.push(format!(
        "A: stale creation rejected as Conflict ({})",
        crate::env::redact(&stale_error.message)
    ));

    // First-write rejection: durable ledgers stay empty, no Thread appears in the
    // public directory, no inbound appears. The old implementation wrote
    // `creating` and created the old project's Thread before its final Conflict,
    // so these facts are defect-sensitive.
    assert_stale_creation_left_nothing(session, &bot_id, &baseline_threads).await?;
    let after_stale = session.bot(&bot_id).await?;
    ensure!(
        after_stale.project_id == project_q && after_stale.config_revision == revision_q,
        "the project switch must survive the stale rejection"
    );
    // The project must stay mutable: one more legitimate save commits at the
    // actual revision, not at a guessed one.
    let renamed_after_stale = save_owned(
        session,
        deadline,
        RENAME_AFTER_CONFLICT,
        &bot_id,
        revision_q,
        "observe-bot-q",
        &project_q,
    )
    .await?;
    let renamed_bot = saved_bot(&renamed_after_stale, &bot_id, "rename after conflict")?;
    ensure!(
        renamed_after_stale.receipt.operation_id == RENAME_AFTER_CONFLICT
            && renamed_after_stale.receipt.disposition == CommandDisposition::Applied,
        "a legitimate save after the stale rejection must still commit"
    );
    ensure!(
        renamed_bot.name == "observe-bot-q"
            && renamed_bot.project_id == project_q
            && renamed_bot.config_revision == revision_q + 1,
        "the rename reply must show the requested name on Q at the next revision, got name={} project={} cfgrev={}",
        renamed_bot.name,
        renamed_bot.project_id,
        renamed_bot.config_revision
    );
    let revision_current = renamed_bot.config_revision;
    evidence.push(format!(
        "A: no binding/operation/Thread/inbound rows; project stayed mutable (cfgrev {revision_q} -> {revision_current})"
    ));
    assert_no_inbound_or_model(session, &bot_id, "A").await?;
    evidence.push("A: zero model requests and zero sends".into());

    // --- B. first occupancy over the public endpoint -----------------------
    let before_first = session.bot(&bot_id).await?;
    ensure!(
        before_first.can_change_project
            && before_first.config_revision == revision_current
            && before_first.project_id == project_q,
        "the bot must still be movable on Q before the first creation"
    );
    assert_no_occupancy_facts(session, &bot_id, "before first creation").await?;

    // The subscription is opened before the action and the baseline is
    // consumed; from here on the strict path must deliver the capability change
    // as an active publication without any product-state read-back.
    let mut watch = BotsTopicWatch::connect(session.http()?.origin()).await?;
    let baseline = watch
        .wait_baseline(&bot_id, http::PREDICATE_TIMEOUT)
        .await?;
    let baseline_revision = baseline.revision;

    let first_request = CreateBotConversationThreadRequest {
        operation_id: CREATE_OPERATION.into(),
        bot_id: bot_id.clone(),
        chat_id: CHAT_ID.into(),
        expected_config_revision: revision_current,
        expected_binding_revision: 0,
    };
    let first = create_thread(
        session,
        deadline,
        "the first occupancy creation",
        &first_request,
    )
    .await
    .map_err(|error| anyhow::anyhow!("first creation request failed: {error:#}"))?
    .map_err(|error| {
        anyhow::anyhow!(
            "first creation failed: {} ({:?})",
            crate::env::redact(&error.message),
            error.code
        )
    })?;
    ensure!(
        first.receipt.disposition == CommandDisposition::Applied
            && first.receipt.operation_id == CREATE_OPERATION,
        "the first creation must Apply under the original operation id, got {:?}",
        first.receipt.disposition
    );
    let thread_id = first
        .binding
        .thread_id
        .clone()
        .context("applied first creation returned no Thread")?;
    ensure!(
        first.binding.state == BotConversationThreadState::Bound
            && first.binding.bot_id == bot_id
            && first.binding.project_id == project_q
            && first.binding.chat_id == CHAT_ID
            && first.binding.revision == 1,
        "applied first binding must be Bound on Q with revision 1, got {:?} rev={}",
        first.binding.state,
        first.binding.revision
    );
    let expected_creation = expected_creation_id(&bot_id);
    evidence.push(format!(
        "B: first creation Applied thread={thread_id} bindingRevision={}",
        first.binding.revision
    ));

    // Active occupancy publication on the subscription opened before the
    // action: canChangeProject flips false with the config revision unchanged
    // and the topic watermark advancing. No product-state read-back, no read or
    // management action sits between the request and this observation.
    let published = watch
        .wait_bot_strict(
            &bot_id,
            http::PREDICATE_TIMEOUT,
            |bot| {
                !bot.can_change_project
                    && bot.config_revision == revision_current
                    && bot.project_id == project_q
            },
            "first occupancy publication",
        )
        .await?;
    ensure!(
        published.revision > baseline_revision,
        "the occupancy publication must advance the topic watermark"
    );
    evidence.push(format!(
        "B: active occupancy publication watermark {} -> {} with cfgrev={revision_current} unchanged (strict, no state read-back)",
        baseline_revision, published.revision
    ));
    drop(watch);

    // Read-only ledger reconciliation after the publication fact: the baseline
    // creation identity is read here, before any retry can touch it.
    assert_creation_identity(
        session,
        &bot_id,
        &thread_id,
        &expected_creation,
        "first creation",
    )
    .await?;
    let threads_after_first = list_thread_facts(session).await?;
    let created = threads_after_first
        .iter()
        .find(|fact| fact.id == thread_id)
        .with_context(|| format!("created Thread {thread_id} missing from the public directory"))?;
    ensure!(
        created.project_id == project_q,
        "the created Thread must belong to project Q"
    );
    let mut baseline_plus_created = baseline_threads.clone();
    baseline_plus_created.insert(created.clone());
    ensure!(
        threads_after_first == baseline_plus_created,
        "the first creation must add exactly one Thread to the directory"
    );
    assert_no_inbound_or_model(session, &bot_id, "B").await?;

    // --- C. same-operation retry reuses the same creation ------------------
    let retry_request = CreateBotConversationThreadRequest {
        operation_id: CREATE_OPERATION.into(),
        bot_id: bot_id.clone(),
        chat_id: CHAT_ID.into(),
        expected_config_revision: revision_current,
        expected_binding_revision: 0,
    };
    let retry = create_thread(
        session,
        deadline,
        "the same-operation retry",
        &retry_request,
    )
    .await
    .map_err(|error| anyhow::anyhow!("same-operation retry request failed: {error:#}"))?
    .map_err(|error| {
        anyhow::anyhow!(
            "same-operation retry failed: {} ({:?})",
            crate::env::redact(&error.message),
            error.code
        )
    })?;
    ensure_retry_reused(&retry, &bot_id, &project_q, &thread_id, "plain retry")?;
    assert_creation_identity(
        session,
        &bot_id,
        &thread_id,
        &expected_creation,
        "after plain retry",
    )
    .await?;

    // A non-identity rename commits and the already persisted operation must
    // still continue the same creation. The retry uses the revision the rename
    // reply actually published, never a guessed increment.
    let renamed = save_owned(
        session,
        deadline,
        RENAME_AFTER_OCCUPANCY,
        &bot_id,
        revision_current,
        "observe-bot-q-occupied",
        &project_q,
    )
    .await?;
    let renamed_bot = saved_bot(&renamed, &bot_id, "rename after occupancy")?;
    ensure!(
        renamed.receipt.operation_id == RENAME_AFTER_OCCUPANCY
            && renamed.receipt.disposition == CommandDisposition::Applied,
        "the non-identity rename after occupancy must commit"
    );
    ensure!(
        renamed_bot.name == "observe-bot-q-occupied"
            && renamed_bot.project_id == project_q
            && renamed_bot.config_revision == revision_current + 1,
        "the rename reply must show the requested name on Q at the next revision, got name={} project={} cfgrev={}",
        renamed_bot.name,
        renamed_bot.project_id,
        renamed_bot.config_revision
    );
    let revision_after_rename = renamed_bot.config_revision;
    let retry_after_rename_request = CreateBotConversationThreadRequest {
        operation_id: CREATE_OPERATION.into(),
        bot_id: bot_id.clone(),
        chat_id: CHAT_ID.into(),
        expected_config_revision: revision_after_rename,
        expected_binding_revision: 0,
    };
    let retry_after_rename = create_thread(
        session,
        deadline,
        "the retry after the rename",
        &retry_after_rename_request,
    )
    .await
    .map_err(|error| anyhow::anyhow!("retry-after-rename request failed: {error:#}"))?
    .map_err(|error| {
        anyhow::anyhow!(
            "retry after non-identity rename failed: {} ({:?})",
            crate::env::redact(&error.message),
            error.code
        )
    })?;
    ensure_retry_reused(
        &retry_after_rename,
        &bot_id,
        &project_q,
        &thread_id,
        "retry after rename",
    )?;
    assert_creation_identity(
        session,
        &bot_id,
        &thread_id,
        &expected_creation,
        "after rename retry",
    )
    .await?;
    let threads_final = list_thread_facts(session).await?;
    ensure!(
        threads_final == threads_after_first,
        "retries must not create any additional Thread"
    );
    assert_canonical_binding(session, &bot_id, &thread_id, &project_q).await?;
    assert_no_inbound_or_model(session, &bot_id, "C").await?;
    evidence.push(format!(
        "C: same operationId retried twice (plain and after the rename at cfgrev {revision_after_rename}) reused thread={thread_id} with the same durable creation identity; the canonical conversation page shows that binding"
    ));

    let platform = session.control()?.snapshot_report().await;
    let chat_lists = accepted_calls(&platform.calls, CallKind::ChatList);
    let tenant_tokens = accepted_calls(&platform.calls, CallKind::TenantToken);
    ensure!(
        platform.ws_connections == 0,
        "no platform WebSocket may be connected in this scenario, got {}",
        platform.ws_connections
    );
    evidence.push(format!(
        "platform calls: chatList={chat_lists} tenantToken={tenant_tokens} (allowed), model=0, messageSend=0, ws={}",
        platform.ws_connections
    ));

    let mut result = report::passed(
        CASE,
        format!(
            "the stale creation was suspended in its pre-write directory verification, the project switch committed P -> Q during that window, and the released creation was rejected as Conflict with no durable writes; the first public creation actively published occupancy (canChangeProject=false, cfgrev unchanged, watermark advanced, no state read-back) and bound exactly one Thread on Q; same-operation retries, including after a rename at the actual next revision, reused the same creation (thread={thread_id})"
        ),
    );
    result.evidence = evidence.clone();
    Ok(result)
}

/// Scene-local first save: one **disabled** bot on project P. No platform
/// connection is started, so no WebSocket, reconnect, or connection-driven
/// publication can appear later in this scenario.
async fn save_disabled_bot(session: &Session, deadline: &Deadline) -> Result<(String, String)> {
    deadline.checkpoint("the first project open")?;
    let project = session
        .http()?
        .open_project(&session.project.to_string_lossy())
        .await?;
    // Two separate RPCs: the project open above and the bot save below, so the
    // first gate cannot cover the second request.
    deadline.checkpoint("the first bot save")?;
    let reply = session
        .http()?
        .save_bot(&SaveBotRequest {
            model_route: None,
            operation_id: "op-obo-save-disabled".into(),
            bot_id: None,
            expected_config_revision: 0,
            name: "observe-bot".into(),
            project_id: project.id.clone(),
            app_id: DEFAULT_APP_ID.into(),
            secret: BotSecretUpdate::Replace {
                value: DEFAULT_APP_SECRET.into(),
            },
            enabled: false,
            tools_enabled: false,
        })
        .await?;
    ensure!(
        reply.receipt.disposition == CommandDisposition::Applied,
        "the first save must apply, got {:?}",
        reply.receipt.disposition
    );
    let bot = reply
        .bot
        .as_ref()
        .filter(|bot| bot.app_id == DEFAULT_APP_ID)
        .context("saveBot did not publish the synthetic bot")?;
    ensure!(
        !bot.enabled && matches!(bot.connection, BotConnectionState::Disabled),
        "the observation bot must be disabled without a platform connection, got enabled={} connection={}",
        bot.enabled,
        crate::topic::redact_connection(&bot.connection)
    );
    match bot.credential {
        BotCredentialAvailability::SessionOnly | BotCredentialAvailability::Stored => {}
        BotCredentialAvailability::Missing => bail!("bot secret was not leased or stored"),
        BotCredentialAvailability::Unavailable => {
            bail!("bot credential store is unavailable and needs retry")
        }
    }
    Ok((bot.id.clone(), project.id))
}

/// One owner configuration save on an existing bot: same app and secret, the
/// project may change, and the bot stays disabled exactly as first saved.
async fn save_owned(
    session: &Session,
    deadline: &Deadline,
    operation_id: &str,
    bot_id: &str,
    expected_config_revision: u64,
    name: &str,
    project_id: &str,
) -> Result<BotsCommandReply> {
    deadline.checkpoint(&format!("the {operation_id} save"))?;
    session
        .http()?
        .save_bot(&SaveBotRequest {
            model_route: None,
            operation_id: operation_id.into(),
            bot_id: Some(bot_id.to_owned()),
            expected_config_revision,
            name: name.into(),
            project_id: project_id.to_owned(),
            app_id: DEFAULT_APP_ID.into(),
            secret: BotSecretUpdate::Preserve,
            enabled: false,
            tools_enabled: false,
        })
        .await
}

/// One conversational-Thread creation behind the shared deadline gate, so the
/// gate and the command stay adjacent by construction. The suspended-creation
/// window in A needs the un-awaited future and keeps its own explicit gate.
async fn create_thread(
    session: &Session,
    deadline: &Deadline,
    phase: &str,
    request: &CreateBotConversationThreadRequest,
) -> Result<std::result::Result<BotConversationThreadReply, StudioError>> {
    deadline.checkpoint(phase)?;
    session.http()?.create_conversation_thread(request).await
}

/// The bot as published by a command reply's canonical snapshot.
fn saved_bot<'a>(
    reply: &'a BotsCommandReply,
    bot_id: &str,
    phase: &str,
) -> Result<&'a BotSnapshot> {
    reply
        .bot
        .as_ref()
        .filter(|bot| bot.id == bot_id)
        .with_context(|| format!("{phase}: bot {bot_id} missing from the reply snapshot"))
}

fn accepted_calls(calls: &[RecordedCall], kind: CallKind) -> usize {
    calls
        .iter()
        .filter(|call| call.kind == Some(kind) && call.accepted)
        .count()
}

/// Real peer counter used as the suspended-window proof: the accepted directory
/// request is recorded before its response waits for the release.
async fn chat_list_accepted(session: &Session, baseline: usize) -> Result<bool> {
    Ok(accepted_calls(
        &session.control()?.snapshot_report().await.calls,
        CallKind::ChatList,
    ) > baseline)
}

type CreationOutcome = std::result::Result<BotConversationThreadReply, StudioError>;

/// Production creation identity derived from the accepted request, exactly as
/// the runtime composes it; observations compare the durable rows against it
/// instead of trusting Thread equality alone.
fn expected_creation_id(bot_id: &str) -> String {
    format!("botthread:{bot_id}:{CHAT_ID}:{CREATE_OPERATION}")
}

/// Releases the suspended directory response and drains the *same* request
/// future to its real terminal, so a failed phase never leaves the server
/// handler waiting. Returns a cleanup note only when the drain itself did not
/// reach a terminal.
async fn release_and_drain<F>(
    session: &Session,
    request: &mut std::pin::Pin<&mut F>,
) -> Option<String>
where
    F: std::future::Future<Output = Result<CreationOutcome>>,
{
    if let Ok(control) = session.control() {
        control.release_chat_list().await;
    }
    match tokio::time::timeout(DRAIN_BUDGET, request.as_mut()).await {
        Ok(Ok(_)) => None,
        Ok(Err(error)) => Some(format!("drained request reported: {error:#}")),
        Err(_) => Some("draining the suspended creation exceeded its budget".to_string()),
    }
}

fn drain_error(error: anyhow::Error, cleanup: Option<String>) -> anyhow::Error {
    match cleanup {
        Some(note) => error.context(format!("parked creation cleanup: {note}")),
        None => error,
    }
}

fn describe_creation_outcome(outcome: &Result<CreationOutcome>) -> String {
    match outcome {
        Ok(Ok(reply)) => format!("accepted with disposition={:?}", reply.receipt.disposition),
        Ok(Err(error)) => format!(
            "rejected {:?} {}",
            error.code,
            crate::env::redact(&error.message)
        ),
        Err(error) => format!("transport error {error:#}"),
    }
}

fn ensure_retry_reused(
    reply: &BotConversationThreadReply,
    bot_id: &str,
    project_id: &str,
    thread_id: &str,
    phase: &str,
) -> Result<()> {
    ensure!(
        reply.receipt.disposition == CommandDisposition::NoChange,
        "{phase}: the persisted operation must replay as NoChange, got {:?}",
        reply.receipt.disposition
    );
    ensure!(
        reply.receipt.operation_id == CREATE_OPERATION,
        "{phase}: the replay must echo the original operation id, got {:?}",
        reply.receipt.operation_id
    );
    ensure!(
        reply.binding.state == BotConversationThreadState::Bound
            && reply.binding.bot_id == bot_id
            && reply.binding.chat_id == CHAT_ID
            && reply.binding.project_id == project_id
            && reply.binding.thread_id.as_deref() == Some(thread_id)
            && reply.binding.revision == 1,
        "{phase}: the replayed binding must keep the original bot/chat/project, Thread and revision"
    );
    Ok(())
}

/// Read-only durable identity check: exactly one bound row and one accepted
/// operation, both carrying the production creation identity of this request,
/// pointing at the same Thread with the original binding revision.
async fn assert_creation_identity(
    session: &Session,
    bot_id: &str,
    thread_id: &str,
    expected_creation: &str,
    phase: &str,
) -> Result<()> {
    let bindings = crate::sqlite::thread_bindings(&session.home, bot_id).await?;
    ensure!(
        bindings.len() == 1,
        "{phase}: exactly one binding row must exist, got {}",
        bindings.len()
    );
    ensure!(
        bindings[0].chat_id == CHAT_ID
            && bindings[0].thread_id == thread_id
            && bindings[0].status == "bound",
        "{phase}: the durable binding must stay bound on the created Thread"
    );
    let operations = crate::sqlite::binding_operations(&session.home, bot_id).await?;
    ensure!(
        operations.len() == 1,
        "{phase}: exactly one binding operation row must exist, got {}",
        operations.len()
    );
    ensure!(
        operations[0].operation_id == CREATE_OPERATION
            && operations[0].chat_id == CHAT_ID
            && operations[0].thread_id == thread_id
            && operations[0].expected_revision == 0,
        "{phase}: the accepted operation must keep the original request identity"
    );
    ensure!(
        bindings[0].creation_id == expected_creation,
        "{phase}: the durable binding must keep the production creation identity (got `{}`)",
        bindings[0].creation_id
    );
    ensure!(
        operations[0].creation_id == expected_creation,
        "{phase}: the accepted operation must keep the production creation identity (got `{}`)",
        operations[0].creation_id
    );
    ensure!(
        bindings[0].creation_id == operations[0].creation_id,
        "{phase}: the binding and the accepted operation must agree on the creation identity"
    );
    Ok(())
}

/// The stale creation must be rejected before its first write. All three facts
/// are reported together so a red run shows exactly what the old build wrote.
async fn assert_stale_creation_left_nothing(
    session: &Session,
    bot_id: &str,
    baseline_threads: &BTreeSet<ThreadFact>,
) -> Result<()> {
    let bindings = crate::sqlite::thread_bindings(&session.home, bot_id).await?;
    let operations = crate::sqlite::binding_operations(&session.home, bot_id).await?;
    let threads = list_thread_facts(session).await?;
    let added: Vec<String> = threads
        .difference(baseline_threads)
        .map(|fact| format!("{}@{}", fact.id, fact.project_id))
        .collect();
    ensure!(
        bindings.is_empty() && operations.is_empty() && added.is_empty(),
        "the stale creation must be rejected before its first write: thread_bindings={} \
         binding_operations={} newThreads={added:?}",
        bindings.len(),
        operations.len()
    );
    assert_no_inbound_or_model_ledger(session, bot_id, "after stale rejection").await
}

/// No durable occupancy facts exist yet (or must not exist after the stale
/// rejection): bindings, creation identities, inbound work and DM observation
/// all stay empty.
async fn assert_no_occupancy_facts(session: &Session, bot_id: &str, phase: &str) -> Result<()> {
    let bindings = crate::sqlite::thread_bindings(&session.home, bot_id).await?;
    ensure!(
        bindings.is_empty(),
        "{phase}: thread_bindings must stay empty, got {}",
        bindings.len()
    );
    let operations = crate::sqlite::binding_operations(&session.home, bot_id).await?;
    ensure!(
        operations.is_empty(),
        "{phase}: binding_operations must stay empty, got {}",
        operations.len()
    );
    assert_no_inbound_or_model_ledger(session, bot_id, phase).await
}

/// Inbound work and DM observation stay empty; this is the part that must also
/// hold after a successful creation.
async fn assert_no_inbound_or_model_ledger(
    session: &Session,
    bot_id: &str,
    phase: &str,
) -> Result<()> {
    let inbound = crate::sqlite::inbound(&session.home, bot_id).await?;
    ensure!(
        inbound.is_empty(),
        "{phase}: no inbound work may exist in this scenario, got {}",
        inbound.len()
    );
    let directs = crate::sqlite::observed_directs(&session.home, bot_id).await?;
    ensure!(
        directs.is_empty(),
        "{phase}: no DM observation may appear in this scenario, got {}",
        directs.len()
    );
    Ok(())
}

async fn assert_no_inbound_or_model(session: &Session, bot_id: &str, phase: &str) -> Result<()> {
    assert_no_inbound_or_model_ledger(session, bot_id, phase).await?;
    // The model script for this scenario is empty, so even a rejected request
    // would be a product defect: count every recorded attempt, not only
    // accepted executions.
    let attempts = session
        .model
        .as_ref()
        .map(|model| model.recorded().len())
        .unwrap_or(0);
    ensure!(
        attempts == 0,
        "{phase}: no model request may reach the fixture in this scenario, got {attempts}"
    );
    let sends = session
        .control()?
        .snapshot_report()
        .await
        .calls
        .iter()
        .filter(|call| call.kind == Some(CallKind::MessageSend))
        .count();
    ensure!(
        sends == 0,
        "{phase}: no Feishu message send may happen in this scenario, got {sends}"
    );
    Ok(())
}

/// The canonical conversation projection the Client reads must show the same
/// bound Thread on the current project.
async fn assert_canonical_binding(
    session: &Session,
    bot_id: &str,
    thread_id: &str,
    project_id: &str,
) -> Result<()> {
    let page = session
        .http()?
        .list_conversations(&ListBotConversationsRequest {
            bot_id: bot_id.to_owned(),
            cursor: None,
            limit: Some(50),
        })
        .await?;
    let conversation = page
        .conversations
        .iter()
        .find(|conversation| conversation.chat_id == CHAT_ID)
        .with_context(|| "the bound group conversation is missing from the canonical page")?;
    let binding = conversation
        .thread_binding
        .as_ref()
        .with_context(|| "the canonical conversation exposes no Thread binding")?;
    ensure!(
        binding.state == BotConversationThreadState::Bound
            && binding.thread_id.as_deref() == Some(thread_id)
            && binding.project_id == project_id
            && binding.revision == 1,
        "the canonical conversation binding must stay Bound on {project_id} with revision 1"
    );
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct ThreadFact {
    id: String,
    project_id: String,
}

/// Public thread directory snapshot: id + owning project for every Thread.
async fn list_thread_facts(session: &Session) -> Result<BTreeSet<ThreadFact>> {
    let mut facts = BTreeSet::new();
    let mut cursor = None;
    loop {
        let page = session
            .http()?
            .list_threads_page(cursor.as_deref(), 50)
            .await
            .context("GET /api/v1/threads failed")?;
        let data = page
            .state
            .value()
            .context("thread directory page had no canonical value")?;
        for thread in &data.threads {
            facts.insert(ThreadFact {
                id: thread.id.clone(),
                project_id: thread.project_id.clone(),
            });
        }
        ensure!(
            facts.len() <= 200,
            "thread directory exceeded the observe page budget"
        );
        match &data.next_cursor {
            Some(next) if !next.is_empty() => cursor = Some(next.clone()),
            _ => break,
        }
    }
    Ok(facts)
}

/// Opens a second isolated git project (Q) through the public project API, in
/// the same isolated working root as project P.
async fn open_second_project(session: &Session, deadline: &Deadline) -> Result<String> {
    let root = session
        .home
        .parent()
        .context("isolated working root missing")?
        .to_path_buf();
    let project_q = root.join("project-q");
    // Each side effect is gated on its own: synchronous work still consumes the
    // absolute budget, so an earlier gate cannot cover a later action.
    deadline.checkpoint("creating the second project directory")?;
    std::fs::create_dir_all(&project_q)?;
    deadline.checkpoint("writing the second project README")?;
    std::fs::write(
        project_q.join("README.md"),
        "Isolated bots protocol observation (project Q).\n",
    )?;
    deadline.checkpoint("initializing the second project repository")?;
    let status = std::process::Command::new("git")
        .current_dir(&project_q)
        .args(["init", "-q"])
        .status()?;
    ensure!(
        status.success(),
        "could not initialize the isolated project Q"
    );
    // The repository exists now; registering it is a separate public RPC.
    deadline.checkpoint("registering the second project")?;
    let record = session
        .http()?
        .open_project(&project_q.to_string_lossy())
        .await?;
    Ok(record.id)
}

/// The model script for this scenario is deliberately empty: nothing here may
/// execute a model turn, and any attempt fails the strict fixture.
pub(crate) fn owner_binding_model_steps() -> Vec<pl_provider_fixture::Step> {
    Vec::new()
}
