//! Bridge-owned live Configuration calls, not a global cache or permanent deduplication history.
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use futures::FutureExt;
use pl_protocol::products::configuration_calls::{
    ConfigurationCallKind, ConfigurationCallOutcome, ConfigurationCallRequest,
};
use pl_protocol::products::configuration_commands::ConfigurationCommandCallIdentity;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_studio_runtime::configuration::ConfigurationCallResult;
use tokio::sync::{Notify, watch};

use super::configuration_commands::BridgeConfigurationCommandOutcome;
use super::profile_commands::{BridgeConfigurationReloadOutcome, BridgeProfileCommandOutcome};
use crate::api::studio::bridge_runtime::BridgeRuntime;
use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use crate::api::studio::types::{
    BridgeCleanupRecovery, BridgeError, BridgeFeedCloseIssue, BridgeFeedCloseOutcome,
    BridgeFeedCloseReport, BridgeShutdownIssue,
};

#[derive(Clone)]
#[flutter_rust_bridge::frb(ignore)]
pub(super) enum BridgeCallOutcome {
    Configuration(BridgeConfigurationCommandOutcome),
    Profile(BridgeProfileCommandOutcome),
    Reload(BridgeConfigurationReloadOutcome),
}
impl From<ConfigurationCallOutcome> for BridgeCallOutcome {
    fn from(outcome: ConfigurationCallOutcome) -> Self {
        match outcome {
            ConfigurationCallOutcome::Configuration(value) => Self::Configuration(value.into()),
            ConfigurationCallOutcome::Profile(value) => Self::Profile(value.into()),
            ConfigurationCallOutcome::Reload(value) => Self::Reload(value.into()),
        }
    }
}

#[derive(Default)]
#[flutter_rust_bridge::frb(ignore)]
struct Calls {
    sealed: bool,
    by_operation: BTreeMap<String, Arc<CommandOwner>>,
    next_call: u64,
}

/// One field of the actual BridgeRuntime. Only retained calls are indexed; clean explicit close
/// removes the entry. The existing operation lifetime and BridgeTaskRegistry remain the owners
/// of admission/supervision; this index adds neither a permit pool nor finished-call history.
#[derive(Default)]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct ConfigurationCommandRegistry(Mutex<Calls>);

struct CallState {
    closing: bool,
    // Set only after explicit close joined both the producer and the admitted query prefix.
    close_joined: bool,
    released: bool,
    inflight_results: usize,
    owned_result: Option<ConfigurationCallResult>,
}

pub(super) struct CommandOwner {
    pub(super) task: Arc<TypedFeedTask>,
    identity: ConfigurationCommandCallIdentity,
    request: ConfigurationCallRequest,
    result: watch::Sender<Option<BridgeCallOutcome>>,
    state: Mutex<CallState>,
    results_changed: Notify,
}

/// A private, non-cloneable registration, held by the typed result wrapper until its return
/// value has been built. Dropping a cancelled wrapper also ends exactly this registration.
#[flutter_rust_bridge::frb(ignore)]
pub(super) struct CommandResultQuery {
    owner: Arc<CommandOwner>,
    result: watch::Receiver<Option<BridgeCallOutcome>>,
}

impl ConfigurationCommandRegistry {
    /// Lookup, full frozen-request comparison, original task registration and installation are
    /// one admission boundary. Joining never allocates a task ID or registers another producer.
    pub(super) fn begin(
        &self,
        bridge: &'static BridgeRuntime,
        request: ConfigurationCallRequest,
    ) -> Result<Arc<CommandOwner>, BridgeError> {
        let mut calls = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        calls.by_operation.retain(|_, owner| !owner.is_released());
        if let Some(owner) = calls.by_operation.get(request.operation_id()) {
            if owner.request != request {
                return Err(StudioError::new(
                    StudioErrorCode::Conflict,
                    "This Configuration operation already owns a different frozen request",
                    false,
                )
                .into());
            }
            return Ok(owner.clone());
        }
        if calls.sealed || bridge.shutdown.is_cancelled() {
            return Err(closed());
        }
        let next_call = calls.next_call.checked_add(1).ok_or_else(|| {
            BridgeError::from(StudioError::new(
                StudioErrorCode::Overloaded,
                "Configuration call identity space is exhausted",
                false,
            ))
        })?;
        let task = TypedFeedTask::new(
            bridge.subscriptions.next_id(),
            bridge.shutdown.child_token(),
        );
        let (result, _) = watch::channel(None);
        let owner = Arc::new(CommandOwner {
            identity: ConfigurationCommandCallIdentity {
                call_id: format!(
                    "configuration-frb-call:{}:{next_call}",
                    bridge.studio.owner_epoch()
                ),
                operation_id: request.operation_id().to_owned(),
            },
            request,
            task: task.clone(),
            result,
            state: Mutex::new(CallState {
                closing: false,
                close_joined: false,
                released: false,
                inflight_results: 0,
                owned_result: None,
            }),
            results_changed: Notify::new(),
        });
        bridge.subscriptions.register_typed(&task, &owner)?;
        calls.next_call = next_call;
        calls
            .by_operation
            .insert(owner.identity.operation_id.clone(), owner.clone());
        let producer = owner.clone();
        if let Err(error) = task.start(async move {
            match std::panic::AssertUnwindSafe(ConfigurationCallResult::run(
                &bridge.studio,
                producer.request.clone(),
            ))
            .catch_unwind()
            .await
            {
                Ok(result) => producer.complete(result),
                Err(panic) => {
                    producer.result.send_replace(Some(
                        producer.request.unknown(StudioError::internal()).into(),
                    ));
                    std::panic::resume_unwind(panic);
                }
            }
        }) {
            // A fresh task's start refusal is before its CAS future was polled. Retain a real
            // rejected call/result so it has the same explicit cleanup and identity contract.
            owner.reject_start(error);
        }
        Ok(owner)
    }

    pub(super) fn find(
        &self,
        operation_id: &str,
        kind: ConfigurationCallKind,
    ) -> Result<Option<Arc<CommandOwner>>, BridgeError> {
        let owner = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .by_operation
            .get(operation_id)
            .filter(|owner| !owner.is_released())
            .cloned();
        if let Some(owner) = &owner {
            owner.require_kind(kind)?;
        }
        Ok(owner)
    }

    pub(super) fn retire(&self, owner: &Arc<CommandOwner>) {
        let mut calls = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if owner.is_released()
            && calls
                .by_operation
                .get(&owner.identity.operation_id)
                .is_some_and(|current| Arc::ptr_eq(current, owner))
        {
            calls.by_operation.remove(&owner.identity.operation_id);
        }
    }

    pub(crate) fn seal(&self) {
        let owners = {
            let mut calls = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            calls.sealed = true;
            calls.by_operation.values().cloned().collect::<Vec<_>>()
        };
        for owner in owners {
            owner.request_close();
        }
    }

    /// Join the original supervised tasks within root's same first absolute exit deadline. A
    /// timeout cancels only these waiters, leaving task/result/capture/index ownership retained.
    pub(crate) async fn close_for_exit(
        &self,
        registry: &BridgeTaskRegistry,
        deadline: Instant,
    ) -> Vec<BridgeShutdownIssue> {
        self.seal();
        let owners: Vec<_> = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .by_operation
            .values()
            .cloned()
            .collect();
        let joining = futures::future::join_all(owners.iter().map(|owner| owner.close()));
        let mut issues = Vec::new();
        if tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), joining)
            .await
            .is_err()
        {
            issues.push(BridgeShutdownIssue {
                stage: "configurationCommand".into(),
                code: "deadlineExceeded".into(),
                message: "Original Configuration calls still own unfinished work".into(),
                retryable: true,
                correlation_id: StudioError::internal().correlation_id,
            });
        }
        for owner in owners {
            issues.extend(
                owner
                    .close_issues()
                    .into_iter()
                    .map(|issue| issue.diagnostic),
            );
            if owner.is_released() {
                registry.unregister_typed(owner.task.id);
                self.retire(&owner);
            }
        }
        issues
    }
}

impl CommandOwner {
    pub(super) fn identity(&self) -> ConfigurationCommandCallIdentity {
        self.identity.clone()
    }
    pub(super) fn require_kind(&self, kind: ConfigurationCallKind) -> Result<(), BridgeError> {
        if self.request.kind() == kind {
            Ok(())
        } else {
            Err(StudioError::new(
                StudioErrorCode::Conflict,
                "Original call belongs to a different Configuration resource kind",
                false,
            )
            .into())
        }
    }
    fn reject_start(&self, error: BridgeError) {
        let operation_id = self.identity.operation_id.clone();
        let outcome = match self.request.kind() {
            ConfigurationCallKind::Configuration => {
                BridgeCallOutcome::Configuration(BridgeConfigurationCommandOutcome::Rejected {
                    operation_id,
                    error,
                })
            }
            ConfigurationCallKind::Profile => {
                BridgeCallOutcome::Profile(BridgeProfileCommandOutcome::Rejected {
                    operation_id,
                    error,
                })
            }
            ConfigurationCallKind::Reload => {
                BridgeCallOutcome::Reload(BridgeConfigurationReloadOutcome::Rejected {
                    operation_id,
                    error,
                })
            }
        };
        self.result.send_replace(Some(outcome));
    }

    fn complete(&self, result: ConfigurationCallResult) {
        let outcome = result.outcome().into();
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .owned_result = Some(result);
        // Even a lost begin reply has an original indexed result and real immutable capture.
        self.result.send_replace(Some(outcome));
    }

    pub(super) fn result_query(self: &Arc<Self>) -> Result<CommandResultQuery, BridgeError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // A producer start refusal may already have cancelled its task token while the
        // registered call still owes a Rejected result. Only this call's explicit fence
        // seals result admission; a task token is not a business outcome or call close.
        if state.closing || state.released {
            return Err(closed());
        }
        let next = state.inflight_results.checked_add(1).ok_or_else(|| {
            BridgeError::from(StudioError::new(
                StudioErrorCode::Overloaded,
                "Configuration result query count is exhausted",
                false,
            ))
        })?;
        // Complete potentially allocating construction before changing the count. The
        // remaining assignment/move cannot suspend or lose an admitted registration.
        let query = CommandResultQuery {
            owner: self.clone(),
            result: self.result.subscribe(),
        };
        state.inflight_results = next;
        Ok(query)
    }

    pub(super) fn request_close(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .closing = true;
        // This seals observation/admission only; the original task never selects cancellation
        // against the admitted CAS/followup, and its owned result is installed even when late.
        self.task.signal_cancel();
    }

    pub(super) async fn close(&self) -> bool {
        self.request_close();
        let producer_joined = self.task.wait_stopped().await.is_ok();
        self.wait_results().await;
        if !producer_joined {
            return false;
        }
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .close_joined = true;
        self.release_if_explicitly_joined();
        true
    }

    pub(super) fn is_released(&self) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .released
    }

    async fn wait_results(&self) {
        loop {
            let changed = self.results_changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .inflight_results
                == 0
            {
                return;
            }
            changed.await;
        }
    }

    fn close_issues(&self) -> Vec<BridgeFeedCloseIssue> {
        let mut issues = self.task.close_issues();
        let producer_has_issues = !issues.is_empty();
        let producer_settled = self.task.is_settled();
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.inflight_results != 0 {
            issues.push(BridgeFeedCloseIssue {
                diagnostic: BridgeShutdownIssue {
                    stage: "configurationCommand".into(),
                    code: "resultQueriesPending".into(),
                    message: "Admitted Configuration call result queries have not finished".into(),
                    retryable: true,
                    correlation_id: StudioError::internal().correlation_id,
                },
                recovery: BridgeCleanupRecovery::AwaitCompletion,
            });
        }
        // A cancelled close waiter may leave the gate unfinished after its last query drops.
        // Clean producer/query facts do not themselves release this original call's evidence.
        if state.closing && !state.released && !producer_has_issues {
            let recovery = if state.inflight_results == 0 && producer_settled {
                BridgeCleanupRecovery::RetryClose
            } else {
                BridgeCleanupRecovery::AwaitCompletion
            };
            issues.push(BridgeFeedCloseIssue {
                diagnostic: BridgeShutdownIssue {
                    stage: "configurationCommand".into(),
                    code: "commandCleanupPending".into(),
                    message: "The original Configuration call has not completed its close gate"
                        .into(),
                    retryable: true,
                    correlation_id: StudioError::internal().correlation_id,
                },
                recovery,
            });
        }
        issues
    }

    fn release_if_explicitly_joined(&self) {
        let result = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if !state.closing || !state.close_joined || state.inflight_results != 0 {
                return;
            }
            state.released = true;
            state.owned_result.take()
        };
        drop(result);
    }
}

impl CommandResultQuery {
    pub(super) async fn result(&mut self) -> Result<BridgeCallOutcome, BridgeError> {
        loop {
            if let Some(value) = self.result.borrow_and_update().clone() {
                return Ok(value);
            }
            self.result
                .changed()
                .await
                .map_err(|_| BridgeError::from(StudioError::internal()))?;
        }
    }
}

impl Drop for CommandResultQuery {
    fn drop(&mut self) {
        let drained = {
            let mut state = self
                .owner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            // Only result_query constructs this non-cloneable guard, once per increment.
            state.inflight_results -= 1;
            state.inflight_results == 0
        };
        if drained {
            self.owner.results_changed.notify_waiters();
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
impl TypedFeedResource for CommandOwner {
    fn release_after_join(&self) {
        // BridgeTaskRegistry may retire a naturally finished producer after requestClose. That
        // is not SDK consumption: the separate live call index still retains its capture until
        // explicit close (or root's real exit close) has joined this exact task and every
        // admitted result query. The same gate applies to this automatic callback.
        self.release_if_explicitly_joined();
    }
}

#[flutter_rust_bridge::frb(ignore)]
pub(super) async fn close_call(
    owner: &Arc<CommandOwner>,
    bridge: &BridgeRuntime,
) -> BridgeFeedCloseReport {
    let outcome = if owner.close().await {
        bridge.subscriptions.unregister_typed(owner.task.id);
        bridge.configuration_commands.retire(owner);
        BridgeFeedCloseOutcome::Clean
    } else {
        BridgeFeedCloseOutcome::Unresolved {
            issues: owner.close_issues(),
        }
    };
    BridgeFeedCloseReport {
        feed_id: owner.identity().call_id,
        outcome,
    }
}
