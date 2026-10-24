//! Independent platform GET bytes and read-only durable segment facts. Neither
//! the upload response nor a metadata summary alone proves file delivery.

use super::super::Session;
use super::notice;
use crate::sqlite;
use anyhow::{Context, Result, ensure};
use pl_model::runtime::ResourceReference;
use pl_protocol::studio::{BotSendResult, BotSendStage, BotSendStatus, BotSendStopReason};
use pl_provider_fixture::{
    bots_observe as model,
    feishu::{
        DIRECT_CHAT_ID, MessageContentObservation, MessageSendObservation, MessageSendOutcome,
        PostElement, TENANT_ACCESS_TOKEN,
    },
};
use serde::Deserialize;
use std::time::Duration;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::cases) struct Segment {
    pub index: u32,
    pub uuid: String,
    pub status: String,
    pub platform_message_id: Option<String>,
    pub content: Option<Content>,
    pub upload: Option<Upload>,
    pub message_stage: Option<String>,
    pub stop_reason: Option<BotSendStopReason>,
}

#[derive(Debug, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(in crate::cases) enum Content {
    Markdown {
        text: String,
    },
    File {
        filename: String,
        upload_filename: String,
        resource: ResourceReference,
    },
}

#[derive(Debug, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(in crate::cases) enum Upload {
    NotStarted,
    InFlight,
    Accepted { file_key: String },
    Rejected,
    Unknown,
}

pub(in crate::cases) fn segments(row: &sqlite::SendDetailRow) -> Result<Vec<Segment>> {
    serde_json::from_str(&row.segment_facts).context("durable typed segment facts are unreadable")
}

pub(in crate::cases) async fn file_roundtrip(
    session: &Session,
    send: &MessageSendObservation,
    expected: &[u8],
    evidence: &mut Vec<String>,
) -> Result<()> {
    let MessageContentObservation::File(resource) = &send.content else {
        anyhow::bail!("expected an actual platform file message");
    };
    ensure!(
        send.outcome == MessageSendOutcome::Stored
            && send.receive_id == DIRECT_CHAT_ID
            && !send.message_id.is_empty(),
        "file message did not target the original source chat or was not stored"
    );
    ensure!(
        resource.byte_len == expected.len() && resource.sha256 == model::sha256(expected),
        "platform file key points at different bytes"
    );
    let facts = session.control()?.snapshot_report().await;
    let upload = facts
        .uploads
        .iter()
        .find(|upload| upload.file_key.as_deref() == Some(&resource.file_key))
        .context("file message has no matching upload")?;
    ensure!(
        upload.call_index < send.call_index
            && upload.byte_len == Some(expected.len())
            && upload.sha256.as_deref() == Some(&resource.sha256),
        "file was not fully uploaded before its message send"
    );
    let origin = session
        .peer
        .as_ref()
        .context("Feishu peer missing")?
        .origin();
    let client = reqwest::Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(10))
        .build()?;
    #[derive(Deserialize)]
    struct ReadReply {
        code: i32,
        data: ReadData,
    }
    #[derive(Deserialize)]
    struct ReadData {
        items: Vec<ReadMessage>,
    }
    #[derive(Deserialize)]
    struct ReadMessage {
        message_id: String,
        chat_id: String,
        msg_type: String,
        body: ReadBody,
    }
    #[derive(Deserialize)]
    struct ReadBody {
        content: String,
    }
    #[derive(Deserialize)]
    struct FileContent {
        file_key: String,
    }
    let read: ReadReply = client
        .get(format!(
            "{origin}/open-apis/im/v1/messages/{}",
            send.message_id
        ))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    ensure!(
        read.code == 0 && read.data.items.len() == 1,
        "independent file message GET failed"
    );
    let message = &read.data.items[0];
    let content: FileContent = serde_json::from_str(&message.body.content)?;
    ensure!(
        message.message_id == send.message_id
            && message.chat_id == DIRECT_CHAT_ID
            && message.msg_type == "file"
            && content.file_key == resource.file_key,
        "file message GET changed identity or uploaded key"
    );
    let bytes = client
        .get(format!(
            "{origin}/open-apis/im/v1/messages/{}/resources/{}?type=file",
            send.message_id, resource.file_key
        ))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .send()
        .await?
        .error_for_status()?
        .bytes()
        .await?;
    ensure!(
        bytes.as_ref() == expected && model::sha256(&bytes) == resource.sha256,
        "independent resource GET bytes do not equal the original"
    );
    evidence.push(format!("upload call={} -> file send call={} uuid={:?} message={} key={} -> independent GET {} bytes sha256={}", upload.call_index, send.call_index, send.uuid, send.message_id, resource.file_key, bytes.len(), resource.sha256));
    Ok(())
}

pub(super) fn verify_file_ledger(
    row: &sqlite::SendDetailRow,
    send: &MessageSendObservation,
    expected: &[u8],
) -> Result<()> {
    let facts = segments(row)?;
    let fact = facts
        .iter()
        .find(|fact| fact.platform_message_id.as_deref() == Some(&send.message_id))
        .context("delivered message missing from typed segment ledger")?;
    let Content::File {
        filename,
        upload_filename,
        resource,
    } = fact
        .content
        .as_ref()
        .context("file segment content missing")?
    else {
        anyhow::bail!("durable segment is not a file");
    };
    let MessageContentObservation::File(platform) = &send.content else {
        anyhow::bail!("platform message is not a file");
    };
    let ids: Vec<&str> = row
        .platform_message_ids
        .split(',')
        .filter(|id| !id.is_empty())
        .collect();
    ensure!(
        row.status == "succeeded"
            && fact.status == "succeeded"
            && fact.message_stage.as_deref() == Some("accepted")
            && ids.contains(&send.message_id.as_str()),
        "durable file operation is not succeeded with its real message identity"
    );
    ensure!(
        fact.index < facts.len() as u32
            && !filename.is_empty()
            && upload_filename == &platform.file_name,
        "ledger file display identity or segment index changed"
    );
    ensure!(
        send.uuid.as_deref() == Some(&fact.uuid)
            && matches!(&fact.upload, Some(Upload::Accepted { file_key }) if file_key == &platform.file_key),
        "ledger UUID or accepted upload key differs from real send"
    );
    ensure!(
        resource.byte_len() == expected.len() as u64
            && resource.content_digest() == format!("sha256:{}", model::sha256(expected)),
        "ledger retained resource identity is not the exact original"
    );
    Ok(())
}

/// The short post must explain the complete downloadable original and identify
/// the file that was really delivered. This product-generated message follows
/// a finite complete affirmative template, not arbitrary model prose.
pub(in crate::cases) fn markdown_notice(
    notice: &MessageSendObservation,
    file: &MessageSendObservation,
) -> Result<String> {
    let MessageContentObservation::File(resource) = &file.content else {
        anyhow::bail!("notice has no associated file message");
    };
    let MessageContentObservation::Post(post) = &notice.content else {
        anyhow::bail!("short Markdown notice is not an official post");
    };
    ensure!(
        file.outcome == MessageSendOutcome::Stored
            && resource.file_name.ends_with(".md")
            && notice.call_index > file.call_index
            && notice.receive_id == file.receive_id
            && notice.request_body_bytes <= 30_000,
        "notice must follow the accepted complete .md file in the same chat"
    );
    let mut text = post.zh_cn.title.clone().unwrap_or_default();
    for row in &post.zh_cn.content {
        for element in row {
            match element {
                PostElement::Markdown { text: value } | PostElement::Text { text: value } => {
                    text.push('\n');
                    text.push_str(value);
                }
                _ => anyhow::bail!(
                    "short download notice unexpectedly contains media rather than a readable file hint"
                ),
            }
        }
    }
    ensure!(
        notice::is_delivery_notice(&text, &resource.file_name),
        "short notice is not a complete affirmative download/delivery template bound to the actual .md filename: file={:?}, text={text:?}",
        resource.file_name
    );
    Ok(text)
}

pub(in crate::cases) fn public_segment(
    result: &BotSendResult,
    index: usize,
    status: BotSendStatus,
    upload: Option<BotSendStage>,
    message: BotSendStage,
    stop: Option<BotSendStopReason>,
) -> Result<()> {
    let segment = result
        .segments
        .get(index)
        .context("public send result lost a planned segment")?;
    ensure!(
        segment.index == index as u32
            && segment.status == status
            && segment.upload_stage == upload
            && segment.message_stage == message
            && segment.stop_reason == stop,
        "public stage result differs from actual network/local outcome: {segment:?}; expected status={status:?} upload={upload:?} message={message:?} stop={stop:?}"
    );
    if matches!(upload, Some(BotSendStage::Accepted)) && message == BotSendStage::NotStarted {
        ensure!(
            stop.is_some(),
            "upload accepted + message not started needs an explicit local stop, not a platform rejection"
        );
    }
    Ok(())
}
