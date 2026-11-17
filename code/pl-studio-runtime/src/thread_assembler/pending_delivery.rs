//! Recipient-owned pending Native deliveries and their Current-backed recovery.
//!
//! A marker is a delivery obligation, not a second history or report projection. It carries the
//! exact immutable message until the recipient's Current proves acceptance, then it is deleted.
//! Before the first marker flush, the original operation still owns retry responsibility, but a
//! process crash cannot recover RAM-only material. This is not a cross-store atomic transaction.
use super::{
    SessionRuntime,
    agent_services::AgentServices,
    observation::DurableMessageIdentity,
    review_delivery::{DeliveryObservation, ReviewDeliveryException},
};
use anyhow::{Context, Result, ensure};
use pl_core::{
    context::{AgentMessageKind, ContextContent, OpaquePayload},
    thread::{
        ThreadError, ThreadHandle, ThreadLifecycle, ThreadSnapshot, extensions::ExtensionMutation,
        inbox::ThreadMessage,
    },
};
use serde::{Deserialize, Serialize};

pub(super) const PENDING_NATIVE_DELIVERY_FORMAT: &str = "pl.studio.pending-native-delivery";
pub(super) const PENDING_NATIVE_DELIVERY_VERSION: u32 = 1;
pub(super) const PENDING_NATIVE_DELIVERY_EXTENSION_PREFIX: &str = "studio.pending-native-delivery:";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum PendingNativeDeliveryKind {
    ParentReport,
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
        generation: u64,
        completion_sequence: u64,
    },
}

/// Exact original delivery material. The extension key is the final inbox message ID.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct PendingNativeDelivery {
    kind: PendingNativeDeliveryKind,
    message: ThreadMessage,
    message_digest: String,
    source: PendingNativeDeliverySource,
    wake: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ParentReportIdentity {
    child_id: String,
    commit_sequence: u64,
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

    pub(super) fn extension_id(&self) -> String {
        format!(
            "{PENDING_NATIVE_DELIVERY_EXTENSION_PREFIX}{}",
            self.message.id
        )
    }

    fn encode(&self) -> Result<OpaquePayload> {
        Ok(OpaquePayload::new(
            PENDING_NATIVE_DELIVERY_FORMAT,
            PENDING_NATIVE_DELIVERY_VERSION,
            serde_json::to_string(self)?,
        )?)
    }

    fn decode(extension_id: &str, payload: &OpaquePayload) -> Result<Self> {
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
        match (&self.kind, &self.source) {
            (
                PendingNativeDeliveryKind::ParentReport,
                PendingNativeDeliverySource::Terminal {
                    child_id,
                    terminal_sequence,
                },
            ) => ensure!(
                !child_id.is_empty()
                    && *terminal_sequence > 0
                    && self.message.id
                        == crate::studio::agent_close::terminal_report_id(
                            child_id,
                            *terminal_sequence
                        )
                    && self.message.source_id == format!("studio.child:{child_id}"),
                "parent report pending identity mismatch"
            ),
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
        .parse::<u64>()?;
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
    /// Reads only recipient Current markers. Absence is not interpreted as an old delivery.
    pub(super) async fn pending_native_deliveries(
        &self,
        recipient: &pl_protocol::Thread,
    ) -> Result<Vec<PendingNativeDelivery>> {
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("pending delivery services unavailable")?;
        let Some(current) = crate::studio::thread_factory::recovery::load_current_read_only(
            &services.store,
            recipient,
        )
        .await?
        else {
            return Ok(Vec::new());
        };
        current
            .state
            .extensions
            .iter()
            .filter(|(id, _)| id.starts_with(PENDING_NATIVE_DELIVERY_EXTENSION_PREFIX))
            .map(|(id, record)| PendingNativeDelivery::decode(id, &record.payload))
            .collect()
    }

    /// Replays only explicit Current markers through the storage-only recipient path.
    pub(super) async fn recover_pending_native_deliveries(
        &self,
        recipient: &pl_protocol::Thread,
    ) -> Result<usize> {
        let pending = self.pending_native_deliveries(recipient).await?;
        let count = pending.len();
        if count == 0 {
            return Ok(0);
        }
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
        Ok(count)
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
    let extension_id = pending.extension_id();
    let marker_revision = ensure_marker(thread, &extension_id, &pending).await?;

    // The marker must be durable before acceptance is allowed to begin.
    services
        .store
        .conversation_store(recipient)
        .await?
        .flush_current(thread.runtime_epoch())
        .await?;

    let sequence = match accepted_identity(&thread.snapshot(), pending.message()) {
        AcceptedIdentity::Matching(sequence) => sequence,
        AcceptedIdentity::Conflict => {
            anyhow::bail!("pending Native delivery conflicts with the recipient inbox")
        }
        AcceptedIdentity::Absent => thread.send_message(pending.message().clone()).await?,
    };

    // Admission is not the ACK. Make the exact inbox identity durable before removing its marker.
    services
        .store
        .conversation_store(recipient)
        .await?
        .flush_current(thread.runtime_epoch())
        .await?;
    match owner
        .durable_message_identity(recipient, &pending.message().id)
        .await?
    {
        Some(DurableMessageIdentity::Proven {
            sequence: saved,
            digest,
        }) if saved == sequence && digest == pending.message_digest.as_str() => {
            // The marker was already flushed before the message. Removing it now is a separate
            // Current transition, so a crash after inbox persistence can only cause another no-op
            // admission and marker cleanup.
        }
        Some(DurableMessageIdentity::Proven { .. }) => {
            anyhow::bail!("pending Native delivery changed its admission identity")
        }
        Some(DurableMessageIdentity::Unverifiable) => {
            anyhow::bail!("pending Native delivery has an unverifiable Current receipt")
        }
        None => anyhow::bail!("pending Native delivery is absent from saved Current"),
    }

    let marker = thread.snapshot().extensions.get(&extension_id).cloned();
    if let Some(record) = marker {
        let saved = PendingNativeDelivery::decode(&extension_id, &record.payload)?;
        ensure!(
            saved == pending,
            "pending Native delivery marker changed before cleanup"
        );
        ensure!(
            record.revision == marker_revision,
            "pending Native delivery marker was concurrently replaced"
        );
        thread
            .mutate_extensions(vec![ExtensionMutation::Delete {
                id: extension_id,
                expected_revision: record.revision,
            }])
            .await?;
            services
            .store
            .conversation_store(recipient)
            .await?
            .flush_current(thread.runtime_epoch())
            .await?;
    }

    if pending.wake && allow_wake {
        let options = native_execution_options(owner, recipient)?;
        match thread
            .wake_accepted_message(&pending.message.id, sequence, options)
            .await
        {
            Ok(_) => {}
            Err(ThreadError::Closed) if thread.snapshot().lifecycle != ThreadLifecycle::Open => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}

async fn ensure_marker(
    thread: &ThreadHandle,
    extension_id: &str,
    pending: &PendingNativeDelivery,
) -> Result<u64> {
    if let Some(record) = thread.snapshot().extensions.get(extension_id) {
        let saved = PendingNativeDelivery::decode(extension_id, &record.payload)?;
        ensure!(
            saved == *pending,
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
                saved == *pending,
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
        saved == *pending,
        "pending Native delivery differs from its committed marker"
    );
    Ok(record.revision)
}

enum AcceptedIdentity {
    Matching(u64),
    Conflict,
    Absent,
}

fn accepted_identity(snapshot: &ThreadSnapshot, message: &ThreadMessage) -> AcceptedIdentity {
    if let Some(record) = snapshot
        .inbox
        .iter()
        .find(|record| record.message.id == message.id)
    {
        return if record.message == *message {
            AcceptedIdentity::Matching(record.sequence)
        } else {
            AcceptedIdentity::Conflict
        };
    }
    if let Some(identity) = snapshot
        .consumed_message_identities
        .iter()
        .find(|identity| identity.id == message.id)
    {
        return if identity.digest == message.digest() {
            AcceptedIdentity::Matching(identity.sequence)
        } else {
            AcceptedIdentity::Conflict
        };
    }
    AcceptedIdentity::Absent
}

fn native_execution_options(
    owner: &SessionRuntime,
    recipient: &str,
) -> Result<pl_core::thread::input::InputDriverOptions> {
    let state = owner.0.state();
    let native = state
        .entries
        .get(recipient)
        .ok_or_else(|| anyhow::anyhow!("pending delivery recipient is unavailable"))?
        .native()
        .map_err(|error| anyhow::anyhow!("pending delivery recipient is not Native: {error}"))?;
    Ok(native.execution)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parent_report() -> PendingNativeDelivery {
        let message = ThreadMessage {
            id: crate::studio::agent_close::terminal_report_id("child", 7),
            source_id: "studio.child:child".into(),
            kind: AgentMessageKind::Report,
            payload: OpaquePayload::new(
                "pl.studio.turn-report",
                3,
                serde_json::json!({
                    "childId": "child",
                    "commitSequence": 7,
                    "turn": {"turnId": "turn"},
                    "turnId": "turn",
                    "inputId": null
                })
                .to_string(),
            )
            .expect("valid fixture payload"),
            context: vec![ContextContent::Text {
                text: "terminal report".into(),
            }],
        };
        PendingNativeDelivery::from_terminal_message(message, true)
            .expect("valid parent report marker")
    }

    #[test]
    fn parent_report_marker_round_trips_exact_message() {
        let pending = parent_report();
        let extension_id = pending.extension_id();
        let payload = pending.encode().expect("encode pending marker");
        let decoded =
            PendingNativeDelivery::decode(&extension_id, &payload).expect("decode pending marker");

        assert_eq!(decoded, pending);
        assert_eq!(
            payload.format(),
            PENDING_NATIVE_DELIVERY_FORMAT,
            "marker format identifies its domain"
        );
        assert_eq!(
            payload.version(),
            PENDING_NATIVE_DELIVERY_VERSION,
            "marker version is explicitly pinned"
        );
    }

    #[test]
    fn parent_report_marker_rejects_a_changed_digest() {
        let mut pending = parent_report();
        pending.message_digest = "sha256:changed".into();
        let payload = pending.encode().expect("encode corrupted marker");

        assert!(
            PendingNativeDelivery::decode(&pending.extension_id(), &payload).is_err(),
            "a saved marker whose digest differs from its exact message must fail closed"
        );
    }
}
