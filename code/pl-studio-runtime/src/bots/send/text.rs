use super::plan::{SendPlan, SendRate};
use crate::bots::protocol::error::FeishuError;
use crate::bots::protocol::http::FeishuHttp;
use crate::bots::protocol::im::FeishuIm;
use crate::bots::storage::{BotStateStore, SendRecord, SendRecordStatus, SendSegmentFact};

pub struct ClaimedSend<'a> {
    pub http: &'a FeishuHttp,
    pub token: &'a str,
    pub bot_id: &'a str,
    pub chat_id: &'a str,
    pub operation_id: &'a str,
    pub store: &'a BotStateStore,
    pub plan: SendPlan,
    pub facts: Vec<SendSegmentFact>,
    pub rate: &'a SendRate,
}

pub async fn send_text(claimed: ClaimedSend<'_>) -> Result<crate::BotSendResult, FeishuError> {
    let ClaimedSend {
        http,
        token,
        bot_id,
        chat_id,
        operation_id,
        store,
        plan,
        mut facts,
        rate,
    } = claimed;
    let im = FeishuIm::new(http.clone());
    let mut segments = Vec::new();
    let mut ids = Vec::new();
    let mut unknown = false;
    let mut rejected = false;
    let progress =
        |ids: &[String], facts: &[SendSegmentFact], unknown: bool, rejected: bool| SendRecord {
            operation_id: operation_id.to_string(),
            bot_id: bot_id.to_string(),
            chat_id: chat_id.to_string(),
            content_hash: plan.content_hash.clone(),
            status: overall_send_status(unknown, rejected, ids.len(), plan.segments.len()),
            platform_message_ids: ids.to_vec(),
            segments: facts.to_vec(),
            facts_complete: true,
        };
    let mut status = None;
    for (index, segment) in plan.segments.iter().enumerate() {
        rate.acquire().await.start();
        match im
            .send_markdown(token, chat_id, segment, &plan.uuids[index])
            .await
        {
            Ok(outcome) => {
                ids.push(outcome.message_id.clone());
                segments.push(crate::BotSendSegment {
                    index: index as u32,
                    status: crate::BotSendStatus::Succeeded,
                    platform_message_id: Some(outcome.message_id.clone()),
                    diagnostic: None,
                });
                facts[index].status = SendRecordStatus::Succeeded;
                facts[index].platform_message_id = Some(outcome.message_id.clone());
            }
            Err(error) if error.acceptance_unknown() => {
                unknown = true;
                segments.push(crate::BotSendSegment {
                    index: index as u32,
                    status: crate::BotSendStatus::Unknown,
                    platform_message_id: None,
                    diagnostic: Some(error.diagnostic()),
                });
                facts[index].status = SendRecordStatus::Unknown;
                facts[index].diagnostic = Some(error.diagnostic().message);
            }
            Err(error) => {
                rejected = true;
                segments.push(crate::BotSendSegment {
                    index: index as u32,
                    status: crate::BotSendStatus::Rejected,
                    platform_message_id: None,
                    diagnostic: Some(error.diagnostic()),
                });
                facts[index].status = SendRecordStatus::Rejected;
                facts[index].diagnostic = Some(error.diagnostic().message);
            }
        }
        // Persist after every segment so a crash never loses which platform messages exist.
        status =
            Some(persist_send_progress(store, &progress(&ids, &facts, unknown, rejected)).await?);
        if unknown || rejected {
            break;
        }
    }
    // The last iteration already wrote the terminal record; only an empty plan still needs one.
    let status = match status {
        Some(status) => status,
        None => persist_send_progress(store, &progress(&ids, &facts, unknown, rejected)).await?,
    };
    Ok(crate::BotSendResult {
        operation_id: operation_id.to_string(),
        bot_id: bot_id.to_string(),
        chat_id: chat_id.to_string(),
        status: product_send_status(status),
        segments,
        receipt: crate::StudioCommandReceipt {
            operation_id: operation_id.to_string(),
            disposition: crate::CommandDisposition::Applied,
            targets: Vec::new(),
            effect: crate::CommandEffectPoint::Immediate,
            effective: true,
            durable: true,
            requires_identity_observation: false,
        },
    })
}

pub(crate) fn replay_send(
    existing: SendRecord,
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
) -> crate::BotSendResult {
    let facts_complete = existing.facts_complete;
    let status = product_send_status(existing.status);
    crate::BotSendResult {
        operation_id: operation_id.to_string(),
        bot_id: bot_id.to_string(),
        chat_id: chat_id.to_string(),
        status,
        segments: existing
            .segments
            .into_iter()
            .map(|fact| crate::BotSendSegment {
                index: fact.index,
                status: product_send_status(fact.status),
                platform_message_id: fact.platform_message_id,
                diagnostic: fact.diagnostic.map(|message| crate::BotDiagnostic {
                    code: "sendSegment".to_string(),
                    message,
                    retryable: false,
                    platform_code: None,
                    guidance: if facts_complete {
                        None
                    } else {
                        Some("legacySegmentFactsUnproven".to_string())
                    },
                }),
            })
            .collect(),
        receipt: crate::StudioCommandReceipt {
            operation_id: operation_id.to_string(),
            disposition: crate::CommandDisposition::NoChange,
            targets: Vec::new(),
            effect: crate::CommandEffectPoint::Immediate,
            effective: true,
            durable: true,
            requires_identity_observation: false,
        },
    }
}

async fn persist_send_progress(
    store: &BotStateStore,
    record: &SendRecord,
) -> Result<SendRecordStatus, FeishuError> {
    store.save_send(record).await?;
    Ok(record.status)
}

fn overall_send_status(
    unknown: bool,
    rejected: bool,
    succeeded: usize,
    planned_len: usize,
) -> SendRecordStatus {
    if unknown {
        SendRecordStatus::Unknown
    } else if rejected && succeeded == 0 {
        SendRecordStatus::Rejected
    } else if rejected || succeeded != planned_len {
        SendRecordStatus::Partial
    } else {
        SendRecordStatus::Succeeded
    }
}

fn product_send_status(status: SendRecordStatus) -> crate::BotSendStatus {
    match status {
        SendRecordStatus::Succeeded => crate::BotSendStatus::Succeeded,
        SendRecordStatus::Partial => crate::BotSendStatus::Partial,
        SendRecordStatus::Rejected => crate::BotSendStatus::Rejected,
        SendRecordStatus::Unknown => crate::BotSendStatus::Unknown,
    }
}
