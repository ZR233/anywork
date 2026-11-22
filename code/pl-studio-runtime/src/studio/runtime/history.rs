//! Independent append-only history access for Native production consumers.

use crate::{StudioError, StudioErrorCode, StudioErrorReason};
use anyhow::{Context, Result};

use crate::studio::StudioRuntime;

impl StudioRuntime {
    /// Opens a bounded history reader after protocol, Thread and permission checks.
    ///
    /// This path never loads `current.json`, activates an execution owner, flushes a writer, or
    /// waits for current persistence. A missing database is a visible NotFound error, never an
    /// empty-history substitute.
    pub async fn open_history_reader(
        &self,
        thread_id: &str,
        history_protocol_version: u32,
    ) -> Result<crate::history::HistoryReader> {
        if history_protocol_version != crate::history::HISTORY_PROTOCOL_VERSION {
            return Err(anyhow::Error::new(
                StudioError::new(
                    StudioErrorCode::Protocol,
                    "unsupported Native history protocol version",
                    false,
                )
                .with_reason(
                    StudioErrorReason::ProtocolVersionMismatch,
                    serde_json::json!({
                        "expected": crate::history::HISTORY_PROTOCOL_VERSION,
                        "received": history_protocol_version,
                    }),
                ),
            ));
        }
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        self.store.open_history_reader(thread_id).await
    }
}

pub(crate) async fn history_turn(
    reader: &crate::history::HistoryReader,
    head: crate::history::HistoryTurnHead,
) -> Result<crate::Turn> {
    let detail_event_id = head.detail_event_id.clone().ok_or_else(|| {
        anyhow::anyhow!(
            "history Turn {} has no immutable original detail",
            head.turn_id
        )
    })?;
    let detail = reader
        .read_event(
            detail_event_id,
            crate::history::HistoryDemand {
                max_rows: 1,
                max_bytes: 1024 * 1024,
            },
        )
        .await
        .map_err(anyhow::Error::from)?;
    let Some(bytes) =
        crate::history::read_event_body_bytes(reader, &detail, "turn_detail", None)
            .await
            .map_err(anyhow::Error::from)?
    else {
        anyhow::bail!("history Turn {} detail body is missing", head.turn_id);
    };
    serde_json::from_slice(&bytes).context("decode immutable Turn detail")
}
