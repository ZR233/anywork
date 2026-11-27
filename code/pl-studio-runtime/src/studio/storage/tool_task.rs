//! Native task queries read the producer receipt carried by the canonical tool original.
use std::sync::Arc;

use pl_core::thread::cold::DurableToolTask;
use pl_core::thread::{ToolDelivery, task::TaskRecord};

use crate::history::{HistoryBody, HistoryBodyRole, HistoryError, HistoryReader, Result};
use serde_json::value::RawValue;

pub(crate) const BODY_KEY: &str = "native.tool-task.v2";

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StoredToolTask {
    task: TaskRecord,
    delivery: ToolDelivery,
}

impl StoredToolTask {
    fn validate(&self, call_id: &str) -> Result<()> {
        let expected = match &self.delivery.outcome {
            pl_core::thread::ToolOutcome::Succeeded => pl_core::thread::task::TaskStatus::Succeeded,
            pl_core::thread::ToolOutcome::Failed(_) => pl_core::thread::task::TaskStatus::Failed,
            pl_core::thread::ToolOutcome::Cancelled => pl_core::thread::task::TaskStatus::Cancelled,
            pl_core::thread::ToolOutcome::Interrupted => {
                pl_core::thread::task::TaskStatus::Interrupted
            }
        };
        if self.task.id != format!("task:{call_id}")
            || self.task.call_id != call_id
            || self.delivery.call_id != call_id
            || self.task.tool_id != self.delivery.tool_id
            || self.task.status != expected
            || self.task.invocation.as_ref().is_some_and(|invocation| {
                invocation.call_id != call_id || invocation.tool_id != self.task.tool_id
            })
        {
            return Err(HistoryError::Integrity(
                "native tool receipt identity or outcome mismatch".into(),
            ));
        }
        Ok(())
    }
}

pub(crate) fn body(task: &TaskRecord, delivery: &ToolDelivery) -> Result<HistoryBody> {
    let saved = StoredToolTask {
        task: task.clone(),
        delivery: delivery.clone(),
    };
    saved.validate(&delivery.call_id)?;
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

/// Converts the retired receipt envelope at the history maintenance boundary.
pub(crate) fn upgrade_v1_body(bytes: &[u8], call_id: &str) -> Result<HistoryBody> {
    #[derive(serde::Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Receipt<'a> {
        task: TaskRecord,
        #[serde(borrow)]
        delivery: &'a RawValue,
    }
    let old: Receipt<'_> = serde_json::from_slice(bytes)?;
    let delivery = super::tool_result_upgrade::decode_delivery(old.delivery.get().as_bytes())?;
    StoredToolTask {
        task: old.task.clone(),
        delivery: delivery.clone(),
    }
    .validate(call_id)?;
    body(&old.task, &delivery)
}

pub(crate) async fn read(reader: &HistoryReader, id: &str) -> Result<Option<DurableToolTask>> {
    async fn by_call(reader: &HistoryReader, call_id: &str) -> Result<Option<StoredToolTask>> {
        let original_id = crate::studio::thread_projection::order::tool_id(call_id);
        let Some(bytes) = reader
            .read_committed_tool_receipt(call_id.to_owned(), original_id, BODY_KEY)
            .await?
        else {
            return Ok(None);
        };
        let saved: StoredToolTask = serde_json::from_slice(&bytes)?;
        saved.validate(call_id)?;
        Ok(Some(saved))
    }
    if id.is_empty() {
        return Ok(None);
    }
    let by_task = match id
        .strip_prefix("task:")
        .filter(|call_id| !call_id.is_empty())
    {
        Some(call_id) => by_call(reader, call_id).await?,
        None => None,
    };
    let by_exact_call = by_call(reader, id).await?;
    if by_task.is_some() && by_exact_call.is_some() {
        return Err(HistoryError::Integrity(
            "ambiguous task and call identities".into(),
        ));
    }
    Ok(by_task.or(by_exact_call).map(|saved| DurableToolTask {
        task: saved.task,
        delivery: Some(saved.delivery),
    }))
}
