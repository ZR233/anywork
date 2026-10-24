//! Presence-sensitive raw post stimuli. The peer supplies exact official JSON;
//! product requests, reliable originals, ACKs and durable wire fingerprints
//! independently decide whether legacy content was consumed.

use super::{ReceivedOriginal, record_original, samples};
use crate::cases::Session;
use crate::cases::files::{requests, write_json};
use crate::{http, sqlite};
use anyhow::{Result, ensure};
use pl_provider_fixture::{
    bots_observe as model,
    feishu::{
        AckObservation, ChatType, DIRECT_CHAT_ID, EventBody, MessageContentObservation,
        PostElement, SenderKind, TRUSTED_USER_OPEN_ID,
        media::{ResourceKind, SyntheticResource},
        text_event,
    },
};
use serde::Serialize;
use serde_json::{Value, json};

const UNSUPPORTED_NOTICE: &str = "此消息类型或富文本元素暂不支持原件接收。可接收文字、富文本、图片、文件及可下载音视频；贴纸和云文档分享没有对应原件下载接口，请直接发送原文件。";
const FORBIDDEN: &str = "LEGACY-POST-MUST-NOT-BE-CONSUMED";
const RAW_POST_IDS: [&str; 5] = [
    "om_post_empty_v2",
    "om_post_null_v2",
    "om_post_bad_v2",
    "om_post_missing_v2",
    "om_post_mixed",
];

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RawPost {
    message_id: String,
    content: String,
    expected_content_hash: String,
}

pub(super) async fn run(
    session: &Session,
    bot_id: &str,
    thread_id: &str,
    received: &mut Vec<ReceivedOriginal>,
    evidence: &mut Vec<String>,
) -> Result<()> {
    let before = session.control()?.snapshot_report().await;
    let initial_originals = received.len();
    let mut raw = Vec::new();
    // Each forbidden legacy key exists on the independent peer. A fallback
    // would therefore really download bytes, not merely fail on an unknown key.
    for (index, (message_id, v2)) in [
        ("om_post_empty_v2", json!([])),
        ("om_post_null_v2", Value::Null),
        ("om_post_bad_v2", json!({"not": "a paragraph array"})),
    ]
    .into_iter()
    .enumerate()
    {
        let key = format!("img-post-legacy-trap-{index}");
        session
            .control()?
            .register_resource(SyntheticResource {
                message_id: message_id.into(),
                file_key: key.clone(),
                kind: ResourceKind::Image,
                file_name: "legacy must not download.png".into(),
                mime_type: "image/png".into(),
                bytes: vec![0x90 + index as u8; 32],
            })
            .await?;
        let body = json!({"title":"", "content":[[{"tag":"text","text":FORBIDDEN},{"tag":"img","image_key":key}]], "content_v2":v2});
        let post = send_raw(session, message_id, body).await?;
        if index > 0 {
            session.wait_inbound_completed(bot_id, message_id).await?;
            let facts = session.control()?.snapshot_report().await;
            ensure!(
                facts.message_sends.len() == before.message_sends.len() + index,
                "schema rejection did not produce exactly its independent notice"
            );
            let notice = &facts.message_sends[facts.message_sends.len() - 1];
            ensure!(
                notice.receive_id == DIRECT_CHAT_ID
                    && matches!(&notice.content, MessageContentObservation::Post(content) if content.zh_cn.content == vec![vec![PostElement::Markdown { text: UNSUPPORTED_NOTICE.into() }]]),
                "null/malformed post has no explicit platform-visible unsupported diagnostic"
            );
        }
        raw.push(post);
    }
    // A positive legacy-only event is the progress barrier after the empty,
    // null and malformed events. No timing-based quiet window is used.
    let legacy_bytes = samples::image(
        &session.output,
        "legacy-post.png",
        "color=c=yellow:s=24x16",
        false,
    )?;
    let legacy = session
        .control()?
        .register_resource(SyntheticResource {
            message_id: "om_post_missing_v2".into(),
            file_key: "img-post-legacy-supported".into(),
            kind: ResourceKind::Image,
            file_name: "legacy original.png".into(),
            mime_type: "image/png".into(),
            bytes: legacy_bytes.clone(),
        })
        .await?;
    raw.push(send_raw(session, "om_post_missing_v2", json!({"title":"post legacy only", "content":[[{"tag":"text","text":"legacy field used only when v2 is missing"}],[{"tag":"img","image_key":legacy.file_key}]]})).await?);
    session
        .wait_inbound_completed(bot_id, "om_post_missing_v2")
        .await?;
    requests::wait_executions(session, 10).await?;
    ensure!(
        requests::execution_requests(session).len() == 10,
        "empty/null/malformed v2 caused business model execution or legacy fallback"
    );
    let request = requests::execution_requests(session)
        .pop()
        .ok_or_else(|| anyhow::anyhow!("legacy request missing"))?;
    ensure!(
        requests::user_texts(&request)?
            .iter()
            .any(|text| text == model::POST_LEGACY_PROMPT),
        "missing v2 did not consume exact legacy text"
    );
    ensure!(
        requests::native_images(&request)?
            .iter()
            .filter(|bytes| **bytes == legacy_bytes)
            .count()
            == 1,
        "legacy supported image was not delivered exactly once"
    );
    record_original(
        session,
        thread_id,
        "om_post_missing_v2",
        legacy,
        None,
        received,
    )
    .await?;
    ensure!(
        received.len() == initial_originals + 1,
        "invalid/empty posts archived a legacy attachment"
    );

    let mixed_bytes = samples::image(
        &session.output,
        "mixed-post.png",
        "color=c=purple:s=28x18",
        false,
    )?;
    let mixed = session
        .control()?
        .register_resource(SyntheticResource {
            message_id: "om_post_mixed".into(),
            file_key: "img-post-mixed-supported".into(),
            kind: ResourceKind::Image,
            file_name: "mixed original.png".into(),
            mime_type: "image/png".into(),
            bytes: mixed_bytes.clone(),
        })
        .await?;
    session
        .control()?
        .register_resource(SyntheticResource {
            message_id: "om_post_mixed".into(),
            file_key: "img-post-unknown-trap".into(),
            kind: ResourceKind::Image,
            file_name: "unknown must not download.png".into(),
            mime_type: "image/png".into(),
            bytes: vec![0xff; 33],
        })
        .await?;
    raw.push(send_raw(session, "om_post_mixed", json!({
        "title":"post mixed supported and unknown",
        "content":[[{"tag":"text","text":FORBIDDEN},{"tag":"img","image_key":mixed.file_key}]],
        "content_v2":[[{"tag":"md","text":"mixed original text"}],[{"tag":"img","image_key":mixed.file_key},{"tag":"sticker","image_key":"img-post-unknown-trap"}]]
    })).await?);
    session
        .wait_inbound_completed(bot_id, "om_post_mixed")
        .await?;
    requests::wait_executions(session, 11).await?;
    let request = requests::execution_requests(session)
        .pop()
        .ok_or_else(|| anyhow::anyhow!("mixed request missing"))?;
    let texts = requests::user_texts(&request)?;
    ensure!(
        texts.iter().any(|text| text == model::POST_MIXED_PROMPT)
            && !texts.iter().any(|text| text.contains(FORBIDDEN)),
        "mixed unknown lost its independent inline limitation or consumed legacy text"
    );
    ensure!(
        requests::native_images(&request)?
            .iter()
            .filter(|bytes| **bytes == mixed_bytes)
            .count()
            == 1,
        "mixed supported image was dropped or duplicated"
    );
    record_original(session, thread_id, "om_post_mixed", mixed, None, received).await?;
    ensure!(
        received.len() == initial_originals + 2,
        "unknown element invented a reliable attachment"
    );
    let facts = session.control()?.snapshot_report().await;
    verify_raw_acks(&facts.acks)?;
    write_json(session, "post-ack-facts.json", &facts.acks)?;
    ensure!(
        facts.resource_downloads.len() == before.resource_downloads.len() + 2,
        "empty/null/bad/unknown legacy resource was downloaded or supported image duplicated"
    );
    let rows = sqlite::inbound(&session.home, bot_id).await?;
    for post in &raw {
        let row = rows.iter().find(|row| row.message_id == post.message_id);
        if post.message_id == "om_post_empty_v2" {
            ensure!(
                row.is_none(),
                "authoritative empty array fell back into business admission"
            );
        } else {
            let row = row.ok_or_else(|| {
                anyhow::anyhow!("raw post has no durable identity: {}", post.message_id)
            })?;
            ensure!(
                row.status == "completed" && row.content_hash == post.expected_content_hash,
                "raw post wire fingerprint or terminal identity differs: {}",
                post.message_id
            );
        }
    }
    write_json(session, "post-raw-inputs.json", &raw)?;
    write_json(session, "post-inbound-identities.json", &rows)?;
    evidence.push("exact Raw content_v2 []/null/malformed/missing/mixed stimuli ACKed; empty did not fall back, null/malformed produced explicit unsupported notices without business model or legacy downloads; missing alone used legacy; mixed retained one supported image and an independent inline unknown-element limitation; accepted wire content hashes matched durable identities".into());
    Ok(())
}

async fn send_raw(session: &Session, message_id: &str, content: Value) -> Result<RawPost> {
    ensure!(
        RAW_POST_IDS.contains(&message_id),
        "undeclared Raw post identity: {message_id}"
    );
    ensure!(
        !session
            .control()?
            .snapshot_report()
            .await
            .acks
            .iter()
            .any(|ack| ack.message_id.as_deref() == Some(message_id)),
        "Raw post {message_id} already has an ACK before its only send"
    );
    let content = serde_json::to_string(&content)?;
    let expected_content_hash =
        model::sha256(format!("{message_id}\0{DIRECT_CHAT_ID}\0{content}").as_bytes());
    let stimulus = RawPost {
        message_id: message_id.into(),
        content: content.clone(),
        expected_content_hash,
    };
    write_json(session, &format!("post-wire-{message_id}.json"), &stimulus)?;
    let mut event = text_event(
        message_id,
        DIRECT_CHAT_ID,
        ChatType::P2p,
        SenderKind::User,
        TRUSTED_USER_OPEN_ID,
        "",
        vec![],
    );
    event.body = EventBody::Raw {
        message_type: "post".into(),
        content: content.clone(),
    };
    session.control()?.send_event(event).await?;
    http::wait_until(http::ACK_BUDGET, || async {
        Ok(session
            .control()?
            .snapshot_report()
            .await
            .acks
            .iter()
            .any(|ack| ack.message_id.as_deref() == Some(message_id)))
    })
    .await?;
    verify_one_ack(&session.control()?.snapshot_report().await.acks, message_id)?;
    Ok(stimulus)
}

/// These five inputs are never retransmitted. Recheck the accumulated peer
/// facts at later progress boundaries, not only immediately after the first ACK.
pub(super) fn verify_raw_acks(acks: &[AckObservation]) -> Result<()> {
    for message_id in RAW_POST_IDS {
        verify_one_ack(acks, message_id)?;
    }
    Ok(())
}

fn verify_one_ack(acks: &[AckObservation], message_id: &str) -> Result<()> {
    let mut matches = acks
        .iter()
        .filter(|ack| ack.message_id.as_deref() == Some(message_id));
    let ack = matches
        .next()
        .ok_or_else(|| anyhow::anyhow!("Raw post {message_id} has no ACK"))?;
    ensure!(
        matches.next().is_none(),
        "Raw post {message_id} has duplicate ACKs despite being sent only once"
    );
    ensure!(
        ack.code == Some(200) && ack.biz_rt.as_deref() == Some("0"),
        "Raw post {message_id} ACK was not successful: code={:?}, biz_rt={:?}",
        ack.code,
        ack.biz_rt
    );
    Ok(())
}
