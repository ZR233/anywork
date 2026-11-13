//! Admission on the original serial owner, while its prepared call is still running.
use super::*;
use crate::model::{
    AdmittedPart, MemberFact, MemberRegistry, ModelMemberAdmission, ModelMemberError,
    ObservedPartIdentity, StartedKey, same_started_identity,
};

/// The member facts carried by one ordinary owner publication.
#[derive(Default)]
pub(super) struct MemberEffects {
    pub(super) completed: Arc<[crate::model::ModelCompletedMember]>,
    pub(super) started: Arc<[crate::model::ModelStartedMember]>,
    pub(super) content_available: Vec<crate::model::ModelContentAvailableMember>,
}

pub(super) struct MemberCall {
    pub(super) receiver: tokio::sync::mpsc::Receiver<ModelMemberAdmission>,
    pub(super) turn_id: String,
    pub(super) attempt_id: String,
    pub(super) cancellation: CancellationToken,
    seen: MemberRegistry,
    error: Option<Arc<ThreadError>>,
    pub(super) generation: u32,
}

impl MemberCall {
    pub(super) fn retains_members(&self) -> bool {
        !self
            .seen
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .is_empty()
    }

    pub(super) fn new(
        receiver: tokio::sync::mpsc::Receiver<ModelMemberAdmission>,
        input: &StepInput,
        seen: MemberRegistry,
    ) -> Self {
        Self {
            receiver,
            turn_id: input.turn_id.clone(),
            attempt_id: input.attempt_id.clone(),
            cancellation: input.cancellation.clone(),
            seen,
            error: None,
            generation: 0,
        }
    }
}

impl Drop for MemberCall {
    fn drop(&mut self) {
        self.receiver.close();
        // A sender clone is not a lifetime owner for call-local validation state or its charge.
        self.seen
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clear();
    }
}

impl Owner {
    pub(super) fn admit_model_member(&mut self, admission: ModelMemberAdmission) {
        let ModelMemberAdmission {
            member,
            reply,
            mut charge,
        } = admission;
        let Some(call) = self.model_members.as_mut() else {
            let _ = reply.send(Err(ModelMemberError::Closed));
            return;
        };
        let generation = self
            .model_progress
            .as_ref()
            .map_or(call.generation, |(_, rx)| {
                rx.borrow().observation().generation
            });
        call.generation = generation;
        let mut seen = call
            .seen
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let (invalid, conflict, duplicate) = match &member {
            MemberFact::Completed(member) => {
                let old = seen
                    .completed
                    .get(&(member.generation, member.member_id.clone()));
                (
                    member.turn_id != call.turn_id
                        || member.attempt_id != call.attempt_id
                        || member.generation != generation
                        || member.member_id.is_empty(),
                    old.is_some_and(|(old, _)| old != &member.payload),
                    old.is_some(),
                )
            }
            MemberFact::Started(member) => {
                let old = seen
                    .started
                    .get(&(member.generation, StartedKey::of(&member.identity)));
                (
                    member.turn_id != call.turn_id
                        || member.attempt_id != call.attempt_id
                        || member.generation != generation
                        || matches!(&member.identity, ObservedPartIdentity::Provider(p) if p.item_id.is_empty()),
                    old.is_some_and(|old| !same_started_identity(&old.identity, &member.identity)),
                    old.is_some(),
                )
            }
            MemberFact::ContentAvailable(member) => {
                let old = seen
                    .started
                    .get(&(member.generation, StartedKey::of(&member.identity)));
                (
                    member.turn_id != call.turn_id
                        || member.attempt_id != call.attempt_id
                        || member.generation != generation
                        || old.is_none()
                        || matches!(&member.identity, ObservedPartIdentity::Provider(p) if p.item_id.is_empty()),
                    old.is_some_and(|old| !same_started_identity(&old.identity, &member.identity)),
                    old.is_some_and(|old| old.content_available),
                )
            }
        };
        if invalid || conflict || call.error.is_some() {
            let error = call
                .error
                .get_or_insert_with(|| Arc::new(ThreadError::InvalidOutput))
                .clone();
            // A faulty producer must unwind on the same cancellation path, not run a detached
            // publisher. The already accepted entries are untouched.
            call.cancellation.cancel();
            let _ = reply.send(Err(ModelMemberError::Rejected(error)));
            return;
        }
        if duplicate {
            let beginning = match &member {
                MemberFact::Started(member) => Some((member.generation, &member.identity)),
                MemberFact::ContentAvailable(member) => Some((member.generation, &member.identity)),
                MemberFact::Completed(_) => None,
            };
            if let Some((generation, identity)) = beginning
                && let ObservedPartIdentity::Provider(new) = identity
                && let Some(old) = seen
                    .started
                    .get_mut(&(generation, StartedKey::of(identity)))
                && let ObservedPartIdentity::Provider(old) = &mut old.identity
            {
                old.output_index = old.output_index.or(new.output_index);
                old.item_kind = new.item_kind;
            }
            let _ = reply.send(Ok(()));
            return;
        }
        // Fund the *whole* encoded effect before publishing, separately from the opaque allocation
        // that the registry still owns. Its claim can transfer this effect funding, not those
        // resident opaque bytes or the accumulator/progress and dedup metadata on the reservation.
        let (completed, started, content_available) = match &member {
            MemberFact::Completed(member) => (vec![member.clone()], vec![], vec![]),
            MemberFact::Started(member) => (vec![], vec![member.clone()], vec![]),
            MemberFact::ContentAvailable(member) => (vec![], vec![], vec![member.clone()]),
        };
        let effect = ThreadEffectBatch::between(
            &self.id,
            &self.published,
            &self.state,
            self.state.commit_sequence.saturating_add(1),
            MemberEffects {
                completed: completed.into(),
                started: started.into(),
                content_available,
            },
            Arc::from([]),
        )
        .expect("a member always produces an effect");
        let funded = crate::model::encoded_member_bytes(&effect)
            .map_err(|error| cold::ColdStoreError {
                source: Box::new(error),
            })
            .and_then(|encoded| match charge.as_mut() {
                Some(charge) => charge.fund_effect(encoded),
                None => Ok(()),
            });
        if let Err(error) = funded {
            let error = Arc::new(ThreadError::Storage(Arc::new(error)));
            call.error = Some(error.clone());
            call.cancellation.cancel();
            let _ = reply.send(Err(ModelMemberError::Rejected(error)));
            return;
        }
        match &member {
            MemberFact::Completed(member) => {
                seen.completed.insert(
                    (member.generation, member.member_id.clone()),
                    (member.payload.clone(), charge),
                );
            }
            MemberFact::Started(member) => {
                seen.started.insert(
                    (member.generation, StartedKey::of(&member.identity)),
                    AdmittedPart {
                        identity: member.identity.clone(),
                        _start_charge: charge,
                        content_available: false,
                        _content_charge: None,
                    },
                );
            }
            MemberFact::ContentAvailable(member) => {
                let part = seen
                    .started
                    .get_mut(&(member.generation, StartedKey::of(&member.identity)))
                    .expect("validated start");
                part.content_available = true;
                part._content_charge = charge;
                if let (ObservedPartIdentity::Provider(old), ObservedPartIdentity::Provider(new)) =
                    (&mut part.identity, &member.identity)
                {
                    old.output_index = old.output_index.or(new.output_index);
                    old.item_kind = new.item_kind;
                }
            }
        }
        drop(seen);
        let operation = call.attempt_id.clone();
        match member {
            MemberFact::Completed(member) => self.pending_model_members.push(member),
            MemberFact::Started(member) => self.pending_model_member_starts.push(member),
            MemberFact::ContentAvailable(member) => {
                self.pending_model_member_content_available.push(member)
            }
        }
        self.claim_output(operation);
        if let Err(error) = self.publish() {
            let error = Arc::new(error);
            if let Some(call) = self.model_members.as_mut() {
                call.error = Some(error.clone());
                call.cancellation.cancel();
            }
            let _ = reply.send(Err(ModelMemberError::Rejected(error)));
            return;
        }
        // publish retains the obligation even if synchronous storage admission is refused.
        let _ = reply.send(Ok(()));
    }

    pub(super) fn finish_model_members(&mut self) -> Option<Arc<ThreadError>> {
        if let Some(call) = self.model_members.as_mut() {
            call.receiver.close();
        }
        // No EOF wait: sender clones are not lifetime owners. reserve() and send() have no await
        // between them, so closing excludes all future sends while preserving every queued fact.
        while let Some(admission) = self
            .model_members
            .as_mut()
            .and_then(|call| call.receiver.try_recv().ok())
        {
            self.admit_model_member(admission);
        }
        self.model_members
            .as_ref()
            .and_then(|call| call.error.clone())
    }
}
