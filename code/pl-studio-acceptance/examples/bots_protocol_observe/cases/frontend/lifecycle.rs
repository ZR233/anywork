//! `conversation-frontend-lifecycle`: audience control and recovery.
//!
//! Pause keeps the audience and the obligation to catch up after an explicit
//! resume on the same generation. Close, disable, trust revocation and binding
//! replacement forbid every new platform write of the old generation - including
//! a late card settings close, an upload or an extra message - while a request
//! that already started keeps its own result and operation identity. A restart
//! never replays an unconfirmed operation or re-executes the input.
//!
//! The model script only streams real public items; every authority change comes
//! from the public local command or the ordinary configuration endpoints.

use super::super::Session;
use super::super::replies::optional_title_step;
use super::{
    Authorized, assert_not_delivered, audience, card_operations_snapshot, change_sync,
    current_binding, expect_sync, first_inbound, platform_counts, prepare_bot, public_items,
    stage_pool, wait_accepted_items, wait_authorized, wait_counts, wait_idle, wait_known_binding,
    wait_public_items, wait_reached,
};
use crate::http;
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::{
    BotAudienceItemStatus, BotAuthorizationPhase, BotConversationThreadReply, BotItemDelivery,
    BotItemPlatform, BotPlatformResult, BotTextIntegrity, BotThreadSyncAction,
    BotThreadSyncCommandState, CreateBotConversationThreadRequest,
    ReadThreadClosedAuthorizationsRequest, SetBotEnabledRequest, SetBotTrustedUserRequest,
    StudioPromptInput, ThreadClosedAuthorizationsRead,
};
use pl_protocol::{BotAudienceCloseReason, BotClosedStart, BotCurrentSync};
use pl_provider_fixture::feishu::{
    CardDisposition, CardObservation, CardOperation, ChatType, DIRECT_CHAT_ID, SenderKind,
    TRUSTED_USER_OPEN_ID, text_event,
};
use pl_provider_fixture::{Protocol, Reply, ReplyStage, Step, responses_public_items_segments};
use std::sync::OnceLock;
use std::time::Instant;

const THINKING_LINES: [&str; 1] = ["FRONTEND_LIFECYCLE_THINKING internal line"];
const THINKING_MARKER: &str = "FRONTEND_LIFECYCLE_THINKING";
const USER_MARKER: &str = "FRONTEND_LIFECYCLE_USER_TEXT";

const PROMPT_START: &str =
    "Conversation frontend fixture: lifecycle first request FRONTEND_LIFECYCLE_USER_TEXT";
const PROMPT_PAUSE: &str = "Conversation frontend fixture: withheld while paused";
const PROMPT_CLOSE: &str = "Conversation frontend fixture: close during the open Turn";
const PROMPT_DISABLED: &str = "Conversation frontend fixture: disable during the open Turn";
const PROMPT_REVOKED: &str = "Conversation frontend fixture: revoke during the open Turn";
const PROMPT_UNKNOWN: &str = "Conversation frontend fixture: unconfirmed platform write";
const PROMPT_REPLACED_NEW: &str = "Conversation frontend fixture: replacement Thread public answer";
const PROMPT_REPLACED_OLD: &str = "Conversation frontend fixture: replaced Thread local answer";

const MESSAGE_START: &str = "om_frontend_lifecycle_first";
const MESSAGE_REPLACED_NEW: &str = "om_frontend_lifecycle_replacement";

const START_COMMENTARY: &str = "FRONTEND_LIFECYCLE_START_COMMENTARY 起始进展。";
const START_FINAL: &str = "FRONTEND_LIFECYCLE_START_FINAL 起始答复。";
const PAUSE_COMMENTARY: &str = "FRONTEND_LIFECYCLE_PAUSE_COMMENTARY 暂停期间产生的进展。";
const PAUSE_FINAL: &str = "FRONTEND_LIFECYCLE_PAUSE_FINAL 暂停期间产生的答复。";
const CLOSE_COMMENTARY: &str = "FRONTEND_LIFECYCLE_CLOSE_COMMENTARY 关闭前已接受的进展。";
const CLOSE_FINAL: &str = "FRONTEND_LIFECYCLE_CLOSE_FINAL 关闭后不得外发的答复。";
const DISABLED_COMMENTARY: &str = "FRONTEND_LIFECYCLE_DISABLED_COMMENTARY 停用前已接受的进展。";
const DISABLED_FINAL: &str = "FRONTEND_LIFECYCLE_DISABLED_FINAL 停用后不得外发的答复。";
const REVOKED_COMMENTARY: &str = "FRONTEND_LIFECYCLE_REVOKED_COMMENTARY 撤权前已接受的进展。";
const REVOKED_FINAL: &str = "FRONTEND_LIFECYCLE_REVOKED_FINAL 撤权后不得外发的答复。";
const UNKNOWN_COMMENTARY: &str = "FRONTEND_LIFECYCLE_UNKNOWN_COMMENTARY 未确认写入前的进展。";
const UNKNOWN_FINAL: &str = "FRONTEND_LIFECYCLE_UNKNOWN_FINAL 未确认写入的答复。";
const NEW_COMMENTARY: &str = "FRONTEND_LIFECYCLE_NEW_COMMENTARY 替换后新代的公开进展。";
const NEW_FINAL: &str = "FRONTEND_LIFECYCLE_NEW_FINAL 替换后新代的公开答复。";
const OLD_COMMENTARY: &str = "FRONTEND_LIFECYCLE_OLD_COMMENTARY 旧代关闭后的本机进展。";
const OLD_FINAL: &str = "FRONTEND_LIFECYCLE_OLD_FINAL 旧代关闭后的本机答复。";

/// Recovery sweeps of the frozen scheduler before a cold fact is re-asserted.
const RESTART_QUIET: std::time::Duration = std::time::Duration::from_secs(14);

static STAGES: OnceLock<Vec<ReplyStage>> = OnceLock::new();

fn stages() -> &'static [ReplyStage] {
    stage_pool(&STAGES, 4)
}

/// One gated attempt: `split` segments are written before the gate, the rest
/// after the case releases it. A wrong split is a hard failure here.
fn gated_turn(
    commentary: &str,
    final_text: &str,
    id: &str,
    stage: &'static ReplyStage,
    split: usize,
) -> Reply {
    let segments = responses_public_items_segments(
        &THINKING_LINES,
        &[("frontend-lifecycle-commentary", commentary)],
        final_text,
        "",
        &[],
        id,
        "fixture-model",
    );
    assert!(
        split > 0 && split < segments.len(),
        "a gated turn needs a split inside its segments"
    );
    let mut before = Vec::new();
    let mut after = Vec::new();
    for (index, segment) in segments.into_iter().enumerate() {
        if index < split {
            before.extend(segment);
        } else {
            after.extend(segment);
        }
    }
    stage.gated(before, after)
}

fn plain_turn(commentary: &str, final_text: &str, id: &str) -> Reply {
    let segments = responses_public_items_segments(
        &THINKING_LINES,
        &[("frontend-lifecycle-commentary", commentary)],
        final_text,
        "",
        &[],
        id,
        "fixture-model",
    );
    Reply::Sse(segments.concat())
}

pub(super) fn lifecycle_model_steps() -> Vec<Step> {
    let gated = stages();
    vec![
        optional_title_step(0, PROMPT_START),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_START,
            1,
            plain_turn(START_COMMENTARY, START_FINAL, "frontend-lifecycle-start"),
        ),
        optional_title_step(2, PROMPT_PAUSE),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_PAUSE,
            3,
            // Split after the reasoning prefix: no public item exists yet, so a
            // pause really has to withhold every following card.
            gated_turn(
                PAUSE_COMMENTARY,
                PAUSE_FINAL,
                "frontend-lifecycle-pause",
                &gated[0],
                1,
            ),
        ),
        optional_title_step(4, PROMPT_CLOSE),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_CLOSE,
            5,
            // Split after the commentary: its card is already accepted, so the
            // close must stop the tail without a late settings close.
            gated_turn(
                CLOSE_COMMENTARY,
                CLOSE_FINAL,
                "frontend-lifecycle-close",
                &gated[1],
                2,
            ),
        ),
        optional_title_step(6, PROMPT_DISABLED),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_DISABLED,
            7,
            gated_turn(
                DISABLED_COMMENTARY,
                DISABLED_FINAL,
                "frontend-lifecycle-disabled",
                &gated[2],
                2,
            ),
        ),
        optional_title_step(8, PROMPT_REVOKED),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_REVOKED,
            9,
            gated_turn(
                REVOKED_COMMENTARY,
                REVOKED_FINAL,
                "frontend-lifecycle-revoked",
                &gated[3],
                2,
            ),
        ),
        optional_title_step(10, PROMPT_UNKNOWN),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_UNKNOWN,
            11,
            plain_turn(
                UNKNOWN_COMMENTARY,
                UNKNOWN_FINAL,
                "frontend-lifecycle-unknown",
            ),
        ),
        // Replacement journey: the new range must publish a real item, and the
        // replaced range must only execute locally afterwards.
        optional_title_step(12, PROMPT_REPLACED_NEW),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_REPLACED_NEW,
            13,
            plain_turn(
                NEW_COMMENTARY,
                NEW_FINAL,
                "frontend-lifecycle-replacement-new",
            ),
        ),
        optional_title_step(14, PROMPT_REPLACED_OLD),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_REPLACED_OLD,
            15,
            plain_turn(
                OLD_COMMENTARY,
                OLD_FINAL,
                "frontend-lifecycle-replacement-old",
            ),
        ),
    ]
}

pub(super) async fn lifecycle(session: &mut Session, evidence: &mut Vec<String>) -> Result<String> {
    let (bot_id, _) = prepare_bot(session).await?;
    let before = platform_counts(session).await?;
    let thread_id = first_inbound(session, &bot_id, MESSAGE_START, PROMPT_START).await?;
    let mut authorized = wait_authorized(session, &thread_id).await?;
    wait_idle(session, &thread_id).await?;
    wait_public_items(session, &thread_id, 2).await?;
    let delivered = wait_counts(session, "the first two public cards", |counts| {
        counts.entities == before.entities + 2 && counts.sends == before.sends + 2
    })
    .await?;
    assert_not_delivered(
        session,
        "the lifecycle journey",
        &[THINKING_MARKER, USER_MARKER],
    )
    .await?;
    evidence.push(format!(
        "phase 1: generation {} delivered two public cards ({} entities, {} sends)",
        authorized.id.generation, delivered.entities, delivered.sends
    ));

    // ---- Phase 2: pause withholds, resume catches up on the same generation --
    submit_local(session, &thread_id, "lifecycle-pause-input", PROMPT_PAUSE).await?;
    wait_reached(&stages()[0], "pause turn reasoning").await?;
    let (cas, _) = current_binding(session, &thread_id).await?;
    let paused = change_sync(
        session,
        &thread_id,
        cas,
        BotThreadSyncAction::Pause,
        "frontend-pause",
    )
    .await?;
    ensure!(
        matches!(&paused.state, BotThreadSyncCommandState::Settled {}),
        "a pause on an idle Thread must settle, got {:?}",
        paused.state
    );
    ensure!(
        matches!(
            expect_sync(&paused, "pause")?,
            BotCurrentSync::Paused { .. }
        ),
        "the audience projection must report Paused"
    );
    let at_pause = platform_counts(session).await?;
    let ops_at_pause = card_operations_snapshot(session).await?;
    stages()[0].release();
    wait_idle(session, &thread_id).await?;
    let after_pause_turn = platform_counts(session).await?;
    let ops_after_pause = card_operations_snapshot(session).await?;
    ensure!(
        after_pause_turn.entities == at_pause.entities
            && after_pause_turn.sends == at_pause.sends
            && after_pause_turn.uploads == at_pause.uploads,
        "a paused frontend must not write anything (entities {} -> {}, sends {} -> {})",
        at_pause.entities,
        after_pause_turn.entities,
        at_pause.sends,
        after_pause_turn.sends
    );
    ensure!(
        ops_after_pause == ops_at_pause,
        "a paused frontend must not append any CardKit operation, including element updates or settings closes: {} -> {} operations",
        ops_at_pause.len(),
        ops_after_pause.len()
    );
    let withheld = wait_public_items(session, &thread_id, 4).await?;
    ensure!(
        withheld
            .iter()
            .any(|item| item.text == PAUSE_FINAL && item.saved),
        "the paused Turn must still be saved locally"
    );
    let (cas, sync) = current_binding(session, &thread_id).await?;
    ensure!(
        matches!(sync, BotCurrentSync::Paused { .. }),
        "the pause must still be effective until an explicit resume"
    );
    let resumed = change_sync(
        session,
        &thread_id,
        cas,
        BotThreadSyncAction::Resume,
        "frontend-resume",
    )
    .await?;
    ensure!(
        matches!(&resumed.state, BotThreadSyncCommandState::Settled {}),
        "a resume must settle, got {:?}",
        resumed.state
    );
    let resumed_sync = expect_sync(&resumed, "resume")?;
    let BotCurrentSync::Active { authorization } = &resumed_sync else {
        bail!("a resume must reach Active, got {resumed_sync:?}");
    };
    ensure!(
        authorization.authorization.id == authorized.id,
        "a resume must stay on the same authorization generation"
    );
    let caught_up = wait_counts(session, "the paused items after resume", |counts| {
        counts.entities == after_pause_turn.entities + 2
            && counts.sends == after_pause_turn.sends + 2
    })
    .await?;
    evidence.push(format!(
        "phase 2: pause settled with zero platform writes while the Turn completed locally; resume on generation {} caught up 2 withheld items ({} entities)",
        authorized.id.generation, caught_up.entities
    ));

    // ---- Phase 3: close during an open Turn stops every further write -------
    submit_local(session, &thread_id, "lifecycle-close-input", PROMPT_CLOSE).await?;
    wait_reached(&stages()[1], "close turn commentary").await?;
    let close_card = wait_card_text(session, CLOSE_COMMENTARY, "the pre-close commentary").await?;
    let at_close = platform_counts(session).await?;
    let cards_at_close = session.control()?.card_observations().await.len();
    let ops_at_close = card_operations_snapshot(session).await?;
    let (cas, _) = current_binding(session, &thread_id).await?;
    let closed = change_sync(
        session,
        &thread_id,
        cas,
        BotThreadSyncAction::Close,
        "frontend-close",
    )
    .await?;
    ensure!(
        matches!(&closed.state, BotThreadSyncCommandState::Settled {})
            && matches!(expect_sync(&closed, "close")?, BotCurrentSync::Closed {}),
        "a close must settle into the closed sync phase, got {:?}",
        closed.state
    );
    stages()[1].release();
    wait_idle(session, &thread_id).await?;
    let after_close = platform_counts(session).await?;
    let ops_after_close = card_operations_snapshot(session).await?;
    ensure!(
        ops_after_close == ops_at_close,
        "a closed authorization must not append any CardKit operation, including a settings close: {} -> {} operations",
        ops_at_close.len(),
        ops_after_close.len()
    );
    ensure!(
        after_close.entities == at_close.entities
            && after_close.sends == at_close.sends
            && after_close.uploads == at_close.uploads,
        "a closed authorization must not create, upload or send anything (entities {} -> {}, sends {} -> {})",
        at_close.entities,
        after_close.entities,
        at_close.sends,
        after_close.sends
    );
    let late = session
        .control()?
        .card_observations()
        .await
        .into_iter()
        .skip(cards_at_close)
        .collect::<Vec<_>>();
    ensure!(
        late.is_empty(),
        "a closed authorization must not write any further card operation, including a close: {late:?}"
    );
    ensure!(
        !card_entity_closed(session, &close_card).await?,
        "the card accepted before the close must stay open, not receive a late settings close"
    );
    assert_not_delivered(session, "the closed authorization", &[CLOSE_FINAL]).await?;
    let local_close_history = closed_history(session, &thread_id).await?;
    ensure!(
        local_close_history
            .iter()
            .any(|(id, reason, start)| *id == authorized.id
                && *reason == BotAudienceCloseReason::LocalClose
                && matches!(start, BotClosedStart::Saved { .. })),
        "the closed authorization must keep its saved start and the local-close reason, got {local_close_history:?}"
    );
    evidence.push(format!(
        "phase 3: close settled while one card was accepted; {} later card operations, no message/upload, the open card stayed open and the saved start was kept with reason LocalClose",
        late.len()
    ));

    // ---- Phase 4: a disabled bot forbids the old generation's writes --------
    set_bot_enabled(session, &bot_id, true, "frontend-enabled-phase4-on").await?;
    authorized = enable_generation(
        session,
        &thread_id,
        authorized.id.generation,
        "frontend-enable-phase4",
    )
    .await?;
    submit_local(
        session,
        &thread_id,
        "lifecycle-disabled-input",
        PROMPT_DISABLED,
    )
    .await?;
    wait_reached(&stages()[2], "disabled turn commentary").await?;
    let disabled_card =
        wait_card_text(session, DISABLED_COMMENTARY, "the pre-disable commentary").await?;
    let at_disable = platform_counts(session).await?;
    let ops_at_disable = card_operations_snapshot(session).await?;
    set_bot_enabled(session, &bot_id, false, "frontend-disabled-phase4-off").await?;
    wait_closed_reason(session, &thread_id, BotAudienceCloseReason::BotDisabled).await?;
    stages()[2].release();
    wait_idle(session, &thread_id).await?;
    let after_disable = platform_counts(session).await?;
    let ops_after_disable = card_operations_snapshot(session).await?;
    ensure!(
        after_disable.entities == at_disable.entities
            && after_disable.sends == at_disable.sends
            && after_disable.uploads == at_disable.uploads,
        "a disabled bot must not write anything for the old generation"
    );
    ensure!(
        ops_after_disable == ops_at_disable,
        "a disabled bot must not append any CardKit operation for the old generation: {} -> {} operations",
        ops_at_disable.len(),
        ops_after_disable.len()
    );
    ensure!(
        !card_entity_closed(session, &disabled_card).await?,
        "a disabled bot must not send a late card close"
    );
    assert_not_delivered(session, "the disabled bot", &[DISABLED_FINAL]).await?;
    evidence.push(format!(
        "phase 4: generation {} closed with BotDisabled; no further entity/message/upload and no late card close",
        authorized.id.generation
    ));

    // ---- Phase 5: trust revocation forbids the old generation's writes ------
    set_bot_enabled(session, &bot_id, true, "frontend-enabled-phase5-on").await?;
    set_trusted(session, &bot_id, true, "frontend-trusted-phase5-on").await?;
    authorized = enable_generation(
        session,
        &thread_id,
        authorized.id.generation,
        "frontend-enable-phase5",
    )
    .await?;
    submit_local(
        session,
        &thread_id,
        "lifecycle-revoked-input",
        PROMPT_REVOKED,
    )
    .await?;
    wait_reached(&stages()[3], "revoked turn commentary").await?;
    let revoked_card =
        wait_card_text(session, REVOKED_COMMENTARY, "the pre-revocation commentary").await?;
    let at_revoke = platform_counts(session).await?;
    let ops_at_revoke = card_operations_snapshot(session).await?;
    set_trusted(session, &bot_id, false, "frontend-trusted-phase5-off").await?;
    wait_closed_reason(session, &thread_id, BotAudienceCloseReason::TrustRevoked).await?;
    stages()[3].release();
    wait_idle(session, &thread_id).await?;
    let after_revoke = platform_counts(session).await?;
    let ops_after_revoke = card_operations_snapshot(session).await?;
    ensure!(
        after_revoke.entities == at_revoke.entities
            && after_revoke.sends == at_revoke.sends
            && after_revoke.uploads == at_revoke.uploads,
        "a revoked trust must not write anything for the old generation"
    );
    ensure!(
        ops_after_revoke == ops_at_revoke,
        "a revoked trust must not append any CardKit operation for the old generation: {} -> {} operations",
        ops_at_revoke.len(),
        ops_after_revoke.len()
    );
    ensure!(
        !card_entity_closed(session, &revoked_card).await?,
        "a revoked trust must not send a late card close"
    );
    assert_not_delivered(session, "the revoked trust", &[REVOKED_FINAL]).await?;
    evidence.push(format!(
        "phase 5: generation {} closed with TrustRevoked; no further entity/message/upload and no late card close",
        authorized.id.generation
    ));

    // ---- Phase 6: one unconfirmed write survives a restart ------------------
    set_trusted(session, &bot_id, true, "frontend-trusted-phase6-on").await?;
    authorized = enable_generation(
        session,
        &thread_id,
        authorized.id.generation,
        "frontend-enable-phase6",
    )
    .await?;
    let at_unknown = platform_counts(session).await?;
    session
        .control()?
        .set_card_script(vec![CardDisposition::AcceptThenDrop])
        .await;
    submit_local(
        session,
        &thread_id,
        "lifecycle-unknown-input",
        PROMPT_UNKNOWN,
    )
    .await?;
    wait_dropped_create(session).await?;
    let model_before_restart = session.model_executions();
    let before_restart = platform_counts(session).await?;
    let restart = session.restart_studio_server().await?;
    evidence.push(restart.to_string());
    session.wait_connected(&bot_id).await?;
    http::hold_for(RESTART_QUIET).await;
    let after_restart = platform_counts(session).await?;
    ensure!(
        after_restart.calls == before_restart.calls,
        "a restart must not replay any platform request ({} -> {})",
        before_restart.calls,
        after_restart.calls
    );
    ensure!(
        after_restart.entities == before_restart.entities
            && after_restart.sends == before_restart.sends
            && after_restart.uploads == before_restart.uploads
            && after_restart.card_operations == before_restart.card_operations,
        "a restart must not create a replacement card, message or upload for an unconfirmed write"
    );
    ensure!(
        session.model_executions() == model_before_restart,
        "a restart must not re-execute the consumed input ({} -> {})",
        model_before_restart,
        session.model_executions()
    );
    let authorized_after = wait_authorized(session, &thread_id).await?;
    let unknown_item = public_items(session, &thread_id)
        .await?
        .into_iter()
        .find(|item| item.text == UNKNOWN_COMMENTARY)
        .context("the unconfirmed item vanished from the canonical timeline")?;
    let unknown =
        wait_card_result_unknown(session, &thread_id, &authorized_after, &unknown_item.id).await?;
    ensure!(
        unknown.canonical_revision == unknown_item.revision,
        "the unconfirmed item must keep its canonical revision"
    );
    ensure!(
        at_unknown.entities + 1 == after_restart.entities,
        "the unconfirmed create must own exactly one platform entity, got {}",
        after_restart.entities.saturating_sub(at_unknown.entities)
    );
    assert_not_delivered(session, "the unconfirmed write", &[UNKNOWN_FINAL]).await?;
    evidence.push(format!(
        "phase 6: one applied-but-dropped card create stayed Unknown at canonical revision {}; restart kept {} calls, {} entities and did not re-execute the input",
        unknown.canonical_revision, after_restart.calls, after_restart.entities
    ));

    // ---- Phase 7: replacement closes the old range, the new range waits ------
    //
    // The explicit local creation command is the public way to replace the
    // mapping of one chat; it takes the current binding revision as its CAS.
    // The old Thread keeps explaining its own closed range but may not write
    // again. A replacement requires an explicit new enable only because this
    // Thread already had an activated head; that precondition is asserted here
    // instead of being generalized to every new chat.
    ensure!(
        authorized_after.start.commit_sequence > 0 && authorized_after.id.chat_id == DIRECT_CHAT_ID,
        "a replacement precondition is an existing activated head, but generation {} has no saved start",
        authorized_after.id.generation
    );
    let binding_revision = current_binding(session, &thread_id)
        .await?
        .0
        .binding_revision;
    let bot = session.bot(&bot_id).await?;
    let replaced = create_conversation_thread(
        session,
        &bot_id,
        DIRECT_CHAT_ID,
        bot.config_revision,
        binding_revision,
        "frontend-replace-direct",
    )
    .await?;
    let new_thread = replaced
        .binding
        .thread_id
        .as_deref()
        .filter(|id| !id.is_empty())
        .context("the replacement binding returned no Thread identity")?
        .to_owned();
    ensure!(
        new_thread != thread_id,
        "an explicit replacement must bind a different Thread"
    );
    let at_replace = platform_counts(session).await?;
    let ops_at_replace = card_operations_snapshot(session).await?;
    http::hold_for(http::ACK_BUDGET).await;
    let after_replace = platform_counts(session).await?;
    let ops_after_replace = card_operations_snapshot(session).await?;
    ensure!(
        after_replace.calls == at_replace.calls
            && after_replace.entities == at_replace.entities
            && after_replace.sends == at_replace.sends,
        "replacing the binding must not write anything for the old generation"
    );
    ensure!(
        ops_after_replace == ops_at_replace,
        "replacing the binding must not append any CardKit operation for the old generation: {} -> {} operations",
        ops_at_replace.len(),
        ops_after_replace.len()
    );
    match audience(session, &thread_id).await? {
        pl_protocol::ThreadAudience::Known { audience: old } => {
            ensure!(
                matches!(
                    old.binding,
                    pl_protocol::BotThreadBindingPosition::Replaced { .. }
                ),
                "the old Thread must report a replaced binding, got {:?}",
                old.binding
            );
            let closed = closed_history(session, &thread_id).await?;
            ensure!(
                closed
                    .iter()
                    .any(|(id, reason, start)| *id == authorized_after.id
                        && *reason == BotAudienceCloseReason::BindingReplaced
                        && matches!(start, BotClosedStart::Saved { .. })),
                "the replaced binding must close the old generation with reason BindingReplaced and keep its saved start, got {closed:?}"
            );
        }
        other => bail!("the old Thread lost its audience binding after replacement: {other:?}"),
    }
    match audience(session, &new_thread).await? {
        // A freshly created replacement has no active authorization yet; the
        // explicit enable below is what creates its first saved start.
        pl_protocol::ThreadAudience::Known { audience: new } => match &new.binding {
            pl_protocol::BotThreadBindingPosition::Current { sync, .. } => ensure!(
                !matches!(sync.as_ref(), BotCurrentSync::Active { .. }),
                "a replacement must not become Active without an explicit enable"
            ),
            pl_protocol::BotThreadBindingPosition::Replaced { .. } => {
                bail!("the replacement Thread reports itself as replaced")
            }
        },
        pl_protocol::ThreadAudience::Unbound {} => {}
        pl_protocol::ThreadAudience::Unavailable { reason } => {
            bail!("the replacement Thread audience is unavailable: {reason:?}")
        }
    }
    let enabled = enable_generation(session, &new_thread, 0, "frontend-enable-replacement").await?;
    ensure!(
        enabled.id.chat_id == DIRECT_CHAT_ID && enabled.start.commit_sequence > 0,
        "the explicit enable of the replacement must save its first start"
    );
    // A saved start alone is not delivery evidence: the new range must publish a
    // real public item, and only the old range must stay silent.
    let before_new_output = platform_counts(session).await?;
    session
        .control()?
        .send_event(text_event(
            MESSAGE_REPLACED_NEW,
            DIRECT_CHAT_ID,
            ChatType::P2p,
            SenderKind::User,
            TRUSTED_USER_OPEN_ID,
            PROMPT_REPLACED_NEW,
            Vec::new(),
        ))
        .await?;
    let new_items = wait_public_items(session, &new_thread, 2).await?;
    wait_idle(session, &new_thread).await?;
    let delivered_new = wait_counts(session, "the replacement public output", |counts| {
        counts.entities == before_new_output.entities + 2
            && counts.sends == before_new_output.sends + 2
    })
    .await?;
    wait_accepted_items(
        session,
        &new_thread,
        &enabled,
        &new_items,
        BotTextIntegrity::Full,
    )
    .await?;
    ensure!(
        new_items.iter().any(|item| item.text == NEW_FINAL),
        "the replacement Thread must publish its own final answer"
    );
    let old_before = platform_counts(session).await?;
    let old_items_before = public_items(session, &thread_id).await?.len();
    // The replaced Thread's later input must not write anything; entity/message/
    // upload counts alone cannot see a late element update or settings close, so
    // the whole ordered CardKit operation history is frozen here as well.
    let ops_before_old_input = card_operations_snapshot(session).await?;
    submit_local(
        session,
        &thread_id,
        "frontend-replaced-old-input",
        PROMPT_REPLACED_OLD,
    )
    .await?;
    let old_items = wait_public_items(session, &thread_id, old_items_before + 2).await?;
    wait_idle(session, &thread_id).await?;
    ensure!(
        old_items.iter().any(|item| item.text == OLD_FINAL),
        "the replaced Thread must keep executing locally"
    );
    let old_after = platform_counts(session).await?;
    let ops_after_old_input = card_operations_snapshot(session).await?;
    ensure!(
        old_after.entities == old_before.entities
            && old_after.sends == old_before.sends
            && old_after.uploads == old_before.uploads,
        "a replaced Thread must not publish its later input (entities {} -> {}, sends {} -> {})",
        old_before.entities,
        old_after.entities,
        old_before.sends,
        old_after.sends
    );
    ensure!(
        ops_after_old_input == ops_before_old_input,
        "a replaced Thread's later input must not append any CardKit operation, including an element update or settings close: {} -> {} operations",
        ops_before_old_input.len(),
        ops_after_old_input.len()
    );
    assert_not_delivered(session, "the replaced Thread", &[OLD_COMMENTARY, OLD_FINAL]).await?;
    evidence.push(format!(
        "phase 7: explicit replacement bound Thread {new_thread}; generation {} closed with BindingReplaced/Saved start, generation {} activated only through the explicit enable, delivered 2 new public items ({} entities / {} sends), and the old Thread's later input stayed local",
        authorized_after.id.generation, enabled.id.generation, delivered_new.entities, delivered_new.sends
    ));

    Ok(format!(
        "Thread {thread_id}: pause withheld and resume caught up on the same generation ({}); close, BotDisabled and TrustRevoked each settled without any new entity/message/upload or late card close; one unconfirmed card create stayed Unknown across a same-home restart without replay or re-execution; an explicit replacement closed the old activated range, only an explicit enable activated generation {} of the new Thread, that new range delivered 2 real public items and the replaced range's later input stayed local",
        authorized.id.generation, enabled.id.generation
    ))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async fn submit_local(
    session: &Session,
    thread_id: &str,
    input_id: &str,
    text: &str,
) -> Result<()> {
    session
        .http()?
        .submit(
            thread_id,
            StudioPromptInput {
                input_id: input_id.into(),
                text: text.into(),
                attachment_draft_ids: Vec::new(),
            },
        )
        .await?;
    Ok(())
}

/// One stable operation id per business intent; a retry of the same intent would
/// reuse it, a different intent must never.
async fn set_bot_enabled(
    session: &Session,
    bot_id: &str,
    enabled: bool,
    operation_id: &str,
) -> Result<()> {
    let snapshot = session.bot(bot_id).await?;
    session
        .http()?
        .set_enabled(&SetBotEnabledRequest {
            operation_id: operation_id.to_owned(),
            bot_id: bot_id.to_owned(),
            expected_config_revision: snapshot.config_revision,
            enabled,
        })
        .await?;
    ensure!(
        session.bot(bot_id).await?.enabled == enabled,
        "the canonical bot snapshot did not keep the requested enabled flag"
    );
    Ok(())
}

async fn set_trusted(
    session: &Session,
    bot_id: &str,
    trusted: bool,
    operation_id: &str,
) -> Result<()> {
    let snapshot = session.bot(bot_id).await?;
    session
        .http()?
        .set_trusted_user(&SetBotTrustedUserRequest {
            operation_id: operation_id.to_owned(),
            bot_id: bot_id.to_owned(),
            expected_config_revision: snapshot.config_revision,
            open_id: TRUSTED_USER_OPEN_ID.into(),
            trusted,
        })
        .await?;
    Ok(())
}

/// Explicit local conversation-Thread creation, also the replacement path for a
/// chat that is already bound (the current binding revision is the CAS).
async fn create_conversation_thread(
    session: &Session,
    bot_id: &str,
    chat_id: &str,
    config_revision: u64,
    binding_revision: u64,
    operation_id: &str,
) -> Result<BotConversationThreadReply> {
    session
        .http()?
        .create_conversation_thread(&CreateBotConversationThreadRequest {
            operation_id: operation_id.to_owned(),
            bot_id: bot_id.to_owned(),
            chat_id: chat_id.to_owned(),
            expected_config_revision: config_revision,
            expected_binding_revision: binding_revision,
        })
        .await?
        .map_err(|error| {
            anyhow::anyhow!(
                "explicit conversation-Thread creation was rejected: {:?}: {}",
                error.code,
                error.message
            )
        })
}

/// Starts one new generation and waits for its saved, active start.
async fn enable_generation(
    session: &Session,
    thread_id: &str,
    previous: u64,
    operation_id: &str,
) -> Result<Authorized> {
    let (cas, _) = wait_known_binding(session, thread_id).await?;
    let reply = change_sync(
        session,
        thread_id,
        cas,
        BotThreadSyncAction::Enable,
        operation_id,
    )
    .await?;
    ensure!(
        matches!(
            &reply.state,
            BotThreadSyncCommandState::Settled {} | BotThreadSyncCommandState::PendingStart { .. }
        ),
        "an explicit enable must be accepted as a settled or pending-start receipt, got {:?}",
        reply.state
    );
    let authorized = wait_authorized(session, thread_id).await?;
    ensure!(
        authorized.id.generation > previous,
        "an explicit enable must start a new authorization generation ({} -> {})",
        previous,
        authorized.id.generation
    );
    Ok(authorized)
}

/// Waits for the authorization to be closed with one documented reason.
async fn wait_closed_reason(
    session: &Session,
    thread_id: &str,
    reason: BotAudienceCloseReason,
) -> Result<()> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        let history = closed_history(session, thread_id).await?;
        if history.iter().any(|(_, seen, _)| *seen == reason) {
            return Ok(());
        }
        last = format!("{history:?}");
        if Instant::now() >= deadline {
            bail!("the authorization never closed with {reason:?}: {last}");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

type ClosedHistory = Vec<(
    pl_protocol::BotAuthorizationId,
    BotAudienceCloseReason,
    BotClosedStart,
)>;

async fn closed_history(session: &Session, thread_id: &str) -> Result<ClosedHistory> {
    let reply = session
        .http()?
        .read_thread_closed_authorizations(&ReadThreadClosedAuthorizationsRequest {
            thread_id: thread_id.to_owned(),
            cursor: None,
            limit: Some(32),
        })
        .await?
        .map_err(|error| {
            anyhow::anyhow!(
                "bots.readThreadClosedAuthorizations was rejected: {:?}: {}",
                error.code,
                error.message
            )
        })?;
    ensure!(
        reply.thread_id == thread_id,
        "the closed history answered for another Thread"
    );
    match reply.result {
        ThreadClosedAuthorizationsRead::Page { page } => Ok(page
            .authorizations
            .into_iter()
            .map(|closed| (closed.authorization.id, closed.reason, closed.start))
            .collect()),
        ThreadClosedAuthorizationsRead::Unbound {} => {
            bail!("a bound Thread must not report an unbound closed history")
        }
        ThreadClosedAuthorizationsRead::Unavailable { reason } => {
            bail!("the closed history is unavailable: {reason:?}")
        }
    }
}

/// Waits for one accepted card content update carrying `marker`.
async fn wait_card_text(session: &Session, marker: &str, label: &str) -> Result<String> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        for observation in session.control()?.card_observations().await {
            if observation.operation == CardOperation::Update
                && observation.accepted
                && observation
                    .content
                    .as_deref()
                    .is_some_and(|content| content.contains(marker))
            {
                return Ok(observation.card_id);
            }
        }
        if Instant::now() >= deadline {
            bail!("no accepted card carried the {label} marker");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

async fn card_entity_closed(session: &Session, card_id: &str) -> Result<bool> {
    Ok(session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| &entity.card_id == card_id)
        .map(|entity| entity.streaming_closed)
        .unwrap_or(false))
}

/// Waits for one card operation the platform applied while the answer was lost.
async fn wait_dropped_create(session: &Session) -> Result<()> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        let observations = session.control()?.card_observations().await;
        if observations.iter().any(|item: &CardObservation| {
            item.operation == CardOperation::Create && item.response_dropped
        }) {
            return Ok(());
        }
        last = format!("{} observations", observations.len());
        if Instant::now() >= deadline {
            bail!("the platform never applied a create whose answer was lost: {last}");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

struct UnknownItem {
    canonical_revision: u64,
}

/// Waits until the per-item ledger reports the unconfirmed card operation.
async fn wait_card_result_unknown(
    session: &Session,
    thread_id: &str,
    authorized: &Authorized,
    item_id: &str,
) -> Result<UnknownItem> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        match super::audience_item_status(session, thread_id, authorized, &[item_id.to_owned()])
            .await
        {
            Ok((phase, statuses)) => {
                let status: &BotAudienceItemStatus = &statuses[0];
                if let (BotItemDelivery::Known { ledger }, BotAuthorizationPhase::Active) =
                    (&status.delivery, phase)
                    && let BotItemPlatform::Card { latest_operation } = &ledger.platform
                {
                    ensure!(
                        !matches!(&latest_operation.result, BotPlatformResult::Accepted {}),
                        "an applied-but-unanswered card operation must never be reported as accepted"
                    );
                    if matches!(&latest_operation.result, BotPlatformResult::Unknown { .. }) {
                        let revision = match &status.canonical {
                            pl_protocol::studio::BotAudienceCanonicalItem::Present {
                                revision,
                                ..
                            } => *revision,
                            other => {
                                bail!("the unconfirmed item lost its canonical fact: {other:?}")
                            }
                        };
                        return Ok(UnknownItem {
                            canonical_revision: revision,
                        });
                    }
                }
                last = format!("{:?}", status.delivery);
            }
            Err(error) => last = error.to_string(),
        }
        if Instant::now() >= deadline {
            bail!("the unconfirmed card operation never became a typed Unknown: {last}");
        }
        tokio::time::sleep(http::POLL).await;
    }
}
