//! Current-owned pending Native delivery obligations and their recovery.
//!
//! A marker is a delivery obligation, not a second history or report projection. It carries the
//! exact immutable message until the recipient's Current proves acceptance, then it is deleted.
//! Before the first marker flush, the original operation still owns retry responsibility, but a
//! process crash cannot recover RAM-only material. This is not a cross-store atomic transaction.
use super::{
    SessionRuntime,
    agent_services::AgentServices,
    review_delivery::{DeliveryObservation, ReviewDeliveryException},
};
use anyhow::{Context, Result, ensure};
use pl_core::{
    context::{AgentMessageKind, ContextContent, OpaquePayload},
    thread::{ThreadError, ThreadHandle, extensions::ExtensionMutation, inbox::ThreadMessage},
};
use serde::{Deserialize, Serialize};

pub(super) const PENDING_NATIVE_DELIVERY_FORMAT: &str = "pl.studio.pending-native-delivery";
pub(super) const PENDING_NATIVE_DELIVERY_VERSION: u32 = 1;
pub(super) const PENDING_NATIVE_DELIVERY_EXTENSION_PREFIX: &str = "studio.pending-native-delivery:";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum PendingNativeDeliveryKind {
    ParentReport,
    ReviewDecision,
    ReviewException,
    AcpResult,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    rename_all = "camelCase",
    tag = "kind",
    content = "detail",
    deny_unknown_fields
)]
pub(super) enum PendingNativeDeliverySource {
    Terminal {
        child_id: String,
        terminal_sequence: u64,
    },
    AcpResult {
        agent_id: String,
        generation: String,
        completion_sequence: u64,
    },
}

/// Exact original delivery material. The extension key is its stable message ID.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct PendingNativeDelivery {
    kind: PendingNativeDeliveryKind,
    message: ThreadMessage,
    message_digest: String,
    source: PendingNativeDeliverySource,
    wake: bool,
    #[serde(default)]
    accepted: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ParentReportIdentity {
    child_id: String,
    commit_sequence: u64,
    #[serde(default)]
    review: Option<serde::de::IgnoredAny>,
}

impl PendingNativeDelivery {
    /// Reconstructs the typed marker from one message produced by an existing terminal path.
    pub(super) fn from_terminal_message(message: ThreadMessage, wake: bool) -> Result<Self> {
        let (kind, source, wake) = if message.payload.format() == "pl.studio.turn-report"
            && message.payload.version() == 3
        {
            let report: ParentReportIdentity = serde_json::from_str(message.payload.content())?;
            (
                PendingNativeDeliveryKind::ParentReport,
                PendingNativeDeliverySource::Terminal {
                    child_id: report.child_id,
                    terminal_sequence: report.commit_sequence,
                },
                wake,
            )
        } else if message.payload.format() == super::review_delivery::MESSAGE_FORMAT
            && message.payload.version() == 1
        {
            let exception: ReviewDeliveryException =
                serde_json::from_str(message.payload.content())?;
            (
                PendingNativeDeliveryKind::ReviewException,
                PendingNativeDeliverySource::Terminal {
                    child_id: exception.reviewer_id,
                    terminal_sequence: exception.terminal_sequence,
                },
                exception.observation == DeliveryObservation::LiveTerminal,
            )
        } else if message.id.starts_with("studio.acp.") {
            (
                PendingNativeDeliveryKind::AcpResult,
                parse_acp_source(&message)?,
                wake,
            )
        } else {
            anyhow::bail!("message is not a supported pending Native delivery");
        };
        Self::new(kind, message, source, wake)
    }

    /// Source-owned decision marker retained until review feedback or its exception is settled.
    pub(super) fn review_decision(message: ThreadMessage) -> Result<Self> {
        ensure!(
            message.payload.format() == "pl.studio.turn-report" && message.payload.version() == 3,
            "review decision requires the immutable terminal report"
        );
        let report: ParentReportIdentity = serde_json::from_str(message.payload.content())?;
        ensure!(
            report.review.is_some(),
            "review decision requires a structured review result"
        );
        Self::new(
            PendingNativeDeliveryKind::ReviewDecision,
            message,
            PendingNativeDeliverySource::Terminal {
                child_id: report.child_id,
                terminal_sequence: report.commit_sequence,
            },
            false,
        )
    }

    fn new(
        kind: PendingNativeDeliveryKind,
        message: ThreadMessage,
        source: PendingNativeDeliverySource,
        wake: bool,
    ) -> Result<Self> {
        let pending = Self {
            kind,
            message_digest: message.digest(),
            message,
            source,
            wake,
            accepted: false,
        };
        pending.validate()?;
        Ok(pending)
    }

    pub(super) fn message(&self) -> &ThreadMessage {
        &self.message
    }

    pub(super) fn source(&self) -> &PendingNativeDeliverySource {
        &self.source
    }

    pub(super) fn is_review_decision(&self) -> bool {
        self.kind == PendingNativeDeliveryKind::ReviewDecision
    }

    fn accepted(&self) -> bool {
        self.accepted
    }

    fn with_accepted(&self, accepted: bool) -> Self {
        let mut pending = self.clone();
        pending.accepted = accepted;
        pending
    }

    fn same_immutable(&self, other: &Self) -> bool {
        self.kind == other.kind
            && self.message == other.message
            && self.message_digest == other.message_digest
            && self.source == other.source
            && self.wake == other.wake
    }

    pub(super) fn terminal_sequence(&self) -> Option<u64> {
        match &self.source {
            PendingNativeDeliverySource::Terminal {
                terminal_sequence, ..
            } => Some(*terminal_sequence),
            PendingNativeDeliverySource::AcpResult { .. } => None,
        }
    }

    pub(super) fn extension_id(&self) -> String {
        format!(
            "{PENDING_NATIVE_DELIVERY_EXTENSION_PREFIX}{}",
            self.message.id
        )
    }

    pub(super) fn encode(&self) -> Result<OpaquePayload> {
        Ok(OpaquePayload::new(
            PENDING_NATIVE_DELIVERY_FORMAT,
            PENDING_NATIVE_DELIVERY_VERSION,
            serde_json::to_string(self)?,
        )?)
    }

    pub(super) fn decode(extension_id: &str, payload: &OpaquePayload) -> Result<Self> {
        ensure!(
            payload.format() == PENDING_NATIVE_DELIVERY_FORMAT
                && payload.version() == PENDING_NATIVE_DELIVERY_VERSION,
            "unsupported pending Native delivery format"
        );
        let pending: Self = serde_json::from_str(payload.content())?;
        ensure!(
            extension_id
                == format!(
                    "{PENDING_NATIVE_DELIVERY_EXTENSION_PREFIX}{}",
                    pending.message.id
                ),
            "pending Native delivery identity differs from its extension key"
        );
        pending.validate()?;
        Ok(pending)
    }

    fn validate(&self) -> Result<()> {
        ensure!(
            !self.message.id.is_empty()
                && !self.message.source_id.is_empty()
                && self.message.kind == AgentMessageKind::Report,
            "pending Native delivery has an invalid message identity"
        );
        ensure!(
            self.message_digest == self.message.digest(),
            "pending Native delivery digest differs from its exact message"
        );
        ensure!(
            !self.accepted || !self.is_review_decision(),
            "source-owned review decision cannot enter the accepted phase"
        );
        match (&self.kind, &self.source) {
            (
                PendingNativeDeliveryKind::ParentReport,
                PendingNativeDeliverySource::Terminal {
                    child_id,
                    terminal_sequence,
                },
            ) => {
                let report: ParentReportIdentity =
                    serde_json::from_str(self.message.payload.content())?;
                ensure!(
                    !child_id.is_empty()
                        && *terminal_sequence > 0
                        && self.message.id
                            == crate::studio::agent_close::terminal_report_id(
                                child_id,
                                *terminal_sequence
                            )
                        && self.message.source_id == format!("studio.child:{child_id}")
                        && report.child_id == *child_id
                        && report.commit_sequence == *terminal_sequence,
                    "parent report pending identity mismatch"
                );
            }
            (
                PendingNativeDeliveryKind::ReviewDecision,
                PendingNativeDeliverySource::Terminal {
                    child_id,
                    terminal_sequence,
                },
            ) => {
                let report: ParentReportIdentity =
                    serde_json::from_str(self.message.payload.content())?;
                ensure!(
                    !child_id.is_empty()
                        && *terminal_sequence > 0
                        && self.message.id
                            == crate::studio::agent_close::terminal_report_id(
                                child_id,
                                *terminal_sequence
                            )
                        && self.message.source_id == format!("studio.child:{child_id}")
                        && report.child_id == *child_id
                        && report.commit_sequence == *terminal_sequence
                        && report.review.is_some()
                        && !self.wake,
                    "review decision pending identity mismatch"
                );
            }
            (
                PendingNativeDeliveryKind::ReviewException,
                PendingNativeDeliverySource::Terminal {
                    child_id,
                    terminal_sequence,
                },
            ) => {
                ensure!(
                    self.message.payload.format() == super::review_delivery::MESSAGE_FORMAT
                        && self.message.payload.version() == 1,
                    "review exception pending payload format mismatch"
                );
                let exception: ReviewDeliveryException =
                    serde_json::from_str(self.message.payload.content())?;
                ensure!(
                    exception.message_id() == self.message.id
                        && exception.reviewer_id == *child_id
                        && exception.terminal_sequence == *terminal_sequence
                        && *terminal_sequence > 0
                        && !exception.turn_id.is_empty()
                        && !exception.target_agent_id.is_empty()
                        && exception.feedback_message_id
                            == super::agent_review::review_message_id(
                                &exception.reviewer_id,
                                &exception.turn_id,
                                exception.terminal_sequence
                            )
                        && self.message.source_id
                            == format!("studio.review:{}", exception.reviewer_id)
                        && self.message.context
                            == vec![ContextContent::Text {
                                text: self.message.payload.content().to_owned().into()
                            }],
                    "review exception pending identity mismatch"
                );
            }
            (
                PendingNativeDeliveryKind::AcpResult,
                PendingNativeDeliverySource::AcpResult {
                    agent_id,
                    generation,
                    completion_sequence,
                },
            ) => {
                ensure!(
                    !agent_id.is_empty()
                        && !generation.is_empty()
                        && *completion_sequence > 0
                        && self.message.id
                            == format!(
                                "studio.acp.{}:{agent_id}:{generation}:{completion_sequence}",
                                agent_id.len()
                            )
                        && self.message.source_id.starts_with("agent:"),
                    "ACP result pending identity mismatch"
                );
            }
            _ => anyhow::bail!("pending Native delivery kind differs from its source"),
        }
        Ok(())
    }
}

fn parse_acp_source(message: &ThreadMessage) -> Result<PendingNativeDeliverySource> {
    let rest = message
        .id
        .strip_prefix("studio.acp.")
        .context("ACP result has no delivery identity")?;
    let (length, rest) = rest
        .split_once(':')
        .context("ACP result has no agent length")?;
    let length = length.parse::<usize>()?;
    ensure!(
        rest.is_char_boundary(length),
        "ACP result agent identity is not a UTF-8 boundary"
    );
    let (agent_id, tail) = rest.split_at(length);
    let tail = tail
        .strip_prefix(':')
        .context("ACP result has no generation")?;
    let mut sequence = tail.split(':');
    let generation = sequence
        .next()
        .context("ACP result has no generation")?
        .to_owned();
    let completion_sequence = sequence
        .next()
        .context("ACP result has no completion sequence")?
        .parse::<u64>()?;
    ensure!(
        sequence.next().is_none(),
        "ACP result has trailing identity fields"
    );
    Ok(PendingNativeDeliverySource::AcpResult {
        agent_id: agent_id.into(),
        generation,
        completion_sequence,
    })
}

impl SessionRuntime {
    /// Inspect only the resident owner, including a closing one.
    pub(super) fn delivery_snapshot(
        &self,
        record: &crate::Thread,
    ) -> Result<Option<pl_core::thread::ThreadSnapshot>> {
        Ok(self
            .observed_thread(&record.id)
            .map(|thread| thread.snapshot()))
    }

    /// Cold recovery preparation, never a lookup used to validate live delivery or admission.
    pub(super) async fn restore_delivery_snapshot(
        &self,
        record: &crate::Thread,
    ) -> Result<Option<pl_core::thread::ThreadSnapshot>> {
        if let Some(current) = self.delivery_snapshot(record)? {
            return Ok(Some(current));
        }
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("pending delivery services unavailable")?;
        Ok(
            crate::studio::thread_factory::recovery::load_current_read_only(
                &services.store,
                record,
            )
            .await?
            .map(|current| current.state.to_paused_snapshot()),
        )
    }

    /// Reads only explicit markers in one Thread's Current. Absence never reconstructs work from
    /// History; recipient deliveries and source-owned review decisions are classified by kind.
    pub(super) async fn pending_native_deliveries(
        &self,
        recipient: &crate::Thread,
    ) -> Result<Vec<PendingNativeDelivery>> {
        let Some(current) = self.restore_delivery_snapshot(recipient).await? else {
            return Ok(Vec::new());
        };
        current
            .extensions
            .iter()
            .filter(|(id, _)| id.starts_with(PENDING_NATIVE_DELIVERY_EXTENSION_PREFIX))
            .map(|(id, record)| PendingNativeDelivery::decode(id, &record.payload))
            .collect()
    }

    /// Replays only explicit Current markers through the storage-only recipient path.
    pub(super) async fn recover_pending_native_deliveries(
        &self,
        recipient: &crate::Thread,
    ) -> Result<()> {
        let pending = self
            .pending_native_deliveries(recipient)
            .await?
            .into_iter()
            .filter(|delivery| !delivery.is_review_decision())
            .collect::<Vec<_>>();
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("pending delivery services unavailable")?;
        for delivery in pending {
            services
                .deliver_pending_native(self, &recipient.id, delivery)
                .await?;
        }
        // Marker removal can precede the final save and a failed receiver cleanup. Absence of
        // replay work does not discharge that receiver's original writer/observation ownership.
        self.finish_report_receiver(&recipient.id).await?;
        Ok(())
    }
}

pub(super) async fn complete_pending_native_delivery(
    services: &AgentServices,
    owner: &SessionRuntime,
    recipient: &str,
    thread: &ThreadHandle,
    pending: PendingNativeDelivery,
    allow_wake: bool,
) -> Result<()> {
    ensure!(
        !pending.is_review_decision(),
        "source-owned review decision is not a recipient delivery"
    );
    let extension_id = pending.extension_id();
    let (_, initial_revision) = ensure_recipient_marker(thread, &pending).await?;

    // The marker must be durable before acceptance is allowed to begin.
    services
        .store
        .conversation_store(recipient)
        .await?
        .flush_current(thread.runtime_epoch())
        .await?;

    let (marker, marker_revision) = marker_from_snapshot(thread, &extension_id, &pending)?
        .context("pending Native delivery marker disappeared before admission")?;
    ensure!(
        marker_revision == initial_revision,
        "pending Native delivery marker changed before admission"
    );
    if !marker.accepted() {
        let accepted = marker.with_accepted(true);
        thread
            .send_message_with_extensions(
                pending.message().clone(),
                vec![ExtensionMutation::Put {
                    id: extension_id.clone(),
                    expected_revision: Some(marker_revision),
                    payload: accepted.encode()?,
                }],
            )
            .await?;
    }

    // The atomic Core command stages both the message and accepted marker. Once this marker says
    // accepted, neither the bounded consumed ledger nor message replay is an admission authority.
    services
        .store
        .conversation_store(recipient)
        .await?
        .flush_current(thread.runtime_epoch())
        .await?;
    if pending.wake && allow_wake {
        let inbox = thread
            .snapshot()
            .inbox
            .iter()
            .find(|record| record.message.id == pending.message.id)
            .cloned();
        if let Some(record) = inbox {
            ensure!(
                record.message.digest() == pending.message_digest.as_str(),
                "accepted pending Native delivery conflicts with its resident inbox identity"
            );
            let options = native_execution_options(owner, recipient)?;
            thread
                .wake_accepted_message(&pending.message.id, record.sequence, options)
                .await?;
        }
    }

    let marker = marker_from_snapshot(thread, &extension_id, &pending)?;
    if let Some((marker, revision)) = marker {
        ensure!(
            marker.accepted(),
            "pending Native delivery lost its accepted phase before cleanup"
        );
        // Delete is the final fallible business action. The accepted marker may remain on disk until
        // the Current writer's next save; recovery then performs cleanup without sending again.
        thread
            .mutate_extensions(vec![ExtensionMutation::Delete {
                id: extension_id,
                expected_revision: revision,
            }])
            .await?;
    }
    Ok(())
}

async fn ensure_recipient_marker(
    thread: &ThreadHandle,
    pending: &PendingNativeDelivery,
) -> Result<(PendingNativeDelivery, u64)> {
    let extension_id = pending.extension_id();
    let resident = thread.snapshot().extensions.get(&extension_id).cloned();
    let marker = resident
        .as_ref()
        .map(|record| PendingNativeDelivery::decode(&extension_id, &record.payload))
        .transpose()?;
    if let Some(marker) = &marker {
        ensure!(
            marker.same_immutable(pending),
            "pending Native delivery conflicts with its current marker"
        );
    }
    let accepted =
        pending.accepted() || marker.as_ref().is_some_and(PendingNativeDelivery::accepted);
    if let (Some(record), Some(marker)) = (&resident, &marker)
        && marker.accepted() == accepted
    {
        return Ok((marker.clone(), record.revision));
    }
    let desired = pending.with_accepted(accepted);
    let changed = thread
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: extension_id.clone(),
            expected_revision: resident.as_ref().map(|record| record.revision),
            payload: desired.encode()?,
        }])
        .await?;
    let revision = changed
        .get(&extension_id)
        .context("pending Native delivery marker was not committed")?
        .revision;
    Ok((desired, revision))
}

fn marker_from_snapshot(
    thread: &ThreadHandle,
    extension_id: &str,
    pending: &PendingNativeDelivery,
) -> Result<Option<(PendingNativeDelivery, u64)>> {
    let Some(record) = thread.snapshot().extensions.get(extension_id).cloned() else {
        return Ok(None);
    };
    let marker = PendingNativeDelivery::decode(extension_id, &record.payload)?;
    ensure!(
        marker.same_immutable(pending),
        "resident pending Native delivery marker changed its immutable material"
    );
    Ok(Some((marker, record.revision)))
}

async fn ensure_marker(
    thread: &ThreadHandle,
    extension_id: &str,
    pending: &PendingNativeDelivery,
) -> Result<u64> {
    if let Some(record) = thread.snapshot().extensions.get(extension_id) {
        let saved = PendingNativeDelivery::decode(extension_id, &record.payload)?;
        ensure!(
            saved.same_immutable(pending),
            "pending Native delivery conflicts with its Current marker"
        );
        return Ok(record.revision);
    }
    let records = match thread
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: extension_id.into(),
            expected_revision: None,
            payload: pending.encode()?,
        }])
        .await
    {
        Ok(records) => records,
        Err(ThreadError::ExtensionConflict { .. }) => {
            let record = thread
                .snapshot()
                .extensions
                .get(extension_id)
                .cloned()
                .context("pending Native delivery marker disappeared after conflict")?;
            let saved = PendingNativeDelivery::decode(extension_id, &record.payload)?;
            ensure!(
                saved.same_immutable(pending),
                "pending Native delivery conflicts with its Current marker"
            );
            return Ok(record.revision);
        }
        Err(error) => return Err(error.into()),
    };
    let record = records
        .get(extension_id)
        .context("pending Native delivery marker was not committed")?;
    let saved = PendingNativeDelivery::decode(extension_id, &record.payload)?;
    ensure!(
        saved.same_immutable(pending),
        "pending Native delivery differs from its committed marker"
    );
    Ok(record.revision)
}

pub(super) async fn persist_pending_marker(
    thread: &ThreadHandle,
    pending: &PendingNativeDelivery,
) -> Result<()> {
    ensure!(
        pending.is_review_decision(),
        "only a source-owned review decision uses the source marker path"
    );
    let extension_id = pending.extension_id();
    ensure_marker(thread, &extension_id, pending).await?;
    Ok(())
}

pub(super) async fn clear_pending_marker(
    thread: &ThreadHandle,
    pending: &PendingNativeDelivery,
) -> Result<bool> {
    ensure!(
        pending.is_review_decision(),
        "only a source-owned review decision uses the source marker path"
    );
    let extension_id = pending.extension_id();
    let Some(record) = thread.snapshot().extensions.get(&extension_id).cloned() else {
        return Ok(false);
    };
    let saved = PendingNativeDelivery::decode(&extension_id, &record.payload)?;
    ensure!(
        saved.same_immutable(pending),
        "pending Native delivery marker changed before cleanup"
    );
    thread
        .mutate_extensions(vec![ExtensionMutation::Delete {
            id: extension_id,
            expected_revision: record.revision,
        }])
        .await?;
    Ok(true)
}

fn native_execution_options(
    owner: &SessionRuntime,
    recipient: &str,
) -> Result<pl_core::thread::input::InputDriverOptions> {
    let state = owner.0.state();
    let native = state
        .members
        .entries
        .get(recipient)
        .ok_or_else(|| anyhow::anyhow!("pending delivery recipient is unavailable"))?
        .native()
        .map_err(|error| anyhow::anyhow!("pending delivery recipient is not Native: {error}"))?;
    Ok(native.execution)
}
