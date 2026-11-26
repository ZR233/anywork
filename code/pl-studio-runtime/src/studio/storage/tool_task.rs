//! Native task queries read the producer receipt carried by the canonical tool original.
use std::sync::Arc;

#[cfg(test)]
use pl_core::thread::cold::DurableToolTask;
use pl_core::thread::{ToolDelivery, task::TaskRecord};

use crate::history::{HistoryBody, HistoryBodyRole, HistoryError, Result};
#[cfg(test)]
use crate::history::{HistoryDemand, HistoryReader, read_event_body_bytes};

const BODY_KEY: &str = "native.tool-task.v1";

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StoredToolTask {
    task: TaskRecord,
    delivery: ToolDelivery,
}

impl StoredToolTask {
    fn validate(&self, task_id: &str, call_id: &str) -> Result<()> {
        let expected = match &self.delivery.outcome {
            pl_core::thread::ToolOutcome::Succeeded => pl_core::thread::task::TaskStatus::Succeeded,
            pl_core::thread::ToolOutcome::Failed(_) => pl_core::thread::task::TaskStatus::Failed,
            pl_core::thread::ToolOutcome::Cancelled => pl_core::thread::task::TaskStatus::Cancelled,
            pl_core::thread::ToolOutcome::Interrupted => {
                pl_core::thread::task::TaskStatus::Interrupted
            }
        };
        if self.task.id != task_id
            || self.task.call_id != call_id
            || self.delivery.call_id != call_id
            || self.task.tool_id != self.delivery.tool_id
            || self.task.status != expected
        {
            return Err(HistoryError::Integrity(
                "native tool receipt identity or outcome mismatch".into(),
            ));
        }
        Ok(())
    }
}

pub(in crate::studio) fn body(task: &TaskRecord, delivery: &ToolDelivery) -> Result<HistoryBody> {
    let saved = StoredToolTask {
        task: task.clone(),
        delivery: delivery.clone(),
    };
    saved.validate(&task.id, &delivery.call_id)?;
    let mut body = HistoryBody::new(
        BODY_KEY,
        HistoryBodyRole::Other {
            name: "native_tool_task".into(),
        },
        Arc::<[u8]>::from(serde_json::to_vec(&saved)?),
    );
    body.media_type = Some("application/json".into());
    Ok(body)
}

#[cfg(test)]
pub(in crate::studio) async fn read(
    reader: &HistoryReader,
    task_id: &str,
) -> Result<Option<DurableToolTask>> {
    // This is the core's receipt format, checked again against the stored task identity below.
    let Some(call_id) = task_id.strip_prefix("task:") else {
        return Ok(None);
    };
    let demand = HistoryDemand {
        max_rows: 64,
        max_bytes: 256 * 1024,
    };
    // The final event is keyed by call ID even when the timeline places it under an inbox
    // message. Reading by tool entity can select the earlier background handoff receipt.
    let original_id = crate::studio::thread_projection::order::tool_id(call_id);
    let event = match reader.read_event(original_id, demand).await {
        Ok(event) => event,
        Err(HistoryError::NotFound(_)) => return Ok(None),
        Err(error) => return Err(error),
    };
    if event.call_id.as_deref() != Some(call_id) {
        return Err(HistoryError::Integrity(
            "tool original call identity mismatch".into(),
        ));
    }
    let Some(bytes) = read_event_body_bytes(reader, &event, BODY_KEY, None).await? else {
        return Ok(None);
    };
    let saved: StoredToolTask = serde_json::from_slice(&bytes)?;
    saved.validate(task_id, call_id)?;
    Ok(Some(DurableToolTask {
        task: saved.task,
        delivery: Some(saved.delivery),
    }))
}
