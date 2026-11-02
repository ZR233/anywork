//! Call-scoped admission of independently ended model members.
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
#[derive(Debug, thiserror::Error)]
pub enum ModelMemberError {
    #[error("model member admission is closed")]
    Closed,
    #[error("model member identity is empty")]
    InvalidIdentity,
    #[error("model member was rejected: {0}")]
    Rejected(#[source] Arc<ThreadError>),
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
}

#[derive(Debug, Default)]
pub(crate) struct AdmittedMembers {
    pub(crate) completed:
        std::collections::BTreeMap<(u32, String), (OpaquePayload, Option<MemberCharge>)>,
    pub(crate) started:
        std::collections::BTreeMap<(u32, StartedKey), (ObservedPartIdentity, Option<MemberCharge>)>,
}

impl AdmittedMembers {
    pub(crate) fn is_empty(&self) -> bool {
        self.completed.is_empty() && self.started.is_empty()
    }

    pub(crate) fn clear(&mut self) {
        self.completed.clear();
        self.started.clear();
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
    Completed(ModelCompletedMember),
}

#[derive(Debug)]
pub(crate) struct MemberCharge {
    pub(super) budget: Arc<super::OutputBudget>,
    pub(super) bytes: u64,
}

impl MemberCharge {
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
    /// Reports invalid identity, closed ownership, or the original typed owner rejection.
    pub async fn start(
        &self,
        generation: u32,
        identity: ObservedPartIdentity,
    ) -> Result<(), ModelMemberError> {
        if let ObservedPartIdentity::Provider(part) = &identity
            && part.item_id.is_empty()
        {
            return Err(ModelMemberError::InvalidIdentity);
        }
        let permit = self
            .sender
            .reserve()
            .await
            .map_err(|_| ModelMemberError::Closed)?;
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
            .is_some_and(|(old, _)| same_started_identity(old, &member.identity));
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
        permit.send(ModelMemberAdmission {
            member: MemberFact::Started(member),
            reply,
            charge,
        });
        admitted.await.map_err(|_| ModelMemberError::Closed)?
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

    /// Transfers a validated, independently ended member to the original call owner.
    ///
    /// The producer must finish this future once sending starts, including during cancellation.
    /// Success means canonical reliable admission, not persistence or consumer delivery. The owner
    /// drains accepted input before ending the call; an unused sender clone does not keep it open.
    ///
    /// # Errors
    /// Reports invalid identity, closed ownership, or the original typed owner rejection.
    pub async fn submit(
        &self,
        generation: u32,
        member_id: String,
        payload: OpaquePayload,
    ) -> Result<(), ModelMemberError> {
        if member_id.is_empty() {
            return Err(ModelMemberError::InvalidIdentity);
        }
        // Reserve before moving the fact into the channel. A successful send alone would not prove
        // receipt; the separate reply only resolves after the owner retains the reliable obligation.
        let permit = self
            .sender
            .reserve()
            .await
            .map_err(|_| ModelMemberError::Closed)?;
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
        permit.send(ModelMemberAdmission {
            member: MemberFact::Completed(member),
            reply,
            charge,
        });
        admitted.await.map_err(|_| ModelMemberError::Closed)?
    }
}
