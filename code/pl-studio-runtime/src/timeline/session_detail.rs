//! Bounded JSON detail windows from one Feed-owned, immutable metadata cut.

use std::io::{self, Write};

use anyhow::Result;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{InteractionRequest, TodoListSnapshot};

use super::models::SessionMetaSnapshot;
use super::timeline_layer::BODY_CHUNK_READ_BYTES;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum SessionDetailKind {
    Plan,
    Interactions,
    Todo,
    Workflow,
    ActiveSkills,
    ActiveMcpServers,
    ActiveLspServers,
}

/// A byte window of the selected field's JSON, identified by its metadata cut.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct SessionDetailWindow {
    pub owner_epoch: String,
    pub revision: u64,
    pub offset: u64,
    pub total_bytes: u64,
    pub bytes: Vec<u8>,
}

#[derive(Serialize)]
#[serde(untagged)]
enum DetailValue {
    Plan(Option<crate::plan_tool::AgentSessionPlanRuntimeSnapshot>),
    Interactions(Vec<InteractionRequest>),
    Todo(Option<TodoListSnapshot>),
    Workflow(Option<crate::workflow_tool::WorkflowRuntimeSnapshot>),
    Names(Option<Vec<String>>),
}

/// Only the selected field is cloned while the original metadata owner is locked.
pub(super) struct SessionDetailSnapshot {
    owner_epoch: String,
    revision: u64,
    value: DetailValue,
}

impl SessionDetailSnapshot {
    pub(super) fn capture(meta: &SessionMetaSnapshot, kind: SessionDetailKind) -> Self {
        let runtime = meta.runtime.as_ref();
        let value = match kind {
            SessionDetailKind::Plan => DetailValue::Plan(meta.plan.clone()),
            SessionDetailKind::Interactions => DetailValue::Interactions(meta.interactions.clone()),
            SessionDetailKind::Todo => DetailValue::Todo(runtime.and_then(|r| r.todo.clone())),
            SessionDetailKind::Workflow => {
                DetailValue::Workflow(runtime.and_then(|r| r.workflow.clone()))
            }
            SessionDetailKind::ActiveSkills => {
                DetailValue::Names(runtime.map(|r| r.active_skills.clone()))
            }
            SessionDetailKind::ActiveMcpServers => {
                DetailValue::Names(runtime.map(|r| r.active_mcp_servers.clone()))
            }
            SessionDetailKind::ActiveLspServers => {
                DetailValue::Names(runtime.map(|r| r.active_lsp_servers.clone()))
            }
        };
        Self {
            owner_epoch: meta.owner_epoch.clone(),
            revision: meta.revision,
            value,
        }
    }

    pub(super) fn window(self, offset: u64, max_bytes: u32) -> Result<SessionDetailWindow> {
        let mut writer = JsonWindowWriter {
            offset,
            total_bytes: 0,
            limit: max_bytes.clamp(1, BODY_CHUNK_READ_BYTES) as usize,
            bytes: Vec::new(),
        };
        // Continue counting after the requested window is full, including requests beyond EOF.
        // The serializer never builds a second buffer containing the complete JSON document.
        serde_json::to_writer(&mut writer, &self.value)?;
        Ok(SessionDetailWindow {
            owner_epoch: self.owner_epoch,
            revision: self.revision,
            offset,
            total_bytes: writer.total_bytes,
            bytes: writer.bytes,
        })
    }
}

struct JsonWindowWriter {
    offset: u64,
    total_bytes: u64,
    limit: usize,
    bytes: Vec<u8>,
}

impl Write for JsonWindowWriter {
    fn write(&mut self, chunk: &[u8]) -> io::Result<usize> {
        let start = self.total_bytes;
        let length = u64::try_from(chunk.len())
            .map_err(|_| io::Error::other("session detail JSON length exceeds u64"))?;
        let end = start
            .checked_add(length)
            .ok_or_else(|| io::Error::other("session detail JSON length exceeds u64"))?;
        let from = self.offset.saturating_sub(start).min(length) as usize;
        let take = (chunk.len() - from).min(self.limit - self.bytes.len());
        self.bytes.extend_from_slice(&chunk[from..from + take]);
        self.total_bytes = end;
        Ok(chunk.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::plan_tool::{
        AgentSessionPlanDocument, AgentSessionPlanPhase, AgentSessionPlanRuntimeSnapshot,
    };
    use crate::timeline::{ConversationFeed, SessionMetaLayer};

    fn metadata(document: &str, revision: u64) -> SessionMetaSnapshot {
        let mut meta = SessionMetaLayer::empty("details").snapshot();
        meta.owner_epoch = format!("owner-{revision}");
        meta.revision = revision;
        meta.plan = Some(AgentSessionPlanRuntimeSnapshot {
            revision: 4,
            state: AgentSessionPlanPhase::Drafting,
            document: Some(AgentSessionPlanDocument {
                version: 2,
                markdown: document.into(),
                content_hash: "hash".into(),
            }),
            updated_at: 1,
        });
        meta
    }

    #[test]
    fn streaming_detail_windows_preserve_json_bytes_cap_and_true_eof_length() -> Result<()> {
        let names = vec!["中文🙂\n\"\\".repeat(20_000)];
        let expected = serde_json::to_vec(&names)?;
        let total = expected.len() as u64;
        assert!(total > u64::from(BODY_CHUNK_READ_BYTES));
        for (offset, max_bytes) in [
            (0, 0),
            (1, 7),
            (u64::from(BODY_CHUNK_READ_BYTES) - 1, u32::MAX),
            (total - 2, 10),
            (total, 10),
            (u64::MAX, 10),
        ] {
            let window = SessionDetailSnapshot {
                owner_epoch: "owner".into(),
                revision: 8,
                value: DetailValue::Names(Some(names.clone())),
            }
            .window(offset, max_bytes)?;
            let from = offset.min(total) as usize;
            let end =
                (from + max_bytes.clamp(1, BODY_CHUNK_READ_BYTES) as usize).min(expected.len());
            assert_eq!(window.bytes, expected[from..end], "offset {offset}");
            assert_eq!(window.total_bytes, total);
            assert_eq!(window.offset, offset);
            assert_eq!(window.owner_epoch, "owner");
            assert_eq!(window.revision, 8);
        }
        Ok(())
    }

    #[test]
    fn detail_kinds_select_existing_metadata_fields_and_serialize_absence_as_null() -> Result<()> {
        let mut meta = metadata("the full plan", 7);
        meta.runtime = Some(serde_json::from_value(serde_json::json!({
            "threadId": "details", "updatedAt": 1,
            "usage": {
                "diagnostics": crate::ThreadUsageDiagnostics::default(), "modelId": "test",
                "latestContextTokens": 0, "promptTokens": 0, "completionTokens": 0,
                "cachedPromptTokens": 0, "totalTokens": 0, "updatedAt": 1
            },
            "todo": {"callId": "todo", "items": [{"step": "one", "status": "pending"}]},
            "workflow": {"revision": 3},
            "activeSkills": ["skill"], "activeMcpServers": ["mcp"], "activeLspServers": ["lsp"]
        }))?);
        for (label, expected) in [
            ("plan", serde_json::to_value(meta.plan.as_ref().unwrap())?),
            ("interactions", serde_json::json!([])),
            (
                "todo",
                serde_json::json!({"callId": "todo", "items": [{"step": "one", "status": "pending"}]}),
            ),
            ("workflow", serde_json::json!({"revision": 3})),
            ("activeSkills", serde_json::json!(["skill"])),
            ("activeMcpServers", serde_json::json!(["mcp"])),
            ("activeLspServers", serde_json::json!(["lsp"])),
        ] {
            let kind: SessionDetailKind = serde_json::from_value(label.into())?;
            assert_eq!(serde_json::to_value(kind)?, label);
            let window = SessionDetailSnapshot::capture(&meta, kind).window(0, 4096)?;
            assert_eq!(
                serde_json::from_slice::<serde_json::Value>(&window.bytes)?,
                expected
            );
            let absent = SessionMetaLayer::empty("empty").snapshot();
            let window = SessionDetailSnapshot::capture(&absent, kind).window(0, 4096)?;
            assert_eq!(
                window.bytes,
                if kind == SessionDetailKind::Interactions {
                    b"[]".as_slice()
                } else {
                    b"null".as_slice()
                }
            );
        }
        Ok(())
    }

    #[test]
    fn detail_cut_keeps_original_owner_revision_and_document_after_metadata_changes() -> Result<()>
    {
        let layer = SessionMetaLayer::new(metadata("original", 10));
        let cut = layer.detail_snapshot(SessionDetailKind::Plan);
        layer.update(metadata("replacement", 11));
        let original = cut.window(0, 4096)?;
        let next = layer
            .detail_snapshot(SessionDetailKind::Plan)
            .window(0, 4096)?;
        assert_eq!(
            (original.owner_epoch.as_str(), original.revision),
            ("owner-10", 10)
        );
        assert_eq!((next.owner_epoch.as_str(), next.revision), ("owner-11", 11));
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&original.bytes)?["document"]["markdown"],
            "original"
        );
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&next.bytes)?["document"]["markdown"],
            "replacement"
        );
        assert_eq!(
            serde_json::to_value(SessionDetailWindow {
                owner_epoch: "owner".into(),
                revision: 2,
                offset: 4,
                total_bytes: 10,
                bytes: vec![123],
            })?,
            serde_json::json!({"ownerEpoch": "owner", "revision": 2, "offset": 4, "totalBytes": 10, "bytes": [123]})
        );
        Ok(())
    }

    #[tokio::test]
    async fn feed_detail_reads_full_internal_plan_without_history_queries_and_rejects_close()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = crate::history::HistoryStore::open(
            temp.path().join("history.sqlite"),
            "details",
            crate::history::HistoryLimits::default(),
        )
        .await?;
        let meta = metadata("full internal document", 5);
        let expected = serde_json::to_vec(&meta.plan)?;
        let feed = ConversationFeed::open_static("details", store.reader(), None, meta, 1).await?;
        let plan_head = feed.session_meta_snapshot().plan.unwrap();
        assert_eq!(plan_head.revision, 4);
        assert!(plan_head.document.is_none());
        let _ = feed.next_event().await; // Initial Reset
        let _ = feed.next_event().await; // Initial LiveStatus
        assert!(matches!(
            feed.next_event().await,
            Some(crate::ConversationEvent::SessionMeta(meta)) if meta.plan == Some(plan_head)
        ));
        let reads = store.read_query_count();
        let window = feed.read_session_detail(SessionDetailKind::Plan, 0, 4096)?;
        assert_eq!(window.bytes, expected);
        assert_eq!(
            (window.owner_epoch.as_str(), window.revision),
            ("owner-5", 5)
        );
        assert!(
            feed.read_session_detail(SessionDetailKind::Plan, u64::MAX, 4096)?
                .bytes
                .is_empty()
        );
        assert_eq!(store.read_query_count(), reads);
        feed.request_close();
        assert!(
            feed.read_session_detail(SessionDetailKind::Plan, 0, 4096)
                .is_err()
        );
        feed.close().await;
        assert!(
            feed.read_session_detail(SessionDetailKind::Plan, 0, 4096)
                .is_err()
        );
        store.close().await?;
        Ok(())
    }
}
