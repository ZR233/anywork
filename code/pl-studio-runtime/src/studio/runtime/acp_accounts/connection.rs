//! 账户连接代次持有唯一进程和 SDK join；认证槽位与业务成员仅租用它。
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::{Result, ensure};
use futures::FutureExt;
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::super::acp_ops::{RetainedJoin, RetainedTask};

use super::admission::AcpAccountRuntime;
use super::mapping::AcpFailure;
use super::mapping::{prepare_failure, prepare_probe_dir};
use super::registry::AcpAccountInner;
use crate::config::AcpServiceDefinition;
use crate::studio::runtime::acp_business::AcpResources;
use crate::studio::runtime::acp_worker::{
    AcpSpawnError, AcpSpawnRequest, AcpWorker, PROCESS_CLEANUP_LIMIT, Reclaim,
};
use crate::{AcpAuthFailureCode, AcpAuthStage, AcpConnectionState};

#[derive(Clone)]
pub(crate) struct PreparedConnection {
    pub(crate) protocol: pl_acp::connection::Connection,
    pub(crate) probe_dir: PathBuf,
    pub(crate) expected_version: Option<String>,
}

pub(crate) struct AccountConnection {
    pub(super) account_id: String,
    pub(super) revision: u64,
    cancel: CancellationToken,
    pub(super) cleanup: pl_acp::auth::CleanupBudget,
    ready: watch::Receiver<Option<Result<PreparedConnection, AcpFailure>>>,
    protocol: Mutex<Option<pl_acp::connection::Connection>>,
    members: Mutex<Vec<Arc<AcpResources>>>,
    // Even after a member closes, the official process can retain its helper image.
    mcp_source: crate::host_mcp_assets::HostMcpSource,
    frontend: tokio::sync::Mutex<Frontend>,
    join: RetainedTask<()>,
    pub(super) settled: AtomicBool,
    pub(super) supervisor_finished: AtomicBool,
    pub(super) failure: Mutex<Option<AcpFailure>>,
    pub(super) initialized_at: Mutex<Option<tokio::time::Instant>>,
    pub(super) installed_version: Mutex<Option<String>>,
    pub(super) pending_upgrade_version: Mutex<Option<String>>,
    pub(super) launch_now: tokio::sync::Notify,
    retirement_wake: Arc<tokio::sync::Notify>,
    issue: Mutex<Option<String>>,
    retry: tokio::sync::Notify,
}

#[derive(Default)]
struct Frontend {
    asset: Option<crate::host_mcp_assets::HostMcpAsset>,
    preparation: Option<JoinHandle<Result<crate::host_mcp_assets::HostMcpAsset, String>>>,
}

impl AccountConnection {
    pub(super) fn is_closing(&self) -> bool {
        self.cancel.is_cancelled()
            || self
                .protocol
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .as_ref()
                .is_some_and(pl_acp::connection::Connection::is_closed)
    }
    pub(crate) fn signal_cancel(&self) {
        self.cancel.cancel();
        if let Some(protocol) = self
            .protocol
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .as_ref()
        {
            protocol.cancel();
        }
        let members = self
            .members
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone();
        for member in members {
            member.cancel();
        }
        self.retry.notify_one();
    }

    pub(crate) fn attach(&self, member: &Arc<AcpResources>) -> Result<()> {
        let mut members = self.members.lock().unwrap_or_else(PoisonError::into_inner);
        ensure!(
            !self.cancel.is_cancelled(),
            "ACP account connection is closing"
        );
        members.retain(|member| member.has_obligations());
        members.push(member.clone());
        Ok(())
    }

    /// 在持 `members` 锁期间检查活跃成员并在非空时原子写入待升级目标版本，避免与成员关闭发生竞态。
    pub(super) fn mark_pending_upgrade_if_active(&self, version: &str) -> bool {
        let mut members = self.members.lock().unwrap_or_else(PoisonError::into_inner);
        members.retain(|member| member.has_obligations());
        if members.is_empty() {
            return false;
        }
        *self
            .pending_upgrade_version
            .lock()
            .unwrap_or_else(PoisonError::into_inner) = Some(version.to_owned());
        true
    }

    pub(crate) fn notify_member_closed(&self) {
        let should_cancel = {
            let mut members = self.members.lock().unwrap_or_else(PoisonError::into_inner);
            members.retain(|member| member.has_obligations());
            if !members.is_empty() {
                false
            } else {
                self.pending_upgrade_version
                    .lock()
                    .unwrap_or_else(PoisonError::into_inner)
                    .is_some()
            }
        };
        if should_cancel {
            self.signal_cancel();
            self.retirement_wake.notify_one();
        }
    }

    pub(crate) async fn frontend(&self) -> Result<crate::host_mcp_assets::HostMcpAsset> {
        let mut frontend = self.frontend.lock().await;
        ensure!(!self.is_closing(), "ACP account connection is closing");
        if let Some(asset) = frontend.asset.as_ref() {
            return Ok(asset.clone());
        }
        if frontend.preparation.is_none() {
            let source = self.mcp_source.clone();
            frontend.preparation = Some(tokio::spawn(async move {
                crate::host_mcp_assets::prepare(source)
                    .await
                    .map_err(|error| error.to_string())
            }));
        }
        // Borrow the original join in its owner. A cancelled session/waiter cannot detach it
        // or start another materialization while that preparation is still in flight.
        let result = frontend
            .preparation
            .as_mut()
            .expect("registered preparation")
            .await;
        frontend.preparation.take();
        let asset = result
            .map_err(|error| anyhow::anyhow!(error.to_string()))?
            .map_err(anyhow::Error::msg)?;
        frontend.asset = Some(asset.clone());
        ensure!(!self.is_closing(), "ACP account connection is closing");
        Ok(asset)
    }

    async fn close_frontend(&self) {
        let mut frontend = self.frontend.lock().await;
        if let Some(preparation) = frontend.preparation.as_mut() {
            if !matches!(preparation.await, Ok(Ok(_))) {
                *self.issue.lock().unwrap_or_else(PoisonError::into_inner) =
                    Some("ACP Host MCP preparation failed during shutdown".into());
            }
            frontend.preparation.take();
        }
        frontend.asset.take();
    }

    async fn launched(&self) -> Result<PreparedConnection, AcpFailure> {
        let mut ready = self.ready.clone();
        loop {
            if let Some(result) = ready.borrow_and_update().clone() {
                return result;
            }
            if ready.changed().await.is_err() {
                return Err(closed_failure());
            }
        }
    }

    pub(super) async fn prepared(&self) -> Result<PreparedConnection, AcpFailure> {
        let prepared = self.launched().await?;
        prepared.protocol.initialized().await.map_err(|error| {
            super::mapping::map_auth_error(&pl_acp::auth::AuthError::from_connection(error))
        })?;
        Ok(prepared)
    }

    pub(crate) async fn ready_business(
        &self,
    ) -> Result<PreparedConnection, crate::AcpBusinessFailure> {
        self.launched().await.map_err(|failure| {
            use crate::{AcpBusinessFailure, AcpBusinessFailureKind as Kind};
            let kind = match failure.code {
                AcpAuthFailureCode::PreparationRequired => Kind::InstallRequired,
                AcpAuthFailureCode::InstallationInvalid => Kind::InstallationInvalid,
                AcpAuthFailureCode::UnsupportedPlatform => Kind::UnsupportedPlatform,
                AcpAuthFailureCode::MissingExecutable => Kind::MissingExecutable,
                AcpAuthFailureCode::ServerVersionMismatch => Kind::ServerVersionMismatch,
                AcpAuthFailureCode::UnsupportedVersion => Kind::UnsupportedVersion,
                AcpAuthFailureCode::Cancelled => Kind::Cancelled,
                AcpAuthFailureCode::Io => Kind::Io,
                _ => Kind::Preparation,
            };
            AcpBusinessFailure {
                kind,
                message: failure.failure().message,
                rpc_code: None,
                rpc_data: None,
                auth_methods: Vec::new(),
            }
        })
    }

    /// Borrow the original join; cancelling a waiter never detaches its supervisor.
    pub(super) async fn wait(&self) -> Result<()> {
        self.observe_join(self.join.join().await)
    }

    #[cfg(all(test, target_os = "linux"))]
    pub(super) async fn close(&self) -> Result<()> {
        self.close_until(self.cleanup.deadline()).await
    }

    /// Cancel and join through one shared deadline. Timeout drops only this waiter.
    pub(super) async fn close_until(&self, deadline: tokio::time::Instant) -> Result<()> {
        self.signal_cancel();
        match self.join.join_until(deadline).await {
            RetainedJoin::TimedOut => Err(anyhow::anyhow!("ACP account cleanup remains pending")),
            joined => self.observe_join(joined),
        }
    }

    fn observe_join(&self, joined: RetainedJoin<()>) -> Result<()> {
        if let RetainedJoin::Observed(Err(error)) = &joined {
            *self.issue.lock().unwrap_or_else(PoisonError::into_inner) = Some(error.to_string());
        }
        if matches!(joined, RetainedJoin::Observed(_)) {
            self.retirement_wake.notify_one();
        }
        if let Some(issue) = self
            .issue
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
        {
            anyhow::bail!(issue);
        }
        if let RetainedJoin::Settled(Err(error)) = joined {
            anyhow::bail!(error);
        }
        Ok(())
    }
}

fn closed_failure() -> AcpFailure {
    AcpFailure {
        code: AcpAuthFailureCode::Transport,
        stage: AcpAuthStage::Initialize,
        retryable: true,
    }
}

impl AcpAccountRuntime {
    pub(crate) fn connection(
        &self,
        definition: &AcpServiceDefinition,
    ) -> Result<Arc<AccountConnection>> {
        self.connection_with_mode(definition, false)
    }

    pub(crate) fn acquire_for_business(
        &self,
        definition: &AcpServiceDefinition,
    ) -> Result<Arc<AccountConnection>> {
        self.connection_with_mode(definition, true)
    }

    fn connection_with_mode(
        &self,
        definition: &AcpServiceDefinition,
        wake_backoff: bool,
    ) -> Result<Arc<AccountConnection>> {
        let inner = self.inner.clone();
        let (connection, emit_snapshot) =
            self.inner.config.with_acp_snapshot(|_, snapshot| {
                let entry = snapshot
                    .definitions
                    .get(&definition.id)
                    .ok_or_else(|| anyhow::anyhow!("ACP account was removed"))?;
                ensure!(
                    entry.definition.enabled
                        && entry.definition.launch == definition.launch
                        && entry.definition.env == definition.env,
                    "ACP account definition changed"
                );
                let mut registry = inner.lock();
                ensure!(!registry.closed, "ACP runtime is closing");
                let slot = registry
                    .slots
                    .get_mut(&definition.id)
                    .ok_or_else(|| anyhow::anyhow!("ACP account is unavailable"))?;
                ensure!(
                    !slot.retired && slot.revision == entry.connection_revision,
                    "ACP account is stale"
                );
                let mut emit_snapshot = None;
                if wake_backoff {
                    slot.lifecycle.retry_at = None;
                }
                let start_at = if wake_backoff {
                    None
                } else {
                    slot.lifecycle.retry_at
                };
                if let Some(connection) = slot.connection.as_ref().cloned() {
                    if !connection.is_closing() && connection.revision == entry.connection_revision
                    {
                        if wake_backoff {
                            connection.launch_now.notify_one();
                            if matches!(
                                slot.lifecycle.state,
                                AcpConnectionState::Retrying { .. } | AcpConnectionState::Stopped
                            ) {
                                slot.lifecycle.state = AcpConnectionState::Starting;
                                registry.bump();
                                emit_snapshot = Some(registry.snapshot());
                            }
                        }
                        return Ok((connection, emit_snapshot));
                    }
                    connection.retry.notify_one();
                    if !connection.settled.load(Ordering::Acquire) {
                        // Keep the explicit retry on the original closing owner, rather than
                        // releasing its auth slot or overlapping a second process.
                        return Ok((connection, None));
                    }
                }
                let mut previous: Vec<_> = registry
                    .retiring
                    .iter()
                    .filter(|connection| connection.account_id == definition.id)
                    .cloned()
                    .collect();
                if let Some(connection) = registry
                    .slots
                    .get_mut(&definition.id)
                    .and_then(|slot| slot.connection.take())
                {
                    previous.push(connection.clone());
                    registry.retiring.push(connection);
                }
                if wake_backoff
                    && let Some(slot) = registry.slots.get_mut(&definition.id)
                    && matches!(
                        slot.lifecycle.state,
                        AcpConnectionState::Retrying { .. } | AcpConnectionState::Stopped
                    )
                {
                    slot.lifecycle.state = AcpConnectionState::Starting;
                    registry.bump();
                    emit_snapshot = Some(registry.snapshot());
                }
                let (publish, ready) = watch::channel(None);
                let connection = Arc::new(AccountConnection {
                    account_id: definition.id.clone(),
                    revision: entry.connection_revision,
                    cancel: CancellationToken::new(),
                    cleanup: pl_acp::auth::CleanupBudget::new(PROCESS_CLEANUP_LIMIT),
                    ready,
                    protocol: Mutex::new(None),
                    members: Mutex::new(Vec::new()),
                    mcp_source: inner.mcp_source.clone(),
                    frontend: tokio::sync::Mutex::new(Frontend::default()),
                    join: RetainedTask::empty(),
                    settled: AtomicBool::new(false),
                    supervisor_finished: AtomicBool::new(false),
                    failure: Mutex::new(None),
                    initialized_at: Mutex::new(None),
                    installed_version: Mutex::new(None),
                    pending_upgrade_version: Mutex::new(None),
                    launch_now: tokio::sync::Notify::new(),
                    retirement_wake: inner.retirement_wake.clone(),
                    issue: Mutex::new(None),
                    retry: tokio::sync::Notify::new(),
                });
                registry
                    .slots
                    .get_mut(&definition.id)
                    .expect("validated slot")
                    .connection = Some(connection.clone());
                // Registry and join owner are installed before the supervisor can acquire launch resources.
                let run_inner = inner.clone();
                let run_account = connection.clone();
                let run_definition = definition.clone();
                let task = tokio::spawn(async move {
                    let result = std::panic::AssertUnwindSafe(supervise(
                        run_inner,
                        run_account.clone(),
                        run_definition,
                        previous,
                        start_at,
                        publish,
                    ))
                    .catch_unwind()
                    .await;
                    run_account
                        .supervisor_finished
                        .store(true, Ordering::Release);
                    run_account.retirement_wake.notify_one();
                    if let Err(panic) = result {
                        std::panic::resume_unwind(panic);
                    }
                });
                connection.join.install(task);
                inner.retirement_wake.notify_one();
                Ok((connection, emit_snapshot))
            })??;
        if let Some(snapshot) = emit_snapshot {
            self.inner.emit(snapshot);
        }
        Ok(connection)
    }

    pub(super) fn connections(&self) -> Vec<Arc<AccountConnection>> {
        let registry = self.inner.lock();
        registry
            .retiring
            .iter()
            .cloned()
            .chain(
                registry
                    .slots
                    .values()
                    .filter_map(|slot| slot.connection.clone()),
            )
            .collect()
    }
}

async fn supervise(
    inner: Arc<AcpAccountInner>,
    account: Arc<AccountConnection>,
    definition: AcpServiceDefinition,
    previous: Vec<Arc<AccountConnection>>,
    start_at: Option<tokio::time::Instant>,
    publish: watch::Sender<Option<Result<PreparedConnection, AcpFailure>>>,
) {
    for predecessor in previous {
        // A failed observation is retained on the predecessor. Only actual supervisor completion
        // allows launch of this generation; no timeout/restart can overlap two real processes.
        let _ = predecessor.wait().await;
        if !predecessor.settled.load(Ordering::Acquire) {
            publish.send_replace(Some(Err(closed_failure())));
            return;
        }
    }
    if let Some(start_at) = start_at {
        tokio::select! {
            biased;
            () = account.cancel.cancelled() => {},
            () = account.launch_now.notified() => {},
            () = tokio::time::sleep_until(start_at) => {},
        }
    }
    if account.cancel.is_cancelled() {
        publish.send_replace(Some(Err(closed_failure())));
        account.settled.store(true, Ordering::Release);
        return;
    }
    inner.connection_state(&account, AcpConnectionState::Starting);
    let launched = spawn_process(&inner, &account.account_id, &definition, &account.cancel).await;
    let (mut worker, probe_dir, expected_version) = match launched {
        Ok((worker, probe_dir, expected_version)) => {
            *account
                .installed_version
                .lock()
                .unwrap_or_else(PoisonError::into_inner) = expected_version.clone();
            (worker, probe_dir, expected_version)
        }
        Err(error) => {
            *account
                .failure
                .lock()
                .unwrap_or_else(PoisonError::into_inner) = Some(error.clone());
            publish.send_replace(Some(Err(error)));
            account.cancel.cancel();
            account.settled.store(true, Ordering::Release);
            return;
        }
    };
    let streams = worker.take_streams();
    if let Some((writer, reader)) = streams {
        let (protocol, driver) =
            pl_acp::connection::channel(expected_version.clone(), account.cleanup.clone());
        *account
            .protocol
            .lock()
            .unwrap_or_else(PoisonError::into_inner) = Some(protocol.clone());
        if account.cancel.is_cancelled() {
            protocol.cancel();
        }
        let mut sdk = tokio::spawn(driver.run(writer, reader));
        // Deliver host launch first. Business observers must be handed out before a slow
        // initialize, while auth waiters share the validated initialized() result above.
        publish.send_replace(Some(Ok(PreparedConnection {
            protocol: protocol.clone(),
            probe_dir,
            expected_version,
        })));
        let mut initialized = false;
        let sdk_result = loop {
            tokio::select! {
                biased;
                () = account.cancel.cancelled() => {
                    inner.connection_state(&account, AcpConnectionState::Stopping);
                    protocol.cancel();
                    break sdk.await;
                }
                result = protocol.initialized(), if !initialized => {
                    initialized = true;
                    match result {
                        Ok(_) => {
                            *account.initialized_at.lock().unwrap_or_else(PoisonError::into_inner) = Some(tokio::time::Instant::now());
                            inner.connection_state(&account, AcpConnectionState::Ready);
                        }
                        Err(error) => {
                            *account.failure.lock().unwrap_or_else(PoisonError::into_inner) = Some(super::mapping::map_auth_error(&pl_acp::auth::AuthError::from_connection(error)));
                        }
                    }
                }
                result = &mut sdk => {
                    inner.connection_state(&account, AcpConnectionState::Stopping);
                    break result;
                }
                _exited = worker.observe_exit() => {
                    // Root exit is observable even when descendants keep stdio open. Reclaim
                    // below remains the authority for process wait / cleanup errors.
                    inner.connection_state(&account, AcpConnectionState::Stopping);
                    account.signal_cancel();
                    break sdk.await;
                }
            }
        };
        match sdk_result {
            Ok(exit) => {
                if exit.cleanup_timed_out {
                    *account.issue.lock().unwrap_or_else(PoisonError::into_inner) =
                        Some("ACP SDK cleanup exceeded its original budget".into());
                } else if let Err(error) = exit.result {
                    account
                        .failure
                        .lock()
                        .unwrap_or_else(PoisonError::into_inner)
                        .get_or_insert_with(|| {
                            super::mapping::map_auth_error(
                                &pl_acp::auth::AuthError::from_connection(error),
                            )
                        });
                }
            }
            Err(error) => {
                *account.issue.lock().unwrap_or_else(PoisonError::into_inner) =
                    Some(error.to_string())
            }
        }
        account.signal_cancel();
        let members = account
            .members
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone();
        let close_results =
            futures::future::join_all(members.iter().map(|member| member.close())).await;
        if close_results.iter().any(|result| !result.local_complete) {
            *account.issue.lock().unwrap_or_else(PoisonError::into_inner) =
                Some("ACP session cleanup remains pending".into());
        }
    } else {
        publish.send_replace(Some(Err(closed_failure())));
    }
    account.signal_cancel();
    loop {
        match worker.reclaim().await {
            Reclaim::Stopped => break,
            Reclaim::Settled(issue) => {
                *account.issue.lock().unwrap_or_else(PoisonError::into_inner) = Some(issue);
                break;
            }
            Reclaim::Pending(issue) => {
                *account.issue.lock().unwrap_or_else(PoisonError::into_inner) = Some(issue);
                inner.connection_state(
                    &account,
                    AcpConnectionState::Blocked {
                        failure: AcpFailure {
                            code: AcpAuthFailureCode::Cleanup,
                            stage: AcpAuthStage::Cleanup,
                            retryable: true,
                        }
                        .failure(),
                    },
                );
                account.retry.notified().await;
            }
        }
    }
    loop {
        let members = account
            .members
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone();
        let results = futures::future::join_all(members.iter().map(|member| async {
            let association_error = member.settle_association(&inner.events).await.err();
            let closed = member.close().await;
            (association_error, closed.local_complete)
        }))
        .await;
        let mut pending = false;
        for (association_error, local_complete) in results {
            if let Some(error) = association_error {
                *account.issue.lock().unwrap_or_else(PoisonError::into_inner) =
                    Some(error.to_string());
                pending = true;
            }
            pending |= !local_complete;
        }
        if !pending {
            break;
        }
        inner.connection_state(
            &account,
            AcpConnectionState::Blocked {
                failure: AcpFailure {
                    code: AcpAuthFailureCode::Cleanup,
                    stage: AcpAuthStage::Cleanup,
                    retryable: true,
                }
                .failure(),
            },
        );
        account.retry.notified().await;
    }
    account
        .members
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clear();
    account.close_frontend().await;
    account.settled.store(true, Ordering::Release);
}

/// 准备探测目录并启动已验证的官方程序；失败时映射为类型化阶段错误。
pub(super) async fn spawn_process(
    inner: &Arc<AcpAccountInner>,
    account_id: &str,
    definition: &crate::config::AcpServiceDefinition,
    cancellation: &tokio_util::sync::CancellationToken,
) -> Result<(AcpWorker, PathBuf, Option<String>), AcpFailure> {
    let probe_dir = prepare_probe_dir(inner, account_id)
        .await
        .map_err(|_error| AcpFailure {
            code: AcpAuthFailureCode::Io,
            stage: AcpAuthStage::Config,
            retryable: true,
        })?;
    let resolved = super::super::acp_launch::resolve_launch(
        &inner.store,
        definition,
        &probe_dir,
        cancellation,
    )
    .await
    .map_err(|error| {
        use super::super::acp_launch::AcpLaunchError;
        match error {
            AcpLaunchError::Template(error) => prepare_failure(error),
            AcpLaunchError::Cancelled => AcpFailure {
                code: AcpAuthFailureCode::Cancelled,
                stage: AcpAuthStage::Config,
                retryable: false,
            },
            AcpLaunchError::MissingExecutable => AcpFailure {
                code: AcpAuthFailureCode::MissingExecutable,
                stage: AcpAuthStage::Process,
                retryable: false,
            },
            AcpLaunchError::InvalidWorkingDirectory | AcpLaunchError::InvalidDefinition => {
                AcpFailure {
                    code: AcpAuthFailureCode::Io,
                    stage: AcpAuthStage::Config,
                    retryable: false,
                }
            }
        }
    })?;
    tracing::debug!(
        managed_template = resolved.template.is_some(),
        "ACP launch prepared"
    );
    let request = AcpSpawnRequest {
        program: resolved.program,
        args: resolved.args,
        env: resolved.env,
        cwd: probe_dir.clone(),
    };
    match AcpWorker::spawn(request, &inner.workers, cancellation).await {
        Ok(worker) => Ok((worker, probe_dir, resolved.expected_server_version)),
        Err(error) => Err(spawn_failure(error)),
    }
}

/// 启动错误到类型化阶段错误的穷尽映射。
fn spawn_failure(error: AcpSpawnError) -> AcpFailure {
    match error {
        AcpSpawnError::MissingExecutable => AcpFailure {
            code: AcpAuthFailureCode::MissingExecutable,
            stage: AcpAuthStage::Process,
            retryable: false,
        },
        AcpSpawnError::Startup { source } => {
            // 原始原因只作内部诊断：日志只记录安全步骤与有界长度，绝不记录或透出任意文本。
            tracing::warn!(
                step = "process",
                source_bytes = source.len(),
                "ACP 连接启动失败"
            );
            AcpFailure {
                code: AcpAuthFailureCode::Startup,
                stage: AcpAuthStage::Process,
                retryable: true,
            }
        }
        AcpSpawnError::Cancelled => AcpFailure {
            code: AcpAuthFailureCode::Cancelled,
            stage: AcpAuthStage::Process,
            retryable: true,
        },
    }
}

#[cfg(all(test, target_os = "linux"))]
mod tests;
