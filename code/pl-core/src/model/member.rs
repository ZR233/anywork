//! Call-scoped admission of model member lifecycle facts.
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, oneshot};

use super::{AggregateChannel, ObservedPartIdentity, ObservedPartKind};
use crate::context::OpaquePayload;
use crate::thread::ThreadError;

#[derive(Default)]
struct EncodedBytes(u64);

impl std::io::Write for EncodedBytes {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.0 = self.0.saturating_add(bytes.len() as u64);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

pub(crate) fn encoded_member_bytes(value: &impl Serialize) -> Result<u64, serde_json::Error> {
    let mut encoded = EncodedBytes::default();
    serde_json::to_writer(&mut encoded, value)?;
    Ok(encoded.0)
}

/// An immutable, producer-validated member, not a model context or attempt outcome.
///
/// Core binds the call identities. The producer owns the member schema, part identities and bytes.
/// The same envelope enters the ordinary effect and reliable output handoff.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelCompletedMember {
    pub turn_id: String,
    pub attempt_id: String,
    pub generation: u32,
    pub member_id: String,
    pub payload: OpaquePayload,
}

/// A validated part beginning, independent of content, context and attempt completion.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelStartedMember {
    pub turn_id: String,
    pub attempt_id: String,
    pub generation: u32,
    pub identity: ObservedPartIdentity,
}

/// Reliable evidence that a validated part first has readable public content.
///
/// This is independent of completion and carries neither a completion ID nor content bytes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelContentAvailableMember {
    pub turn_id: String,
    pub attempt_id: String,
    pub generation: u32,
    pub identity: ObservedPartIdentity,
}

/// The producer's opaque settlement for one finished model observation generation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelSubAttemptSettlement {
    /// The original Turn, when the owner proved this call belongs to one.
    pub turn_id: Option<String>,
    pub attempt_id: String,
    pub generation: u32,
    pub payload: OpaquePayload,
}

/// Kind of model transport connection boundary observed during an attempt.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ModelConnectionEventKind {
    Disconnected,
    Reconnected,
}

impl ModelConnectionEventKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Disconnected => "disconnected",
            Self::Reconnected => "reconnected",
        }
    }
}

/// Input parameters for admitting a [`ModelConnectionEvent`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelConnectionFact {
    pub generation: u32,
    pub kind: ModelConnectionEventKind,
    pub transport: String,
    pub fallback_transport: Option<String>,
    pub retry: u32,
    pub max_retries: u32,
    pub recoverable: bool,
    pub reason: Option<String>,
    pub duration_ms: Option<u64>,
}

/// Canonical model transport disconnection/reconnection boundary emitted during an attempt.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelConnectionEvent {
    pub turn_id: String,
    pub attempt_id: String,
    pub generation: u32,
    pub kind: ModelConnectionEventKind,
    pub transport: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fallback_transport: Option<String>,
    pub retry: u32,
    pub max_retries: u32,
    pub recoverable: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum StartedKey {
    Aggregate(AggregateChannel),
    Provider(Arc<str>, ObservedPartKind, u32),
}

impl StartedKey {
    pub(crate) fn of(identity: &ObservedPartIdentity) -> Self {
        match identity {
            ObservedPartIdentity::Aggregate { channel } => Self::Aggregate(*channel),
            ObservedPartIdentity::Provider(part) => {
                Self::Provider(part.item_id.clone(), part.part, part.content_index)
            }
        }
    }
}

pub(crate) fn same_started_identity(a: &ObservedPartIdentity, b: &ObservedPartIdentity) -> bool {
    match (a, b) {
        (ObservedPartIdentity::Provider(a), ObservedPartIdentity::Provider(b)) => {
            a.item_id == b.item_id
                && a.part == b.part
                && a.content_index == b.content_index
                && std::mem::discriminant(&a.item_kind) == std::mem::discriminant(&b.item_kind)
                && (a.output_index.is_none()
                    || b.output_index.is_none()
                    || a.output_index == b.output_index)
        }
        _ => a == b,
    }
}

/// A member that did not enter the owner's canonical reliable obligation.
#[derive(Debug, Clone, thiserror::Error)]
pub enum ModelMemberError {
    #[error("model member admission cancelled before sending")]
    Cancelled,
    #[error("model member admission is closed")]
    Closed,
    #[error("model member identity is empty")]
    InvalidIdentity,
    #[error("persistent model settlement requires an owner with a durable writer")]
    SettlementUnavailable,
    #[error("model settlement identity already has different content")]
    SettlementConflict,
    #[error("model settlement identity is no longer active or saved")]
    SettlementExpired,
    #[error("model member was rejected: {0}")]
    Rejected(#[source] Arc<ThreadError>),
    #[error("model sub-attempt settlement was retained but not saved: {0}")]
    SettlementNotSaved(#[source] Arc<ThreadError>),
}

/// A single-slot input to the model call's existing Thread owner.
///
/// It does not write history, publish product items or spawn tasks. The owner validates and charges
/// a member against the original operation budget before acknowledging its reliable effect.
#[derive(Debug, Clone)]
pub struct ModelMemberSender {
    turn_id: Arc<str>,
    attempt_id: Arc<str>,
    sender: mpsc::Sender<ModelMemberAdmission>,
    output: Option<Arc<super::OutputBudget>>,
    registry: MemberRegistry,
    context_recovery: Option<super::ModelContextRecovery>,
    settlement: Option<crate::thread::ModelSettlementPort>,
}

#[derive(Debug, Default)]
pub(crate) struct AdmittedMembers {
    pub(crate) completed:
        std::collections::BTreeMap<(u32, String), (OpaquePayload, Option<MemberCharge>)>,
    pub(crate) started: std::collections::BTreeMap<(u32, StartedKey), AdmittedPart>,
    pub(crate) connections:
        std::collections::BTreeMap<(u32, u8, u32), (ModelConnectionEvent, Option<MemberCharge>)>,
}

#[derive(Debug)]
pub(crate) struct AdmittedSettlement {
    pub(crate) payload: OpaquePayload,
    pub(crate) sequence: u64,
    pub(crate) _charge: Option<MemberCharge>,
}

#[derive(Debug)]
pub(crate) struct AdmittedPart {
    pub(crate) identity: ObservedPartIdentity,
    pub(crate) _start_charge: Option<MemberCharge>,
    pub(crate) content_available: bool,
    pub(crate) _content_charge: Option<MemberCharge>,
}

impl AdmittedMembers {
    pub(crate) fn is_empty(&self) -> bool {
        self.completed.is_empty() && self.started.is_empty() && self.connections.is_empty()
    }

    pub(crate) fn clear(&mut self) {
        self.completed.clear();
        self.started.clear();
        self.connections.clear();
    }
}

/// The owner's single call-local dedup ledger, shared only to identify zero-copy resubmissions.
#[derive(Debug, Clone, Default)]
pub(crate) struct MemberRegistry(pub(crate) Arc<std::sync::Mutex<AdmittedMembers>>);

#[derive(Debug)]
pub(crate) struct ModelMemberAdmission {
    pub(crate) member: MemberFact,
    pub(crate) reply: oneshot::Sender<Result<(), ModelMemberError>>,
    pub(crate) charge: Option<MemberCharge>,
}

#[derive(Debug)]
pub(crate) enum MemberFact {
    Started(ModelStartedMember),
    ContentAvailable(ModelContentAvailableMember),
    Completed(ModelCompletedMember),
    Connection(ModelConnectionEvent),
}

#[derive(Debug)]
pub(crate) struct MemberCharge {
    pub(super) budget: Arc<super::OutputBudget>,
    pub(super) bytes: u64,
}

impl MemberCharge {
    pub(crate) fn retain(
        budget: Arc<super::OutputBudget>,
        bytes: u64,
    ) -> Result<Self, crate::thread::cold::ColdStoreError> {
        budget.retain_member(bytes)
    }
    pub(crate) fn fund_effect(
        &self,
        encoded: u64,
    ) -> Result<(), crate::thread::cold::ColdStoreError> {
        // The registry still strongly owns the opaque allocation even after the effect becomes
        // durable. Keep its full resident charge; the effect's encoded copy needs separate funding
        // on this same operation, which only that effect's claim may transfer.
        self.budget.fund_member_effect(encoded)
    }
}

impl Drop for MemberCharge {
    fn drop(&mut self) {
        self.budget.release_member(self.bytes);
    }
}

impl ModelMemberSender {
    /// Transfers a canonical, validated part beginning through the same admission slot as `submit`.
    ///
    /// As with `submit`, once sending starts the producer must await the owner's reply even during
    /// cancellation. Success retains a reliable effect, not context, usage or a terminal outcome.
    ///
    /// # Errors
    /// Reports cancellation before sending, invalid identity, closed ownership, or the original
    /// typed owner rejection.
    pub async fn start(
        &self,
        generation: u32,
        identity: ObservedPartIdentity,
        cancellation: Option<&tokio_util::sync::CancellationToken>,
    ) -> Result<(), ModelMemberError> {
        if let ObservedPartIdentity::Provider(part) = &identity
            && part.item_id.is_empty()
        {
            return Err(ModelMemberError::InvalidIdentity);
        }
        let permit = self.reserve(generation, cancellation).await?;
        let member = ModelStartedMember {
            turn_id: self.turn_id.to_string(),
            attempt_id: self.attempt_id.to_string(),
            generation,
            identity,
        };
        let encoded = encoded_member_bytes(&member).map_err(|source| {
            ModelMemberError::Rejected(Arc::new(ThreadError::Storage(Arc::new(
                crate::thread::cold::ColdStoreError {
                    source: Box::new(source),
                },
            ))))
        })?;
        // Cover the slot, retained identity, dedup key and frozen envelope on the original budget.
        let metadata = (2 * (self.turn_id.len() + self.attempt_id.len())
            + std::mem::size_of::<ModelMemberAdmission>()
            + std::mem::size_of::<ModelStartedMember>()
            + 128) as u64;
        let duplicate = self
            .registry
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .started
            .get(&(generation, StartedKey::of(&member.identity)))
            .is_some_and(|old| same_started_identity(&old.identity, &member.identity));
        let bytes = if duplicate {
            0
        } else {
            encoded.saturating_mul(2).saturating_add(metadata)
        };
        let charge = self
            .output
            .as_ref()
            .map(|output| {
                output.retain_member(bytes).map_err(|error| {
                    ModelMemberError::Rejected(Arc::new(ThreadError::Storage(Arc::new(error))))
                })
            })
            .transpose()?;
        let (reply, admitted) = oneshot::channel();
        if cancellation.is_some_and(tokio_util::sync::CancellationToken::is_cancelled) {
            return Err(ModelMemberError::Cancelled);
        }
        permit.send(ModelMemberAdmission {
            member: MemberFact::Started(member),
            reply,
            charge,
        });
        self.receive_admission(generation, admitted).await
    }

    /// Admits the first readable public content of an already started part on the original slot.
    ///
    /// Repeated evidence for the same part is idempotent. As with `start` and `submit`, the producer
    /// must await the owner's reply after sending, including during cancellation. Success retains a
    /// reliable fact; it does not complete the part or wait for persistence.
    ///
    /// # Errors
    /// Reports cancellation before sending, invalid identity, missing or contradictory start,
    /// closed ownership, or the original typed owner rejection.
    pub async fn content_available(
        &self,
        generation: u32,
        identity: ObservedPartIdentity,
        cancellation: Option<&tokio_util::sync::CancellationToken>,
    ) -> Result<(), ModelMemberError> {
        if let ObservedPartIdentity::Provider(part) = &identity
            && part.item_id.is_empty()
        {
            return Err(ModelMemberError::InvalidIdentity);
        }
        let permit = self.reserve(generation, cancellation).await?;
        let member = ModelContentAvailableMember {
            turn_id: self.turn_id.to_string(),
            attempt_id: self.attempt_id.to_string(),
            generation,
            identity,
        };
        let encoded = encoded_member_bytes(&member).map_err(|source| {
            ModelMemberError::Rejected(Arc::new(ThreadError::Storage(Arc::new(
                crate::thread::cold::ColdStoreError {
                    source: Box::new(source),
                },
            ))))
        })?;
        let metadata = (2 * (self.turn_id.len() + self.attempt_id.len())
            + std::mem::size_of::<ModelMemberAdmission>()
            + std::mem::size_of::<ModelContentAvailableMember>()
            + 128) as u64;
        let duplicate = self
            .registry
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .started
            .get(&(generation, StartedKey::of(&member.identity)))
            .is_some_and(|old| {
                old.content_available && same_started_identity(&old.identity, &member.identity)
            });
        let bytes = if duplicate {
            0
        } else {
            encoded.saturating_mul(2).saturating_add(metadata)
        };
        let charge = self
            .output
            .as_ref()
            .map(|output| {
                output.retain_member(bytes).map_err(|error| {
                    ModelMemberError::Rejected(Arc::new(ThreadError::Storage(Arc::new(error))))
                })
            })
            .transpose()?;
        let (reply, admitted) = oneshot::channel();
        if cancellation.is_some_and(tokio_util::sync::CancellationToken::is_cancelled) {
            return Err(ModelMemberError::Cancelled);
        }
        permit.send(ModelMemberAdmission {
            member: MemberFact::ContentAvailable(member),
            reply,
            charge,
        });
        self.receive_admission(generation, admitted).await
    }

    pub(crate) fn channel(
        turn_id: &str,
        attempt_id: &str,
    ) -> (Self, mpsc::Receiver<ModelMemberAdmission>) {
        let (sender, receiver) = mpsc::channel(1);
        (
            Self {
                turn_id: Arc::from(turn_id),
                attempt_id: Arc::from(attempt_id),
                sender,
                output: None,
                registry: MemberRegistry::default(),
                context_recovery: None,
                settlement: None,
            },
            receiver,
        )
    }

    pub(crate) fn with_output(mut self, output: Arc<super::OutputBudget>) -> Self {
        output.track_member_claims();
        self.output = Some(output);
        self
    }

    pub(crate) fn registry(&self) -> MemberRegistry {
        self.registry.clone()
    }

    pub(crate) fn with_context_recovery(
        mut self,
        recovery: Option<super::ModelContextRecovery>,
    ) -> Self {
        self.context_recovery = recovery;
        self
    }

    pub fn context_recovery(&self) -> Option<&super::ModelContextRecovery> {
        self.context_recovery.as_ref()
    }

    pub(crate) fn with_settlement(
        mut self,
        settlement: crate::thread::ModelSettlementPort,
    ) -> Self {
        self.settlement = Some(settlement);
        self
    }

    /// The registered settlement capability of this call, independent of content delivery.
    pub fn settlement_port(&self) -> Option<&crate::thread::ModelSettlementPort> {
        self.settlement.as_ref()
    }

    /// Transfers a validated, independently ended member to the original call owner.
    ///
    /// The producer must finish this future once sending starts, including during cancellation.
    /// Success means canonical reliable admission, not persistence or consumer delivery. The owner
    /// drains accepted input before ending the call; an unused sender clone does not keep it open.
    ///
    /// # Errors
    /// Reports cancellation before sending, invalid identity, closed ownership, or the original
    /// typed owner rejection.
    pub async fn submit(
        &self,
        generation: u32,
        member_id: String,
        payload: OpaquePayload,
        cancellation: Option<&tokio_util::sync::CancellationToken>,
    ) -> Result<(), ModelMemberError> {
        if member_id.is_empty() {
            return Err(ModelMemberError::InvalidIdentity);
        }
        // Reserve before moving the fact into the channel. A successful send alone would not prove
        // receipt; the separate reply only resolves after the owner retains the reliable obligation.
        let permit = self.reserve(generation, cancellation).await?;
        // Charge the opaque allocation and all call-local envelope/dedup identities before they
        // enter the slot. This guard moves into the owner's dedup entry; transfer is not a new copy.
        let member = ModelCompletedMember {
            turn_id: self.turn_id.to_string(),
            attempt_id: self.attempt_id.to_string(),
            generation,
            member_id,
            payload,
        };
        let encoded = encoded_member_bytes(&member).map_err(|error| {
            ModelMemberError::Rejected(Arc::new(ThreadError::Storage(Arc::new(
                crate::thread::cold::ColdStoreError {
                    source: Box::new(error),
                },
            ))))
        })?;
        let metadata = (2 * (self.turn_id.len() + self.attempt_id.len() + member.member_id.len())
            + std::mem::size_of::<ModelMemberAdmission>()
            + std::mem::size_of::<ModelCompletedMember>()
            + 128) as u64;
        let shared = self
            .registry
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .completed
            .get(&(generation, member.member_id.clone()))
            .is_some_and(|(old, _)| {
                old == &member.payload && std::ptr::eq(old.content(), member.payload.content())
            });
        // The accepted entry already funds this slot's envelope and identities. Reusing its exact
        // immutable allocation is not a second body; a separately allocated copy still is charged.
        let bytes = if shared {
            0
        } else {
            encoded.saturating_add(metadata)
        };
        let charge = self
            .output
            .as_ref()
            .map(|output| {
                output.retain_member(bytes).map_err(|error| {
                    ModelMemberError::Rejected(Arc::new(ThreadError::Storage(Arc::new(error))))
                })
            })
            .transpose()?;
        let (reply, admitted) = oneshot::channel();
        if cancellation.is_some_and(tokio_util::sync::CancellationToken::is_cancelled) {
            return Err(ModelMemberError::Cancelled);
        }
        permit.send(ModelMemberAdmission {
            member: MemberFact::Completed(member),
            reply,
            charge,
        });
        self.receive_admission(generation, admitted).await
    }

    /// Transfers a canonical model transport disconnect or reconnect boundary to the owner.
    pub async fn connection(
        &self,
        fact: ModelConnectionFact,
        cancellation: Option<&tokio_util::sync::CancellationToken>,
    ) -> Result<(), ModelMemberError> {
        if fact.transport.is_empty() {
            return Err(ModelMemberError::InvalidIdentity);
        }
        let generation = fact.generation;
        let permit = self.reserve(generation, cancellation).await?;
        let event = ModelConnectionEvent {
            turn_id: self.turn_id.to_string(),
            attempt_id: self.attempt_id.to_string(),
            generation,
            kind: fact.kind,
            transport: fact.transport,
            fallback_transport: fact.fallback_transport,
            retry: fact.retry,
            max_retries: fact.max_retries,
            recoverable: fact.recoverable,
            reason: fact.reason,
            duration_ms: fact.duration_ms,
        };
        let encoded = encoded_member_bytes(&event).map_err(|error| {
            ModelMemberError::Rejected(Arc::new(ThreadError::Storage(Arc::new(
                crate::thread::cold::ColdStoreError {
                    source: Box::new(error),
                },
            ))))
        })?;
        let metadata = (2 * (self.turn_id.len() + self.attempt_id.len())
            + std::mem::size_of::<ModelMemberAdmission>()
            + std::mem::size_of::<ModelConnectionEvent>()
            + 128) as u64;
        let key = (generation, event.kind as u8, event.retry);
        let duplicate = self
            .registry
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .connections
            .get(&key)
            .is_some_and(|(old, _)| old == &event);
        let bytes = if duplicate {
            0
        } else {
            encoded.saturating_add(metadata)
        };
        let charge = self
            .output
            .as_ref()
            .map(|output| {
                output.retain_member(bytes).map_err(|error| {
                    ModelMemberError::Rejected(Arc::new(ThreadError::Storage(Arc::new(error))))
                })
            })
            .transpose()?;
        let (reply, admitted) = oneshot::channel();
        if cancellation.is_some_and(tokio_util::sync::CancellationToken::is_cancelled) {
            return Err(ModelMemberError::Cancelled);
        }
        permit.send(ModelMemberAdmission {
            member: MemberFact::Connection(event),
            reply,
            charge,
        });
        self.receive_admission(generation, admitted).await
    }

    async fn reserve(
        &self,
        generation: u32,
        cancellation: Option<&tokio_util::sync::CancellationToken>,
    ) -> Result<mpsc::Permit<'_, ModelMemberAdmission>, ModelMemberError> {
        use tracing::Instrument;
        let started = std::time::Instant::now();
        async {
            tokio::select! {
                biased;
                () = async {
                    match cancellation {
                        Some(token) => token.cancelled().await,
                        None => std::future::pending().await,
                    }
                } => Err(ModelMemberError::Cancelled),
                permit = self.sender.reserve() => permit.map_err(|_| ModelMemberError::Closed),
            }
        }
        .instrument(tracing::debug_span!(
            "model_member",
            stage = "member_capacity",
            turn_id = %self.turn_id,
            attempt_id = %self.attempt_id,
            generation,
            stage_started_at = ?started,
        ))
        .await
    }

    async fn receive_admission(
        &self,
        generation: u32,
        admitted: oneshot::Receiver<Result<(), ModelMemberError>>,
    ) -> Result<(), ModelMemberError> {
        use tracing::Instrument;
        let started = std::time::Instant::now();
        // Sending transferred the fact. Cancellation cannot revoke this original owner's reply.
        admitted
            .instrument(tracing::debug_span!(
                "model_member",
                stage = "member_reply",
                turn_id = %self.turn_id,
                attempt_id = %self.attempt_id,
                generation,
                stage_started_at = ?started,
            ))
            .await
            .map_err(|_| ModelMemberError::Closed)?
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::FutureExt;
    use tokio_util::sync::CancellationToken;

    async fn deliver(
        sender: &ModelMemberSender,
        kind: u8,
        cancellation: Option<&CancellationToken>,
    ) -> Result<(), ModelMemberError> {
        let identity = ObservedPartIdentity::Aggregate {
            channel: AggregateChannel::Text,
        };
        match kind {
            0 => sender.start(0, identity, cancellation).await,
            1 => sender.content_available(0, identity, cancellation).await,
            _ => {
                sender
                    .submit(
                        0,
                        "item".into(),
                        OpaquePayload::text("complete"),
                        cancellation,
                    )
                    .await
            }
        }
    }

    fn budget() -> Arc<super::super::OutputBudget> {
        Arc::new(
            super::super::OutputBudget::reserve(None, "thread", "attempt", 1024 * 1024, None)
                .unwrap(),
        )
    }

    #[tokio::test]
    async fn cancellation_while_reserving_sends_nothing_and_releases_capacity_for_all_facts() {
        for kind in 0..3 {
            let output = budget();
            let (sender, mut receiver) = ModelMemberSender::channel("turn", "attempt");
            let sender = sender.with_output(output.clone());
            let first = deliver(&sender, 2, None);
            tokio::pin!(first);
            assert!(first.as_mut().now_or_never().is_none());
            let charged = output.charged.lock().unwrap().members;
            assert!(charged > 0);
            let cancellation = CancellationToken::new();
            let waiting = deliver(&sender, kind, Some(&cancellation));
            tokio::pin!(waiting);
            assert!(waiting.as_mut().now_or_never().is_none());
            cancellation.cancel();
            assert!(matches!(waiting.await, Err(ModelMemberError::Cancelled)));
            assert_eq!(output.charged.lock().unwrap().members, charged);
            let first_admission = receiver.try_recv().unwrap();
            assert!(
                receiver.try_recv().is_err(),
                "cancelled fact never entered the slot"
            );
            first_admission.reply.send(Ok(())).unwrap();
            drop(first_admission.charge);
            first.await.unwrap();
            assert_eq!(sender.sender.capacity(), 1);
            assert_eq!(output.charged.lock().unwrap().members, 0);
        }
    }

    #[derive(Debug)]
    struct CancelOnCharge(CancellationToken);

    impl crate::thread::history_sink::HistorySink for CancelOnCharge {
        fn fold_usage(
            &self,
            _: &mut crate::thread::UsageSummary,
            _: &crate::thread::ThreadEffectBatch,
        ) {
        }
        fn reserve_observed_item(
            &self,
            _: &str,
            _: &str,
            _: &str,
        ) -> Result<(), crate::thread::cold::ColdStoreError> {
            Ok(())
        }
        fn reserve_operation_output(
            &self,
            _: &str,
            _: &str,
            max: u64,
        ) -> Result<u64, crate::thread::cold::ColdStoreError> {
            Ok(max)
        }
        fn charge_operation_output(
            &self,
            _: &str,
            _: &str,
            _: u64,
        ) -> Result<(), crate::thread::cold::ColdStoreError> {
            self.0.cancel();
            Ok(())
        }
        fn release_operation_output(&self, _: &str, _: &str) {}
        fn pressure(&self, _: &str) -> crate::thread::cold::StoragePressure {
            Default::default()
        }
        fn idle_status(&self, _: &str) -> crate::thread::cold::StorageIdleStatus {
            crate::thread::cold::StorageIdleStatus {
                pressure: Default::default(),
                reclaimable_thread_bytes: Some(0),
            }
        }
        fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
            None
        }
        fn admit(
            &self,
            _: &str,
            _: Arc<crate::thread::HistoryExport>,
        ) -> Result<(), crate::thread::cold::ColdStoreError> {
            unreachable!("sender does not persist");
        }
    }

    #[tokio::test]
    async fn cancellation_after_permit_before_send_returns_this_charge_for_all_facts() {
        for kind in 0..3 {
            let cancellation = CancellationToken::new();
            let storage = crate::thread::history_sink::HistorySinkHandle::new(CancelOnCharge(
                cancellation.clone(),
            ))
            .into_storage();
            let output = Arc::new(
                super::super::OutputBudget::reserve(
                    Some(storage),
                    "thread",
                    "attempt",
                    1024 * 1024,
                    None,
                )
                .unwrap(),
            );
            let (sender, mut receiver) = ModelMemberSender::channel("turn", "attempt");
            let sender = sender.with_output(output.clone());
            assert!(matches!(
                deliver(&sender, kind, Some(&cancellation)).await,
                Err(ModelMemberError::Cancelled)
            ));
            assert_eq!(sender.sender.capacity(), 1);
            assert!(receiver.try_recv().is_err());
            assert_eq!(output.charged.lock().unwrap().members, 0);
        }
    }

    #[tokio::test]
    async fn cancellation_after_send_waits_for_original_reply_without_resending_for_all_facts() {
        for kind in 0..3 {
            let output = budget();
            let (sender, mut receiver) = ModelMemberSender::channel("turn", "attempt");
            let sender = sender.with_output(output.clone());
            let cancellation = CancellationToken::new();
            let delivery = deliver(&sender, kind, Some(&cancellation));
            tokio::pin!(delivery);
            assert!(delivery.as_mut().now_or_never().is_none());
            let admission = receiver.try_recv().unwrap();
            cancellation.cancel();
            assert!(delivery.as_mut().now_or_never().is_none());
            assert!(output.charged.lock().unwrap().members > 0);
            assert!(receiver.try_recv().is_err());
            admission.reply.send(Ok(())).unwrap();
            delivery.await.unwrap();
            drop(admission.charge);
            assert_eq!(output.charged.lock().unwrap().members, 0);
            assert!(receiver.try_recv().is_err());
        }
    }
}
