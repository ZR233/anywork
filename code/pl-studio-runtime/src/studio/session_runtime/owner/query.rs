//! Read-only history paging, cursor binding and cold directory snapshots.
use super::*;
use crate::{AgentSessionReadDetail, AgentSessionReadOrder};
use base64::Engine;
use pl_core::tool::opaque::ToolError;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) enum Order {
    Ascending,
    #[default]
    Descending,
}
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) enum Detail {
    #[default]
    Text,
    Full,
}
#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct SessionInput {
    pub(crate) target: String,
    #[serde(default)]
    pub(crate) cursor: Option<String>,
    #[serde(default = "page_size")]
    pub(crate) limit: usize,
    #[serde(default)]
    pub(crate) order: Order,
    #[serde(default)]
    pub(crate) detail: Detail,
}
pub(crate) fn page_size() -> usize {
    20
}
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct Cursor {
    pub(crate) database_id: Option<String>,
    pub(crate) version: u32,
    pub(crate) target: String,
    pub(crate) through: u64,
    pub(crate) order: Order,
    pub(crate) detail: Detail,
    pub(crate) anchor: u64,
}
impl StudioSessionOwner {
    pub(crate) async fn session_page(
        &self,
        input: SessionInput,
        path: Vec<crate::AgentId>,
        cancellation: &CancellationToken,
    ) -> Result<AgentSessionPage> {
        let read = async {
            self.recovery
                .ensure_thread_read_access(&self.record(&input.target).await?)?;
            if !(1..=50).contains(&input.limit) {
                bail!("session limit must be between 1 and 50");
            }
            let cursor = input
                .cursor
                .as_ref()
                .map(|value| {
                    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(value)?;
                    Ok::<Cursor, anyhow::Error>(serde_json::from_slice(&bytes)?)
                })
                .transpose()?;
            if let Some(cursor) = &cursor
                && (cursor.version != 4
                    || cursor.target != input.target
                    || cursor.order != input.order
                    || cursor.detail != input.detail)
            {
                bail!("session cursor does not belong to this query");
            }
            let reader = self.store.open_history_reader(&input.target).await?;
            let database_id = Some(reader.database_id().to_owned());
            if let Some(cursor) = &cursor {
                anyhow::ensure!(
                    cursor.database_id == database_id,
                    "session cursor belongs to another history database"
                );
            }
            let (through, entries, more) = reader
                .events_window(
                    if input.detail == Detail::Text {
                        crate::history::HistoryEventsQuery::TextOriginals
                    } else {
                        crate::history::HistoryEventsQuery::Originals {
                            scope: crate::ChatScope {
                                query_class: crate::ChatClassFilter::All {},
                                parent_id: None,
                            },
                        }
                    },
                    cursor.as_ref().map(|cursor| cursor.through),
                    cursor.as_ref().map(|cursor| cursor.anchor),
                    input.order == Order::Ascending,
                    crate::history::HistoryDemand {
                        max_rows: input.limit as u32,
                        max_bytes: 64 * 1024,
                    },
                )
                .await?;
            let next_cursor =
                if more {
                    let anchor = entries
                        .last()
                        .context("session continuation has no anchor")?
                        .seq;
                    Some(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(
                        serde_json::to_vec(&Cursor {
                            version: 4,
                            database_id: database_id.clone(),
                            target: input.target.clone(),
                            through,
                            order: input.order,
                            detail: input.detail,
                            anchor,
                        })?,
                    ))
                } else {
                    None
                };
            Ok(AgentSessionPage {
                agent_id: self
                    .events
                    .agent_execution_identity(&input.target)
                    .map(|(identity, _, _)| identity.agent_id)
                    .context("agent directory identity is missing")?,
                path,
                history_through_seq: through,
                order: match input.order {
                    Order::Ascending => AgentSessionReadOrder::Ascending,
                    Order::Descending => AgentSessionReadOrder::Descending,
                },
                detail: match input.detail {
                    Detail::Text => AgentSessionReadDetail::Text,
                    Detail::Full => AgentSessionReadDetail::Full,
                },
                items: entries,
                has_more: more,
                next_cursor,
            })
        };
        tokio::select! {
            biased;
            () = cancellation.cancelled() => {
                Err(ToolError::new(pl_core::thread::ThreadError::Cancelled).into())
            }
            result = read => result,
        }
    }
}
/// 由 catalog 目录摘要构造只读 snapshot：仅承载 durable lifecycle，不含 Turn/Task 明细。
pub(crate) fn directory_snapshot(status: crate::ThreadStatus) -> pl_core::thread::ThreadSnapshot {
    use crate::ThreadStatus;
    use pl_core::thread::{ThreadLifecycle, ThreadSnapshot};
    ThreadSnapshot {
        lifecycle: match status {
            ThreadStatus::Closing => ThreadLifecycle::Closing,
            ThreadStatus::Closed => ThreadLifecycle::Closed,
            ThreadStatus::Idle
            | ThreadStatus::Queued
            | ThreadStatus::Running
            | ThreadStatus::WaitingTool
            | ThreadStatus::WaitingInteraction
            | ThreadStatus::Cancelling
            | ThreadStatus::Faulted => ThreadLifecycle::Open,
        },
        ..Default::default()
    }
}
