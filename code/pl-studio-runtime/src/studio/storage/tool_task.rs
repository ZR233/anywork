//! Native task queries read the producer receipt carried by the canonical tool original.
use std::sync::Arc;

use pl_core::thread::{ToolDelivery, cold::DurableToolTask, task::TaskRecord};

use crate::history::{
    BODY_CHUNK_BYTES, HistoryBody, HistoryBodyRole, HistoryDemand, HistoryError, HistoryReader,
    Result,
};

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
    let Some(event) = reader
        .original_for_entity(
            crate::studio::thread_projection::order::tool_id(call_id),
            demand,
        )
        .await?
    else {
        return Ok(None);
    };
    if event.header.call_id.as_deref() != Some(call_id) {
        return Err(HistoryError::Integrity(
            "tool original call identity mismatch".into(),
        ));
    }
    let mut cursor = None;
    loop {
        let page = reader
            .list_bodies(event.header.event_id.clone(), cursor, demand)
            .await?;
        for entry in page.entries {
            if entry.reference.body_key != BODY_KEY {
                continue;
            }
            let reference = entry.reference;
            let mut bytes = Vec::new();
            while (bytes.len() as u64) < reference.byte_length {
                let window = reader
                    .read_body(
                        reference.clone(),
                        bytes.len() as u64,
                        BODY_CHUNK_BYTES as u32,
                    )
                    .await?;
                if window.bytes.is_empty() || window.total_length != reference.byte_length {
                    return Err(HistoryError::Integrity(
                        "native tool receipt body did not advance".into(),
                    ));
                }
                bytes.extend(window.bytes);
            }
            let saved: StoredToolTask = serde_json::from_slice(&bytes)?;
            saved.validate(task_id, call_id)?;
            return Ok(Some(DurableToolTask {
                task: saved.task,
                delivery: Some(saved.delivery),
            }));
        }
        cursor = page.next;
        if cursor.is_none() {
            return Ok(None);
        }
    }
}
