//! 账户连接代次持有唯一进程和 SDK join；认证槽位与业务成员仅租用它。
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::{Result, ensure};
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::admission::AcpAuthRuntime;
use super::mapping::AcpFailure;
use super::mapping::{prepare_failure, prepare_probe_dir};
use super::registry::AcpAuthInner;
use crate::config::AcpServiceDefinition;
use crate::studio::runtime::acp_business::AcpResources;
use crate::studio::runtime::acp_worker::{
    AcpSpawnError, AcpSpawnRequest, AcpWorker, PROCESS_CLEANUP_LIMIT, Reclaim,
};
use pl_protocol::studio::{AcpAuthAction, AcpAuthFailureCode, AcpAuthStage, StartAcpAuthRequest};

#[derive(Clone)]
pub(crate) struct PreparedConnection {
    pub(crate) protocol: pl_acp::connection::Connection,
    pub(crate) probe_dir: PathBuf,
    pub(crate) expected_version: Option<String>,
}

pub(crate) struct AccountConnection {
    account_id: String,
    revision: u64,
    cancel: CancellationToken,
    pub(super) cleanup: pl_acp::auth::CleanupBudget,
    ready: watch::Receiver<Option<Result<PreparedConnection, AcpFailure>>>,
    protocol: Mutex<Option<pl_acp::connection::Connection>>,
    members: Mutex<Vec<Arc<AcpResources>>>,
    // Even after a member closes, the official process can retain its helper image.
    frontends: Mutex<Vec<crate::host_mcp_assets::HostMcpAsset>>,
    join: tokio::sync::Mutex<Option<JoinHandle<()>>>,
    settled: AtomicBool,
    issue: Mutex<Option<String>>,
    retry: tokio::sync::Notify,
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

    pub(crate) fn retain_frontend(&self, frontend: crate::host_mcp_assets::HostMcpAsset) {
        self.frontends
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .push(frontend);
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
    ) -> Result<PreparedConnection, pl_protocol::studio::AcpBusinessFailure> {
        self.launched().await.map_err(|failure| {
            use pl_protocol::studio::{AcpBusinessFailure, AcpBusinessFailureKind as Kind};
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
        let mut join = self.join.lock().await;
        if let Some(task) = join.as_mut() {
            if let Err(error) = task.await {
                *self.issue.lock().unwrap_or_else(PoisonError::into_inner) =
                    Some(error.to_string());
            }
            join.take();
        }
        if let Some(issue) = self
            .issue
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
        {
            anyhow::bail!(issue);
        }
        Ok(())
    }

    pub(super) async fn close(&self) -> Result<()> {
        self.signal_cancel();
        tokio::time::timeout_at(self.cleanup.deadline(), self.wait())
            .await
            .map_err(|_| anyhow::anyhow!("ACP account cleanup remains pending"))?
    }
}

fn closed_failure() -> AcpFailure {
    AcpFailure {
        code: AcpAuthFailureCode::Transport,
        stage: AcpAuthStage::Initialize,
        retryable: true,
    }
}

impl AcpAuthRuntime {
    pub(crate) fn connection(
        &self,
        definition: &AcpServiceDefinition,
    ) -> Result<Arc<AccountConnection>> {
        let inner = self.inner.clone();
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
                .get(&definition.id)
                .ok_or_else(|| anyhow::anyhow!("ACP account is unavailable"))?;
            ensure!(
                !slot.retired && slot.revision == entry.connection_revision,
                "ACP account is stale"
            );
            if let Some(connection) = slot.connection.as_ref() {
                if !connection.is_closing() && connection.revision == entry.connection_revision {
                    return Ok(connection.clone());
                }
                connection.retry.notify_one();
                if !connection.settled.load(Ordering::Acquire) {
                    // Keep the explicit retry on the original closing owner, rather than
                    // releasing its auth slot or overlapping a second process.
                    return Ok(connection.clone());
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
            let (publish, ready) = watch::channel(None);
            let connection = Arc::new(AccountConnection {
                account_id: definition.id.clone(),
                revision: entry.connection_revision,
                cancel: CancellationToken::new(),
                cleanup: pl_acp::auth::CleanupBudget::new(PROCESS_CLEANUP_LIMIT),
                ready,
                protocol: Mutex::new(None),
                members: Mutex::new(Vec::new()),
                frontends: Mutex::new(Vec::new()),
                join: tokio::sync::Mutex::new(None),
                settled: AtomicBool::new(false),
                issue: Mutex::new(None),
                retry: tokio::sync::Notify::new(),
            });
            registry
                .slots
                .get_mut(&definition.id)
                .expect("validated slot")
                .connection = Some(connection.clone());
            // Registry and join owner are installed before the supervisor can acquire launch resources.
            let task = tokio::spawn(supervise(
                inner.clone(),
                connection.clone(),
                definition.clone(),
                previous,
                publish,
            ));
            *connection.join.try_lock().expect("private join") = Some(task);
            Ok(connection)
        })?
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

    pub(super) fn background_prepare(
        &self,
        revision: u64,
        snapshot: &crate::config::AcpDefinitionsSnapshot,
    ) {
        let requests = {
            let mut registry = self.inner.lock();
            if registry.closed {
                return;
            }
            snapshot
                .definitions
                .iter()
                .filter_map(|(id, entry)| {
                    let slot = registry.slots.get_mut(id)?;
                    if !entry.definition.enabled
                        || entry.definition.template_kind().is_none()
                        || slot.background_scheduled
                        || slot.operation.is_some()
                    {
                        return None;
                    }
                    slot.background_scheduled = true;
                    Some(StartAcpAuthRequest {
                        account_id: id.clone(),
                        expected_connection_revision: entry.connection_revision,
                        operation_id: format!("background-{}", uuid::Uuid::new_v4()),
                        action: AcpAuthAction::Check,
                    })
                })
                .collect::<Vec<_>>()
        };
        // start only registers the original operation; all filesystem and process work is async.
        for request in requests {
            let _ = AcpAuthInner::admit(self.inner.clone(), revision, snapshot, request);
        }
    }
}

async fn supervise(
    inner: Arc<AcpAuthInner>,
    account: Arc<AccountConnection>,
    definition: AcpServiceDefinition,
    previous: Vec<Arc<AccountConnection>>,
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
    let launched = spawn_process(&inner, &account.account_id, &definition, &account.cancel).await;
    let (mut worker, probe_dir, expected_version) = match launched {
        Ok(value) => value,
        Err(error) => {
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
        let sdk_result = tokio::select! {
            biased;
            () = account.cancel.cancelled() => { protocol.cancel(); sdk.await }
            result = &mut sdk => result,
            exited = worker.observe_exit() => {
                if let Err(error) = exited { *account.issue.lock().unwrap_or_else(PoisonError::into_inner) = Some(error); }
                // Root exit is observable even if descendants still hold stdout/stderr open.
                account.signal_cancel();
                sdk.await
            }
        };
        match sdk_result {
            Ok(exit) => {
                if exit.cleanup_timed_out {
                    *account.issue.lock().unwrap_or_else(PoisonError::into_inner) =
                        Some("ACP SDK cleanup exceeded its original budget".into());
                } else if let Err(error) = exit.result {
                    *account.issue.lock().unwrap_or_else(PoisonError::into_inner) =
                        Some(error.to_string());
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
        for member in members {
            let result = member.close().await;
            if !result.local_complete {
                *account.issue.lock().unwrap_or_else(PoisonError::into_inner) =
                    Some("ACP session cleanup remains pending".into());
            }
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
        let mut pending = false;
        for member in members {
            if let Err(error) = member.settle_association(&inner.events).await {
                *account.issue.lock().unwrap_or_else(PoisonError::into_inner) =
                    Some(error.to_string());
                pending = true;
            }
            pending |= !member.close().await.local_complete;
        }
        if !pending {
            break;
        }
        account.retry.notified().await;
    }
    account
        .members
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clear();
    account
        .frontends
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clear();
    account.settled.store(true, Ordering::Release);
}

/// 准备探测目录并启动已验证的官方程序；失败时映射为类型化阶段错误。
pub(super) async fn spawn_process(
    inner: &Arc<AcpAuthInner>,
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
        AcpSpawnError::Startup { step, source } => {
            // 原始原因只作内部诊断：日志只记录安全步骤与有界长度，绝不记录或透出任意文本。
            tracing::warn!(
                step = step.label(),
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
mod tests {
    use super::*;
    use crate::acp_transport_fixture::AcpTransportFixture as Fixture;
    use crate::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};
    use futures::FutureExt;
    use pl_protocol::studio::*;
    use std::time::Duration;

    async fn with_cleanup(
        runtime: &StudioRuntime,
        work: impl std::future::Future<Output = Result<()>>,
    ) -> Result<()> {
        let result = std::panic::AssertUnwindSafe(work).catch_unwind().await;
        let cleanup = runtime.shutdown_runtime().await.map(|_| ());
        match result {
            Ok(Ok(())) => cleanup,
            Ok(Err(error)) => match cleanup {
                Ok(()) => Err(error),
                Err(cleanup) => {
                    Err(error.context(format!("account cleanup also failed: {cleanup:#}")))
                }
            },
            Err(panic) => {
                if let Err(error) = cleanup {
                    eprintln!("account cleanup after panic failed: {error:#}");
                }
                std::panic::resume_unwind(panic)
            }
        }
    }

    async fn auth_state(
        runtime: &StudioRuntime,
        account: &str,
        predicate: impl Fn(&AcpAuthAccount) -> bool,
    ) -> AcpAuthAccount {
        tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                if let Some(state) = runtime
                    .read_acp_auth_state()
                    .accounts
                    .into_iter()
                    .find(|state| state.account_id == account)
                    && predicate(&state)
                {
                    return state;
                }
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .expect("account reached expected state")
    }

    async fn marker(path: &std::path::Path) {
        tokio::time::timeout(Duration::from_secs(15), async {
            while !path.exists() {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .expect("synthetic peer reached marker");
    }

    #[tokio::test]
    async fn acp_account_reuses_check_and_business_sessions_and_retires_configuration() -> Result<()>
    {
        let fixture = Fixture::new("replay").await?;
        with_cleanup(&fixture.runtime, async {
            assert!(
                !fixture.home.path().join("spawns").exists(),
                "ordinary command is lazy"
            );
            fixture.runtime.start_acp_auth(StartAcpAuthRequest {
                operation_id: "first-check".into(),
                account_id: "business-peer".into(),
                expected_connection_revision: fixture.revision,
                action: AcpAuthAction::Check,
            })?;
            auth_state(&fixture.runtime, "business-peer", |account| {
                account.active_operation.is_none()
                    && matches!(account.state, AcpAuthState::Verified { .. })
            })
            .await;
            let pid = fixture.pid("pid")?;
            let mut first = fixture.open().await?;
            Fixture::ready(&mut first).await?;
            first.completion.wait().await?;
            let mut second = fixture.open().await?;
            Fixture::ready(&mut second).await?;
            second.completion.wait().await?;
            assert_ne!(
                fixture
                    .runtime
                    .acp_session_snapshot(first.target.clone())
                    .await?
                    .acp_session_id,
                fixture
                    .runtime
                    .acp_session_snapshot(second.target.clone())
                    .await?
                    .acp_session_id
            );
            assert_eq!(fixture.pid("pid")?, pid);
            let definition = fixture
                .runtime
                .config_runtime
                .read_acp_definitions()
                .definitions["business-peer"]
                .clone();
            let mut renamed = definition.definition.clone();
            renamed.display_name = "Only the name changed".into();
            fixture.runtime.config_runtime.save_acp_definition(
                fixture.runtime.config_runtime.read()?.revision,
                &renamed,
                Some(definition.document_revision),
            )?;
            assert_eq!(
                fixture
                    .runtime
                    .config_runtime
                    .read_acp_definitions()
                    .definitions["business-peer"]
                    .connection_revision,
                fixture.revision
            );
            fixture.runtime.start_acp_auth(StartAcpAuthRequest {
                operation_id: "second-check".into(),
                account_id: "business-peer".into(),
                expected_connection_revision: fixture.revision,
                action: AcpAuthAction::Check,
            })?;
            auth_state(&fixture.runtime, "business-peer", |account| {
                account.active_operation.is_none()
                    && matches!(account.state, AcpAuthState::Verified { .. })
            })
            .await;
            assert!(
                fixture
                    .runtime
                    .close_acp_session(first.target)
                    .await?
                    .local_complete
            );
            assert!(std::path::Path::new(&format!("/proc/{pid}")).exists());
            fixture
                .runtime
                .prompt_acp_session(
                    second.target.clone(),
                    vec![pl_acp::session::schema::ContentBlock::Text(
                        pl_acp::session::schema::TextContent::new("only the second member"),
                    )],
                )
                .await?;
            loop {
                if let Some(AcpSessionEvent::Completed { completed }) =
                    second.observation.as_mut().unwrap().recv().await
                {
                    assert!(completed.result.is_ok());
                    break;
                }
            }
            let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
            assert_eq!(
                calls.lines().filter(|call| *call == "initialize").count(),
                1
            );
            assert_eq!(
                std::fs::read_to_string(fixture.home.path().join("spawns"))?
                    .lines()
                    .count(),
                1
            );
            let process_cwd = std::fs::read_to_string(fixture.home.path().join("process-cwd"))?;
            assert_ne!(process_cwd, fixture.workspace.path);
            let sessions = std::fs::read_to_string(fixture.home.path().join("sessions"))?;
            let sessions: Vec<serde_json::Value> = sessions
                .lines()
                .map(|line| serde_json::from_str(line).unwrap())
                .collect();
            assert_eq!(
                sessions
                    .iter()
                    .filter(|session| session["cwd"] == process_cwd && session["mcp"] == false)
                    .count(),
                2
            );
            assert_eq!(
                sessions
                    .iter()
                    .filter(|session| session["cwd"] == fixture.workspace.path
                        && session["mcp"] == true)
                    .count(),
                2
            );
            let definition = fixture
                .runtime
                .config_runtime
                .read_acp_definitions()
                .definitions["business-peer"]
                .clone();
            let mut changed = definition.definition;
            changed
                .env
                .insert("SYNTHETIC_GENERATION".into(), "two".into());
            fixture.runtime.config_runtime.save_acp_definition(
                fixture.runtime.config_runtime.read()?.revision,
                &changed,
                Some(definition.document_revision),
            )?;
            assert!(
                fixture
                    .runtime
                    .prompt_acp_session(second.target, vec![])
                    .await
                    .is_err()
            );
            let revision = fixture
                .runtime
                .config_runtime
                .read_acp_definitions()
                .definitions["business-peer"]
                .connection_revision;
            let mut replacement = fixture
                .runtime
                .open_acp_session(OpenAcpSessionRequest {
                    account_id: "business-peer".into(),
                    expected_connection_revision: revision,
                    workspace_id: fixture.workspace.id.clone(),
                    thread_id: None,
                    intent: AcpOpenIntent::New,
                })
                .await?;
            Fixture::ready(&mut replacement).await?;
            replacement.completion.wait().await?;
            assert!(
                !std::path::Path::new(&format!("/proc/{pid}")).exists(),
                "old process was reaped before replacement became ready"
            );
            assert_ne!(fixture.pid("pid")?, pid);
            assert_eq!(
                std::fs::read_to_string(fixture.home.path().join("spawns"))?
                    .lines()
                    .count(),
                2
            );
            let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
            assert_eq!(
                calls.lines().filter(|call| *call == "initialize").count(),
                2
            );
            assert_eq!(
                calls
                    .lines()
                    .filter(|call| *call == "session/prompt")
                    .count(),
                1,
                "retirement cannot replay accepted input"
            );
            let final_pid = fixture.pid("pid")?;
            fixture.runtime.shutdown_runtime().await?;
            assert!(!std::path::Path::new(&format!("/proc/{final_pid}")).exists());
            Ok(())
        })
        .await
    }

    #[tokio::test]
    async fn acp_template_background_prepare_is_shared_nonblocking_and_never_autoauthenticates()
    -> Result<()> {
        let fixture = Fixture::new("initialize-hold").await?;
        with_cleanup(&fixture.runtime, async {
            let script = format!("#!/usr/bin/python3\n{}", crate::acp_transport_fixture::PEER);
            crate::studio::runtime::acp_install::seed_synthetic_install(
                &fixture.runtime.store,
                script.as_bytes(),
            );
            let entry = fixture
                .runtime
                .config_runtime
                .read_acp_definitions()
                .definitions["business-peer"]
                .clone();
            let mut definition = entry.definition;
            definition.launch =
                crate::config::AcpLaunch::Template(crate::config::AcpProvider::Antigravity);
            // Config returns while initialize is still deliberately held by the peer.
            fixture.runtime.config_runtime.save_acp_definition(
                fixture.runtime.config_runtime.read()?.revision,
                &definition,
                Some(entry.document_revision),
            )?;
            marker(&fixture.home.path().join("initializing")).await;
            let one = fixture.runtime.acp_auth.connection(&definition)?;
            let two = fixture.runtime.acp_auth.connection(&definition)?;
            assert!(Arc::ptr_eq(&one, &two));
            let waiter = tokio::spawn(async move { two.prepared().await });
            tokio::task::yield_now().await;
            waiter.abort();
            assert!(matches!(waiter.await, Err(error) if error.is_cancelled()));
            assert!(
                !one.cancel.is_cancelled(),
                "waiter cancellation cannot withdraw shared preparation"
            );
            std::fs::write(fixture.home.path().join("mode"), "auth")?;
            std::fs::write(fixture.home.path().join("release-init"), "continue")?;
            let required = auth_state(&fixture.runtime, "business-peer", |account| {
                matches!(account.state, AcpAuthState::Required { .. })
            })
            .await;
            let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
            assert_eq!(
                calls.lines().filter(|call| *call == "initialize").count(),
                1
            );
            assert!(!calls.contains("authenticate") && !calls.contains("session/prompt"));
            let pid = fixture.pid("pid")?;
            fixture.runtime.continue_acp_auth(ContinueAcpAuthRequest {
                operation_id: "explicit-login".into(),
                account_id: "business-peer".into(),
                expected_connection_revision: required.connection_revision,
                target_operation_id: required.active_operation.unwrap().operation_id,
                method_id: "login".into(),
            })?;
            auth_state(&fixture.runtime, "business-peer", |account| {
                account.active_operation.is_none()
                    && matches!(account.state, AcpAuthState::Verified { .. })
            })
            .await;
            let mut business = fixture
                .runtime
                .open_acp_session(OpenAcpSessionRequest {
                    account_id: "business-peer".into(),
                    expected_connection_revision: required.connection_revision,
                    workspace_id: fixture.workspace.id.clone(),
                    thread_id: None,
                    intent: AcpOpenIntent::New,
                })
                .await?;
            Fixture::ready(&mut business).await?;
            business.completion.wait().await?;
            fixture.runtime.start_acp_auth(StartAcpAuthRequest {
                operation_id: "explicit-usage".into(),
                account_id: "business-peer".into(),
                expected_connection_revision: required.connection_revision,
                action: AcpAuthAction::QueryUsage,
            })?;
            auth_state(&fixture.runtime, "business-peer", |account| {
                account.active_operation.is_none() && account.usage.is_some()
            })
            .await;
            assert!(
                fixture
                    .runtime
                    .acp_session_snapshot(business.target)
                    .await?
                    .ready
            );
            assert_eq!(fixture.pid("pid")?, pid);
            assert_eq!(
                std::fs::read_to_string(fixture.home.path().join("spawns"))?
                    .lines()
                    .count(),
                1
            );
            let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
            assert_eq!(
                calls.lines().filter(|call| *call == "authenticate").count(),
                1
            );
            assert_eq!(
                calls
                    .lines()
                    .filter(|call| *call == "session/prompt")
                    .count(),
                1
            );
            fixture.runtime.shutdown_runtime().await?;
            assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists());
            // Startup consumes the saved template definition and validated synthetic install, not a GUI read.
            let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
                studio_home: Some(fixture.home.path().join("studio")),
                host: StudioHostKind::Test,
                ..StudioRuntimeOptions::desktop()
            })
            .await?;
            with_cleanup(&runtime, async {
                auth_state(&runtime, "business-peer", |account| {
                    account.active_operation.is_none()
                        && matches!(account.state, AcpAuthState::Verified { .. })
                })
                .await;
                assert_eq!(
                    std::fs::read_to_string(fixture.home.path().join("spawns"))?
                        .lines()
                        .count(),
                    2
                );
                let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
                assert_eq!(
                    calls.lines().filter(|call| *call == "authenticate").count(),
                    1
                );
                assert_eq!(
                    calls.lines().filter(|call| *call == "session/load").count(),
                    0
                );
                let pid = fixture.pid("pid")?;
                runtime.shutdown_runtime().await?;
                assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists());
                Ok(())
            })
            .await?;
            Ok(())
        })
        .await
    }

    #[tokio::test]
    async fn acp_different_accounts_keep_remote_ids_and_retirement_isolated() -> Result<()> {
        let fixture = Fixture::new("replay").await?;
        with_cleanup(&fixture.runtime, async {
            let mut first = fixture.open().await?;
            Fixture::ready(&mut first).await?;
            first.completion.wait().await?;
            let entry = fixture
                .runtime
                .config_runtime
                .read_acp_definitions()
                .definitions["business-peer"]
                .clone();
            let first_owner = fixture.runtime.acp_auth.connection(&entry.definition)?;
            let other_root = fixture.home.path().join("other-peer");
            std::fs::create_dir(&other_root)?;
            std::fs::write(other_root.join("mode"), "replay")?;
            let mut definition = entry.definition.clone();
            definition.id = "other-peer".into();
            definition.env.insert(
                "ACP_FIXTURE_ROOT".into(),
                other_root.to_string_lossy().into_owned(),
            );
            fixture.runtime.config_runtime.save_acp_definition(
                fixture.runtime.config_runtime.read()?.revision,
                &definition,
                None,
            )?;
            let revision = fixture
                .runtime
                .config_runtime
                .read_acp_definitions()
                .definitions["other-peer"]
                .connection_revision;
            let mut second = fixture
                .runtime
                .open_acp_session(OpenAcpSessionRequest {
                    account_id: "other-peer".into(),
                    expected_connection_revision: revision,
                    workspace_id: fixture.workspace.id.clone(),
                    thread_id: None,
                    intent: AcpOpenIntent::New,
                })
                .await?;
            Fixture::ready(&mut second).await?;
            second.completion.wait().await?;
            assert_eq!(
                fixture
                    .runtime
                    .acp_session_snapshot(first.target.clone())
                    .await?
                    .acp_session_id,
                fixture
                    .runtime
                    .acp_session_snapshot(second.target.clone())
                    .await?
                    .acp_session_id,
                "identical remote IDs belong to different connection scopes"
            );
            let first_pid = fixture.pid("pid")?;
            let second_pid: u32 = std::fs::read_to_string(other_root.join("pid"))?.parse()?;
            assert_ne!(first_pid, second_pid);
            let mut disabled = entry.definition;
            disabled.enabled = false;
            fixture.runtime.config_runtime.save_acp_definition(
                fixture.runtime.config_runtime.read()?.revision,
                &disabled,
                Some(entry.document_revision),
            )?;
            first_owner.close().await?;
            assert!(!std::path::Path::new(&format!("/proc/{first_pid}")).exists());
            assert!(std::path::Path::new(&format!("/proc/{second_pid}")).exists());
            fixture
                .runtime
                .prompt_acp_session(
                    second.target.clone(),
                    vec![pl_acp::session::schema::ContentBlock::Text(
                        pl_acp::session::schema::TextContent::new("other account still works"),
                    )],
                )
                .await?;
            loop {
                if let Some(AcpSessionEvent::Completed { completed }) =
                    second.observation.as_mut().unwrap().recv().await
                {
                    assert!(completed.result.is_ok());
                    break;
                }
            }
            assert_eq!(
                std::fs::read_to_string(other_root.join("calls"))?
                    .lines()
                    .filter(|call| *call == "initialize")
                    .count(),
                1
            );
            fixture.runtime.shutdown_runtime().await?;
            assert!(!std::path::Path::new(&format!("/proc/{second_pid}")).exists());
            Ok(())
        })
        .await
    }
    #[tokio::test]
    async fn acp_business_observer_is_delivered_before_slow_shared_initialize() -> Result<()> {
        let fixture = Fixture::new("initialize-hold").await?;
        with_cleanup(&fixture.runtime, async {
            let opening = tokio::time::timeout(Duration::from_secs(5), fixture.open()).await;
            // Release even on a failed assertion so failure cleanup does not depend on killing
            // a blocked protocol fixture to establish the behavior under test.
            std::fs::write(fixture.home.path().join("mode"), "replay")?;
            std::fs::write(fixture.home.path().join("release-init"), "continue")?;
            let mut open = opening??;
            assert!(open.observation.is_some());
            Fixture::ready(&mut open).await?;
            open.completion.wait().await?;
            assert_eq!(
                std::fs::read_to_string(fixture.home.path().join("spawns"))?
                    .lines()
                    .count(),
                1
            );
            Ok(())
        })
        .await
    }
}
