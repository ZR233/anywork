//! `conversation-frontend`: the vertical public journey of one bot chat.
//!
//! The first legitimate inbound of a trusted DM must create the Thread *and*
//! save the first authorization start before that input executes. Every real
//! public item then becomes its own card, a revised item updates its existing
//! card, and at least one frame is observable while the Turn is still open.
//! Public output continues for GUI-originated local input and for one canonical
//! continuation, while raw user text, input attachments, thinking, tool material,
//! old local history and other Threads are never mirrored.
//!
//! Nothing here seeds a binding, enables a started authorization by hand, or
//! accepts a tool receipt as a platform result.

use super::super::Session;
use super::super::replies::{answers_json, optional_title_step};
use super::{
    PlatformCounts, PublicItem, accepted_sends, assert_not_delivered, entity_texts, first_inbound,
    first_turn_id, gates, platform_counts, prepare_bot, receipts, stage_pool, wait_accepted_items,
    wait_authorized, wait_card_message_sent, wait_idle, wait_public_items, wait_reached,
};
use crate::http;
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::{
    BotAudienceCanonicalItem, BotItemDelivery, BotItemEligibility, BotItemPlatform,
    BotItemPresentation, BotPlatformResult, BotPublicTextChannel, BotTextIntegrity,
    ResolveInteractionRequest, StudioPromptInput,
};
use pl_protocol::{
    InteractionContent, InteractionResolution, InteractionStatus, ThreadItemState, TurnState,
    UserInputAnswer, UserInputResolution,
};
use pl_provider_fixture::feishu::media::{ResourceKind, SyntheticResource};
use pl_provider_fixture::feishu::{
    BOT_OPEN_ID, CardEntityReport, ChatType, DIRECT_CHAT_ID, EventBody, GROUP_CHAT_ID, SenderKind,
    TRUSTED_USER_OPEN_ID, UNKNOWN_USER_OPEN_ID, text_event, trusted_user_mention,
};
use pl_provider_fixture::{
    Protocol, RealtimeToolCall, Reply, ReplyStage, Step, responses_public_items_segments,
};
use std::sync::OnceLock;
use std::time::Instant;

// ---------------------------------------------------------------------------
// Scenario-owned text and markers. Every marker is invented for this run.
// ---------------------------------------------------------------------------

const USER_TEXT_MARKER: &str = "FRONTEND_USER_TEXT_ONLY_MARKER";
const ATTACHMENT_MARKER: &str = "FRONTEND_ATTACHMENT_ONLY_MARKER";
const THINKING_MARKER: &str = "FRONTEND_THINKING_ONLY_MARKER";
const TOOL_MARKER: &str = "FRONTEND_TOOL_ONLY_MARKER";
const OTHER_THREAD_MARKER: &str = "FRONTEND_OTHER_THREAD_MARKER";

const COMMENTARY_ONE: &str = "FRONTEND_COMMENTARY_ONE 第一条公开进展：正在读取会话上下文。";
const COMMENTARY_TWO: &str = "FRONTEND_COMMENTARY_TWO 第二条公开进展：正在整理公开答复。";
const COMMENTARY_THREE: &str = "FRONTEND_COMMENTARY_THREE 附件已按原件接收，仍在本地处理。";
const COMMENTARY_FOUR: &str = "FRONTEND_COMMENTARY_FOUR 本机输入对应的公开进展。";
const COMMENTARY_FIVE: &str = "FRONTEND_COMMENTARY_FIVE 交互等待前的公开进展。";
const COMMENTARY_SIX: &str = "FRONTEND_COMMENTARY_SIX 交互决议后继续公开进展。";

const FINAL_HEAD: &str = "# 公开答复\n\nFRONTEND_FINAL_HEAD 第一段公开正文。\n\n";
const FINAL_TAIL: &str = "- 第二段公开正文 FRONTEND_FINAL_TAIL\n- 第三段公开正文\n";

const FINAL_TWO: &str = "FRONTEND_FINAL_TWO 附件输入后的公开答复。";
const FINAL_THREE: &str = "FRONTEND_FINAL_THREE 本机输入后的公开答复。";
const FINAL_FOUR: &str = "FRONTEND_FINAL_FOUR 交互等待前的公开答复。";
const FINAL_FIVE: &str = "FRONTEND_FINAL_FIVE 续接输入后的公开答复。";

const THINKING_LINES: [&str; 2] = [
    "FRONTEND_THINKING_ONLY_MARKER internal plan line",
    "FRONTEND_THINKING_ONLY_MARKER internal tail line",
];

const PROMPT_INBOUND: &str =
    "Conversation frontend fixture: first platform request FRONTEND_USER_TEXT_ONLY_MARKER";
const PROMPT_LOCAL: &str =
    "Conversation frontend fixture: desktop local request FRONTEND_USER_TEXT_ONLY_MARKER";
const PROMPT_INTERACTION: &str = "Conversation frontend fixture: request a local decision";
const QUESTION_ID: &str = "frontend_public_receipt";
const QUESTION_ANSWER: &str = "public receipt";

const MESSAGE_INBOUND: &str = "om_frontend_first_inbound";
const MESSAGE_ATTACHMENT: &str = "om_frontend_attachment_inbound";
const MESSAGE_UNSUPPORTED: &str = "om_frontend_unsupported_first";

const ATTACHMENT_KEY: &str = "file-frontend-attachment";
const ATTACHMENT_NAME: &str = "输入附件 FRONTEND_ATTACHMENT_ONLY_MARKER.txt";
const ATTACHMENT_BYTES: &str =
    "FRONTEND_ATTACHMENT_ONLY_MARKER 输入附件原件正文，不得镜像到外部渠道。\n";

const TOOL_PATH: &str = "frontend-tool-output-FRONTEND_TOOL_ONLY_MARKER.txt";
const TOOL_CONTENT: &str = "FRONTEND_TOOL_ONLY_MARKER tool argument body\n";

/// One Thread of the same project that the bot audience never covers.
const OTHER_THREAD_PROMPT: &str =
    "independent Thread that must not broadcast FRONTEND_OTHER_THREAD_MARKER";

/// Gates inside the first model attempt: reasoning, commentary one, commentary
/// two, final head, final tail, and the item completion before the response
/// terminal. Six prefixes therefore six gates.
static STAGES: OnceLock<Vec<ReplyStage>> = OnceLock::new();

fn stages() -> &'static [ReplyStage] {
    stage_pool(&STAGES, 6)
}

pub(super) fn journey_model_steps() -> Vec<Step> {
    let first = responses_public_items_segments(
        &THINKING_LINES,
        &[
            ("frontend-commentary-1", COMMENTARY_ONE),
            ("frontend-commentary-2", COMMENTARY_TWO),
        ],
        FINAL_HEAD,
        FINAL_TAIL,
        &[],
        "frontend-journey-1",
        "fixture-model",
    );
    let attachment = responses_public_items_segments(
        &THINKING_LINES,
        &[("frontend-commentary-3", COMMENTARY_THREE)],
        FINAL_TWO,
        "",
        &[],
        "frontend-journey-2",
        "fixture-model",
    );
    let local = responses_public_items_segments(
        &THINKING_LINES,
        &[("frontend-commentary-4", COMMENTARY_FOUR)],
        FINAL_THREE,
        "",
        &[],
        "frontend-journey-3",
        "fixture-model",
    );
    let question = serde_json::json!({
        "questions": [{
            "id": QUESTION_ID,
            "header": "Public receipt",
            "question": "Which public receipt wording should the continuation use?",
            "isOther": true,
            "isSecret": false,
            "options": [{ "label": QUESTION_ANSWER, "description": "Continue this exact input." }],
        }]
    })
    .to_string();
    let interaction = responses_public_items_segments(
        &THINKING_LINES,
        &[("frontend-commentary-5", COMMENTARY_FIVE)],
        FINAL_FOUR,
        "",
        &[RealtimeToolCall {
            item_id: "frontend-question-item",
            call_id: "frontend-question-call",
            name: "request_user_input",
            arguments: question,
        }],
        "frontend-journey-4",
        "fixture-model",
    );
    let continuation = answers_json(&[(QUESTION_ID, QUESTION_ANSWER)]);
    let continued = responses_public_items_segments(
        &THINKING_LINES,
        &[("frontend-commentary-6", COMMENTARY_SIX)],
        FINAL_FIVE,
        "",
        &[],
        "frontend-journey-5",
        "fixture-model",
    );
    vec![
        optional_title_step(0, PROMPT_INBOUND),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_INBOUND,
            1,
            ReplyStage::staged(first, &gates(stages())),
        ),
        optional_title_step(2, "[附件 1]"),
        Step::prompt(
            Protocol::ResponsesHttp,
            pl_provider_fixture::bots_observe::MEDIA_PROMPT,
            3,
            Reply::Sse(attachment.concat()),
        ),
        optional_title_step(4, PROMPT_LOCAL),
        Step::prompt(Protocol::ResponsesHttp, PROMPT_LOCAL, 5, write_tool_call()),
        Step::tool_output(
            Protocol::ResponsesHttp,
            "frontend-write-call",
            "",
            6,
            Reply::Sse(local.concat()),
        ),
        optional_title_step(7, PROMPT_INTERACTION),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_INTERACTION,
            8,
            Reply::Sse(interaction.concat()),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            continuation,
            9,
            Reply::Sse(continued.concat()),
        ),
        // One independent Thread of the same project answers locally; its text
        // must never be mirrored into the bot chat. Required: a skipped model
        // step would make the negative boundary vacuous.
        Step::prompt(
            Protocol::ResponsesHttp,
            OTHER_THREAD_PROMPT,
            10,
            Reply::Sse(pl_provider_fixture::responses_text(
                "FRONTEND_OTHER_THREAD_FINAL 独立会话答复 FRONTEND_OTHER_THREAD_MARKER",
                "frontend-other-thread",
                "fixture-model",
            )),
        ),
    ]
}

/// One tool call whose arguments carry material that must never be mirrored.
fn write_tool_call() -> Reply {
    Reply::Sse(pl_provider_fixture::responses_tool_calls(
        "frontend-local",
        "fixture-model",
        &[RealtimeToolCall {
            item_id: "frontend-write-item",
            call_id: "frontend-write-call",
            name: "write_file",
            arguments: serde_json::json!({
                "path": TOOL_PATH,
                "content": TOOL_CONTENT,
                "mode": "create",
            })
            .to_string(),
        }],
    ))
}

// ---------------------------------------------------------------------------
// Case
// ---------------------------------------------------------------------------

pub(super) async fn journey(session: &mut Session, evidence: &mut Vec<String>) -> Result<String> {
    let (bot_id, project_id) = prepare_bot(session).await?;
    let before = platform_counts(session).await?;
    let thread_id = first_inbound(session, &bot_id, MESSAGE_INBOUND, PROMPT_INBOUND).await?;

    // The first model attempt is already open, so a start that is not saved here
    // means the first input executed before its authorization existed.
    wait_reached(&stages()[0], "reasoning prefix").await?;
    let authorized = wait_authorized(session, &thread_id).await?;
    ensure!(
        session.model_executions() == 1,
        "the handshake must happen inside the first model attempt, got {} executions",
        session.model_executions()
    );
    let turn_one = running_turn(session, &thread_id).await?;
    let first_turn = first_turn_id(session, &thread_id).await?;
    ensure!(
        first_turn == turn_one,
        "the running Turn must be the first canonical Turn of the Thread ({turn_one} != {first_turn})"
    );
    // Durable ordering, not the provider gate: the first authorization cut must
    // precede the first Turn start in the same history, and that Turn start must
    // name the first reliable inbound input.
    let first_input = format!("bot:{bot_id}:{DIRECT_CHAT_ID}:{MESSAGE_INBOUND}");
    let proof = receipts::first_start_proof(
        &session.home,
        &thread_id,
        &authorized,
        &first_turn,
        &first_input,
    )
    .await?;
    ensure!(
        proof.cut_sequence < proof.turn_start_sequence
            && proof.excluded_turn_id.as_deref() != Some(first_turn.as_str()),
        "the durable first cut must precede the first Turn start and must not exclude it"
    );
    evidence.push(format!(
        "auto-init: the first inbound created Thread {thread_id} with its creation identity; audience Active at generation {}; durable receipts in history {} (watermark {}) prove operation {} cut sequence {} < first turn-start sequence {} (input {}) with excludedTurnId {:?}",
        authorized.id.generation,
        proof.database_id,
        proof.applied_write_sequence,
        proof.operation_id,
        proof.cut_sequence,
        proof.turn_start_sequence,
        first_input,
        proof.excluded_turn_id
    ));

    // ---- Phase 1: per-item cards and in-place revision updates ---------------
    // Gate `i` holds the stream after segment `i`, so every public item is only
    // written once its own gate is released. The assertions below therefore
    // always release the current gate first and then prove the effect of the
    // segment that was just written.
    stages()[0].release();
    wait_reached(&stages()[1], "commentary one").await?;
    let commentary_one =
        wait_card_content(session, &before, COMMENTARY_ONE, "commentary one").await?;
    // The next model stage gate is still unreleased here, so this proves the
    // platform frame *while the Turn is open*: the card entity must already own
    // a real message id and the peer must hold the matching accepted interactive
    // send for this same card and the bound direct chat. A CardKit update
    // answer alone is not delivery.
    let open_send = wait_card_message_sent(session, &commentary_one.card_id).await?;
    ensure!(
        running_turn(session, &thread_id).await? == turn_one,
        "the first commentary card must be observable while its Turn is still running"
    );
    let open_entity = card_entity(session, &commentary_one.card_id).await?;
    ensure!(
        !open_entity.streaming_closed,
        "a card must not be closed while the Turn that owns it is still open"
    );
    let mut counts = platform_counts(session).await?;
    ensure!(
        counts.entities == before.entities + 1,
        "the first public item must own exactly one card entity, got {}",
        counts.entities.saturating_sub(before.entities)
    );
    evidence.push(format!(
        "open-Turn frame: commentary one card {} was accepted as interactive message {} in {} and held {} bytes while Turn {turn_one} was running and the card was still open",
        commentary_one.card_id,
        open_send.message_id,
        open_send.chat_id,
        open_entity.content.len()
    ));

    stages()[1].release();
    wait_reached(&stages()[2], "commentary two").await?;
    let commentary_two =
        wait_card_content(session, &before, COMMENTARY_TWO, "commentary two").await?;
    ensure!(
        commentary_two.card_id != commentary_one.card_id,
        "two different public items must own two different card entities"
    );
    counts = platform_counts(session).await?;
    ensure!(
        counts.entities == before.entities + 2,
        "two public items must own two card entities, got {}",
        counts.entities.saturating_sub(before.entities)
    );

    stages()[2].release();
    wait_reached(&stages()[3], "final head").await?;
    let head = wait_card_content(session, &before, "FRONTEND_FINAL_HEAD", "final head").await?;
    ensure!(
        running_turn(session, &thread_id).await? == turn_one,
        "the final card revision must be observable while its Turn is still running"
    );

    stages()[3].release();
    wait_reached(&stages()[4], "final tail").await?;
    let final_text = format!("{FINAL_HEAD}{FINAL_TAIL}");
    let tail = wait_card_content(session, &before, "FRONTEND_FINAL_TAIL", "final tail").await?;
    ensure!(
        tail.card_id == head.card_id,
        "a new revision of one item must update its original card, not create another entity"
    );
    ensure!(
        card_entity(session, &tail.card_id).await?.content == final_text,
        "the updated card must hold the complete cumulative item text"
    );
    counts = platform_counts(session).await?;
    ensure!(
        counts.entities == before.entities + 3,
        "one Turn with two commentary items and one final item must own three cards, got {}",
        counts.entities.saturating_sub(before.entities)
    );

    stages()[4].release();
    // Item completion is served, the response terminal is still withheld.
    wait_reached(&stages()[5], "item completion").await?;
    let still_running = session.http()?.read_thread(&thread_id).await?;
    ensure!(
        matches!(
            still_running.active_turn.as_ref().map(|turn| &turn.state),
            Some(TurnState::Running(_))
        ),
        "after the item completion but before the response terminal the Turn must still be running"
    );
    ensure!(
        !card_entity(session, &tail.card_id).await?.streaming_closed,
        "no card may be closed before the response terminal"
    );
    stages()[5].release();

    let items = wait_public_items(session, &thread_id, 3).await?;
    assert_item_channels(
        &items,
        &[
            BotPublicTextChannel::Commentary,
            BotPublicTextChannel::Commentary,
            BotPublicTextChannel::Final,
        ],
    )?;
    ensure!(
        items[2].text == final_text,
        "the canonical Final item must keep the complete model answer"
    );
    // Stage one only owns the first real input, so it must show three items that
    // all belong to that one real Turn. The many-Turn requirement belongs to the
    // stage that really published five inputs.
    let first_turns = item_turn_identities(session, &thread_id, &items).await?;
    let first_turn = first_turn_id(session, &thread_id).await?;
    ensure!(
        items.len() == 3 && first_turns.len() == 1 && first_turns.contains(&first_turn),
        "the first real input must publish three items inside its own first real Turn {first_turn}, got {} items in {:?}",
        items.len(),
        first_turns
    );
    let accepted = assert_public_text_items(
        session,
        &thread_id,
        &authorized,
        &items,
        &[
            (BotPublicTextChannel::Commentary, COMMENTARY_ONE),
            (BotPublicTextChannel::Commentary, COMMENTARY_TWO),
            (BotPublicTextChannel::Final, final_text.as_str()),
        ],
    )
    .await?;
    assert_card_per_item(
        session,
        &before,
        &items,
        &[
            COMMENTARY_ONE.to_string(),
            COMMENTARY_TWO.to_string(),
            final_text.clone(),
        ],
    )
    .await?;
    evidence.push(format!(
        "phase one: 3 public items -> 3 independent cards in item order, the final item revised in place ({} bytes); {} per-item statuses read",
        final_text.len(),
        accepted.len()
    ));

    // ---- Phase 2: one platform attachment must not be mirrored --------------
    session
        .control()?
        .register_resource(SyntheticResource {
            message_id: MESSAGE_ATTACHMENT.into(),
            file_key: ATTACHMENT_KEY.into(),
            kind: ResourceKind::File,
            file_name: ATTACHMENT_NAME.into(),
            mime_type: "text/plain".into(),
            bytes: ATTACHMENT_BYTES.as_bytes().to_vec(),
        })
        .await?;
    let mut attachment_event = text_event(
        MESSAGE_ATTACHMENT,
        DIRECT_CHAT_ID,
        ChatType::P2p,
        SenderKind::User,
        TRUSTED_USER_OPEN_ID,
        "",
        Vec::new(),
    );
    attachment_event.body = EventBody::File {
        file_key: ATTACHMENT_KEY.into(),
        file_name: ATTACHMENT_NAME.into(),
    };
    session.control()?.send_event(attachment_event).await?;
    let after_attachment = wait_public_items(session, &thread_id, 5).await?;
    wait_idle(session, &thread_id).await?;
    assert_card_per_item(
        session,
        &before,
        &after_attachment,
        &[
            COMMENTARY_ONE.to_string(),
            COMMENTARY_TWO.to_string(),
            final_text.clone(),
            COMMENTARY_THREE.to_string(),
            FINAL_TWO.to_string(),
        ],
    )
    .await?;
    evidence.push(format!(
        "attachment input: {} public items after the attachment Turn; the {} original bytes stayed local",
        after_attachment.len(),
        ATTACHMENT_BYTES.len()
    ));

    // ---- Phase 3: GUI local input continues the public stream --------------
    submit_local(session, &thread_id, "frontend-local-input", PROMPT_LOCAL).await?;
    let after_local = wait_public_items(session, &thread_id, 7).await?;
    wait_idle(session, &thread_id).await?;
    assert_card_per_item(
        session,
        &before,
        &after_local,
        &[
            COMMENTARY_ONE.to_string(),
            COMMENTARY_TWO.to_string(),
            final_text.clone(),
            COMMENTARY_THREE.to_string(),
            FINAL_TWO.to_string(),
            COMMENTARY_FOUR.to_string(),
            FINAL_THREE.to_string(),
        ],
    )
    .await?;
    evidence.push(
        "GUI local input: the same Thread published its own commentary and final items without a platform inbound row".into(),
    );

    // ---- Phase 4: one canonical continuation --------------------------------
    submit_local(
        session,
        &thread_id,
        "frontend-interaction-input",
        PROMPT_INTERACTION,
    )
    .await?;
    let (question, host_thread_id, expected_revision) =
        wait_pending_question(session, &thread_id).await?;
    session
        .http()?
        .resolve_interaction(
            &question,
            &ResolveInteractionRequest {
                operation_id: "frontend-resolution".into(),
                host_thread_id,
                expected_revision,
                resolution: InteractionResolution::UserInput(UserInputResolution {
                    answers: std::collections::HashMap::from([(
                        QUESTION_ID.to_string(),
                        UserInputAnswer {
                            answers: vec![QUESTION_ANSWER.to_string()],
                        },
                    )]),
                }),
            },
        )
        .await
        .context("resolving the public question over HTTP failed")?;
    let after_continuation = wait_public_items(session, &thread_id, 11).await?;
    wait_idle(session, &thread_id).await?;
    assert_card_per_item(
        session,
        &before,
        &after_continuation,
        &[
            COMMENTARY_ONE.to_string(),
            COMMENTARY_TWO.to_string(),
            final_text.clone(),
            COMMENTARY_THREE.to_string(),
            FINAL_TWO.to_string(),
            COMMENTARY_FOUR.to_string(),
            FINAL_THREE.to_string(),
            COMMENTARY_FIVE.to_string(),
            FINAL_FOUR.to_string(),
            COMMENTARY_SIX.to_string(),
            FINAL_FIVE.to_string(),
        ],
    )
    .await?;
    // The complete journey: exactly six Commentary and five Final items, each in
    // its canonical order and each accepted at its own current revision.
    assert_public_text_items(
        session,
        &thread_id,
        &authorized,
        &after_continuation,
        &[
            (BotPublicTextChannel::Commentary, COMMENTARY_ONE),
            (BotPublicTextChannel::Commentary, COMMENTARY_TWO),
            (BotPublicTextChannel::Final, final_text.as_str()),
            (BotPublicTextChannel::Commentary, COMMENTARY_THREE),
            (BotPublicTextChannel::Final, FINAL_TWO),
            (BotPublicTextChannel::Commentary, COMMENTARY_FOUR),
            (BotPublicTextChannel::Final, FINAL_THREE),
            (BotPublicTextChannel::Commentary, COMMENTARY_FIVE),
            (BotPublicTextChannel::Final, FINAL_FOUR),
            (BotPublicTextChannel::Commentary, COMMENTARY_SIX),
            (BotPublicTextChannel::Final, FINAL_FIVE),
        ],
    )
    .await?;
    // Five real inputs are published by now, so the items must spread over
    // several real Turns instead of collapsing into one execution record.
    check_turn_identity(session, &thread_id, &after_continuation).await?;
    let ids: std::collections::BTreeSet<&str> = after_continuation
        .iter()
        .map(|item| item.id.as_str())
        .collect();
    ensure!(
        ids.len() == after_continuation.len(),
        "every public item must keep one unique canonical identity"
    );
    evidence.push(format!(
        "continuation: one public question was resolved over HTTP and the continuation published 2 more items ({} total)",
        after_continuation.len()
    ));

    // ---- Phase 5: other Threads never mirror --------------------------------
    let other = session
        .http()?
        .create_thread(
            &project_id,
            &pl_protocol::studio::CreateThreadRequest {
                title: Some("Frontend other Thread".into()),
                input: StudioPromptInput {
                    input_id: "frontend-other-thread".into(),
                    text: OTHER_THREAD_PROMPT.into(),
                    attachment_draft_ids: Vec::new(),
                },
                mode: "mode.simple".into(),
                route: pl_protocol::studio::NewThreadModelRoute {
                    account_id: crate::env::model_account_id(&session.home)?,
                    model_id: "fixture-model".into(),
                    effort: None,
                },
                delegation_mode: Some(pl_protocol::DelegationMode::Profile),
                delegation_preference: None,
                workspace_mode: pl_protocol::ThreadWorkspaceMode::Local,
            },
        )
        .await?;
    ensure!(
        other.thread.id != thread_id,
        "the independent Thread must not be the bound Thread"
    );
    wait_idle(session, &other.thread.id).await?;
    // The negative boundary is only worth something if the other Thread really
    // produced its own saved public answer in this run.
    let other_items = wait_public_items(session, &other.thread.id, 1).await?;
    ensure!(
        other_items
            .iter()
            .any(|item| item.saved && item.text.contains(OTHER_THREAD_MARKER)),
        "the independent Thread never reached a saved canonical answer carrying its own marker"
    );
    // The tool negative is derived from the product's own canonical tool result,
    // never from a scripted fixture string: the write_file result must expose the
    // marker-bearing path before its absence on the platform proves anything.
    let tool_result = write_tool_success_result(session, &thread_id, "frontend-write-call").await?;
    ensure!(
        tool_result.contains(TOOL_MARKER),
        "the canonical write_file result does not expose the tool-output marker, so the tool-output negative cannot be proven (result bytes: {})",
        tool_result.len()
    );
    let after_other = platform_counts(session).await?;
    ensure!(
        after_other.entities == before.entities + 11 && after_other.sends == before.sends + 11,
        "an independent Thread must not publish anything into the bot chat (entities {}, sends {})",
        after_other.entities.saturating_sub(before.entities),
        after_other.sends.saturating_sub(before.sends)
    );
    assert_not_delivered(
        session,
        "the public frontend journey",
        &[
            USER_TEXT_MARKER,
            ATTACHMENT_MARKER,
            ATTACHMENT_NAME,
            THINKING_MARKER,
            TOOL_MARKER,
            OTHER_THREAD_MARKER,
            "frontend-tool-output",
        ],
    )
    .await?;
    evidence.push(
        "non-public material: user text, attachment name/bytes, thinking, the product's own write_file result marker and the other Thread's saved answer never appeared in any delivered payload".into(),
    );

    // ---- Phase 6: unsupported-only first inbound of another chat -----------
    let snapshot = session.bot(&bot_id).await?;
    session
        .http()?
        .set_trusted_chat(&pl_protocol::studio::SetBotTrustedChatRequest {
            operation_id: "frontend-trust-group".into(),
            bot_id: bot_id.clone(),
            expected_config_revision: snapshot.config_revision,
            chat_id: GROUP_CHAT_ID.into(),
            trusted: true,
        })
        .await?;
    let before_group = session.model_executions();
    let mut unsupported = text_event(
        MESSAGE_UNSUPPORTED,
        GROUP_CHAT_ID,
        ChatType::Group,
        SenderKind::User,
        UNKNOWN_USER_OPEN_ID,
        "",
        // The group admission rule is a real mention of *this bot*, so the
        // unsupported-only probe must be addressed to the bot as well; `@all` is
        // correctly ignored long before any inbound work row exists.
        vec![trusted_user_mention(BOT_OPEN_ID)],
    );
    unsupported.body = EventBody::Raw {
        message_type: "share_chat".into(),
        content: serde_json::json!({ "chat_id": "oc_frontend_unsupported" }).to_string(),
    };
    session.control()?.send_event(unsupported).await?;
    let unsupported_status = wait_inbound_completed(session, &bot_id, MESSAGE_UNSUPPORTED).await?;
    let unsupported_rows = crate::sqlite::inbound(&session.home, &bot_id)
        .await?
        .into_iter()
        .filter(|row| row.message_id == MESSAGE_UNSUPPORTED)
        .collect::<Vec<_>>();
    ensure!(
        unsupported_rows.len() == 1,
        "the same unsupported input must be recorded exactly once, got {}",
        unsupported_rows.len()
    );
    ensure!(
        unsupported_rows[0].status == "completed"
            && unsupported_status == "completed"
            && unsupported_rows[0].diagnostic.trim().is_empty(),
        "a handled notice-only inbound must finish as one clean completed row, got status={} diagnostic={}",
        unsupported_rows[0].status,
        crate::env::redact(&unsupported_rows[0].diagnostic)
    );
    let group_bindings = crate::sqlite::thread_bindings(&session.home, &bot_id)
        .await?
        .into_iter()
        .filter(|row| row.chat_id == GROUP_CHAT_ID)
        .count();
    ensure!(
        group_bindings == 0,
        "an unsupported-only first inbound must not create a Thread binding"
    );
    ensure!(
        session.model_executions() == before_group,
        "an unsupported-only first inbound must not execute the model"
    );
    // The handled notice-only inbound owns exactly one bounded auxiliary
    // rich-text message: no card, no file, no placeholder attachment, and its
    // identity is the durable operation the bot ledger recorded — not a word in
    // the text.
    let group_sends = accepted_sends(session)
        .await?
        .into_iter()
        .filter(|call| {
            call.send_body
                .as_ref()
                .and_then(|body| body.get("receive_id"))
                .and_then(serde_json::Value::as_str)
                == Some(GROUP_CHAT_ID)
        })
        .collect::<Vec<_>>();
    ensure!(
        group_sends.len() == 1,
        "a notice-only first inbound must answer with exactly one auxiliary notice, got {}",
        group_sends.len()
    );
    let notice = &group_sends[0];
    ensure!(
        notice.card_id.is_none(),
        "the auxiliary notice must not be a public card"
    );
    ensure!(
        notice.msg_type.as_deref() == Some("post"),
        "the auxiliary notice must be one bounded rich-text message, got {:?}",
        notice.msg_type
    );
    ensure!(
        notice
            .send_body
            .as_ref()
            .and_then(|body| body.get("content"))
            .is_none_or(|content| !content.to_string().contains("file_key")),
        "the auxiliary notice must not fake an attachment placeholder"
    );
    let notice_id = notice.assigned_message_id.as_deref().context(
        "the auxiliary notice must keep the real platform message id it was accepted as",
    )?;
    ensure!(
        !notice_id.is_empty(),
        "the auxiliary notice message id must not be empty"
    );
    let notice_text = notice
        .md_text
        .as_deref()
        .context("the auxiliary notice must carry its rich-text body")?;
    ensure!(
        notice_text.contains("暂不支持"),
        "the auxiliary notice must state the unsupported content type"
    );
    ensure!(
        !notice_text.contains("oc_frontend_unsupported")
            && !notice_text.contains("share_chat")
            && !notice_text.contains("FRONTEND_USER_TEXT_ONLY_MARKER")
            && !notice_text.contains("FRONTEND_ATTACHMENT_ONLY_MARKER")
            && !notice_text.contains("FRONTEND_TOOL_ONLY_MARKER")
            && !notice_text.contains(MESSAGE_UNSUPPORTED),
        "the auxiliary notice must not echo the original message body or any local material"
    );
    // Read-only ledger identity: one stable operation for this exact chat and
    // inbound, one bounded segment, the same accepted platform message id, and
    // exactly the body the platform holds.
    let group_operations = crate::sqlite::send_details(&session.home, &bot_id)
        .await?
        .into_iter()
        .filter(|row| row.operation_id.contains(&format!(":{GROUP_CHAT_ID}:")))
        .collect::<Vec<_>>();
    ensure!(
        group_operations.len() == 1,
        "the notice-only chat must own exactly one send operation, got {}",
        group_operations.len()
    );
    let operation = &group_operations[0];
    let expected_operation =
        format!("botunsupported:{bot_id}:{GROUP_CHAT_ID}:{MESSAGE_UNSUPPORTED}");
    ensure!(
        operation.operation_id == expected_operation,
        "the auxiliary notice must keep its stable operation identity {expected_operation}, got {}",
        operation.operation_id
    );
    ensure!(
        operation.status == "succeeded" && operation.platform_message_ids == notice_id,
        "the auxiliary notice ledger must be a succeeded send of {notice_id}, got {} / {}",
        operation.status,
        operation.platform_message_ids
    );
    let segments: Vec<serde_json::Value> = serde_json::from_str(&operation.segment_facts)
        .context("the auxiliary notice segment facts must be readable typed JSON, not ignored")?;
    ensure!(
        segments.len() == 1,
        "the auxiliary notice must be one bounded segment, got {}",
        segments.len()
    );
    let segment = &segments[0];
    let segment_uuid = segment["uuid"]
        .as_str()
        .context("the auxiliary notice segment must keep its stable uuid")?;
    ensure!(
        !segment_uuid.is_empty()
            && segment["status"] == "succeeded"
            && segment["messageStage"] == "accepted"
            && segment["platformMessageId"].as_str() == Some(notice_id),
        "the auxiliary notice segment must be one accepted, succeeded send of {notice_id}: {segment}"
    );
    ensure!(
        segment["content"]["text"].as_str() == Some(notice_text),
        "the ledger and the platform must hold the same auxiliary notice body"
    );
    evidence.push(format!(
        "unsupported-only first inbound: one clean {unsupported_status} inbound work row, zero Thread binding, zero model execution, and exactly one auxiliary rich-text notice with stable operation identity {expected_operation} / segment uuid {segment_uuid} / accepted platform message {notice_id} (no card, file or placeholder attachment)"
    ));

    let final_counts = platform_counts(session).await?;
    ensure!(
        final_counts.entities == before.entities + 11,
        "eleven public items must own eleven card entities, got {}",
        final_counts.entities.saturating_sub(before.entities)
    );
    // Eleven public cards plus the one separate auxiliary notice: no third kind
    // of send may exist anywhere in this journey.
    ensure!(
        final_counts.sends == before.sends + 12,
        "the journey must send eleven public cards and exactly one auxiliary notice, got {}",
        final_counts.sends.saturating_sub(before.sends)
    );
    ensure!(
        final_counts.uploads == before.uploads,
        "a text-only journey must not upload any file"
    );
    let all_sends = accepted_sends(session).await?;
    let card_sends = all_sends
        .iter()
        .filter(|call| call.card_id.is_some())
        .collect::<Vec<_>>();
    let aux_sends = all_sends
        .iter()
        .filter(|call| call.card_id.is_none())
        .collect::<Vec<_>>();
    ensure!(
        card_sends.len() == 11 && aux_sends.len() == 1,
        "the accepted sends must split into eleven public cards and one auxiliary notice, got {} / {}",
        card_sends.len(),
        aux_sends.len()
    );
    let distinct_cards: std::collections::BTreeSet<&str> = card_sends
        .iter()
        .filter_map(|call| call.card_id.as_deref())
        .collect();
    ensure!(
        distinct_cards.len() == 11,
        "each public card must be sent exactly once, got {} distinct cards",
        distinct_cards.len()
    );
    let final_entities = session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .skip(before.entities)
        .collect::<Vec<_>>();
    ensure!(
        final_entities.len() == 11,
        "eleven public items must own eleven card entities, got {}",
        final_entities.len()
    );
    for entity in &final_entities {
        let call = card_sends
            .iter()
            .find(|call| call.card_id.as_deref() == Some(entity.card_id.as_str()))
            .with_context(|| format!("card {} has no accepted send", entity.card_id))?;
        ensure!(
            call.msg_type.as_deref() == Some("interactive"),
            "every public item must be delivered as an interactive card, got {:?} for {}",
            call.msg_type,
            entity.card_id
        );
        ensure!(
            call.send_body
                .as_ref()
                .and_then(|body| body.get("receive_id"))
                .and_then(serde_json::Value::as_str)
                == Some(DIRECT_CHAT_ID),
            "card {} must be delivered to the bound direct chat {DIRECT_CHAT_ID}, not another target",
            entity.card_id
        );
        let sent = call.assigned_message_id.as_deref().context(
            "a delivered public card must keep the real platform message id it was accepted as",
        )?;
        ensure!(
            !sent.is_empty() && entity.sent_message_id.as_deref() == Some(sent),
            "card {} must keep the platform message id it was sent as, got {sent} vs {:?}",
            entity.card_id,
            entity.sent_message_id
        );
    }
    ensure!(
        aux_sends[0]
            .send_body
            .as_ref()
            .and_then(|body| body.get("receive_id"))
            .and_then(serde_json::Value::as_str)
            == Some(GROUP_CHAT_ID)
            && aux_sends[0].msg_type.as_deref() == Some("post"),
        "the only non-card send must be the auxiliary notice of the unsupported-only chat"
    );
    evidence.push(format!(
        "final platform facts: {} entities, {} accepted sends, {} uploads, {} card operations",
        final_counts.entities,
        final_counts.sends,
        final_counts.uploads,
        final_counts.card_operations
    ));

    Ok(format!(
        "first trusted inbound auto-created Thread {thread_id} and saved authorization generation {} (start commit {}) before execution; 11 real public items (6 commentary + 5 final) became 11 independent cards with in-place revision updates and an open-Turn frame; GUI local input and one real continuation published without platform inbound rows; user text, attachment, thinking, tool material, another Thread and the unsupported-only first inbound never mirrored anything",
        authorized.id.generation, authorized.start.commit_sequence
    ))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async fn running_turn(session: &Session, thread_id: &str) -> Result<String> {
    let snapshot = session.http()?.read_thread(thread_id).await?;
    match snapshot
        .active_turn
        .as_ref()
        .map(|turn| (&turn.id, &turn.state))
    {
        Some((id, TurnState::Running(_))) => Ok(id.clone()),
        other => bail!("Thread {thread_id} must have a running Turn, got {other:?}"),
    }
}

/// Waits for one accepted card content update carrying `marker`.
async fn wait_card_content(
    session: &Session,
    before: &PlatformCounts,
    marker: &str,
    label: &str,
) -> Result<pl_provider_fixture::feishu::CardObservation> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        let observations = session.control()?.card_observations().await;
        if let Some(found) = observations
            .iter()
            .skip(before.card_operations)
            .find(|item| {
                item.operation == pl_provider_fixture::feishu::CardOperation::Update
                    && item.accepted
                    && item
                        .content
                        .as_deref()
                        .is_some_and(|content| content.contains(marker))
            })
        {
            return Ok(found.clone());
        }
        if Instant::now() >= deadline {
            bail!("no accepted card content update carried the {label} marker");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

async fn card_entity(session: &Session, card_id: &str) -> Result<CardEntityReport> {
    session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == card_id)
        .with_context(|| format!("card entity {card_id} disappeared"))
}

/// The real result of one canonical *successful* `write_file` call.
///
/// A terminal output alone is not success: `Failed`/`Cancelled` items can carry
/// one too. The typed invocation identity and the `Succeeded` state are checked
/// first, on a saved terminal item, and only then is its result used to bound the
/// outbound negative.
async fn write_tool_success_result(
    session: &Session,
    thread_id: &str,
    call_id: &str,
) -> Result<String> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        for item in session.http()?.timeline(thread_id).await? {
            let tool = match item.preview.state() {
                ThreadItemState::Tool(tool) => Some(tool.clone()),
                _ => None,
            };
            let Some(tool) = tool else {
                continue;
            };
            if tool.invocation().tool_call_id() != call_id {
                continue;
            }
            ensure!(
                tool.invocation().name() == "write_file",
                "tool {call_id} is {:?}, not the typed write_file call the negative depends on",
                tool.invocation().name()
            );
            ensure!(
                item.saved && item.lifecycle == pl_protocol::TimelineLifecycle::Terminal,
                "the write_file item must be saved and terminal before its result can bound a negative"
            );
            match tool.state() {
                pl_protocol::ThreadToolState::Succeeded(_) => {
                    let output = tool
                        .terminal_output()
                        .context("a succeeded write_file item must expose its terminal result")?;
                    return Ok(output.result().to_owned());
                }
                other => bail!(
                    "tool {call_id} must be a canonical Succeeded write_file, got {other:?}; a failed or cancelled call cannot prove the negative"
                ),
            }
        }
        if Instant::now() >= deadline {
            bail!("tool call {call_id} never reached a canonical terminal result");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// The complete per-item public fact set of one stage.
///
/// Every item must be saved, terminal and complete with the expected channel and
/// text in canonical ordinal order, and its *current* revision must be projected,
/// accepted and accepted on the platform. Both the first three items and the full
/// eleven-item journey use this one helper, so no stage can quietly keep a weaker
/// criterion.
async fn assert_public_text_items(
    session: &Session,
    thread_id: &str,
    authorized: &super::Authorized,
    items: &[PublicItem],
    expected: &[(BotPublicTextChannel, &str)],
) -> Result<Vec<pl_protocol::studio::BotAudienceItemStatus>> {
    ensure!(
        items.len() == expected.len(),
        "expected {} public items for this stage, got {}",
        expected.len(),
        items.len()
    );
    for (index, (item, (channel, text))) in items.iter().zip(expected).enumerate() {
        ensure!(
            item.channel == *channel,
            "public item {index} ({}) has channel {:?}, expected {channel:?}",
            item.id,
            item.channel
        );
        ensure!(
            item.text == *text,
            "public item {index} ({}) must keep its complete canonical text ({} bytes vs {})",
            item.id,
            item.text.len(),
            text.len()
        );
        ensure!(
            item.saved && item.terminal && item.omitted_bytes == 0,
            "public item {index} ({}) must be a complete saved terminal item (saved={} terminal={} omitted={})",
            item.id,
            item.saved,
            item.terminal,
            item.omitted_bytes
        );
        ensure!(
            item.total_bytes == text.len() as u64,
            "public item {index} ({}) must keep all {} bytes locally, got {}",
            item.id,
            text.len(),
            item.total_bytes
        );
        if index > 0 {
            ensure!(
                item.ordinal > items[index - 1].ordinal,
                "public items must keep strictly increasing canonical ordinals, got {} after {}",
                item.ordinal,
                items[index - 1].ordinal
            );
        }
    }
    let accepted = wait_accepted_items(
        session,
        thread_id,
        authorized,
        items,
        BotTextIntegrity::Full,
    )
    .await?;
    for (index, (item, status)) in items.iter().zip(&accepted).enumerate() {
        ensure!(
            matches!(
                &status.canonical,
                BotAudienceCanonicalItem::Present {
                    revision,
                    saved: true,
                    eligibility: BotItemEligibility::Text { .. },
                } if *revision == item.revision
            ),
            "public item {index} ({}) must be a saved, current-revision text item: {:?}",
            item.id,
            status.canonical
        );
        let BotItemDelivery::Known { ledger } = &status.delivery else {
            bail!(
                "public item {index} ({}) has no known per-item delivery: {:?}",
                item.id,
                status.delivery
            );
        };
        ensure!(
            matches!(
                &ledger.projected,
                BotItemPresentation::Text { revision, saved: true, .. } if *revision == item.revision
            ) && matches!(
                &ledger.accepted,
                BotItemPresentation::Text { revision, saved: true, .. } if *revision == item.revision
            ),
            "public item {index} ({}) must project and accept its current revision {}: {:?} / {:?}",
            item.id,
            item.revision,
            ledger.projected,
            ledger.accepted
        );
        ensure!(
            matches!(
                &ledger.platform,
                BotItemPlatform::Card { latest_operation }
                    if latest_operation.content_revision == item.revision
                        && matches!(&latest_operation.result, BotPlatformResult::Accepted {})
            ),
            "public item {index} ({}) must be accepted on the platform at its current card revision {}: {:?}",
            item.id,
            item.revision,
            ledger.platform
        );
    }
    Ok(accepted)
}

/// Requires each public item to own the next card entity, in canonical order.
///
/// Association is by the item's own text (the peer never receives an item id):
/// every expected text must appear exactly once as a complete card element, the
/// entities must follow the canonical ordinal order, and each entity must have a
/// real platform message identity. No `None == None` identity is accepted.
async fn assert_card_per_item(
    session: &Session,
    before: &PlatformCounts,
    items: &[PublicItem],
    markers: &[String],
) -> Result<()> {
    ensure!(
        items.len() == markers.len(),
        "expected {} public items for the card association, got {}",
        markers.len(),
        items.len()
    );
    // Publication continues after the Turn ends, so the platform fact is waited
    // on with the shared predicate budget before its count is asserted. A product
    // that never delivers still fails here, with the real count.
    let entities = wait_card_entities(session, before.entities, items.len()).await?;
    ensure!(
        entities.len() == items.len(),
        "every public item must own exactly one card entity, got {} for {} items",
        entities.len(),
        items.len()
    );
    let mut seen = std::collections::BTreeSet::new();
    for (index, (item, marker)) in items.iter().zip(markers).enumerate() {
        let entity = &entities[index];
        let (texts, _) = entity_texts(&entity.entity_json)?;
        let matches = texts.iter().filter(|text| *text == marker).count();
        ensure!(
            matches == 1,
            "card entity {} must carry the text of canonical item {} exactly once as a rendered element, got {matches} matches ({} bytes expected)",
            entity.card_id,
            item.id,
            marker.len()
        );
        ensure!(
            entity
                .sent_message_id
                .as_deref()
                .is_some_and(|id| !id.is_empty()),
            "card entity {} was never sent as a platform message",
            entity.card_id
        );
        ensure!(
            seen.insert(entity.card_id.as_str()),
            "two public items shared one card entity"
        );
    }
    Ok(())
}

/// Waits until the peer holds `expected` new card entities.
///
/// The item is the canonical fact; the card entity is the platform fact, and the
/// two are produced by different stages. This waits for the platform to catch
/// up, never fabricates an entity and never relaxes the count assertion that
/// runs afterwards.
async fn wait_card_entities(
    session: &Session,
    before: usize,
    expected: usize,
) -> Result<Vec<CardEntityReport>> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        let entities = session
            .control()?
            .card_entities()
            .await
            .into_iter()
            .skip(before)
            .collect::<Vec<_>>();
        let all_sent = entities.iter().all(|entity| {
            entity
                .sent_message_id
                .as_deref()
                .is_some_and(|id| !id.is_empty())
        });
        if entities.len() >= expected && all_sent {
            return Ok(entities);
        }
        let held = entities.len();
        if Instant::now() >= deadline {
            bail!(
                "one sent card per public item never appeared: wanted {expected} sent messages, the peer held {held} entities (all sent: {all_sent}) for the whole {}s predicate budget",
                http::PREDICATE_TIMEOUT.as_secs()
            );
        }
        tokio::time::sleep(http::POLL).await;
    }
}

fn assert_item_channels(items: &[PublicItem], expected: &[BotPublicTextChannel]) -> Result<()> {
    ensure!(
        items.len() == expected.len(),
        "expected {} public items, got {}",
        expected.len(),
        items.len()
    );
    for (item, channel) in items.iter().zip(expected) {
        ensure!(
            item.channel == *channel,
            "public item {} has channel {:?}, expected {channel:?}",
            item.id,
            item.channel
        );
        ensure!(
            item.saved && item.terminal && item.omitted_bytes == 0,
            "public item {} must be a complete saved terminal item",
            item.id
        );
    }
    Ok(())
}

/// The distinct real Turn identities of the given public items.
///
/// Every item must keep a non-empty canonical Turn id. The caller decides how
/// many Turns its stage really published: the first input owns exactly one, the
/// complete journey publishes through five separate inputs.
async fn item_turn_identities(
    session: &Session,
    thread_id: &str,
    items: &[PublicItem],
) -> Result<std::collections::BTreeSet<String>> {
    let timeline = session.http()?.timeline(thread_id).await?;
    let mut by_id = std::collections::BTreeMap::new();
    for item in timeline {
        if matches!(item.preview.state(), ThreadItemState::Text(_)) {
            by_id.insert(item.preview.id.clone(), item.preview.turn_id.clone());
        }
    }
    let mut turns = std::collections::BTreeSet::new();
    for item in items {
        let turn = by_id
            .get(&item.id)
            .with_context(|| format!("public item {} vanished from the timeline", item.id))?;
        ensure!(
            !turn.is_empty(),
            "public item {} must keep its real Turn identity",
            item.id
        );
        turns.insert(turn.clone());
    }
    Ok(turns)
}

/// Every public item keeps the real Turn identity it was produced by.
///
/// The journey publishes through five separate inputs, so a single shared Turn
/// id would mean the items were merged into one execution record.
async fn check_turn_identity(
    session: &Session,
    thread_id: &str,
    items: &[PublicItem],
) -> Result<()> {
    let turns = item_turn_identities(session, thread_id, items).await?;
    ensure!(
        turns.len() >= 4,
        "eleven public items produced by five inputs must belong to several real Turns, got {}",
        turns.len()
    );
    Ok(())
}

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

/// The pending public question with the identity and revision the host needs.
///
/// A resolution is an explicit host write: it must name the host Thread the
/// interaction really belongs to and the exact revision it was read at, so a
/// stale or foreign resolution cannot be accepted.
async fn wait_pending_question(
    session: &Session,
    thread_id: &str,
) -> Result<(String, String, u64)> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        let snapshot = session.http()?.read_thread(thread_id).await?;
        if let Some(question) = snapshot.interactions.iter().find(|item| {
            item.status() == InteractionStatus::Pending
                && matches!(&item.content, InteractionContent::UserInput(value)
                    if value.questions().iter().any(|question| question.id == QUESTION_ID))
        }) {
            return Ok((
                question.interaction_id.clone(),
                question.scope.thread_id.clone(),
                question.revision,
            ));
        }
        if Instant::now() >= deadline {
            bail!("the public pending question never appeared on Thread {thread_id}");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// Waits until one inbound work row for `message_id` is cleanly completed.
///
/// A handled notice-only inbound finishes as a plain `completed` row. It must
/// never be reported as `needs_attention`, which is the product's failure and
/// exhausted-recovery state: treating it as an acceptable answer would hide a
/// real defect behind "some terminal fact".
async fn wait_inbound_completed(
    session: &Session,
    bot_id: &str,
    message_id: &str,
) -> Result<String> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last = String::from("no inbound row for this message yet");
    loop {
        for row in crate::sqlite::inbound(&session.home, bot_id).await? {
            if row.message_id != message_id {
                continue;
            }
            if row.status == "needs_attention" {
                bail!(
                    "a handled notice-only inbound must not fall into needs_attention: {}",
                    crate::env::redact(&row.diagnostic)
                );
            }
            if row.status == "completed" {
                return Ok(row.status);
            }
            last = format!(
                "status={} diagnostic={}",
                row.status,
                crate::env::redact(&row.diagnostic)
            );
        }
        if Instant::now() >= deadline {
            bail!("the unsupported-only inbound never completed cleanly: {last}");
        }
        tokio::time::sleep(http::POLL).await;
    }
}
