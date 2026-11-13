use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use lsp_types::InitializedParams;
use serde_json::Value;
use tokio::io::BufReader;

use super::configuration::initialize_params;
use super::connection::LspClient;
use super::message::{clear_progress_status, record_last_error_status};
use super::rpc::RpcClient;
use super::status::LspClientRuntimeStatus;
use super::transport::LspTransport;
use crate::host::{LspHostProcess, LspHostSpawnRequest};
use crate::runtime::{LspResult, LspRuntimeError};

const STARTUP_TIMEOUT: Duration = Duration::from_secs(30);
const SHUTDOWN_WAIT_TIMEOUT: Duration = Duration::from_secs(2);
static NEXT_LSP_PROCESS_ID: AtomicU64 = AtomicU64::new(1);

impl LspClient {
    pub(crate) async fn start(&self) -> LspResult<()> {
        let result = self.ensure_started().await;
        if let Err(error) = result {
            if let Err(cleanup) = self.shutdown().await {
                return Err(LspRuntimeError::Unavailable(format!("{error}; {cleanup}")));
            }
            return Err(error);
        }
        Ok(())
    }

    /// 请求关闭并确认整棵 language-server 进程树已回收。
    ///
    /// 只有在 wait/kill 真实成功后才删除 child owner；未确认回收时保留 owner 并返回
    /// typed error，供 runtime 报告而不是当作 clean。
    pub(crate) async fn shutdown(&self) -> LspResult<()> {
        self.closed.store(true, Ordering::Release);
        self.shutdown_requested.cancel();
        let _lifecycle_guard = self.lifecycle_lock.lock().await;
        self.shutdown_connection_locked().await
    }

    pub(crate) async fn runtime_status(&self) -> LspClientRuntimeStatus {
        self.status.lock().await.runtime_status()
    }

    pub(crate) async fn wait_until_idle(&self, timeout: Duration) {
        let mut updates = self.diagnostics.updates.subscribe();
        let wait = async {
            loop {
                if self.status.lock().await.is_idle_after_observed_activity() {
                    return;
                }
                match updates.recv().await {
                    Ok(()) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => return,
                }
            }
        };
        let _ = tokio::time::timeout(timeout, wait).await;
    }

    pub(super) async fn ensure_started(&self) -> LspResult<()> {
        if self.closed.load(Ordering::Acquire) {
            return Err(shutting_down_error());
        }
        if self.initialized.load(Ordering::Relaxed) {
            return Ok(());
        }
        let _guard = self.lifecycle_lock.lock().await;
        if self.closed.load(Ordering::Acquire) {
            return Err(shutting_down_error());
        }
        if self.initialized.load(Ordering::Relaxed) {
            return Ok(());
        }
        self.stop_stale_connection_locked().await?;

        let child = self.spawn_server().await?;
        self.child.lock().await.replace(child);
        let mut child_guard = self.child.lock().await;
        let child = child_guard.as_mut().expect("owned child");
        let stdin = child.take_stdin().ok_or_else(|| {
            LspRuntimeError::Unavailable("LSP child stdin pipe is unavailable".to_string())
        })?;
        let stdout = child.take_stdout().ok_or_else(|| {
            LspRuntimeError::Unavailable("LSP child stdout pipe is unavailable".to_string())
        })?;
        let stderr = child.take_stderr();
        drop(child_guard);
        let (transport, inbound) = LspTransport::spawn(stdin, stdout)?;
        let rpc = RpcClient::new(transport.sender()?);
        let generation = self.connection_generation.fetch_add(1, Ordering::Relaxed) + 1;
        self.connection_alive.store(true, Ordering::Release);
        self.spawn_dispatcher(inbound, rpc.clone(), generation);
        self.transport.lock().await.replace(transport);
        self.rpc
            .write()
            .map_err(|_| {
                LspRuntimeError::Unavailable("LSP connection state is poisoned".to_string())
            })?
            .replace(rpc.clone());
        self.observe_stderr(stderr);
        self.observe_process();
        self.startup_phase
            .send_replace(crate::runtime::LspLifecyclePhase::Initializing);

        let initialize = tokio::select! {
            biased;
            _ = self.shutdown_requested.cancelled() => {
                let _ = self.shutdown_connection_locked().await;
                return Err(shutting_down_error());
            }
            initialize = rpc.request(
                "initialize",
                initialize_params(&self.server, self.driver.initialization_options(), self.path_style())?,
                STARTUP_TIMEOUT,
            ) => initialize,
        };
        let initialize = match initialize {
            Ok(value) => value,
            Err(error) => {
                self.record_last_error(error.to_string()).await;
                let _ = self.shutdown_connection_locked().await;
                return Err(error);
            }
        };
        let result: lsp_types::InitializeResult = match serde_json::from_value(initialize) {
            Ok(result) => result,
            Err(error) => {
                let _ = self.shutdown_connection_locked().await;
                return Err(error.into());
            }
        };
        let operations = negotiated_operations(&result.capabilities);
        *self.negotiated_document_sync.write().map_err(|_| {
            LspRuntimeError::Unavailable("LSP document sync state is poisoned".into())
        })? = super::documents::DocumentSync::from_capability(
            result.capabilities.text_document_sync.as_ref(),
        );
        *self.negotiated_operations.write().map_err(|_| {
            LspRuntimeError::Unavailable("LSP capability state is poisoned".into())
        })? = operations;
        if self.closed.load(Ordering::Acquire) {
            let _ = self.shutdown_connection_locked().await;
            return Err(shutting_down_error());
        }
        let initialized_params = serde_json::to_value(InitializedParams {})?;
        if let Err(error) = rpc.notify("initialized", initialized_params).await {
            self.record_last_error(error.to_string()).await;
            let _ = self.shutdown_connection_locked().await;
            return Err(error);
        }
        if !self.server.settings.is_null()
            && let Err(error) = rpc
                .notify(
                    "workspace/didChangeConfiguration",
                    serde_json::json!({ "settings": self.server.settings }),
                )
                .await
        {
            self.record_last_error(error.to_string()).await;
            let _ = self.shutdown_connection_locked().await;
            return Err(error);
        }
        self.initialized.store(true, Ordering::Relaxed);
        Ok(())
    }

    async fn spawn_server(&self) -> LspResult<LspHostProcess> {
        if let Some(host) = &self.host {
            let sequence = NEXT_LSP_PROCESS_ID.fetch_add(1, Ordering::Relaxed);
            return host
                .spawn(LspHostSpawnRequest {
                    process_id: format!("lsp-{}-{}-{sequence}", self.server.id, std::process::id()),
                    program: self.server.program.clone(),
                    args: self.server.args.clone(),
                    env: self.server.env.clone(),
                    cwd: self.server.workspace_root.clone(),
                    cancellation: self.shutdown_requested.clone(),
                    deadline: tokio::time::Instant::now() + STARTUP_TIMEOUT,
                })
                .await
                .map_err(|error| {
                    LspRuntimeError::Unavailable(format!(
                        "Failed to start LSP server '{}': {error}",
                        self.server.id
                    ))
                });
        }
        Err(LspRuntimeError::Unavailable(
            "LSP requires an explicit execution host".into(),
        ))
    }

    fn observe_stderr(&self, stderr: Option<crate::host::LspHostReader>) {
        let Some(stderr) = stderr else {
            return;
        };
        let status = self.status.clone();
        let updates = self.diagnostics.updates.clone();
        self.retain_task(tokio::spawn(async move {
            let mut reader = BufReader::new(stderr);
            loop {
                let mut line = String::new();
                match tokio::io::AsyncBufReadExt::read_line(&mut reader, &mut line).await {
                    Ok(0) | Err(_) => break,
                    Ok(_) => {
                        let line = line.trim();
                        if !line.is_empty()
                            && is_error_stderr_line(line)
                            && record_last_error_status(&status, line.to_string()).await
                        {
                            let _ = updates.send(());
                        }
                    }
                }
            }
        }));
    }

    async fn shutdown_connection_locked(&self) -> LspResult<()> {
        self.process_monitor_stop.cancel();
        let was_initialized = self.initialized.swap(false, Ordering::Relaxed);
        let mut degraded: Vec<String> = Vec::new();
        if was_initialized && let Ok(rpc) = self.rpc() {
            if let Err(error) = rpc
                .request("shutdown", Value::Null, Duration::from_secs(3))
                .await
            {
                degraded.push(format!("LSP 'shutdown' request failed: {error}"));
            }
            // The outbound channel is capacity-bounded: a stalled writer can in principle
            // block a `notify` forever, which would stop this reclaim path from ever
            // reaching the process-tree owner. Bound it so a cancel is never blocked by an
            // unbounded protocol write.
            match tokio::time::timeout(SHUTDOWN_WAIT_TIMEOUT, rpc.notify("exit", Value::Null)).await
            {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    degraded.push(format!("LSP 'exit' notification failed: {error}"));
                }
                Err(_elapsed) => degraded.push(
                    "LSP 'exit' notification did not complete within the timeout".to_string(),
                ),
            }
        }

        // Reclaim through the existing owned-process mechanism. Only a confirmed wait may
        // remove the child owner; otherwise it is retained for retry/reporting.
        let mut startup_failure = None;
        let reclaim = {
            let mut child_guard = self.child.lock().await;
            let confirmed: std::result::Result<Vec<String>, String> = match child_guard.as_mut() {
                None => Ok(Vec::new()),
                Some(child) => {
                    if was_initialized {
                        match tokio::time::timeout(SHUTDOWN_WAIT_TIMEOUT, child.wait()).await {
                            Ok(Ok(_)) => Ok(Vec::new()),
                            Ok(Err(error)) => match child.terminate().await {
                                Ok(()) => Ok(vec![format!("LSP process wait failed: {error}")]),
                                Err(terminate) => {
                                    Err(format!("LSP process wait failed: {error}; {terminate}"))
                                }
                            },
                            Err(_elapsed) => match child.terminate().await {
                                Ok(()) => {
                                    Ok(vec!["LSP process did not exit after shutdown".to_string()])
                                }
                                Err(terminate) => Err(format!(
                                    "LSP process did not exit after shutdown; {terminate}"
                                )),
                            },
                        }
                    } else {
                        match child.terminate().await {
                            Ok(()) => Ok(Vec::new()),
                            Err(error) => Err(error.to_string()),
                        }
                    }
                }
            };
            match confirmed {
                Ok(issues) => {
                    degraded.extend(issues);
                    startup_failure = child_guard
                        .as_ref()
                        .and_then(LspHostProcess::startup_failure)
                        .map(str::to_owned);
                    child_guard.take();
                    Ok(())
                }
                Err(error) => Err(error),
            }
        };
        if let Some(message) = startup_failure {
            self.record_last_error(message).await;
        }

        self.connection_generation.fetch_add(1, Ordering::Relaxed);
        if let Ok(mut rpc) = self.rpc.write() {
            rpc.take();
        }
        if let Some(mut transport) = self.transport.lock().await.take() {
            match tokio::task::spawn_blocking(move || transport.close()).await {
                Ok(()) => {}
                Err(join_error) => {
                    degraded.push(format!("LSP transport close task failed: {join_error}"));
                }
            }
        }
        let tasks = self
            .background
            .lock()
            .expect("LSP background task list is not poisoned")
            .clone();
        for task in tasks {
            let mut task = task.lock().await;
            if let Some(handle) = task.as_mut() {
                if let Err(error) = handle.await {
                    degraded.push(format!("LSP background task failed: {error}"));
                }
                task.take();
            }
        }
        self.background
            .lock()
            .expect("LSP background task list is not poisoned")
            .clear();
        self.opened_files.lock().await.clear();
        self.clear_progress().await;

        // Every recoverable issue must reach the caller instead of being downgraded to a
        // status-only note the runtime can never see.
        for issue in &degraded {
            self.record_last_error(issue.clone()).await;
        }
        match reclaim {
            Err(error) => {
                let mut message =
                    format!("LSP client did not confirm process-tree reclamation: {error}");
                if !degraded.is_empty() {
                    message.push_str("; degraded shutdown: ");
                    message.push_str(&degraded.join("; "));
                }
                Err(LspRuntimeError::Unavailable(message))
            }
            Ok(()) => {
                // Degraded but reclaimed is still not clean: the process tree is gone, so no
                // owner is retained, but the issues above already recorded on the client
                // status are also returned as an error.
                if degraded.is_empty() {
                    Ok(())
                } else {
                    Err(LspRuntimeError::Unavailable(format!(
                        "LSP process tree reclaimed with degraded shutdown: {}",
                        degraded.join("; ")
                    )))
                }
            }
        }
    }

    fn observe_process(&self) {
        let child = self.child.clone();
        let stop = self.process_monitor_stop.clone();
        let alive = self.connection_alive.clone();
        let updates = self.diagnostics.updates.clone();
        let status = self.status.clone();
        self.retain_task(tokio::spawn(async move {
            let outcome = {
                let mut child = child.lock().await;
                let Some(child) = child.as_mut() else {
                    return;
                };
                tokio::select! {
                    biased;
                    _ = stop.cancelled() => return,
                    result = child.wait() => result,
                }
            };
            alive.store(false, Ordering::Release);
            let message = match outcome {
                Ok(_) => "LSP process exited".to_string(),
                Err(error) => format!("LSP process exit observation failed: {error}"),
            };
            record_last_error_status(&status, message).await;
            let _ = updates.send(());
        }));
    }

    async fn stop_stale_connection_locked(&self) -> LspResult<()> {
        if self.child.lock().await.is_none()
            && self.transport.lock().await.is_none()
            && self.rpc.read().is_ok_and(|rpc| rpc.is_none())
        {
            return Ok(());
        }
        match self.shutdown_connection_locked().await {
            Ok(()) => Ok(()),
            // A reclaimed-but-degraded connection is safe to replace: the previous process
            // tree is gone, so a fresh server may start. The degraded issues stay on the
            // client status for this internal restart path.
            Err(_) if self.child.lock().await.is_none() => Ok(()),
            Err(error) => Err(error),
        }
    }

    pub(super) async fn record_last_error(&self, message: String) {
        if record_last_error_status(&self.status, message).await {
            let _ = self.diagnostics.updates.send(());
        }
    }

    async fn clear_progress(&self) {
        if clear_progress_status(&self.status).await {
            let _ = self.diagnostics.updates.send(());
        }
    }
}

fn shutting_down_error() -> LspRuntimeError {
    LspRuntimeError::Unavailable("LSP client is shutting down".to_string())
}

fn is_error_stderr_line(line: &str) -> bool {
    let line = line.to_ascii_lowercase();
    line.contains("warn") || line.contains("error")
}

fn negotiated_operations(
    capabilities: &lsp_types::ServerCapabilities,
) -> Vec<crate::query::LspQueryOperation> {
    use crate::query::LspQueryOperation as Operation;
    let capabilities = serde_json::to_value(capabilities).expect("serializable LSP capabilities");
    Operation::all()
        .iter()
        .copied()
        .filter(|operation| {
            let key = match operation {
                Operation::GoToDefinition => "definitionProvider",
                Operation::FindReferences => "referencesProvider",
                Operation::Hover => "hoverProvider",
                Operation::DocumentSymbol => "documentSymbolProvider",
                Operation::WorkspaceSymbol => "workspaceSymbolProvider",
                Operation::GoToImplementation => "implementationProvider",
                Operation::PrepareCallHierarchy
                | Operation::IncomingCalls
                | Operation::OutgoingCalls => "callHierarchyProvider",
                Operation::Diagnostics => return true,
            };
            capabilities
                .get(key)
                .is_some_and(|value| !value.is_null() && value != &Value::Bool(false))
        })
        .collect()
}
