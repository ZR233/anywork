//! Model cost facts share the Thread's original ordered effects and storage fence.
use super::*;
use crate::model::{
    AdmittedSettlement, MemberCharge, ModelMemberError, ModelSubAttemptSettlement, OutputBudget,
};
use futures::future::{BoxFuture, FutureExt, Shared};
use std::collections::BTreeMap;

type Confirmation = Shared<BoxFuture<'static, Result<(), ModelMemberError>>>;
pub(super) type SettlementReply = oneshot::Sender<Result<Confirmation, ModelMemberError>>;

pub(super) async fn await_settlement(
    response: oneshot::Receiver<Result<Confirmation, ModelMemberError>>,
) -> Result<(), ModelMemberError> {
    response.await.map_err(|_| ModelMemberError::Closed)??.await
}

/// A settlement capability bound to one original model call.
#[derive(Debug, Clone)]
pub struct ModelSettlementPort {
    thread_id: String,
    turn_id: Option<String>,
    attempt_id: String,
    commands: mpsc::WeakSender<handle::LoopEvent>,
    stop: Option<CancellationToken>,
    _lifetime: Option<Arc<CallLifetime>>,
}

#[derive(Debug)]
struct CallLifetime(CancellationToken);

impl Drop for CallLifetime {
    fn drop(&mut self) {
        self.0.cancel();
    }
}

impl ModelSettlementPort {
    pub fn thread_id(&self) -> &str {
        &self.thread_id
    }
    pub fn turn_id(&self) -> Option<&str> {
        self.turn_id.as_deref()
    }
    pub fn attempt_id(&self) -> &str {
        &self.attempt_id
    }

    /// Cancellation of the auxiliary call when its Thread stops. Already incurred facts still
    /// use the same settlement capability while the call unwinds.
    pub fn cancellation(&self) -> Option<&CancellationToken> {
        self.stop.as_ref()
    }

    /// Transfers one incurred attempt to the owner. A persistent call waits for the original
    /// effect to be durable. An in-memory call transfers its fact on admission.
    /// Invocation cancellation must not interrupt this transfer of an already-incurred fact.
    pub async fn settle(
        &self,
        generation: u32,
        payload: OpaquePayload,
    ) -> Result<(), ModelMemberError> {
        let commands = self.commands.upgrade().ok_or(ModelMemberError::Closed)?;
        let (reply, response) = oneshot::channel();
        commands
            .send(handle::LoopEvent::SettleModel {
                settlement: ModelSubAttemptSettlement {
                    turn_id: self.turn_id.clone(),
                    attempt_id: self.attempt_id.clone(),
                    generation,
                    payload,
                },
                reply,
            })
            .await
            .map_err(|_| ModelMemberError::Closed)?;
        await_settlement(response).await
    }
}

pub(super) struct SettlementCall {
    turn_id: Option<String>,
    budget: Arc<OutputBudget>,
    accepted: BTreeMap<u32, AdmittedSettlement>,
    confirming: Option<(u64, Confirmation)>,
    retired: bool,
    stop: Option<CancellationToken>,
}

impl Owner {
    pub(super) fn register_model_settlement(
        &mut self,
        turn_id: Option<String>,
        attempt_id: String,
        budget: Arc<OutputBudget>,
        auxiliary: bool,
    ) -> Result<ModelSettlementPort, ThreadError> {
        if turn_id.as_ref().is_some_and(String::is_empty)
            || attempt_id.is_empty()
            || self.model_settlements.contains_key(&attempt_id)
        {
            return Err(ThreadError::InvalidIdentity);
        }
        budget.track_member_claims();
        let stop = auxiliary.then(CancellationToken::new);
        let lifetime = auxiliary.then(|| {
            let retired = CancellationToken::new();
            let wait = retired.clone();
            let attempt = attempt_id.clone();
            self.model_settlement_jobs += 1;
            self.maintenance.push(Box::pin(async move {
                wait.cancelled().await;
                execution::MaintenanceCompletion::RetireModelSettlement(attempt)
            }));
            Arc::new(CallLifetime(retired))
        });
        self.model_settlements.insert(
            attempt_id.clone(),
            SettlementCall {
                turn_id: turn_id.clone(),
                budget,
                accepted: BTreeMap::new(),
                confirming: None,
                retired: false,
                stop: stop.clone(),
            },
        );
        Ok(ModelSettlementPort {
            thread_id: self.id.clone(),
            turn_id,
            attempt_id,
            commands: self.task_commands.clone(),
            stop,
            _lifetime: lifetime,
        })
    }

    pub(super) fn open_auxiliary_model_settlement(
        &mut self,
        caller: Option<String>,
        turn_id: Option<String>,
    ) -> Result<ModelSettlementPort, ModelMemberError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ModelMemberError::Closed);
        }
        if self.cold.is_none() {
            return Err(ModelMemberError::SettlementUnavailable);
        }
        let turn_id = if let Some(caller) = caller {
            Some(
                self.state
                    .tasks
                    .get(&caller)
                    .filter(|task| {
                        task.status == task::TaskStatus::Running && !task.cancel_requested
                    })
                    .ok_or_else(|| {
                        ModelMemberError::Rejected(Arc::new(ThreadError::TaskAccessExpired))
                    })?
                    .turn_id
                    .clone(),
            )
        } else {
            if turn_id
                .as_ref()
                .is_some_and(|id| !self.state.turns.iter().any(|turn| &turn.turn_id == id))
            {
                return Err(ModelMemberError::InvalidIdentity);
            }
            turn_id
        };
        let attempt = format!("auxiliary:{}", uuid::Uuid::new_v4());
        let budget = self
            .try_reserve_operation_output(&attempt)
            .map_err(|error| ModelMemberError::Rejected(Arc::new(error)))?;
        self.register_model_settlement(turn_id, attempt, budget, true)
            .map_err(|error| ModelMemberError::Rejected(Arc::new(error)))
    }

    pub(super) fn cancel_auxiliary_model_calls(&self) {
        for call in self.model_settlements.values() {
            if let Some(stop) = &call.stop {
                stop.cancel();
            }
        }
    }

    /// Closes first admission, while an unsaved original still owns its charge and exact sequence.
    pub(super) fn retire_model_settlement(&mut self, attempt: &str) {
        if let Some(call) = self.model_settlements.get_mut(attempt) {
            call.retired = true;
            self.release_saved_model_settlements();
        } else {
            self.settle_operation_output(attempt);
        }
    }

    pub(super) fn release_saved_model_settlements(&mut self) {
        let durable = self.state.persistence.durable_sequence;
        let mut done = Vec::new();
        self.model_settlements.retain(|id, call| {
            if call.retired
                && (self.cold.is_none()
                    || call
                        .accepted
                        .last_key_value()
                        .is_none_or(|(_, last)| last.sequence <= durable))
            {
                done.push(id.clone());
                false
            } else {
                true
            }
        });
        for id in done {
            self.settle_operation_output(&id);
        }
    }

    pub(super) fn check_model_settlements_saved(&self) -> Result<(), ThreadError> {
        if self.model_settlements.values().any(|call| {
            call.accepted
                .last_key_value()
                .is_some_and(|(_, last)| last.sequence > self.state.persistence.durable_sequence)
        }) {
            let error = self.cold_error.clone().unwrap_or_else(|| {
                Arc::new(cold::ColdStoreError {
                    source: Box::new(std::io::Error::other(
                        "model settlement has no durable confirmation",
                    )),
                })
            });
            return Err(ThreadError::Storage(error));
        }
        Ok(())
    }

    pub(super) fn admit_model_settlement(
        &mut self,
        settlement: ModelSubAttemptSettlement,
        reply: SettlementReply,
    ) {
        if self.interrupt.is_deleting() {
            let _ = reply.send(Err(ModelMemberError::Closed));
            return;
        }
        let Some(call) = self.model_settlements.get(&settlement.attempt_id) else {
            self.verify_saved_model_settlement(settlement, reply);
            return;
        };
        if settlement.turn_id != call.turn_id {
            let _ = reply.send(Err(ModelMemberError::InvalidIdentity));
            return;
        }
        if let Some(accepted) = call.accepted.get(&settlement.generation) {
            if accepted.payload == settlement.payload {
                self.confirm_model_settlement(&settlement.attempt_id, accepted.sequence, reply);
            } else {
                let _ = reply.send(Err(ModelMemberError::SettlementConflict));
            }
            return;
        }
        if call.retired {
            self.verify_saved_model_settlement(settlement, reply);
            return;
        }
        let next = call
            .accepted
            .last_key_value()
            .map_or(Some(0), |(generation, _)| generation.checked_add(1));
        let predecessor_saved = self.cold.is_none()
            || call
                .accepted
                .last_key_value()
                .is_none_or(|(_, last)| last.sequence <= self.state.persistence.durable_sequence);
        if next != Some(settlement.generation) || !predecessor_saved {
            let _ = reply.send(Err(ModelMemberError::InvalidIdentity));
            return;
        }
        let Some(sequence) = self.state.commit_sequence.checked_add(1) else {
            let _ = reply.send(Err(ModelMemberError::Rejected(Arc::new(
                ThreadError::RevisionExhausted,
            ))));
            return;
        };
        let effect = ThreadEffectBatch::between(
            &self.id,
            &self.published,
            &self.state,
            sequence,
            model_members::MemberEffects {
                settlements: Arc::from([settlement.clone()]),
                ..Default::default()
            },
            Arc::from([]),
            Arc::from([]),
        )
        .expect("a settlement produces an effect");
        let funded = crate::model::encoded_member_bytes(&settlement)
            .and_then(|bytes| {
                crate::model::encoded_member_bytes(&effect).map(|effect| (bytes, effect))
            })
            .map_err(|source| cold::ColdStoreError {
                source: Box::new(source),
            })
            .and_then(|(body, encoded)| {
                let charge = MemberCharge::retain(
                    call.budget.clone(),
                    body.saturating_mul(2).saturating_add(256),
                )?;
                charge.fund_effect(encoded)?;
                Ok(charge)
            });
        let charge = match funded {
            Ok(charge) => charge,
            Err(error) => {
                let _ = reply.send(Err(ModelMemberError::Rejected(Arc::new(
                    ThreadError::Storage(Arc::new(error)),
                ))));
                return;
            }
        };
        let id = settlement.attempt_id.clone();
        let generation = settlement.generation;
        self.model_settlements
            .get_mut(&id)
            .expect("owner retains the active registration")
            .accepted
            .insert(
                generation,
                AdmittedSettlement {
                    payload: settlement.payload.clone(),
                    sequence,
                    _charge: Some(charge),
                },
            );
        self.pending_model_sub_attempt_settlements.push(settlement);
        self.claim_output(id.clone());
        match self.publish_primary() {
            Ok(Some(committed)) => {
                debug_assert_eq!(sequence, committed);
                self.confirm_model_settlement(&id, committed, reply);
            }
            failed => {
                self.model_settlements
                    .get_mut(&id)
                    .expect("owner retains the active registration")
                    .accepted
                    .remove(&generation);
                self.pending_model_sub_attempt_settlements.clear();
                self.pending_output_claim = None;
                let error = failed.err().map_or(ModelMemberError::Closed, |error| {
                    ModelMemberError::Rejected(Arc::new(error))
                });
                let _ = reply.send(Err(error));
            }
        }
    }

    fn confirm_model_settlement(&mut self, id: &str, sequence: u64, reply: SettlementReply) {
        if self.interrupt.is_deleting() || sequence > self.state.commit_sequence {
            let _ = reply.send(Err(ModelMemberError::Closed));
            return;
        }
        let Some(store) = self
            .cold
            .clone()
            .filter(|_| self.state.persistence.durable_sequence < sequence)
        else {
            let _ = reply.send(Ok(futures::future::ready(Ok(())).boxed().shared()));
            return;
        };
        let call = self
            .model_settlements
            .get_mut(id)
            .expect("an admitted settlement retains its call");
        if let Some((confirming, confirmation)) = &call.confirming
            && *confirming == sequence
            && confirmation.peek().is_none()
        {
            let _ = reply.send(Ok(confirmation.clone()));
            return;
        }
        if self.state.persistence.admitted_sequence < sequence {
            let error = self.cold_error.clone().or_else(|| {
                (!store.0.is_history()).then(|| {
                    Arc::new(cold::ColdStoreError {
                        source: Box::new(cold::StorageAdmissionBackpressure(
                            "model settlement is awaiting storage admission".into(),
                        )),
                    })
                })
            });
            if let Some(error) = error {
                let _ = reply.send(Err(ModelMemberError::SettlementNotSaved(Arc::new(
                    ThreadError::Storage(error),
                ))));
                return;
            }
        }
        let (saved, response) = oneshot::channel();
        let confirmation = response
            .map(|result| result.unwrap_or(Err(ModelMemberError::Closed)))
            .boxed()
            .shared();
        call.confirming = Some((sequence, confirmation.clone()));
        let thread = self.id.clone();
        let deletion = self.interrupt.deletion_token();
        self.model_settlement_jobs += 1;
        self.maintenance.push(Box::pin(async move {
            let result = tokio::select! {
                biased;
                () = deletion.cancelled() => Err(ModelMemberError::Closed),
                result = store.0.confirm_model_settlement(&thread, sequence) => result.map_err(|error|
                    ModelMemberError::SettlementNotSaved(Arc::new(ThreadError::Storage(Arc::new(error))))),
            };
            execution::MaintenanceCompletion::ModelSettlement { sequence, result, reply: saved }
        }));
        let _ = reply.send(Ok(confirmation));
    }

    pub(super) fn verify_saved_model_settlement(
        &self,
        settlement: ModelSubAttemptSettlement,
        reply: SettlementReply,
    ) {
        if self.interrupt.is_deleting() {
            let _ = reply.send(Err(ModelMemberError::Closed));
            return;
        }
        let Some(store) = self.cold.clone() else {
            let _ = reply.send(Err(ModelMemberError::SettlementExpired));
            return;
        };
        let thread = self.id.clone();
        let deletion = self.interrupt.deletion_token();
        let verification = async move {
            tokio::select! {
                biased;
                () = deletion.cancelled() => Err(ModelMemberError::Closed),
                saved = store.0.read_saved_model_settlement(&thread, &settlement) => match saved {
                    Ok(Some(original)) if original == settlement => Ok(()),
                    Ok(Some(_)) => Err(ModelMemberError::SettlementConflict),
                    Ok(None) => Err(ModelMemberError::SettlementExpired),
                    Err(error) => Err(ModelMemberError::Rejected(Arc::new(ThreadError::Storage(Arc::new(error))))),
                }
            }
        }.boxed().shared();
        let _ = reply.send(Ok(verification));
    }
}
