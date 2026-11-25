//! 账户期望状态、后台准备、退避与退役共用原 registry 和唯一驱动。
//! 不持有第二份进程表；每个实例的实际退出仍由 AccountConnection 汇合。
use std::sync::atomic::Ordering;
use std::sync::{Arc, PoisonError};
use std::time::Duration;

use crate::{
    AcpAuthAction, AcpAuthFailureCode, AcpAuthStage, AcpAuthState, AcpConnectionState,
    StartAcpAuthRequest,
};
use anyhow::Result;
use tokio::time::Instant;

use super::super::acp_ops::RetainedJoin;
use super::admission::AcpAccountRuntime;
use super::connection::AccountConnection;
use super::mapping::AcpFailure;
use super::registry::AcpAccountInner;

pub(super) struct ConnectionLifecycle {
    pub(super) state: AcpConnectionState,
    pub(super) retry_at: Option<Instant>,
    attempts: u32,
}

impl Default for ConnectionLifecycle {
    fn default() -> Self {
        Self {
            state: AcpConnectionState::Stopped,
            retry_at: None,
            attempts: 0,
        }
    }
}

impl ConnectionLifecycle {
    pub(super) fn reset(&mut self) {
        *self = Self::default();
    }

    #[cfg(all(test, target_os = "linux"))]
    pub(super) fn seed_attempts_for_test(&mut self, attempts: u32) {
        self.attempts = attempts;
    }
}

pub(super) fn retry_delay(attempt: u32) -> Duration {
    Duration::from_secs((1u64 << attempt.saturating_sub(1).min(5)).min(30))
}

fn reconnects(failure: &AcpFailure) -> bool {
    matches!(
        failure.code,
        AcpAuthFailureCode::Startup | AcpAuthFailureCode::Transport
    ) || (failure.code == AcpAuthFailureCode::Io
        && matches!(
            failure.stage,
            AcpAuthStage::Process | AcpAuthStage::Initialize
        ))
}

impl AcpAccountInner {
    /// 实例资格在账户锁内裁决，旧连接的迟到初始化不能覆盖后继。
    pub(super) fn connection_state(
        &self,
        account: &Arc<AccountConnection>,
        state: AcpConnectionState,
    ) {
        let snapshot = {
            let mut registry = self.lock();
            if registry.closed {
                return;
            }
            let Some(slot) = registry.slots.get_mut(&account.account_id) else {
                return;
            };
            if slot.retired
                || !slot.identity.enabled
                || slot.revision != account.revision
                || !slot
                    .connection
                    .as_ref()
                    .is_some_and(|current| Arc::ptr_eq(current, account))
            {
                return;
            }
            if slot.lifecycle.state == state {
                return;
            }
            if matches!(state, AcpConnectionState::Starting) {
                slot.lifecycle.retry_at = None;
            }
            if matches!(state, AcpConnectionState::Ready)
                && slot.operation.is_none()
                && matches!(slot.state, AcpAuthState::Failed { .. })
            {
                slot.state = AcpAuthState::Unchecked;
            }
            if matches!(state, AcpConnectionState::Stopping) {
                // Measure healthy uptime when the connection stops. Physical cleanup can
                // take longer and must not turn a short-lived instance into a stable one.
                if account
                    .initialized_at
                    .lock()
                    .unwrap_or_else(PoisonError::into_inner)
                    .is_some_and(|started| started.elapsed() >= Duration::from_secs(60))
                {
                    slot.lifecycle.attempts = 0;
                }
                slot.usage = None;
                if slot.operation.is_none() {
                    slot.state = AcpAuthState::Unchecked;
                }
            }
            slot.lifecycle.state = state;
            registry.bump();
            registry.snapshot()
        };
        self.emit(snapshot);
    }

    fn instance_finished(&self, account: &Arc<AccountConnection>, joined: Result<()>) {
        let snapshot = {
            let mut registry = self.lock();
            let closed = registry.closed;
            let Some(slot) = registry.slots.get_mut(&account.account_id) else {
                return;
            };
            if !slot
                .connection
                .as_ref()
                .is_some_and(|current| Arc::ptr_eq(current, account))
            {
                return;
            }
            let cleanup = joined.is_err() || !account.settled.load(Ordering::Acquire);
            let failure = if cleanup {
                AcpFailure {
                    code: AcpAuthFailureCode::Cleanup,
                    stage: AcpAuthStage::Cleanup,
                    retryable: true,
                }
            } else {
                account
                    .failure
                    .lock()
                    .unwrap_or_else(PoisonError::into_inner)
                    .clone()
                    .unwrap_or(AcpFailure {
                        code: AcpAuthFailureCode::Transport,
                        stage: AcpAuthStage::Initialize,
                        retryable: true,
                    })
            };
            let intentional_upgrade = !cleanup
                && account
                    .pending_upgrade_version
                    .lock()
                    .unwrap_or_else(PoisonError::into_inner)
                    .is_some();
            // A cleanup owner with outstanding physical obligations stays registered.
            if account.settled.load(Ordering::Acquire) {
                slot.connection.take();
            }
            slot.usage = None;
            if slot.operation.is_none() {
                slot.state = AcpAuthState::Unchecked;
            }
            slot.background_scheduled = false;
            slot.lifecycle.retry_at = None;
            slot.lifecycle.state = if closed || slot.retired || !slot.identity.enabled {
                AcpConnectionState::Stopped
            } else if intentional_upgrade {
                slot.lifecycle.attempts = 0;
                AcpConnectionState::Stopped
            } else if !cleanup && reconnects(&failure) {
                slot.lifecycle.attempts = slot.lifecycle.attempts.saturating_add(1);
                let delay = retry_delay(slot.lifecycle.attempts);
                slot.lifecycle.retry_at = Some(Instant::now() + delay);
                AcpConnectionState::Retrying {
                    attempt: slot.lifecycle.attempts,
                    next_retry_at: crate::studio::unix_seconds()
                        .saturating_add(delay.as_secs() as i64),
                    failure: failure.failure(),
                }
            } else {
                AcpConnectionState::Blocked {
                    failure: failure.failure(),
                }
            };
            if slot.operation.is_none()
                && let AcpConnectionState::Blocked { failure } = &slot.lifecycle.state
            {
                slot.state = AcpAuthState::Failed {
                    failure: failure.clone(),
                };
            }
            registry.bump();
            registry.snapshot()
        };
        self.emit(snapshot);
    }
}

impl AcpAccountRuntime {
    pub(crate) fn installation_ready(&self, provider: crate::AcpProvider, installed_version: &str) {
        let mut emitted = None;
        let _ = self.inner.config.with_acp_snapshot(|revision, snapshot| {
            let mut operations_to_cancel = Vec::new();
            let mut connections_to_cancel = Vec::new();
            let changed_snapshot = {
                let mut registry = self.inner.lock();
                if registry.closed {
                    return;
                }
                let mut changed = false;
                let mut retiring = Vec::new();
                for (id, entry) in &snapshot.definitions {
                    let matches = match provider {
                        crate::AcpProvider::Antigravity => {
                            entry.definition.template_kind()
                                == Some(crate::config::AcpProvider::Antigravity)
                        }
                    };
                    if !entry.definition.enabled || !matches {
                        continue;
                    }
                    let Some(slot) = registry.slots.get_mut(id) else {
                        continue;
                    };
                    if slot.retired {
                        continue;
                    }
                    if matches!(
                        &slot.lifecycle.state,
                        AcpConnectionState::Blocked { failure }
                            if matches!(
                                failure.code,
                                AcpAuthFailureCode::PreparationRequired
                                    | AcpAuthFailureCode::InstallationInvalid
                                    | AcpAuthFailureCode::ServerVersionMismatch
                            )
                    ) {
                        slot.lifecycle.reset();
                        slot.background_scheduled = false;
                        if slot.operation.is_none() {
                            slot.state = AcpAuthState::Unchecked;
                        }
                        changed = true;
                        continue;
                    }
                    if matches!(
                        slot.lifecycle.state,
                        AcpConnectionState::Retrying { .. } | AcpConnectionState::Stopped
                    ) && slot.connection.is_none()
                    {
                        slot.lifecycle.reset();
                        slot.background_scheduled = false;
                        changed = true;
                        continue;
                    }
                    let running_version = slot.connection.as_ref().and_then(|connection| {
                        connection
                            .installed_version
                            .lock()
                            .unwrap_or_else(PoisonError::into_inner)
                            .clone()
                    });
                    if running_version
                        .as_deref()
                        .is_some_and(|v| v != installed_version)
                        && let Some(connection) = slot.connection.as_ref().cloned()
                        && !connection.mark_pending_upgrade_if_active(installed_version)
                    {
                        slot.connection.take();
                        retiring.push(connection.clone());
                        connections_to_cancel.push(connection);
                        if let Some(operation) = slot.operation.as_ref() {
                            operations_to_cancel.push(Arc::clone(operation));
                        }
                        slot.lifecycle.reset();
                        slot.lifecycle.state = AcpConnectionState::Stopping;
                        slot.background_scheduled = false;
                        slot.usage = None;
                        slot.state = match slot.operation.as_ref() {
                            Some(operation) => AcpAuthState::Closing {
                                operation_id: operation.operation_id.clone(),
                                failure: None,
                            },
                            None => AcpAuthState::Unchecked,
                        };
                        changed = true;
                    }
                }
                registry.retiring.extend(retiring);
                changed.then(|| {
                    registry.bump();
                    registry.snapshot()
                })
            };
            for operation in operations_to_cancel {
                operation.cancel.cancel();
            }
            for connection in connections_to_cancel {
                connection.signal_cancel();
            }
            emitted = changed_snapshot;
            self.background_prepare(revision, snapshot);
        });
        if let Some(snapshot) = emitted {
            self.inner.emit(snapshot);
        }
        self.inner.retirement_wake.notify_one();
    }

    pub(super) fn start_lifecycle_driver(&self) {
        let weak = Arc::downgrade(&self.inner);
        let wake = self.inner.retirement_wake.clone();
        let task = tokio::spawn(async move {
            loop {
                let notified = wake.notified();
                tokio::pin!(notified);
                notified.as_mut().enable();
                let Some(inner) = weak.upgrade() else {
                    return;
                };
                let (retiring, current) = {
                    let registry = inner.lock();
                    let finished = |account: &&Arc<AccountConnection>| {
                        account.supervisor_finished.load(Ordering::Acquire)
                    };
                    (
                        registry
                            .retiring
                            .iter()
                            .filter(finished)
                            .cloned()
                            .collect::<Vec<_>>(),
                        registry
                            .slots
                            .values()
                            .filter_map(|slot| slot.connection.as_ref())
                            .filter(finished)
                            .cloned()
                            .collect::<Vec<_>>(),
                    )
                };
                for account in retiring {
                    let result = account.wait().await;
                    if account.settled.load(Ordering::Acquire) {
                        let mut registry = inner.lock();
                        registry
                            .retiring
                            .retain(|entry| !Arc::ptr_eq(entry, &account));
                        if let Err(error) = result {
                            registry.retirement_issue = Some(
                                format!("ACP retired account cleanup failed: {error}")
                                    .chars()
                                    .take(2048)
                                    .collect(),
                            );
                        }
                    }
                }
                for account in current {
                    // Join only completed supervisors, never block another account's preparation.
                    let result = account.wait().await;
                    inner.instance_finished(&account, result);
                }
                let stopped = {
                    let mut registry = inner.lock();
                    let retiring = registry
                        .retiring
                        .iter()
                        .map(|account| account.account_id.clone())
                        .collect::<std::collections::BTreeSet<_>>();
                    let mut changed = false;
                    for (id, slot) in &mut registry.slots {
                        if slot.connection.is_none()
                            && !retiring.contains(id)
                            && matches!(slot.lifecycle.state, AcpConnectionState::Stopping)
                        {
                            slot.lifecycle.state = AcpConnectionState::Stopped;
                            changed = true;
                        }
                    }
                    changed.then(|| {
                        registry.bump();
                        registry.snapshot()
                    })
                };
                if let Some(snapshot) = stopped {
                    inner.emit(snapshot);
                }
                let runtime = Self {
                    inner: inner.clone(),
                };
                let _ = inner.config.with_acp_snapshot(|revision, snapshot| {
                    runtime.background_prepare(revision, snapshot);
                });
                let (done, deadline) = {
                    let registry = inner.lock();
                    let done = registry.closed
                        && registry
                            .retiring
                            .iter()
                            .all(|account| account.supervisor_finished.load(Ordering::Acquire))
                        && registry
                            .slots
                            .values()
                            .filter_map(|slot| slot.connection.as_ref())
                            .all(|account| account.supervisor_finished.load(Ordering::Acquire));
                    let deadline = registry
                        .slots
                        .values()
                        .filter(|slot| {
                            !registry.closed
                                && !slot.retired
                                && slot.identity.enabled
                                && slot.operation.is_none()
                        })
                        .filter_map(|slot| slot.lifecycle.retry_at)
                        .min();
                    (done, deadline)
                };
                drop(runtime);
                drop(inner);
                if done {
                    return;
                }
                match deadline {
                    Some(deadline) => {
                        tokio::select! { () = notified => {}, () = tokio::time::sleep_until(deadline) => {} }
                    }
                    None => notified.await,
                }
            }
        });
        self.inner.retirement_join.install(task);
    }

    pub(super) async fn join_lifecycle_driver(&self, deadline: Instant) -> Result<()> {
        self.inner.retirement_wake.notify_one();
        match self.inner.retirement_join.join_until(deadline).await {
            RetainedJoin::TimedOut => Err(anyhow::anyhow!("ACP lifecycle driver remains pending")),
            RetainedJoin::Absent
            | RetainedJoin::Observed(Ok(()))
            | RetainedJoin::Settled(Ok(())) => Ok(()),
            RetainedJoin::Observed(Err(error)) => {
                self.inner.lock().retirement_issue =
                    Some("ACP lifecycle driver join failed".into());
                Err(error.into())
            }
            RetainedJoin::Settled(Err(error)) => {
                self.inner.lock().retirement_issue =
                    Some("ACP lifecycle driver join failed".into());
                Err(anyhow::anyhow!(error))
            }
        }
    }

    pub(super) fn background_prepare(
        &self,
        revision: u64,
        snapshot: &crate::config::AcpDefinitionsSnapshot,
    ) {
        let (requests, changed) = {
            let mut registry = self.inner.lock();
            if registry.closed || registry.settings_revision != revision {
                return;
            }
            let mut changed = false;
            let requests = snapshot
                .definitions
                .iter()
                .filter_map(|(id, entry)| {
                    let slot = registry.slots.get_mut(id)?;
                    if !entry.definition.enabled
                        || slot.retired
                        || slot.background_scheduled
                        || slot.operation.is_some()
                        || matches!(
                            slot.lifecycle.state,
                            AcpConnectionState::Blocked { .. } | AcpConnectionState::Stopping
                        )
                        || slot
                            .lifecycle
                            .retry_at
                            .is_some_and(|deadline| deadline > Instant::now())
                    {
                        return None;
                    }
                    slot.background_scheduled = true;
                    slot.lifecycle.retry_at = None;
                    if !matches!(slot.lifecycle.state, AcpConnectionState::Ready) {
                        slot.lifecycle.state = AcpConnectionState::Starting;
                        changed = true;
                    }
                    Some(StartAcpAuthRequest {
                        account_id: id.clone(),
                        expected_connection_revision: entry.connection_revision,
                        operation_id: format!("background-{}", uuid::Uuid::new_v4()),
                        action: AcpAuthAction::Check,
                    })
                })
                .collect::<Vec<_>>();
            let changed = changed.then(|| {
                registry.bump();
                registry.snapshot()
            });
            (requests, changed)
        };
        if let Some(snapshot) = changed {
            self.inner.emit(snapshot);
        }
        for request in requests {
            let _ =
                AcpAccountInner::admit_background(self.inner.clone(), revision, snapshot, request);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reconnect_backoff_is_capped_and_permanent_failures_do_not_restart() {
        assert_eq!(
            (1..=8)
                .map(|attempt| retry_delay(attempt).as_secs())
                .collect::<Vec<_>>(),
            [1, 2, 4, 8, 16, 30, 30, 30]
        );
        for code in [
            AcpAuthFailureCode::MissingExecutable,
            AcpAuthFailureCode::Authentication,
            AcpAuthFailureCode::ServerVersionMismatch,
            AcpAuthFailureCode::Cleanup,
        ] {
            assert!(!reconnects(&AcpFailure {
                code,
                stage: AcpAuthStage::Initialize,
                retryable: true
            }));
        }
    }
}
