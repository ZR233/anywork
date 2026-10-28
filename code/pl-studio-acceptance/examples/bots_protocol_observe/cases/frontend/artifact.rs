//! `conversation-frontend-artifact`: a saved public artifact really leaves the
//! conversation.
//!
//! One real tool call chain (`write_file` -> `publish_artifact`) must produce a
//! typed, history-saved public artifact; only then may the platform receive the
//! upload and the file message. The independent peer reads the message back,
//! receives a *different* message-scoped download key and returns the exact
//! original bytes. Zero-byte and over-budget originals stay valid locally and are
//! explicitly not delivered, and the active send tool keeps its own permission.

use super::super::Session;
use super::super::replies::optional_title_step;
use super::{
    PlatformCounts, artifact_bytes, first_inbound, platform_counts, prepare_bot_with_id, sha256,
    stage_pool, wait_accepted_items, wait_authorized, wait_idle, wait_public_items, wait_reached,
    workspace,
};
use crate::cases::files::delivery;
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::{
    BotAudienceCanonicalItem, BotFileBlockReason, BotFileOutcome, BotItemDelivery,
    BotItemEligibility, BotItemPlatform, BotItemPresentation, BotPlatformResult, BotTextIntegrity,
    StudioPromptInput,
};
use pl_protocol::{
    ThreadItemState, ThreadPublicArtifactItem, ThreadToolFailureKind, ThreadToolState, TimelineItem,
};
use pl_provider_fixture::feishu::media::{FileMessageKeyMode, UploadObservation};
use pl_provider_fixture::feishu::{
    CallKind, CardEntityReport, CardObservation, DIRECT_CHAT_ID, MessageContentObservation,
    MessageSendObservation, MessageSendOutcome, RecordedCall,
};
use pl_provider_fixture::{Protocol, RealtimeToolCall, Reply, ReplyStage, Step, responses_text};
use std::sync::OnceLock;
use std::time::Instant;

const PROMPT_A: &str = "Conversation frontend fixture: publish one explicit Markdown artifact";
const PROMPT_B: &str = "Conversation frontend fixture: publish an empty and try an active send";
const PROMPT_C: &str = "Conversation frontend fixture: publish the over-budget original";

const MESSAGE_A: &str = "om_frontend_artifact_inbound";

const WRITE_A: &str = "frontend-write-a";
const PUBLISH_A: &str = "frontend-publish-a";
const WRITE_EMPTY: &str = "frontend-write-empty";
const PUBLISH_EMPTY: &str = "frontend-publish-empty";
const ACTIVE_SEND: &str = "frontend-active-send";
const PUBLISH_BIG: &str = "frontend-publish-big";

/// The synthetic bot identity this case's static script addresses.
///
/// `saveBot` accepts an explicit id on a fresh project (8..=80 ASCII
/// alphanumerics, `-` or `_`), which is the only way a *static* model script can
/// name the bot before the Turn runs. Nothing else is seeded: no binding and no
/// manual enable.
const ARTIFACT_BOT_ID: &str = "bot_frontend_artifact";

/// A dedicated marker so a refused active send can never be confused with the
/// automatic publication's own text.
const ACTIVE_SEND_MARKER: &str = "FRONTEND_ARTIFACT_ACTIVE_SEND_MARKER 显式主动发送必须被拒绝";

/// The exact reason the product publishes when the tool path is not authorized.
const ACTIVE_SEND_REJECTION: &str = "bot is not authorized for this project";

/// The runtime's own text-summary compaction prefix (`bots`/`compaction.rs`).
///
/// The observer only reads it back from the request the product really built; it
/// never injects a summary into the fixture's request input.
const COMPACTION_SUMMARY_PREFIX: &str = "以下是此前对话的压缩摘要。";

const ARTIFACT_A: &str = "公开产物 FRONTEND_ARTIFACT_LONG.md";
const ARTIFACT_EMPTY: &str = "公开产物 空原件.txt";
const ARTIFACT_BIG: &str = "公开产物 超限原件.bin";

const FINAL_A: &str = "FRONTEND_ARTIFACT_FINAL_A 已发布显式产物。";
const FINAL_B: &str = "FRONTEND_ARTIFACT_FINAL_B 空原件与主动发送边界已记录。";
const FINAL_C: &str = "FRONTEND_ARTIFACT_FINAL_C 超限原件保留在本地。";

/// The runtime's own text-summary compaction requirement.
///
/// The fixture matches this exact requirement on the request's last user
/// message, so the compaction request gets a real summary instead of a tool
/// call. It is the runtime's contract text, not a scenario invention.
const COMPACTION_REQUIREMENT: &str = "请根据以上完整上下文生成压缩摘要。";
const COMPACTION_SUMMARY: &str = "FRONTEND_ARTIFACT_COMPACT_SUMMARY 前一阶段上下文已压缩为摘要。";

/// The documented platform file ceiling for one outgoing file.
const PLATFORM_FILE_LIMIT: u64 = 30_000_000;

/// One long, non-empty Markdown original: Chinese text, quotes and fences.
fn artifact_markdown() -> String {
    let mut text = String::from("# 公开产物原件 FRONTEND_ARTIFACT_LONG_HEAD\n\n");
    let mut index = 0;
    while text.len() < 120_000 {
        text.push_str(&format!(
            "## 第 {index:04} 段\n\n这是显式公开产物的合成中文正文，包含「书名号」、\"双引号\"、反斜杠 \\ 与代码围栏。\n\n```rust\nlet line = {index};\n```\n\n"
        ));
        index += 1;
    }
    text.push_str("\nFRONTEND_ARTIFACT_LONG_TAIL\n");
    text
}

fn call(id: &str, name: &str, arguments: serde_json::Value) -> Reply {
    Reply::Sse(tool_call_events(id, name, arguments))
}

/// The raw SSE events of one scripted tool call.
fn tool_call_events(id: &str, name: &str, arguments: serde_json::Value) -> Vec<serde_json::Value> {
    pl_provider_fixture::responses_tool_calls(
        "frontend-artifact",
        "fixture-model",
        &[RealtimeToolCall {
            item_id: id,
            call_id: id,
            name,
            arguments: arguments.to_string(),
        }],
    )
}

fn publish(id: &str, path: &str) -> Reply {
    call(
        id,
        "publish_artifact",
        serde_json::json!({ "source": { "kind": "workspaceFile", "path": path } }),
    )
}

fn text(value: &str) -> Reply {
    Reply::Sse(text_events(value))
}

fn text_events(value: &str) -> Vec<serde_json::Value> {
    responses_text(value, "frontend-artifact", "fixture-model")
}

/// The two gates that shape the active-send observation window.
///
/// `start` withholds the `send_bot_message` tool call itself: at `reached` the
/// product has not run the tool, so the platform write set can be frozen before
/// the intent exists. `end` withholds the Final_B text until the tool's real
/// failure has entered the next request and the write set was compared, so no
/// automatic public output can race the window.
static TOOL_GATES: OnceLock<Vec<ReplyStage>> = OnceLock::new();

fn tool_gates() -> &'static [ReplyStage] {
    stage_pool(&TOOL_GATES, 2)
}

pub(super) fn artifact_model_steps() -> Vec<Step> {
    let mut steps = Vec::new();
    steps.push(optional_title_step(0, PROMPT_A));
    steps.push(Step::prompt(
        Protocol::ResponsesHttp,
        PROMPT_A,
        1,
        call(
            WRITE_A,
            "write_file",
            serde_json::json!({ "path": ARTIFACT_A, "content": artifact_markdown(), "mode": "create" }),
        ),
    ));
    // The 120 KB tool call pushes the Turn over the model's context budget, so
    // the runtime first compacts the older context. That request is a normal
    // Responses request whose prompt ends with the runtime's summary
    // requirement, so it must be answered with a real summary — answering it
    // with the publish tool call would leave the Turn without a summary.
    steps.push(Step::prompt(
        Protocol::ResponsesHttp,
        COMPACTION_REQUIREMENT,
        2,
        text(COMPACTION_SUMMARY),
    ));
    steps.push(Step::tool_output(
        Protocol::ResponsesHttp,
        WRITE_A,
        "",
        3,
        publish(PUBLISH_A, ARTIFACT_A),
    ));
    steps.push(Step::tool_output(
        Protocol::ResponsesHttp,
        PUBLISH_A,
        "Original archived",
        4,
        text(FINAL_A),
    ));
    steps.push(optional_title_step(5, PROMPT_B));
    steps.push(Step::prompt(
        Protocol::ResponsesHttp,
        PROMPT_B,
        6,
        call(
            WRITE_EMPTY,
            "write_file",
            serde_json::json!({ "path": ARTIFACT_EMPTY, "content": "", "mode": "create" }),
        ),
    ));
    steps.push(Step::tool_output(
        Protocol::ResponsesHttp,
        WRITE_EMPTY,
        "",
        7,
        publish(PUBLISH_EMPTY, ARTIFACT_EMPTY),
    ));
    // The active send is an independent external write intent; with
    // `toolsEnabled=false` it must fail on its own permission, not because the
    // automatic frontend or the typed artifact projection changed.
    steps.push(Step::tool_output(
        Protocol::ResponsesHttp,
        PUBLISH_EMPTY,
        "",
        8,
        // Held before the tool call: the platform write set is frozen while this
        // intent does not exist yet.
        tool_gates()[0].gated(
            Vec::new(),
            tool_call_events(
                ACTIVE_SEND,
                // The current active-send tool is `send_bot_message`; its typed
                // input is `{botId, chatId, text}` (camelCase on the wire). The
                // bot identity is the explicit one this case really creates.
                "send_bot_message",
                serde_json::json!({
                    "botId": ARTIFACT_BOT_ID,
                    "chatId": DIRECT_CHAT_ID,
                    "text": ACTIVE_SEND_MARKER,
                }),
            ),
        ),
    ));
    steps.push(Step::tool_output(
        Protocol::ResponsesHttp,
        ACTIVE_SEND,
        "",
        9,
        // Held until the tool really failed and produced no platform write, so
        // the Final_B public output cannot race the observation window.
        tool_gates()[1].gated(Vec::new(), text_events(FINAL_B)),
    ));
    steps.push(optional_title_step(10, PROMPT_C));
    steps.push(Step::prompt(
        Protocol::ResponsesHttp,
        PROMPT_C,
        11,
        publish(PUBLISH_BIG, ARTIFACT_BIG),
    ));
    steps.push(Step::tool_output(
        Protocol::ResponsesHttp,
        PUBLISH_BIG,
        "Original archived",
        12,
        text(FINAL_C),
    ));
    steps
}

pub(super) async fn artifact(session: &mut Session, evidence: &mut Vec<String>) -> Result<String> {
    session
        .control()?
        .set_file_message_key_mode(FileMessageKeyMode::MessageScoped)
        .await?;
    let (bot_id, _) = prepare_bot_with_id(session, ARTIFACT_BOT_ID).await?;
    let saved_bot = session.bot(&bot_id).await?;
    ensure!(
        bot_id == ARTIFACT_BOT_ID && saved_bot.id == ARTIFACT_BOT_ID,
        "the artifact journey must run against its explicit bot identity {ARTIFACT_BOT_ID}, got {bot_id} / {}",
        saved_bot.id
    );
    ensure!(
        !saved_bot.tools_enabled,
        "the artifact journey must run with toolsEnabled=false"
    );
    let before = platform_counts(session).await?;
    let thread_id = first_inbound(session, &bot_id, MESSAGE_A, PROMPT_A).await?;
    let authorized = wait_authorized(session, &thread_id).await?;

    // ---- Phase A: one saved, delivered Markdown artifact --------------------
    let expected = artifact_markdown();
    let (item, artifact) = wait_artifact(session, &thread_id, PUBLISH_A).await?;
    ensure!(
        item.saved && item.lifecycle == pl_protocol::TimelineLifecycle::Terminal,
        "a delivered artifact must be history-saved and terminal before delivery"
    );
    ensure!(
        artifact.tool_call_id == PUBLISH_A
            && artifact.display_name == ARTIFACT_A
            && artifact.resource.byte_len == expected.len() as u64
            && artifact.resource.content_digest
                == format!("sha256:{}", sha256(expected.as_bytes()))
            && !artifact.resource.media_type.is_empty(),
        "the typed artifact metadata must describe the exact original (name/bytes/digest/MIME presence)"
    );
    let status = wait_item_platform(
        session,
        &thread_id,
        &authorized,
        &item,
        PlatformExpectation::Delivered,
    )
    .await?;
    ensure!(
        matches!(
            status.canonical,
            BotAudienceCanonicalItem::Present {
                saved: true,
                eligibility: BotItemEligibility::PublicArtifact {},
                ..
            }
        ),
        "the artifact item must be a saved, eligible public artifact"
    );
    let (send, bytes) = wait_file_message(session, expected.as_bytes(), ARTIFACT_A).await?;
    delivery::file_roundtrip(session, &send, expected.as_bytes(), evidence).await?;
    let BotItemDelivery::Known { ledger } = &status.delivery else {
        bail!("the delivered artifact must have a known per-item ledger status");
    };
    ensure!(
        matches!(&ledger.projected, BotItemPresentation::File { revision }
            if *revision == item.preview.revision)
            && matches!(&ledger.accepted, BotItemPresentation::File { revision }
                if *revision == item.preview.revision),
        "the artifact ledger must project and accept the canonical item revision"
    );
    match &ledger.platform {
        BotItemPlatform::File {
            upload,
            message,
            outcome,
            ..
        } => {
            ensure!(
                matches!(upload, BotPlatformResult::Accepted {})
                    && matches!(message, BotPlatformResult::Accepted {})
                    && *outcome == BotFileOutcome::Delivered,
                "the per-item platform facts must show an accepted upload, an accepted file message and Delivered, got {upload:?}/{message:?}/{outcome:?}"
            );
        }
        other => {
            bail!("the delivered artifact must be reported as a file operation, got {other:?}")
        }
    }
    let local = artifact_bytes(session, &thread_id, &artifact.resource.id).await?;
    ensure!(
        local == bytes && local == expected.as_bytes(),
        "the public read port must return the exact original bytes"
    );
    let workspace_dir = workspace(session, &bot_id).await?;
    ensure!(
        std::fs::read(workspace_dir.join(ARTIFACT_A))? == expected.as_bytes(),
        "the model must have written the original into the real workspace"
    );
    evidence.push(format!(
        "phase A: saved artifact {} ({} bytes) delivered as one file message; public read and message resource GET both returned the exact original",
        artifact.publication_id,
        expected.len()
    ));

    // ---- The compaction request and the normal request keep their own facts --
    //
    // The 120 KB tool call really pushes the Turn over the model's context
    // budget, so the runtime compacts first and only then continues with the
    // write result. Both requests are checked on the recorded wire bodies: the
    // summary request carries the write result it summarizes, and the later
    // normal request carries the same result without the summary requirement.
    let model = session
        .model
        .as_ref()
        .context("the artifact journey needs the model fixture request log")?;
    let requests = model.recorded();
    let compaction_index = requests
        .iter()
        .position(|request| request.accepted && is_compaction_request(&request.body))
        .context(
            "the 120 KB tool call must make the runtime compact the older context before it continues",
        )?;
    let compaction_output = tool_output_text(&requests[compaction_index].body, WRITE_A)
        .context("the compaction request must carry the real write_file result it summarizes")?;
    let normal_index = requests
        .iter()
        .enumerate()
        .skip(compaction_index + 1)
        .find(|(_, request)| {
            request.accepted
                && !is_compaction_request(&request.body)
                && carries_tool_output(&request.body, WRITE_A)
        })
        .map(|(index, _)| index)
        .context(
            "the continuation after compaction must be one accepted normal request carrying the write result",
        )?;
    ensure!(
        normal_index > compaction_index,
        "the normal request must follow the compaction request, got {normal_index} after {compaction_index}"
    );
    let normal_output = tool_output_text(&requests[normal_index].body, WRITE_A).context(
        "the post-compaction request must carry the same write_file result the summary kept",
    )?;
    ensure!(
        !compaction_output.trim().is_empty() && compaction_output == normal_output,
        "the write result must survive compaction unchanged ({} vs {} bytes)",
        compaction_output.len(),
        normal_output.len()
    );
    // The summary itself must be a real record of the product-built context; the
    // observer never injects it into the fixture request input.
    ensure!(
        request_carries_text(&requests[normal_index].body, COMPACTION_SUMMARY_PREFIX)
            && request_carries_text(&requests[normal_index].body, COMPACTION_SUMMARY),
        "the post-compaction request must carry the runtime's own summary record (prefix {COMPACTION_SUMMARY_PREFIX:?}), not only the tool result"
    );
    ensure!(
        !request_carries_text(&requests[compaction_index].body, COMPACTION_SUMMARY),
        "the summary can only come from the compaction reply, never from the compacted request"
    );
    evidence.push(format!(
        "phase A wire: request {compaction_index} compacted the older context (it carried the real {} byte write result), request {normal_index} continued with the identical result and the runtime's own summary record, and produced the publish call; {} model requests in total",
        compaction_output.len(),
        requests.len()
    ));

    // ---- Phase B: a legal empty original is not uploaded --------------------
    // Phase A must be settled on the platform, not only Turn-idle, before the
    // observation window opens.
    wait_phase_a_settled(session, &thread_id, &authorized, &before).await?;
    // Baseline of the durable send ledger before the active-send Turn, so a
    // refused tool can be proven to add nothing by its own identity.
    let ledger_before_b = crate::sqlite::send_details(&session.home, &bot_id).await?;
    session
        .http()?
        .submit(
            &thread_id,
            StudioPromptInput {
                input_id: "frontend-artifact-empty".into(),
                text: PROMPT_B.into(),
                attachment_draft_ids: Vec::new(),
            },
        )
        .await?;
    // The window opens at the start gate: step 8's reply has emitted nothing yet,
    // so `send_bot_message` has not reached the product. Everything the window
    // must see (the empty artifact blocked, phase A settled) is already true.
    wait_reached(&tool_gates()[0], "active-send window start").await?;
    let (empty_item, empty) = wait_artifact(session, &thread_id, PUBLISH_EMPTY).await?;
    ensure!(
        empty_item.saved
            && empty.resource.byte_len == 0
            && empty.resource.content_digest == format!("sha256:{}", sha256(b"")),
        "a zero-byte original must stay a saved typed artifact"
    );
    let empty_status = wait_item_platform(
        session,
        &thread_id,
        &authorized,
        &empty_item,
        PlatformExpectation::EmptyFile,
    )
    .await?;
    let BotItemDelivery::Known { ledger } = &empty_status.delivery else {
        bail!("the empty artifact must keep a known per-item ledger status");
    };
    ensure!(
        matches!(
            &ledger.platform,
            BotItemPlatform::Blocked {
                reason: BotFileBlockReason::EmptyFile
            }
        ),
        "an empty original must be reported as a local EmptyFile block, not platform delivery: {:?}",
        ledger.platform
    );
    ensure!(
        upload_count(session, ARTIFACT_EMPTY).await? == 0
            && file_message_count(session, ARTIFACT_EMPTY).await? == 0,
        "an empty original must not be uploaded or sent"
    );
    // Freeze every raw platform write the peer holds: all MessageSend calls
    // whatever their acceptance flag, message type or target, every upload,
    // every CardKit operation and the entity count. Nothing is filtered by
    // marker, so a differently worded or differently addressed write cannot slip
    // through.
    let frozen_writes = raw_write_set(session).await?;
    tool_gates()[0].release();
    // The end gate is reached only after the tool really failed and its output
    // became the next request's input; Final_B is still withheld.
    wait_reached(&tool_gates()[1], "active-send window end").await?;
    let tool = timeline_tool(session, &thread_id, ACTIVE_SEND).await?;
    ensure!(
        tool.invocation().name() == "send_bot_message",
        "the active send must invoke the current send_bot_message tool, got {:?}",
        tool.invocation().name()
    );
    let arguments: serde_json::Value = serde_json::from_str(tool.invocation().arguments())
        .context("the active-send invocation arguments must be the typed JSON the script sent")?;
    ensure!(
        arguments["botId"] == ARTIFACT_BOT_ID
            && arguments["chatId"] == DIRECT_CHAT_ID
            && arguments["text"] == ACTIVE_SEND_MARKER,
        "the active-send invocation must carry the exact bot/chat/text arguments, got {arguments}"
    );
    let ThreadToolState::Failed(failed) = tool.state() else {
        bail!(
            "an active send must fail on its own permission with toolsEnabled=false, got {:?}",
            tool.state()
        );
    };
    ensure!(
        failed.failure().kind() == ThreadToolFailureKind::Execution
            && failed.failure().message().contains(ACTIVE_SEND_REJECTION),
        "the active send must fail as an execution error carrying the exact unauthorized reason, got {:?}: {}",
        failed.failure().kind(),
        failed.failure().message()
    );
    // Whole-set equality: the refused intent must not add, replace or re-shape a
    // single raw platform write.
    let window_after = raw_write_set(session).await?;
    ensure!(
        window_after == frozen_writes,
        "the refused active send must leave the raw platform write set unchanged (write calls {} -> {}, uploads {} -> {}, message sends {} -> {}, card operations {} -> {}, entities {} -> {})",
        frozen_writes.writes.len(),
        window_after.writes.len(),
        frozen_writes.uploads.len(),
        window_after.uploads.len(),
        frozen_writes.message_sends.len(),
        window_after.message_sends.len(),
        frozen_writes.cards.len(),
        window_after.cards.len(),
        frozen_writes.entities.len(),
        window_after.entities.len()
    );
    // The refused intent must leave no send, no upload and no durable operation.
    let accepted_after_tool = super::accepted_sends(session).await?;
    ensure!(
        !accepted_after_tool.iter().any(|call| {
            call.md_text
                .as_deref()
                .is_some_and(|text| text.contains(ACTIVE_SEND_MARKER))
                || call
                    .send_body
                    .as_ref()
                    .is_some_and(|body| body.to_string().contains(ACTIVE_SEND_MARKER))
        }),
        "a refused active send must never reach the chat as a platform message"
    );
    let report_after_tool = session.control()?.snapshot_report().await;
    ensure!(
        !report_after_tool.uploads.iter().any(|upload| {
            upload
                .file_name
                .as_deref()
                .is_some_and(|name| name.contains(ACTIVE_SEND_MARKER))
        }),
        "a refused active send must never upload anything"
    );
    let ledger_after_b = crate::sqlite::send_details(&session.home, &bot_id).await?;
    ensure!(
        ledger_after_b.iter().all(|row| {
            !row.operation_id.contains(ACTIVE_SEND)
                && !row.operation_id.contains(ACTIVE_SEND_MARKER)
                && !row.segment_facts.contains(ACTIVE_SEND_MARKER)
        }),
        "the refused active send must not own a durable send operation: started with {} rows, now {}",
        ledger_before_b.len(),
        ledger_after_b.len()
    );
    // Only after the whole-set comparison may the normal Final_B output be
    // emitted; releasing earlier would make the zero-write window vacuous.
    tool_gates()[1].release();
    wait_idle(session, &thread_id).await?;
    let after_b = platform_counts(session).await?;
    ensure!(
        after_b.uploads == before.uploads + 1,
        "only the delivered artifact may upload anything, got {} uploads",
        after_b.uploads.saturating_sub(before.uploads)
    );
    evidence.push(
        format!(
            "phase B: zero-byte original saved locally and blocked as EmptyFile; inside a gated window that withheld both the tool call and the next public output, the explicit send_bot_message call failed as {ACTIVE_SEND_REJECTION:?} and the peer's whole typed write snapshot ({} write calls / {} uploads / {} message sends / {} card operations / {} entities) stayed identical"
            , frozen_writes.writes.len(), frozen_writes.uploads.len(), frozen_writes.message_sends.len(), frozen_writes.cards.len(), frozen_writes.entities.len()
        ),
    );

    // ---- Phase C: an over-budget original stays local ----------------------
    let big = workspace(session, &bot_id).await?.join(ARTIFACT_BIG);
    write_over_limit(&big)?;
    session
        .http()?
        .submit(
            &thread_id,
            StudioPromptInput {
                input_id: "frontend-artifact-big".into(),
                text: PROMPT_C.into(),
                attachment_draft_ids: Vec::new(),
            },
        )
        .await?;
    let (big_item, big_artifact) = wait_artifact(session, &thread_id, PUBLISH_BIG).await?;
    wait_idle(session, &thread_id).await?;
    ensure!(
        big_item.saved && big_artifact.resource.byte_len == PLATFORM_FILE_LIMIT + 1,
        "the over-budget original must stay a saved typed artifact with its real length, got {}",
        big_artifact.resource.byte_len
    );
    let big_status = wait_item_platform(
        session,
        &thread_id,
        &authorized,
        &big_item,
        PlatformExpectation::PlatformSizeLimit,
    )
    .await?;
    let BotItemDelivery::Known { ledger } = &big_status.delivery else {
        bail!("the over-budget artifact must keep a known per-item ledger status");
    };
    ensure!(
        matches!(
            &ledger.platform,
            BotItemPlatform::Blocked {
                reason: BotFileBlockReason::PlatformSizeLimit
            }
        ),
        "an over-budget original must be reported as a local platform-size block: {:?}",
        ledger.platform
    );
    let after_c = platform_counts(session).await?;
    ensure!(
        after_c.uploads == after_b.uploads,
        "an over-budget original must not be uploaded"
    );
    ensure!(
        file_message_count(session, ARTIFACT_BIG).await? == 0,
        "an over-budget original must not be sent as a file message"
    );
    let big_bytes = artifact_bytes(session, &thread_id, &big_artifact.resource.id).await?;
    ensure!(
        big_bytes.len() as u64 == PLATFORM_FILE_LIMIT + 1
            && format!("sha256:{}", sha256(&big_bytes)) == big_artifact.resource.content_digest,
        "the over-budget original must stay readable with its exact digest"
    );
    evidence.push(format!(
        "phase C: {} bytes kept locally and readable, no upload/message; total uploads {} and sends {}",
        big_artifact.resource.byte_len,
        after_c.uploads.saturating_sub(before.uploads),
        after_c.sends.saturating_sub(before.sends)
    ));

    ensure!(
        !session.bot(&bot_id).await?.tools_enabled,
        "the artifact journey must not change the active-tool switch"
    );
    Ok(format!(
        "Thread {thread_id}: one saved 120KB Markdown artifact was delivered through a real upload + file message and read back byte-identical through the distinct message-scoped download key; the zero-byte and 30,000,001-byte originals stayed valid, readable and explicitly undelivered; toolsEnabled=false never blocked the automatic frontend while the explicit send_bot_message call failed as {ACTIVE_SEND_REJECTION:?} with no platform write"
    ))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The last user-role text of one recorded model request.
///
/// Runtime host facts are projected onto their own user message and are not the
/// request identity, so they are skipped exactly like the fixture does.
fn last_user_text(body: &serde_json::Value) -> Option<String> {
    let items = body["input"].as_array()?;
    let user = items.iter().rev().find(|item| {
        if item["role"] != "user" {
            return false;
        }
        let text = item["content"]
            .as_array()
            .map(|content| {
                content
                    .iter()
                    .filter_map(|part| part["text"].as_str())
                    .collect::<String>()
            })
            .unwrap_or_default();
        !text.starts_with("[当前宿主事实：")
    })?;
    let text = user["content"]
        .as_array()?
        .iter()
        .filter_map(|part| part["text"].as_str())
        .collect::<String>();
    Some(text)
}

/// Whether one recorded request is the runtime's text-summary compaction ask.
fn is_compaction_request(body: &serde_json::Value) -> bool {
    last_user_text(body).is_some_and(|text| text.ends_with(COMPACTION_REQUIREMENT))
}

/// The complete output text delivered for one tool call inside a request body.
fn tool_output_text(body: &serde_json::Value, call_id: &str) -> Option<String> {
    body["input"].as_array()?.iter().find_map(|item| {
        if item["type"] != "function_call_output" || item["call_id"] != call_id {
            return None;
        }
        item["output"].as_str().map(ToOwned::to_owned)
    })
}

/// Whether one recorded request carries the real result of `call_id`.
fn carries_tool_output(body: &serde_json::Value, call_id: &str) -> bool {
    tool_output_text(body, call_id).is_some()
}

/// Whether any text-bearing field of the request input carries `needle`.
///
/// The product owns the message shapes, so this walks the real structure
/// (message content parts, tool outputs and plain text fields) instead of
/// assuming one fixed layout, and it never adds anything to the request.
fn request_carries_text(body: &serde_json::Value, needle: &str) -> bool {
    fn walk(value: &serde_json::Value, needle: &str) -> bool {
        match value {
            serde_json::Value::String(text) => text.contains(needle),
            serde_json::Value::Array(items) => items.iter().any(|item| walk(item, needle)),
            serde_json::Value::Object(map) => map.values().any(|item| walk(item, needle)),
            _ => false,
        }
    }
    body["input"]
        .as_array()
        .is_some_and(|items| items.iter().any(|item| walk(item, needle)))
}

/// Every raw platform write the peer observed, as the peer's own typed facts.
///
/// This is deliberately broader than "accepted card messages of the direct
/// chat": it keeps the whole ordered call log for every write kind — including
/// early authorization or budget rejections and any unknown write-shaped
/// attempt — plus the complete upload, message-send, CardKit and entity records.
/// Nothing is filtered by acceptance, projected into a smaller shape, or
/// re-serialized, so a rejected or differently shaped write cannot hide.
#[derive(Debug, Clone, PartialEq, Eq)]
struct RawWriteSet {
    writes: Vec<RecordedCall>,
    uploads: Vec<UploadObservation>,
    message_sends: Vec<MessageSendObservation>,
    cards: Vec<CardObservation>,
    entities: Vec<CardEntityReport>,
}

async fn raw_write_set(session: &Session) -> Result<RawWriteSet> {
    let report = session.control()?.snapshot_report().await;
    let writes = report
        .calls
        .into_iter()
        .filter(|call| match call.kind {
            Some(
                CallKind::MessageSend
                | CallKind::FileUpload
                | CallKind::CardCreate
                | CallKind::CardUpdate
                | CallKind::CardSettings,
            ) => true,
            // An unclassified write-shaped call is counted conservatively instead
            // of being dropped from the comparison.
            None => matches!(call.method.as_str(), "POST" | "PUT" | "PATCH" | "DELETE"),
            Some(_) => false,
        })
        .collect();
    Ok(RawWriteSet {
        writes,
        uploads: report.uploads,
        message_sends: report.message_sends,
        cards: report.cards,
        entities: report.card_entities,
    })
}

/// Waits until every automatic card of the previous phase really settled.
///
/// Turn idle alone is not the platform fact: each public item must be accepted
/// at its current revision, and every new card entity must keep a real message
/// id and have closed its stream, before the next observation window opens.
async fn wait_phase_a_settled(
    session: &Session,
    thread_id: &str,
    authorized: &super::Authorized,
    before: &PlatformCounts,
) -> Result<()> {
    let items = wait_public_items(session, thread_id, 1).await?;
    wait_accepted_items(
        session,
        thread_id,
        authorized,
        &items,
        BotTextIntegrity::Full,
    )
    .await?;
    let deadline = Instant::now() + crate::http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        let entities = session
            .control()?
            .card_entities()
            .await
            .into_iter()
            .skip(before.entities)
            .collect::<Vec<_>>();
        let settled = !entities.is_empty()
            && entities.iter().all(|entity| {
                entity.streaming_closed
                    && entity
                        .sent_message_id
                        .as_deref()
                        .is_some_and(|id| !id.is_empty())
            });
        if settled {
            return Ok(());
        }
        last = entities
            .iter()
            .map(|entity| {
                format!(
                    "{}:closed={} message={:?}",
                    entity.card_id, entity.streaming_closed, entity.sent_message_id
                )
            })
            .collect::<Vec<_>>()
            .join(", ");
        if Instant::now() >= deadline {
            bail!("the previous phase's cards never settled (delivered and closed): {last}");
        }
        tokio::time::sleep(crate::http::POLL).await;
    }
}

async fn wait_artifact(
    session: &Session,
    thread_id: &str,
    tool_call_id: &str,
) -> Result<(TimelineItem, ThreadPublicArtifactItem)> {
    let deadline = Instant::now() + crate::http::PREDICATE_TIMEOUT;
    loop {
        for item in session.http()?.timeline(thread_id).await? {
            let artifact = match item.preview.state() {
                ThreadItemState::PublicArtifact(artifact) => Some(artifact.clone()),
                _ => None,
            };
            if let Some(artifact) = artifact
                && artifact.tool_call_id == tool_call_id
                && item.saved
                && item.lifecycle == pl_protocol::TimelineLifecycle::Terminal
            {
                return Ok((item, artifact));
            }
        }
        if Instant::now() >= deadline {
            bail!("public artifact {tool_call_id} never reached its saved history barrier");
        }
        tokio::time::sleep(crate::http::POLL).await;
    }
}

async fn timeline_tool(
    session: &Session,
    thread_id: &str,
    tool_call_id: &str,
) -> Result<pl_protocol::ThreadToolItem> {
    let timeline = session.http()?.timeline(thread_id).await?;
    for item in timeline {
        let tool = match item.preview.state() {
            ThreadItemState::Tool(tool) => Some(tool.clone()),
            _ => None,
        };
        if let Some(tool) = tool
            && tool.invocation().tool_call_id() == tool_call_id
        {
            return Ok(tool);
        }
    }
    bail!("tool {tool_call_id} is not a canonical item")
}

/// Waits for the per-item ledger to reach a terminal platform fact.
/// The exact platform outcome one artifact phase must reach.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PlatformExpectation {
    /// Upload accepted, message accepted and the ledger outcome `Delivered`.
    Delivered,
    /// An explicit local `EmptyFile` block.
    EmptyFile,
    /// An explicit local `PlatformSizeLimit` block.
    PlatformSizeLimit,
}

/// The revision a file presentation was accepted at, if it is a file at all.
fn file_presentation_revision(presentation: &BotItemPresentation) -> Option<u64> {
    match presentation {
        BotItemPresentation::File { revision } => Some(*revision),
        _ => None,
    }
}

/// Waits for one *specific* platform outcome on the item's current revision.
///
/// "Some non-empty platform fact" is never terminal here: an accepted upload
/// with a pending message, a stale revision, or a different block reason keeps
/// waiting, and an incompatible terminal outcome fails immediately instead of
/// being reported as success after the timeout.
async fn wait_item_platform(
    session: &Session,
    thread_id: &str,
    authorized: &super::Authorized,
    item: &TimelineItem,
    expected: PlatformExpectation,
) -> Result<pl_protocol::studio::BotAudienceItemStatus> {
    let deadline = Instant::now() + crate::http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        match super::audience_item_status(
            session,
            thread_id,
            authorized,
            std::slice::from_ref(&item.preview.id),
        )
        .await
        {
            Ok((_, mut statuses)) => {
                let status = statuses.remove(0);
                let canonical_revision = match &status.canonical {
                    BotAudienceCanonicalItem::Present {
                        revision,
                        saved: true,
                        ..
                    } => Some(*revision),
                    _ => None,
                };
                let known = match &status.delivery {
                    BotItemDelivery::Known { ledger } => Some(ledger),
                    BotItemDelivery::NotProjected {} => None,
                };
                let observed = known.map(|ledger| ledger.observed_revision);
                if canonical_revision.is_some_and(|revision| revision > item.preview.revision)
                    || observed.is_some_and(|revision| revision > item.preview.revision)
                {
                    // A newer revision is a different fact: accepting it here would
                    // silently answer for a snapshot this case never read.
                    bail!(
                        "the artifact item {} advanced past the observed revision {} (canonical {:?}, ledger {:?}); it must be re-read instead of accepting a newer revision",
                        item.preview.id,
                        item.preview.revision,
                        canonical_revision,
                        observed
                    );
                }
                let current = canonical_revision == Some(item.preview.revision)
                    && observed == Some(item.preview.revision);
                if !current {
                    last = format!(
                        "not settled at revision {} yet: canonical={:?} ledger.observed={:?}",
                        item.preview.revision, canonical_revision, observed
                    );
                } else if let Some(ledger) = known {
                    match expected {
                        PlatformExpectation::Delivered => match &ledger.platform {
                            BotItemPlatform::File {
                                content_revision,
                                upload,
                                message,
                                outcome,
                                ..
                            } => {
                                if *content_revision > item.preview.revision {
                                    bail!(
                                        "the delivered artifact reports content revision {} instead of the observed {}; the item must be re-read",
                                        content_revision,
                                        item.preview.revision
                                    );
                                }
                                if *content_revision < item.preview.revision {
                                    last = format!(
                                        "the file content revision {content_revision} is still behind {}",
                                        item.preview.revision
                                    );
                                } else if file_presentation_revision(&ledger.projected)
                                    != Some(item.preview.revision)
                                    || file_presentation_revision(&ledger.accepted)
                                        != Some(item.preview.revision)
                                {
                                    last = format!(
                                        "the file presentation is not settled at revision {} yet: {:?} / {:?}",
                                        item.preview.revision, ledger.projected, ledger.accepted
                                    );
                                } else if matches!(upload, BotPlatformResult::Accepted {})
                                    && matches!(message, BotPlatformResult::Accepted {})
                                    && *outcome == BotFileOutcome::Delivered
                                {
                                    return Ok(status);
                                } else {
                                    match outcome {
                                        BotFileOutcome::Pending => {
                                            last = format!(
                                                "upload={upload:?} message={message:?} outcome=pending"
                                            );
                                        }
                                        other => bail!(
                                            "the artifact reached the terminal file outcome {other:?} instead of Delivered (upload={upload:?} message={message:?})"
                                        ),
                                    }
                                }
                            }
                            BotItemPlatform::Blocked { reason } => bail!(
                                "the artifact was blocked locally as {reason:?} instead of delivered"
                            ),
                            other => bail!(
                                "the delivered artifact reported an incompatible platform fact: {other:?}"
                            ),
                        },
                        PlatformExpectation::EmptyFile => match &ledger.platform {
                            BotItemPlatform::Blocked {
                                reason: BotFileBlockReason::EmptyFile,
                            } => return Ok(status),
                            BotItemPlatform::Blocked { reason } => bail!(
                                "the empty original was blocked as {reason:?}, expected EmptyFile"
                            ),
                            BotItemPlatform::File {
                                content_revision, ..
                            } if *content_revision > item.preview.revision => bail!(
                                "the empty original reports content revision {content_revision} instead of the observed {}; the item must be re-read",
                                item.preview.revision
                            ),
                            BotItemPlatform::File {
                                content_revision, ..
                            } if *content_revision < item.preview.revision => {
                                last = format!(
                                    "the empty original's file fact is still at content revision {content_revision} instead of {}",
                                    item.preview.revision
                                );
                            }
                            BotItemPlatform::File { .. } => {
                                bail!("a zero-byte original must never be uploaded or sent")
                            }
                            BotItemPlatform::None {} => {
                                last = "the empty original has no platform fact yet".into()
                            }
                            other => bail!(
                                "the empty original reported an incompatible platform fact: {other:?}"
                            ),
                        },
                        PlatformExpectation::PlatformSizeLimit => match &ledger.platform {
                            BotItemPlatform::Blocked {
                                reason: BotFileBlockReason::PlatformSizeLimit,
                            } => return Ok(status),
                            BotItemPlatform::Blocked { reason } => bail!(
                                "the over-budget original was blocked as {reason:?}, expected PlatformSizeLimit"
                            ),
                            BotItemPlatform::File {
                                content_revision, ..
                            } if *content_revision > item.preview.revision => bail!(
                                "the over-budget original reports content revision {content_revision} instead of the observed {}; the item must be re-read",
                                item.preview.revision
                            ),
                            BotItemPlatform::File {
                                content_revision, ..
                            } if *content_revision < item.preview.revision => {
                                last = format!(
                                    "the over-budget original's file fact is still at content revision {content_revision} instead of {}",
                                    item.preview.revision
                                );
                            }
                            BotItemPlatform::File { .. } => {
                                bail!("an over-budget original must never be uploaded or sent")
                            }
                            BotItemPlatform::None {} => {
                                last = "the over-budget original has no platform fact yet".into()
                            }
                            other => bail!(
                                "the over-budget original reported an incompatible platform fact: {other:?}"
                            ),
                        },
                    }
                } else {
                    last = "the item is not projected by the audience ledger yet".into()
                }
            }
            Err(error) => last = error.to_string(),
        }
        if Instant::now() >= deadline {
            bail!(
                "the artifact item {} never reached {expected:?}: {last}",
                item.preview.id
            );
        }
        tokio::time::sleep(crate::http::POLL).await;
    }
}

/// Waits for one accepted file message whose bytes match `expected`.
async fn wait_file_message(
    session: &Session,
    expected: &[u8],
    name: &str,
) -> Result<(MessageSendObservation, Vec<u8>)> {
    let deadline = Instant::now() + crate::http::PREDICATE_TIMEOUT;
    let digest = sha256(expected);
    loop {
        let report = session.control()?.snapshot_report().await;
        for send in &report.message_sends {
            let MessageContentObservation::File(resource) = &send.content else {
                continue;
            };
            if send.outcome != MessageSendOutcome::Stored
                || resource.sha256 != digest
                || resource.byte_len != expected.len()
                || resource.file_name != name
            {
                continue;
            }
            let upload = report
                .uploads
                .iter()
                .find(|upload| upload.file_key.as_deref() == Some(resource.file_key.as_str()))
                .context("the file message has no matching upload")?;
            ensure!(
                upload.call_index < send.call_index
                    && upload.sha256.as_deref() == Some(digest.as_str()),
                "the platform must hold the complete upload before the file message"
            );
            return Ok((send.clone(), expected.to_vec()));
        }
        if Instant::now() >= deadline {
            bail!("no accepted file message carried the exact original ({digest}) of {name}");
        }
        tokio::time::sleep(crate::http::POLL).await;
    }
}

/// How many uploads the peer really received for one filename.
async fn upload_count(session: &Session, name: &str) -> Result<usize> {
    let report = session.control()?.snapshot_report().await;
    Ok(report
        .uploads
        .iter()
        .filter(|upload| upload.file_name.as_deref() == Some(name))
        .count())
}

/// How many file messages the peer holds for one filename.
async fn file_message_count(session: &Session, name: &str) -> Result<usize> {
    let report = session.control()?.snapshot_report().await;
    Ok(report
        .message_sends
        .iter()
        .filter(|send| {
            matches!(&send.content, MessageContentObservation::File(resource) if resource.file_name == name)
        })
        .count())
}

fn write_over_limit(path: &std::path::Path) -> Result<()> {
    let block = [b'X'; 64 * 1024];
    let mut remaining = PLATFORM_FILE_LIMIT + 1;
    let file = std::fs::File::create(path).with_context(|| {
        format!(
            "failed to create the over-budget original {}",
            path.display()
        )
    })?;
    let mut writer = std::io::BufWriter::new(file);
    use std::io::Write as _;
    while remaining > 0 {
        let count = remaining.min(block.len() as u64) as usize;
        writer.write_all(&block[..count])?;
        remaining -= count as u64;
    }
    writer.flush()?;
    Ok(())
}
