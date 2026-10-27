//! Preserve the original terminal projection in child history before attempting parent delivery.
use super::ObservationServices;
use crate::studio::thread_projection::TurnResult;
use crate::thread_assembler::observation::ParentMessageDelivery;
use anyhow::Result;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::{ThreadSnapshot, TurnRecord},
};
use pl_protocol::Thread;

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct TurnReport<'a> {
    child_id: &'a str,
    commit_sequence: u64,
    turn: &'a TurnRecord,
    message: String,
    messages: Vec<MessageIdentity<'a>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    last_tool: Option<pl_protocol::ThreadToolItem>,
    running_tasks: Vec<&'a str>,
    pending_interactions: Vec<&'a str>,
    permissions: Vec<&'a pl_core::thread::permissions::PermissionRecord>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MessageIdentity<'a> {
    id: &'a str,
    source_id: &'a str,
    sequence: u64,
    consumed: bool,
}

pub(super) async fn publish_terminal(
    services: &ObservationServices,
    thread: &Thread,
    message: pl_core::thread::inbox::ThreadMessage,
    wake: bool,
) -> Result<Option<ParentMessageDelivery>> {
    let Some(parent) = thread.parent_thread_id.as_deref() else {
        return Ok(None);
    };
    let delivery = services
        .threads
        .notify_parent(parent, message, wake)
        .await?;
    match &delivery {
        ParentMessageDelivery::Accepted {
            message_id,
            sequence,
        } => {
            tracing::trace!(%message_id, parent_sequence = sequence, "terminal report admitted; durable receipt still required")
        }
        ParentMessageDelivery::ProvenExisting {
            message_id,
            sequence,
        } => {
            tracing::trace!(%message_id, parent_sequence = sequence, "terminal report already durable")
        }
        ParentMessageDelivery::Skipped(reason) => tracing::trace!(
            ?reason,
            "terminal report publication skipped; no delivery ACK"
        ),
    }
    // Keeping the child projection drainable during shutdown is not a delivery ACK. Retirement
    // separately verifies the exact report identities in the parent's durable history index.
    Ok(Some(delivery))
}

/// Frozen while the projection still owns the exact terminal write's snapshot and Turn result.
/// The writer stores this message alongside that effect, even if publication is skipped or fails.
pub(super) fn terminal_message(
    thread: &Thread,
    snapshot: &ThreadSnapshot,
    turn: &TurnRecord,
    sequence: u64,
    result: &TurnResult,
) -> Result<pl_core::thread::inbox::ThreadMessage> {
    let content = serde_json::to_string(&report(thread, turn, snapshot, result)?)?;
    Ok(pl_core::thread::inbox::ThreadMessage {
        kind: pl_core::context::AgentMessageKind::Report,
        id: crate::studio::agent_close::terminal_report_id(&thread.id, sequence),
        source_id: format!("studio.child:{}", thread.id),
        payload: OpaquePayload::new("pl.studio.turn-report", 1, content.clone())?,
        context: vec![ContextContent::Text {
            text: content.into(),
        }],
    })
}

fn report<'a>(
    thread: &'a Thread,
    turn: &'a TurnRecord,
    snapshot: &'a ThreadSnapshot,
    result: &'a TurnResult,
) -> Result<TurnReport<'a>> {
    let mut message = result.final_text().unwrap_or_default();
    let last_tool = if message.is_empty() {
        result.last_tool().cloned()
    } else {
        None
    };
    if message.is_empty() {
        message = format!(
            "本轮已停止，未提交最终总结。实际状态：{:?}。\n\n本轮已有可见输出：\n{}",
            turn.state,
            result.commentary()
        );
    }
    let message_item_ids = result
        .identities()
        .collect::<std::collections::BTreeSet<_>>();
    let through = snapshot
        .wake_messages_through
        .max(snapshot.consumed_messages);
    let messages = snapshot
        .inbox
        .iter()
        .filter(|record| {
            let item_id = crate::studio::thread_projection::order::message_id(&record.message.id);
            record.sequence <= through && message_item_ids.contains(item_id.as_str())
        })
        .map(|record| MessageIdentity {
            id: &record.message.id,
            source_id: &record.message.source_id,
            sequence: record.sequence,
            consumed: record.sequence <= snapshot.consumed_messages,
        })
        .collect();
    Ok(TurnReport {
        child_id: &thread.id,
        commit_sequence: snapshot.commit_sequence,
        turn,
        message,
        messages,
        last_tool,
        running_tasks: snapshot
            .tasks
            .values()
            .filter(|task| task.status == pl_core::thread::task::TaskStatus::Running)
            .map(|task| task.id.as_str())
            .collect(),
        pending_interactions: snapshot
            .interactions
            .values()
            .filter(|item| item.state == pl_core::thread::interactions::InteractionState::Pending)
            .map(|item| item.request.id.as_str())
            .collect(),
        permissions: snapshot
            .permissions
            .values()
            .filter(|item| {
                item.turn_id == turn.turn_id
                    || item.state == pl_core::thread::permissions::PermissionState::Pending
            })
            .collect(),
    })
}
