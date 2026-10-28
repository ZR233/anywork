//! `conversation-frontend*`: the complete conversation frontend of one bot.
//!
//! Every case here owns the whole Session: a fresh isolated home, one saved and
//! trusted DM bot with **no seeded Thread binding and no manual enable**, a
//! private model script, and the independent Feishu peer. A verdict may only
//! come from public HTTP, read-only SQLite facts and the peer's ordered platform
//! observations; no product truncation, authorization or delivery helper is
//! imported, and the peer never builds a product timeline.
//!
//! Authority facts are read through the shared audience projection
//! (`ThreadSnapshot::audience`) and the per-item typed query
//! `bots.readThreadAudienceItems`. Both are product projections, so a case can
//! prove "eligible but not delivered" and "delivered exactly once" separately
//! instead of inferring either from the other.

mod artifact;
mod budget;
mod journey;
mod lifecycle;
mod receipts;

use super::Session;
use super::replies;
use crate::http;
use crate::report::{self, CaseResult};
use crate::sqlite;
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::{
    BotAudienceItemStatus, BotAudienceItemsRead, BotAuthorizationPhase, BotItemEligibility,
    BotPublicTextChannel, BotTextIntegrity, BotThreadSyncAction, ChangeBotThreadSyncReply,
    ChangeBotThreadSyncRequest, ReadThreadAudienceItemsRequest, SetBotTrustedUserRequest,
};
use pl_protocol::{
    BotAudienceStart, BotAuthorizationId, BotCurrentSync, BotSyncCas, BotThreadBindingPosition,
    ThreadAudience, ThreadContentField, ThreadItemState, ThreadTextChannel, TimelineLifecycle,
};
use pl_provider_fixture::ReplyStage;
use pl_provider_fixture::feishu::{
    CallKind, CardObservation, CardOperation, ChatType, DIRECT_CHAT_ID, SenderKind,
    TRUSTED_USER_OPEN_ID, text_event,
};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

pub(super) const CASE_JOURNEY: &str = "conversation-frontend";
pub(super) const CASE_BUDGET: &str = "conversation-frontend-budget";
pub(super) const CASE_ARTIFACT: &str = "conversation-frontend-artifact";
pub(super) const CASE_LIFECYCLE: &str = "conversation-frontend-lifecycle";

pub(super) const CASES: &[&str] = &[CASE_JOURNEY, CASE_BUDGET, CASE_ARTIFACT, CASE_LIFECYCLE];

/// Absolute observe budget of one frontend case. Phase waits stay on the shared
/// predicate budgets; this is only the outer bound.
const CASE_TIMEOUT: Duration = Duration::from_secs(720);

pub(super) fn model_steps(name: &str) -> Vec<pl_provider_fixture::Step> {
    match name {
        CASE_JOURNEY => journey::journey_model_steps(),
        CASE_BUDGET => budget::budget_model_steps(),
        CASE_ARTIFACT => artifact::artifact_model_steps(),
        CASE_LIFECYCLE => lifecycle::lifecycle_model_steps(),
        _ => Vec::new(),
    }
}

pub(super) async fn run(session: &mut Session, name: &'static str) -> Result<CaseResult> {
    let mut evidence = Vec::new();
    let outcome = tokio::time::timeout(CASE_TIMEOUT, async {
        match name {
            CASE_JOURNEY => journey::journey(session, &mut evidence).await,
            CASE_BUDGET => budget::budget(session, &mut evidence).await,
            CASE_ARTIFACT => artifact::artifact(session, &mut evidence).await,
            CASE_LIFECYCLE => lifecycle::lifecycle(session, &mut evidence).await,
            other => bail!("unknown conversation-frontend case {other}"),
        }
    })
    .await;
    // Strict peer/model evidence is preserved even for a red phase: the run
    // reports what the platform really received, not only the failing assert.
    let capture = capture(session, name).await;
    let mut result = match outcome {
        Ok(Ok(detail)) => report::passed(name, detail),
        Ok(Err(error)) => report::failed(name, format!("{error:#}")),
        Err(_) => report::failed(name, format!("{name} exceeded its absolute observe budget")),
    };
    if let Err(error) = capture {
        result = report::failed(
            name,
            format!("{}; evidence capture: {error:#}", result.detail),
        );
    }
    result.evidence = evidence;
    Ok(result)
}

async fn capture(session: &Session, name: &str) -> Result<()> {
    let stem = name.replace('-', "_");
    if let Some(model) = session.model.as_ref() {
        super::files::write_json(
            session,
            &format!("{stem}-model-requests.json"),
            &model.recorded(),
        )?;
        super::files::write_json(
            session,
            &format!("{stem}-model-status.json"),
            &model.live_status(),
        )?;
    }
    super::files::write_json(
        session,
        &format!("{stem}-feishu-facts.json"),
        &session.control()?.snapshot_report().await,
    )?;
    Ok(())
}

// ---------------------------------------------------------------------------
// First binding, authorization start and audience projection
// ---------------------------------------------------------------------------

/// The saved, trusted DM bot of one fresh home.
///
/// Only ordinary configuration is written here: the bot is saved (already
/// enabled) and the fixture user is trusted. Creating a conversation Thread or
/// toggling `enabled` would bypass the automatic first initialization this case
/// exists to observe, so neither happens.
pub(super) async fn prepare_bot(session: &Session) -> Result<(String, String)> {
    prepare_bot_with(session, None).await
}

/// The same preparation for a case whose static script must name the bot.
///
/// The identity is created through the ordinary `saveBot` request; no binding,
/// no manual enable and no audience fact is seeded.
pub(super) async fn prepare_bot_with_id(
    session: &Session,
    bot_id: &str,
) -> Result<(String, String)> {
    prepare_bot_with(session, Some(bot_id)).await
}

async fn prepare_bot_with(
    session: &Session,
    requested_bot_id: Option<&str>,
) -> Result<(String, String)> {
    let (bot_id, project_id) = match requested_bot_id {
        Some(expected) => session.save_manual_bot_with_id(false, expected).await?,
        None => session.save_manual_bot(false).await?,
    };
    ensure!(
        !session.bot(&bot_id).await?.tools_enabled,
        "the frontend journey must run with toolsEnabled=false"
    );
    let snapshot = session.bot(&bot_id).await?;
    if !snapshot
        .trusted_open_ids
        .iter()
        .any(|id| id == TRUSTED_USER_OPEN_ID)
    {
        session
            .http()?
            .set_trusted_user(&SetBotTrustedUserRequest {
                operation_id: "frontend-trust-user".into(),
                bot_id: bot_id.clone(),
                expected_config_revision: snapshot.config_revision,
                open_id: TRUSTED_USER_OPEN_ID.into(),
                trusted: true,
            })
            .await?;
    }
    session.wait_connected(&bot_id).await?;
    ensure!(
        sqlite::thread_bindings(&session.home, &bot_id)
            .await?
            .is_empty(),
        "a fresh frontend bot must own no seeded Thread binding"
    );
    ensure!(
        session.model_executions() == 0,
        "no model may run before the first platform input"
    );
    Ok((bot_id, project_id))
}

/// Sends one real inbound platform message and returns the Thread the product
/// created for it.
pub(super) async fn first_inbound(
    session: &Session,
    bot_id: &str,
    message_id: &str,
    text: &str,
) -> Result<String> {
    session
        .control()?
        .send_event(text_event(
            message_id,
            DIRECT_CHAT_ID,
            ChatType::P2p,
            SenderKind::User,
            TRUSTED_USER_OPEN_ID,
            text,
            Vec::new(),
        ))
        .await?;
    let thread_id = replies::wait_thread_binding(&session.home, bot_id, DIRECT_CHAT_ID).await?;
    let row = sqlite::thread_bindings(&session.home, bot_id)
        .await?
        .into_iter()
        .find(|row| row.chat_id == DIRECT_CHAT_ID)
        .context("the DM binding vanished after it appeared")?;
    replies::ensure_bound_row(&row)?;
    ensure!(
        !row.creation_id.trim().is_empty(),
        "the automatic creation must keep its immutable creation identity"
    );
    Ok(thread_id)
}

/// One active full-frontend authorization with its shared CAS and saved start.
#[derive(Debug, Clone)]
pub(super) struct Authorized {
    pub id: BotAuthorizationId,
    pub start: BotAudienceStart,
}

pub(super) async fn audience(session: &Session, thread_id: &str) -> Result<ThreadAudience> {
    Ok(session.http()?.read_thread(thread_id).await?.audience)
}

/// The current binding CAS and sync phase, whatever that phase is.
pub(super) async fn current_binding(
    session: &Session,
    thread_id: &str,
) -> Result<(BotSyncCas, BotCurrentSync)> {
    match audience(session, thread_id).await? {
        ThreadAudience::Known { audience } => match &audience.binding {
            BotThreadBindingPosition::Current { cas, sync } => {
                Ok((cas.clone(), sync.as_ref().clone()))
            }
            BotThreadBindingPosition::Replaced {
                last_binding_revision,
                current_binding_revision,
            } => bail!(
                "Thread {thread_id} is bound through a replaced revision ({last_binding_revision} -> {current_binding_revision})"
            ),
        },
        ThreadAudience::Unbound {} => bail!("Thread {thread_id} has no audience binding"),
        ThreadAudience::Unavailable { reason } => {
            bail!("Thread {thread_id} has an unavailable audience: {reason:?}")
        }
    }
}

/// Waits (bounded) for the binding projection of a Thread to become readable.
///
/// A freshly created replacement binding may be published a moment after the
/// creation receipt; the command needs the real CAS, so this waits for the
/// product's own projection instead of guessing one.
pub(super) async fn wait_known_binding(
    session: &Session,
    thread_id: &str,
) -> Result<(BotSyncCas, BotCurrentSync)> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        match current_binding(session, thread_id).await {
            Ok(found) => return Ok(found),
            Err(error) => {
                if Instant::now() >= deadline {
                    bail!(
                        "Thread {thread_id} never published a readable binding projection: {error:#}"
                    );
                }
            }
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// Waits for the first saved full-frontend start of the bound Thread.
///
/// The proof is the product's own projection: a `Known` audience whose binding
/// is current, whose sync state is `Active`, and whose saved start carries a
/// real commit sequence. A pending or unbound projection is a bounded wait; a
/// conflicting or unavailable one is reported as such instead of being retried
/// into a pass.
pub(super) async fn wait_authorized(session: &Session, thread_id: &str) -> Result<Authorized> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        match audience(session, thread_id).await? {
            ThreadAudience::Known { audience } => match &audience.binding {
                BotThreadBindingPosition::Current { sync, .. } => {
                    if let BotCurrentSync::Active { authorization } = sync.as_ref() {
                        ensure!(
                            authorization.authorization.id.chat_id == DIRECT_CHAT_ID
                                && !authorization.authorization.id.bot_id.is_empty(),
                            "the active authorization must belong to the bound DM target, got {:?}",
                            authorization.authorization.id
                        );
                        ensure!(
                            authorization.start.commit_sequence > 0,
                            "an active authorization must carry its saved start commit sequence"
                        );
                        return Ok(Authorized {
                            id: authorization.authorization.id.clone(),
                            start: authorization.start.clone(),
                        });
                    }
                    last = format!("binding is current but sync is {:?}", sync);
                }
                BotThreadBindingPosition::Replaced {
                    last_binding_revision,
                    current_binding_revision,
                } => {
                    last = format!(
                        "binding was replaced ({last_binding_revision} -> {current_binding_revision})"
                    )
                }
            },
            ThreadAudience::Unbound {} => last = "audience is Unbound".to_owned(),
            ThreadAudience::Unavailable { reason } => {
                last = format!("audience is unavailable: {reason:?}")
            }
        }
        if Instant::now() >= deadline {
            bail!(
                "Thread {thread_id} never reported an active full-frontend authorization: {last}"
            );
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// The canonical identity of the first Turn of one Thread.
///
/// Taken from the Turn item with the smallest ordinal, so a later Turn of the
/// same Thread can never stand in for the first execution.
pub(super) async fn first_turn_id(session: &Session, thread_id: &str) -> Result<String> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        let mut turns: Vec<(u64, String)> = session
            .http()?
            .timeline(thread_id)
            .await?
            .into_iter()
            .filter(|item| matches!(item.preview.state(), ThreadItemState::Turn(_)))
            .map(|item| (item.preview.ordinal, item.preview.turn_id))
            .collect();
        turns.sort();
        if let Some((_, turn_id)) = turns.first() {
            return Ok(turn_id.clone());
        }
        last = "the timeline has no canonical Turn item".to_owned();
        if Instant::now() >= deadline {
            bail!("Thread {thread_id} never exposed its first Turn item: {last}");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// Sends one explicit local audience command and returns the typed reply.
pub(super) async fn change_sync(
    session: &Session,
    thread_id: &str,
    expected: BotSyncCas,
    action: BotThreadSyncAction,
    operation_id: &str,
) -> Result<ChangeBotThreadSyncReply> {
    let reply = session
        .http()?
        .change_thread_sync(&ChangeBotThreadSyncRequest {
            operation_id: operation_id.to_owned(),
            thread_id: thread_id.to_owned(),
            expected,
            action,
        })
        .await?
        .map_err(|error| {
            anyhow::anyhow!(
                "audience command {action:?} was rejected: {:?}: {}",
                error.code,
                error.message
            )
        })?;
    ensure!(
        reply.thread_id == thread_id,
        "the audience command answered for another Thread"
    );
    Ok(reply)
}

/// Requires the projection to show exactly the expected sync phase.
pub(super) fn expect_sync(reply: &ChangeBotThreadSyncReply, label: &str) -> Result<BotCurrentSync> {
    match &reply.audience {
        ThreadAudience::Known { audience } => match &audience.binding {
            BotThreadBindingPosition::Current { sync, .. } => Ok(sync.as_ref().clone()),
            BotThreadBindingPosition::Replaced { .. } => {
                bail!(
                    "{label}: the current binding was replaced instead of reaching the requested phase"
                )
            }
        },
        ThreadAudience::Unbound {} => bail!("{label}: audience became Unbound"),
        ThreadAudience::Unavailable { reason } => {
            bail!("{label}: audience became unavailable: {reason:?}")
        }
    }
}

// ---------------------------------------------------------------------------
// Canonical public items
// ---------------------------------------------------------------------------

/// One public text item of the bound Thread, as the canonical timeline shows it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct PublicItem {
    pub id: String,
    pub ordinal: u64,
    pub revision: u64,
    pub channel: BotPublicTextChannel,
    pub text: String,
    pub saved: bool,
    pub terminal: bool,
    pub total_bytes: u64,
    pub omitted_bytes: u64,
}

pub(super) async fn public_items(session: &Session, thread_id: &str) -> Result<Vec<PublicItem>> {
    let mut items = Vec::new();
    for item in session.http()?.timeline(thread_id).await? {
        let ThreadItemState::Text(text) = item.preview.state() else {
            continue;
        };
        let channel = match text.channel() {
            ThreadTextChannel::Commentary => BotPublicTextChannel::Commentary,
            ThreadTextChannel::Final => BotPublicTextChannel::Final,
            // User/parent-agent input is not a public output item.
            ThreadTextChannel::User | ThreadTextChannel::ParentAgent => continue,
        };
        let total_bytes = item
            .details
            .iter()
            .find(|detail| detail.field == ThreadContentField::Text)
            .map_or(0, |detail| detail.total_bytes);
        items.push(PublicItem {
            id: item.preview.id.clone(),
            ordinal: item.preview.ordinal,
            revision: item.preview.revision,
            channel,
            text: text.text().to_owned(),
            saved: item.saved,
            terminal: item.lifecycle == TimelineLifecycle::Terminal,
            total_bytes,
            omitted_bytes: item.omitted_bytes,
        });
    }
    items.sort_by_key(|item| item.ordinal);
    Ok(items)
}

/// Waits until at least `min` public items exist and every one is saved.
pub(super) async fn wait_public_items(
    session: &Session,
    thread_id: &str,
    min: usize,
) -> Result<Vec<PublicItem>> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        match public_items(session, thread_id).await {
            Ok(items) => {
                if items.len() >= min && items.iter().all(|item| item.saved) {
                    return Ok(items);
                }
                last = format!(
                    "{} public items, saved flags {:?}",
                    items.len(),
                    items.iter().map(|item| item.saved).collect::<Vec<_>>()
                );
            }
            Err(error) => last = error.to_string(),
        }
        if Instant::now() >= deadline {
            bail!("Thread {thread_id} never reached {min} saved public items: {last}");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// The bounded per-item canonical + delivery query for one authorization.
pub(super) async fn audience_item_status(
    session: &Session,
    thread_id: &str,
    authorized: &Authorized,
    item_ids: &[String],
) -> Result<(BotAuthorizationPhase, Vec<BotAudienceItemStatus>)> {
    ensure!(
        !item_ids.is_empty() && item_ids.len() <= 100,
        "one per-item query covers 1..=100 identities"
    );
    let reply = session
        .http()?
        .read_thread_audience_items(&ReadThreadAudienceItemsRequest {
            thread_id: thread_id.to_owned(),
            authorization: authorized.id.clone(),
            item_ids: item_ids.to_vec(),
        })
        .await?
        .map_err(|error| {
            anyhow::anyhow!(
                "bots.readThreadAudienceItems was rejected: {:?}: {}",
                error.code,
                error.message
            )
        })?;
    ensure!(
        reply.thread_id == thread_id && reply.authorization == authorized.id,
        "the per-item query answered for another Thread or authorization"
    );
    match reply.result {
        BotAudienceItemsRead::Items { phase, items, .. } => {
            ensure!(
                items.len() == item_ids.len()
                    && items
                        .iter()
                        .zip(item_ids)
                        .all(|(status, id)| &status.item_id == id),
                "the per-item query must answer in request order with one item per identity"
            );
            Ok((phase, items))
        }
        BotAudienceItemsRead::Unavailable { reason } => {
            bail!("the per-item query is unavailable: {reason:?}")
        }
    }
}

/// Waits until every requested identity is present with saved, accepted text.
pub(super) async fn wait_accepted_items(
    session: &Session,
    thread_id: &str,
    authorized: &Authorized,
    items: &[PublicItem],
    integrity: BotTextIntegrity,
) -> Result<Vec<BotAudienceItemStatus>> {
    let ids: Vec<String> = items.iter().map(|item| item.id.clone()).collect();
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        match audience_item_status(session, thread_id, authorized, &ids).await {
            Ok((phase, statuses)) => {
                let complete = statuses.iter().zip(items).all(|(status, item)| {
                    let canonical = matches!(
                        &status.canonical,
                        pl_protocol::studio::BotAudienceCanonicalItem::Present {
                            revision,
                            saved: true,
                            eligibility: BotItemEligibility::Text { channel },
                        } if *revision == item.revision && *channel == item.channel
                    );
                    // The ledger must show this very revision as projected *and*
                    // accepted with the expected integrity; an older accepted
                    // revision or an Unknown platform result can never pass.
                    let delivery = matches!(
                        &status.delivery,
                        pl_protocol::studio::BotItemDelivery::Known { ledger }
                            if matches!(
                                &ledger.projected,
                                pl_protocol::studio::BotItemPresentation::Text {
                                    revision,
                                    integrity: seen,
                                    saved: true,
                                } if *revision == item.revision && *seen == integrity
                            )
                            && matches!(
                                &ledger.accepted,
                                pl_protocol::studio::BotItemPresentation::Text {
                                    revision,
                                    integrity: seen,
                                    saved: true,
                                } if *revision == item.revision && *seen == integrity
                            )
                            && matches!(
                                &ledger.platform,
                                pl_protocol::studio::BotItemPlatform::Card { latest_operation }
                                    if latest_operation.content_revision == item.revision
                                        && matches!(
                                            &latest_operation.result,
                                            pl_protocol::studio::BotPlatformResult::Accepted {}
                                        )
                            )
                    );
                    canonical && delivery
                });
                if complete && phase == BotAuthorizationPhase::Active {
                    return Ok(statuses);
                }
                last = format!("phase={phase:?} items={statuses:?}");
            }
            Err(error) => last = error.to_string(),
        }
        if Instant::now() >= deadline {
            bail!(
                "the per-item projection never reached saved/accepted {integrity:?} for {} items: {last}",
                items.len()
            );
        }
        tokio::time::sleep(http::POLL).await;
    }
}

// ---------------------------------------------------------------------------
// Independent platform facts
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct PlatformCounts {
    pub calls: usize,
    pub sends: usize,
    pub entities: usize,
    pub card_operations: usize,
    pub uploads: usize,
}

pub(super) async fn platform_counts(session: &Session) -> Result<PlatformCounts> {
    let report = session.control()?.snapshot_report().await;
    Ok(PlatformCounts {
        calls: report.calls.len(),
        sends: report
            .calls
            .iter()
            .filter(|call| {
                call.kind == Some(pl_provider_fixture::feishu::CallKind::MessageSend)
                    && call.accepted
                    && !call.deduplicated
            })
            .count(),
        entities: report.card_entities.len(),
        card_operations: report.cards.len(),
        uploads: report.uploads.len(),
    })
}

/// Waits (bounded) for one platform fact the caller can state precisely.
pub(super) async fn wait_counts(
    session: &Session,
    label: &str,
    mut ready: impl FnMut(PlatformCounts) -> bool,
) -> Result<PlatformCounts> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        let counts = platform_counts(session).await?;
        if ready(counts) {
            return Ok(counts);
        }
        last = counts;
        if Instant::now() >= deadline {
            bail!("{label} never became true; last platform counts {last:?}");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// All textual leaves of one serialized card entity, plus the primary markdown
/// body when the entity follows the documented JSON 2.0 shape.
///
/// The whole document is walked, so a host status element, a header or a second
/// element is audited too instead of only the selected body.
pub(super) fn entity_texts(entity_json: &str) -> Result<(Vec<String>, Option<String>)> {
    let value: serde_json::Value =
        serde_json::from_str(entity_json).context("card entity is not JSON")?;
    let mut all = Vec::new();
    let mut primary = None;
    collect_texts(&value, &mut all, &mut primary);
    Ok((all, primary))
}

fn collect_texts(value: &serde_json::Value, all: &mut Vec<String>, primary: &mut Option<String>) {
    match value {
        serde_json::Value::Object(map) => {
            if let Some(text) = map.get("content").and_then(serde_json::Value::as_str) {
                match map.get("tag").and_then(serde_json::Value::as_str) {
                    Some("markdown") | Some("lark_md") | Some("plain_text") => {
                        all.push(text.to_owned());
                        if primary.is_none()
                            && matches!(
                                map.get("tag").and_then(serde_json::Value::as_str),
                                Some("markdown")
                            )
                        {
                            *primary = Some(text.to_owned());
                        }
                    }
                    _ => {}
                }
            }
            for nested in map.values() {
                collect_texts(nested, all, primary);
            }
        }
        serde_json::Value::Array(items) => {
            for item in items {
                collect_texts(item, all, primary);
            }
        }
        _ => {}
    }
}

/// Scalars, not bytes, tokens or UTF-16 units: the documented display bound.
pub(super) fn scalars(text: &str) -> usize {
    text.chars().count()
}

/// One shared pool of explicit model stages for one case.
pub(super) fn stage_pool(
    cell: &'static OnceLock<Vec<ReplyStage>>,
    count: usize,
) -> &'static [ReplyStage] {
    cell.get_or_init(|| (0..count).map(|_| ReplyStage::new()).collect())
}

pub(super) fn gates(stages: &'static [ReplyStage]) -> Vec<&'static ReplyStage> {
    stages.iter().collect()
}

/// Waits for one stage to publish that its prefix was written.
pub(super) async fn wait_reached(stage: &ReplyStage, label: &str) -> Result<()> {
    tokio::time::timeout(http::PREDICATE_TIMEOUT, stage.wait_reached())
        .await
        .with_context(|| format!("the model fixture never wrote the {label} prefix"))?;
    Ok(())
}

/// A Thread directory entry used to prove "another session never broadcasts".
pub(super) async fn wait_idle(session: &Session, thread_id: &str) -> Result<()> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        if session
            .http()?
            .thread(thread_id)
            .await?
            .active_turn
            .is_none()
        {
            return Ok(());
        }
        if Instant::now() >= deadline {
            bail!("Thread {thread_id} never returned to idle");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// Fails when any delivered payload carries one of the hidden markers.
pub(super) async fn assert_not_delivered(
    session: &Session,
    phase: &str,
    markers: &[&str],
) -> Result<()> {
    replies::assert_no_hidden_markers(session, phase, markers).await
}

/// Every accepted platform message send recorded by the independent peer.
pub(super) async fn accepted_sends(
    session: &Session,
) -> Result<Vec<pl_provider_fixture::feishu::RecordedCall>> {
    let report = session.control()?.snapshot_report().await;
    Ok(report
        .calls
        .into_iter()
        .filter(|call| {
            call.kind == Some(pl_provider_fixture::feishu::CallKind::MessageSend) && call.accepted
        })
        .collect())
}

/// One accepted platform card message, tied to the card entity it carries.
pub(super) struct CardSend {
    pub message_id: String,
    pub chat_id: String,
}

/// Waits until the card entity behind `card_id` really has an accepted message.
///
/// A CardKit answer alone is not delivery: the entity must hold a non-empty
/// platform message id, and the peer must hold the matching accepted
/// `MessageSend` for that same card, addressed to the bound direct chat and
/// shaped as an interactive card message. The wait uses the shared predicate
/// budget and never advances a scripted stage by itself.
pub(super) async fn wait_card_message_sent(session: &Session, card_id: &str) -> Result<CardSend> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last = format!("card {card_id} has no platform message yet");
    loop {
        let report = session.control()?.snapshot_report().await;
        let sent = report
            .card_entities
            .iter()
            .find(|entity| entity.card_id == card_id)
            .and_then(|entity| entity.sent_message_id.as_deref())
            .filter(|id| !id.is_empty())
            .map(ToOwned::to_owned);
        if let Some(message_id) = sent {
            if let Some(call) = report.calls.iter().find(|call| {
                call.kind == Some(CallKind::MessageSend)
                    && call.accepted
                    && call.card_id.as_deref() == Some(card_id)
                    && call.assigned_message_id.as_deref() == Some(message_id.as_str())
            }) {
                let chat_id = call
                    .send_body
                    .as_ref()
                    .and_then(|body| body.get("receive_id"))
                    .and_then(serde_json::Value::as_str)
                    .context("an accepted card message must keep its real chat target")?
                    .to_owned();
                ensure!(
                    chat_id == DIRECT_CHAT_ID,
                    "card {card_id} was sent to {chat_id} instead of the bound direct chat {DIRECT_CHAT_ID}"
                );
                ensure!(
                    call.msg_type.as_deref() == Some("interactive"),
                    "card {card_id} must be delivered as an interactive card message, got {:?}",
                    call.msg_type
                );
                return Ok(CardSend {
                    message_id,
                    chat_id,
                });
            }
            last = format!(
                "card {card_id} holds message {message_id} but no accepted MessageSend call matches that identity"
            );
        }
        if Instant::now() >= deadline {
            bail!(
                "card {card_id} never reached an accepted platform message within {}s: {last}",
                http::PREDICATE_TIMEOUT.as_secs()
            );
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// The complete ordered CardKit operation identity history of one session.
///
/// A no-write stage must be proven on this whole history, not only on entity or
/// message counts: a late element update or a settings close leaves every count
/// unchanged while still writing to the platform.
pub(super) type CardOperationIdentities = Vec<(
    usize,
    CardOperation,
    String,
    Option<i64>,
    Option<String>,
    bool,
)>;

pub(super) fn card_operation_identities(
    observations: &[CardObservation],
) -> CardOperationIdentities {
    observations
        .iter()
        .map(|item| {
            (
                item.ordinal,
                item.operation,
                item.card_id.clone(),
                item.sequence,
                item.uuid.clone(),
                item.accepted,
            )
        })
        .collect()
}

pub(super) async fn card_operations_snapshot(session: &Session) -> Result<CardOperationIdentities> {
    Ok(card_operation_identities(
        &session.control()?.card_observations().await,
    ))
}

/// Path of the execution workspace the bot really owns.
pub(super) async fn workspace(session: &Session, bot_id: &str) -> Result<std::path::PathBuf> {
    Ok(std::path::PathBuf::from(
        session.bot(bot_id).await?.workspace_path,
    ))
}

/// Reads the raw bytes of one saved public artifact through the public port.
pub(super) async fn artifact_bytes(
    session: &Session,
    thread_id: &str,
    resource_id: &str,
) -> Result<Vec<u8>> {
    session
        .http()?
        .attachment_bytes(thread_id, resource_id)
        .await
}

/// Digest oracle used by the artifact journey.
pub(super) fn sha256(bytes: &[u8]) -> String {
    pl_provider_fixture::bots_observe::sha256(bytes)
}
