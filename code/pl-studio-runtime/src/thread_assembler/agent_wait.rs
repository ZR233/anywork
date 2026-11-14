//! Read-only source reports for ACP callers; no submission or completion ledger.
use base64::Engine;
use pl_tool::collaboration::{
    control::{AgentCallContext, ControlError},
    thread::AgentControlHost,
};
use serde_json::Value;
use std::{sync::Arc, time::Duration};
use tokio::{sync::watch, time::Instant};

use crate::{
    session::AgentRuntime,
    studio::runtime::{
        acp_business::AcpResources,
        thread_observation::{HistoryStatus, HistoryStore},
    },
};

/// Sum of complete serialized reports, excluding current and the MCP envelope.
const REPORT_BYTE_BUDGET: usize = 64 * 1024;

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct WaitAgentRequest {
    pub target: String,
    pub after: Option<String>,
    pub timeout_ms: u64,
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct WaitAgentResult {
    pub target: String,
    pub cursor: Option<String>,
    pub reports: Vec<serde_json::Value>,
    pub current: serde_json::Value,
    pub timed_out: bool,
    pub gap: bool,
}

fn invalid_cursor() -> ControlError {
    ControlError::service(std::io::Error::new(
        std::io::ErrorKind::InvalidInput,
        "invalid or stale agent report cursor",
    ))
}

fn service(error: anyhow::Error) -> ControlError {
    ControlError::service(super::agent_services::ServiceError(error))
}

#[derive(Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(tag = "backend", rename_all = "camelCase", deny_unknown_fields)]
enum Position {
    Native { sequence: u64 },
    Acp { generation: String, sequence: u64 },
}

impl Position {
    fn sequence(&self) -> u64 {
        match self {
            Self::Native { sequence } | Self::Acp { sequence, .. } => *sequence,
        }
    }
}

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct Cursor {
    version: u8,
    target: String,
    thread: String,
    position: Position,
}

impl Cursor {
    fn decode(value: &str, target: &str, thread: &str) -> Result<Position, ControlError> {
        // The encoding is opaque, not a persisted lookup or an authority token.
        if value.len() > 4096 {
            return Err(invalid_cursor());
        }
        let bytes = base64::prelude::BASE64_URL_SAFE_NO_PAD
            .decode(value)
            .map_err(|_| invalid_cursor())?;
        let cursor: Self = serde_json::from_slice(&bytes).map_err(|_| invalid_cursor())?;
        if cursor.version != 1
            || cursor.target != target
            || cursor.thread != thread
            || cursor.position.sequence() == 0
        {
            return Err(invalid_cursor());
        }
        Ok(cursor.position)
    }

    fn encode(target: &str, thread: &str, position: Position) -> Result<String, ControlError> {
        let cursor = Self {
            version: 1,
            target: target.into(),
            thread: thread.into(),
            position,
        };
        Ok(base64::prelude::BASE64_URL_SAFE_NO_PAD
            .encode(serde_json::to_vec(&cursor).map_err(ControlError::service)?))
    }
}

enum Source {
    Native {
        history: HistoryStore,
        changes: Option<watch::Receiver<HistoryStatus>>,
        thread: Option<pl_core::thread::ThreadHandle>,
        lifecycle: Option<pl_core::thread::ThreadSubscription>,
    },
    Acp {
        resources: Arc<AcpResources>,
        changes: watch::Receiver<u64>,
    },
}

struct Read {
    reports: Vec<Value>,
    position: Option<Position>,
    gap: bool,
    ended: bool,
}

impl Source {
    async fn read(&self, after: Option<&Position>) -> Result<Read, ControlError> {
        match self {
            Self::Native {
                history, thread, ..
            } => {
                let latest = history
                    .latest_terminal_report_sequence()
                    .await
                    .map_err(service)?;
                let sequences = match after {
                    Some(Position::Native { sequence }) if *sequence <= latest.unwrap_or(0) => {
                        history
                            .terminal_report_sequences(*sequence)
                            .await
                            .map_err(service)?
                    }
                    Some(_) => return Err(invalid_cursor()),
                    None => latest.into_iter().collect(),
                };
                let page = history
                    .terminal_reports(&sequences, REPORT_BYTE_BUDGET)
                    .await
                    .map_err(service)?;
                let mut reports = Vec::with_capacity(page.len());
                let mut position = None;
                for (sequence, report) in page {
                    reports.push(serde_json::to_value(report).map_err(ControlError::service)?);
                    position = Some(Position::Native { sequence });
                }
                Ok(Read {
                    reports,
                    position,
                    gap: false,
                    ended: thread.as_ref().is_none_or(|thread| {
                        thread.snapshot().lifecycle == pl_core::thread::ThreadLifecycle::Closed
                    }),
                })
            }
            Self::Acp { resources, .. } => {
                if let Some(position) = after
                    && !matches!(position, Position::Acp { generation, .. } if generation == &resources.generation)
                {
                    return Err(invalid_cursor());
                }
                let snapshot = resources
                    .session()
                    .map_err(service)?
                    .snapshot()
                    .await
                    .map_err(ControlError::service)?;
                acp_read(
                    &resources.generation,
                    snapshot.last_completed,
                    after,
                    snapshot.closing || resources.cancellation.is_cancelled(),
                )
            }
        }
    }

    async fn changed(&mut self) -> Result<(), ControlError> {
        match self {
            Self::Native {
                changes, lifecycle, ..
            } => {
                let changes = changes.as_mut().ok_or_else(|| {
                    service(anyhow::anyhow!(
                        "Native target has no original writer readability notification"
                    ))
                })?;
                loop {
                    tokio::select! {
                        changed = changes.changed() => {
                            return changed.map_err(|_| ControlError::Closed);
                        }
                        snapshot = async {
                            match lifecycle.as_mut() {
                                Some(lifecycle) => lifecycle.next().await,
                                None => std::future::pending::<Option<pl_core::thread::ThreadSnapshot>>().await,
                            }
                        } => {
                            if snapshot.is_none_or(|snapshot| snapshot.lifecycle == pl_core::thread::ThreadLifecycle::Closed) {
                                return Ok(());
                            }
                        }
                    }
                }
            }
            Self::Acp { resources, changes } => {
                tokio::select! {
                    // A closed notification also triggers one final read.
                    _ = changes.changed() => Ok(()),
                    () = resources.cancellation.cancelled() => Ok(()),
                }
            }
        }
    }
}

fn acp_read(
    generation: &str,
    completed: Option<pl_acp::session::Completed>,
    after: Option<&Position>,
    ended: bool,
) -> Result<Read, ControlError> {
    let latest = completed
        .as_ref()
        .map_or(0, |completed| completed.completion_sequence);
    if let Some(position) = after
        && (!matches!(position, Position::Acp { generation: value, .. } if value == generation)
            || position.sequence() > latest)
    {
        return Err(invalid_cursor());
    }
    let mut read = Read {
        reports: Vec::new(),
        position: None,
        gap: false,
        ended,
    };
    if let Some(completed) = completed
        && after.is_none_or(|position| completed.completion_sequence > position.sequence())
    {
        read.gap = after.is_some_and(|position| latest - position.sequence() > 1);
        read.position = Some(Position::Acp {
            generation: generation.into(),
            sequence: latest,
        });
        let report = serde_json::json!({
            "generation": generation,
            "run": { "instance": completed.run.instance, "sequence": completed.run.sequence },
            "completionSequence": completed.completion_sequence,
            "result": completed.result,
            "summary": completed.summary,
            "truncated": completed.truncated,
        });
        if serde_json::to_vec(&report)
            .map_err(ControlError::service)?
            .len()
            > REPORT_BYTE_BUDGET
        {
            return Err(service(anyhow::anyhow!(
                "ACP terminal report exceeds report byte budget ({REPORT_BYTE_BUDGET} bytes)"
            )));
        }
        read.reports.push(report);
    }
    Ok(read)
}

impl super::agents::AgentHost {
    async fn wait_current(
        &self,
        context: &AgentCallContext,
        target: &str,
    ) -> Result<Value, ControlError> {
        self.list(context.clone())
            .await?
            .into_iter()
            .find(|row| row["id"].as_str() == Some(target))
            .ok_or_else(|| ControlError::Missing(target.into()))
    }

    pub(crate) async fn wait_agent(
        &self,
        context: AgentCallContext,
        request: WaitAgentRequest,
    ) -> Result<WaitAgentResult, ControlError> {
        if request.timeout_ms == 0 || request.timeout_ms > 300_000 {
            return Err(ControlError::service(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "timeoutMs must be between 1 and 300000",
            )));
        }
        let deadline = Instant::now() + Duration::from_millis(request.timeout_ms);
        self.caller(&context)?;
        let identity = self.target_identity(&request.target)?;
        if identity.parent_agent_id.as_ref() != Some(&self.identity.agent_id)
            || identity.agent_id == self.identity.agent_id
        {
            return Err(ControlError::Relationship {
                caller: context.caller.to_string(),
                target: request.target,
            });
        }
        let after = request
            .after
            .as_deref()
            .map(|cursor| Cursor::decode(cursor, &request.target, identity.thread_id.as_str()))
            .transpose()?;
        let mut result = WaitAgentResult {
            target: request.target.clone(),
            cursor: request.after.clone(),
            reports: Vec::new(),
            current: Value::Null,
            timed_out: false,
            gap: false,
        };
        let observe = async {
            result.current = self.wait_current(&context, &request.target).await?;
            let owner = self.owner()?;
            let (native, acp, services) = {
                let state = owner.0.state();
                let entry = state.entries.get(identity.thread_id.as_str());
                let (native, acp) = match entry.map(|entry| &entry.runtime) {
                    Some(AgentRuntime::Native(native)) => (
                        Some((native.thread.clone(), native.resources.clone())),
                        None,
                    ),
                    Some(AgentRuntime::Acp(acp)) => (None, Some(acp.clone())),
                    None => (None, None),
                };
                (native, acp, state.agent_services.clone())
            };
            let mut source = if let Some(resources) = acp {
                let changes = resources.session().map_err(service)?.completion_changes();
                Source::Acp { resources, changes }
            } else {
                // Register the original incarnation's writer before even opening the reader.
                let changes = native.as_ref().and_then(|(_, resources)| {
                    resources
                        .observations
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .last()
                        .map(|observation| observation.report_changes())
                });
                let thread = native.map(|(thread, _)| thread);
                let lifecycle = thread.as_ref().map(|thread| thread.subscribe());
                let services = services.ok_or_else(|| {
                    service(anyhow::anyhow!(
                        "Native report history services are unavailable"
                    ))
                })?;
                let history = services
                    .store
                    .history(identity.thread_id.as_str())
                    .await
                    .map_err(service)?;
                Source::Native {
                    history,
                    changes,
                    thread,
                    lifecycle,
                }
            };
            loop {
                self.caller(&context)?;
                let read = source.read(after.as_ref()).await?;
                result.current = self.wait_current(&context, &request.target).await?;
                if !read.reports.is_empty() || read.ended {
                    result.reports = read.reports;
                    result.gap = read.gap;
                    if let Some(position) = read.position {
                        result.cursor = Some(Cursor::encode(
                            &request.target,
                            identity.thread_id.as_str(),
                            position,
                        )?);
                    }
                    return Ok::<(), ControlError>(());
                }
                source.changed().await?;
            }
        };
        tokio::select! {
            outcome = observe => outcome?,
            () = context.cancellation.cancelled() => return Err(ControlError::Closed),
            () = tokio::time::sleep_until(deadline) => result.timed_out = true,
        }
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cursors_bind_source_target_and_instance() {
        for position in [
            Position::Native { sequence: 42 },
            Position::Acp {
                generation: "generation-8".into(),
                sequence: 3,
            },
        ] {
            let encoded = Cursor::encode("child", "thread", position).unwrap();
            let decoded = Cursor::decode(&encoded, "child", "thread").unwrap();
            assert!(Cursor::decode(&encoded, "sibling", "thread").is_err());
            assert!(Cursor::decode(&encoded, "child", "other-thread").is_err());
            if matches!(decoded, Position::Acp { .. }) {
                assert!(acp_read("generation-9", None, Some(&decoded), false).is_err());
            }
        }
        assert!(Cursor::decode("not a cursor", "child", "thread").is_err());
        let zero = Cursor::encode("child", "thread", Position::Native { sequence: 0 }).unwrap();
        assert!(Cursor::decode(&zero, "child", "thread").is_err());
    }

    #[test]
    fn acp_cursor_rejects_a_new_generation_with_reused_protocol_run_numbers() {
        let old = uuid::Uuid::new_v4().to_string();
        let new = uuid::Uuid::new_v4().to_string();
        let cursor = Cursor::encode(
            "child",
            "thread",
            Position::Acp {
                generation: old,
                sequence: 1,
            },
        )
        .unwrap();
        let after = Cursor::decode(&cursor, "child", "thread").unwrap();
        assert!(acp_read(&new, Some(completed(1)), Some(&after), false).is_err());
        let latest = acp_read(&new, Some(completed(1)), None, false).unwrap();
        assert_eq!(latest.reports[0]["generation"], new);
    }

    fn completed(sequence: u64) -> pl_acp::session::Completed {
        pl_acp::session::Completed {
            run: pl_acp::session::RunId {
                instance: 17,
                sequence: sequence + 10,
            },
            completion_sequence: sequence,
            result: Ok(pl_acp::session::schema::PromptResponse::new(
                pl_acp::session::schema::StopReason::EndTurn,
            )),
            summary: "original completed response".into(),
            truncated: false,
        }
    }

    #[test]
    fn acp_retention_reports_gap_without_claiming_a_newer_run() {
        let after = Position::Acp {
            generation: "generation-8".into(),
            sequence: 2,
        };
        let read = acp_read("generation-8", Some(completed(5)), Some(&after), true).unwrap();
        assert!(read.gap && read.ended);
        assert_eq!(read.reports.len(), 1);
        assert_eq!(read.reports[0]["run"]["sequence"], 15);
        assert_eq!(read.reports[0]["summary"], "original completed response");
        assert_eq!(
            read.position,
            Some(Position::Acp {
                generation: "generation-8".into(),
                sequence: 5
            })
        );
        let future = Position::Acp {
            generation: "generation-8".into(),
            sequence: 6,
        };
        assert!(acp_read("generation-8", Some(completed(5)), Some(&future), false).is_err());
        assert!(
            acp_read(
                "generation-8",
                Some(completed(5)),
                Some(&Position::Native { sequence: 1 }),
                false
            )
            .is_err()
        );
        let latest = Position::Acp {
            generation: "generation-8".into(),
            sequence: 5,
        };
        let empty = acp_read("generation-8", Some(completed(5)), Some(&latest), false).unwrap();
        assert!(empty.reports.is_empty() && empty.position.is_none() && !empty.gap);
        let first = acp_read("generation-8", Some(completed(5)), None, false).unwrap();
        assert_eq!(first.reports.len(), 1);
        assert!(!first.gap);
        let overhead =
            serde_json::to_vec(&first.reports[0]).unwrap().len() - completed(5).summary.len();
        let mut boundary = completed(5);
        boundary.summary = "x".repeat(REPORT_BYTE_BUDGET - overhead);
        let exact = acp_read("generation-8", Some(boundary.clone()), None, false).unwrap();
        assert_eq!(
            serde_json::to_vec(&exact.reports[0]).unwrap().len(),
            REPORT_BYTE_BUDGET
        );
        boundary.summary.push('x');
        let error = acp_read("generation-8", Some(boundary), None, false)
            .err()
            .unwrap();
        assert!(error.to_string().contains("exceeds report byte budget"));
    }

    #[tokio::test]
    async fn native_wait_registers_before_read_and_reads_persisted_terminal_index() {
        let directory = tempfile::tempdir().unwrap();
        let history = HistoryStore::open(&directory.path().join("history.sqlite"), "child")
            .await
            .unwrap();
        let (writer, changes) = watch::channel(HistoryStatus::default());
        let mut source = Source::Native {
            history: history.clone(),
            changes: Some(changes),
            thread: None,
            lifecycle: None,
        };
        assert!(source.read(None).await.unwrap().reports.is_empty());
        // The writer commits between the reader's empty query and its first wait.
        // A registered watch must retain that notification instead of requiring polling.
        let item = crate::ExecutionItem::new(
            "turn:actual".into(),
            "child".into(),
            "actual".into(),
            1,
            1,
            1,
            1,
            crate::ExecutionShape::Turn(pl_protocol::ThreadTurnItem::new(
                pl_protocol::TurnState::Completed(pl_protocol::CompletedTurnState::new(
                    Some(1),
                    1,
                    pl_protocol::TurnCompletion::Normal,
                )),
            )),
        );
        crate::studio::storage::history::persist_completed(&history, 12, &[item])
            .await
            .unwrap();
        writer.send_modify(|status| status.committed_sequence = 12);
        tokio::time::timeout(Duration::from_millis(100), source.changed())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            history.latest_terminal_report_sequence().await.unwrap(),
            Some(12)
        );
        // A terminal without its original receipt is not a synthesized successful report.
        assert!(source.read(None).await.is_err());
        assert!(
            source
                .read(Some(&Position::Native { sequence: 13 }))
                .await
                .is_err()
        );
        assert!(
            source
                .read(Some(&Position::Acp {
                    generation: "generation-1".into(),
                    sequence: 1
                }))
                .await
                .is_err()
        );
        assert!(
            source
                .read(Some(&Position::Native { sequence: 12 }))
                .await
                .unwrap()
                .reports
                .is_empty()
        );
    }
}
