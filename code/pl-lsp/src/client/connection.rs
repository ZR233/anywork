use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, RwLock};
use std::time::Duration;

use serde::Serialize;
use serde_json::Value;
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use super::diagnostics::DiagnosticSink;
use super::documents::OpenDocument;
use super::retry::is_content_modified_error;
use super::rpc::RpcClient;
use super::status::LspClientStatus;
use super::transport::LspTransport;
type ClientTask = Arc<Mutex<Option<tokio::task::JoinHandle<()>>>>;
use crate::driver::LspServerDriver;
use crate::host::{LspChild, LspHostBackend};
use crate::runtime::{LspResult, LspRuntimeError, ResolvedLspServer};

const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

pub(crate) struct LspClient {
    pub(super) server: ResolvedLspServer,
    pub(super) driver: Arc<dyn LspServerDriver>,
    pub(super) host: Option<Arc<dyn LspHostBackend>>,
    pub(super) child: Arc<Mutex<Option<LspChild>>>,
    pub(super) transport: Mutex<Option<LspTransport>>,
    pub(super) rpc: RwLock<Option<RpcClient>>,
    pub(super) opened_files: Mutex<HashMap<PathBuf, OpenDocument>>,
    pub(super) document_sync: Mutex<()>,
    pub(super) initialized: Arc<AtomicBool>,
    pub(super) connection_alive: Arc<AtomicBool>,
    pub(super) negotiated_operations: RwLock<Vec<crate::query::LspQueryOperation>>,
    pub(super) connection_generation: Arc<AtomicU64>,
    pub(super) lifecycle_lock: Mutex<()>,
    pub(super) shutdown_requested: CancellationToken,
    pub(super) process_monitor_stop: CancellationToken,
    pub(super) closed: AtomicBool,
    pub(super) diagnostics: DiagnosticSink,
    pub(super) status: Arc<Mutex<LspClientStatus>>,
    pub(super) background: std::sync::Mutex<Vec<ClientTask>>,
    pub(super) startup_phase: tokio::sync::watch::Sender<crate::runtime::LspLifecyclePhase>,
}

impl std::fmt::Debug for LspClient {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("LspClient")
            .field("server_id", &self.server.id)
            .field("workspace_root", &self.server.workspace_root)
            .field("initialized", &self.initialized.load(Ordering::Relaxed))
            .finish_non_exhaustive()
    }
}

impl LspClient {
    pub(crate) fn is_ready(&self) -> bool {
        self.initialized.load(Ordering::Acquire)
            && self.connection_alive.load(Ordering::Acquire)
            && !self.closed.load(Ordering::Acquire)
    }

    pub(crate) fn reclaimed(&self) -> bool {
        self.closed.load(Ordering::Acquire)
            && self.child.try_lock().is_ok_and(|child| child.is_none())
    }

    pub(crate) fn supports(&self, operation: crate::query::LspQueryOperation) -> bool {
        self.negotiated_operations
            .read()
            .is_ok_and(|operations| operations.contains(&operation))
    }

    pub(crate) fn cancel(&self) {
        self.closed.store(true, Ordering::Release);
        self.shutdown_requested.cancel();
    }

    pub(crate) fn startup_updates(
        &self,
    ) -> tokio::sync::watch::Receiver<crate::runtime::LspLifecyclePhase> {
        self.startup_phase.subscribe()
    }

    pub(crate) fn path_style(&self) -> crate::host::LspPathStyle {
        self.host
            .as_ref()
            .map_or(crate::host::LspPathStyle::Native, |host| host.path_style())
    }
    pub(crate) fn new(
        server: ResolvedLspServer,
        driver: Arc<dyn LspServerDriver>,
        diagnostics: DiagnosticSink,
        host: Option<Arc<dyn LspHostBackend>>,
    ) -> Self {
        Self {
            server,
            driver,
            host,
            child: Arc::new(Mutex::new(None)),
            transport: Mutex::new(None),
            rpc: RwLock::new(None),
            opened_files: Mutex::new(HashMap::new()),
            document_sync: Mutex::new(()),
            initialized: Arc::new(AtomicBool::new(false)),
            connection_alive: Arc::new(AtomicBool::new(false)),
            negotiated_operations: RwLock::new(Vec::new()),
            connection_generation: Arc::new(AtomicU64::new(0)),
            lifecycle_lock: Mutex::new(()),
            shutdown_requested: CancellationToken::new(),
            process_monitor_stop: CancellationToken::new(),
            closed: AtomicBool::new(false),
            diagnostics,
            status: Arc::new(Mutex::new(LspClientStatus::default())),
            background: std::sync::Mutex::new(Vec::new()),
            startup_phase: tokio::sync::watch::channel(crate::runtime::LspLifecyclePhase::Starting)
                .0,
        }
    }

    pub(super) fn retain_task(&self, task: tokio::task::JoinHandle<()>) {
        self.background
            .lock()
            .expect("LSP background task list is not poisoned")
            .push(Arc::new(Mutex::new(Some(task))));
    }

    pub(crate) async fn request(&self, method: &str, params: Value) -> LspResult<Value> {
        if !self.is_ready() {
            return Err(LspRuntimeError::Unavailable(
                "LSP server is not ready".into(),
            ));
        }
        let result = self.rpc()?.request(method, params, REQUEST_TIMEOUT).await;
        if let Err(error) = &result
            && !is_content_modified_error(error)
        {
            self.record_last_error(error.to_string()).await;
        }
        result
    }

    pub(crate) async fn notify(&self, method: &str, params: impl Serialize) -> LspResult<()> {
        if !self.is_ready() {
            return Err(LspRuntimeError::Unavailable(
                "LSP server is not ready".into(),
            ));
        }
        self.rpc()?
            .notify(method, serde_json::to_value(params)?)
            .await
    }

    pub(super) fn rpc(&self) -> LspResult<RpcClient> {
        self.rpc
            .read()
            .map_err(|_| {
                LspRuntimeError::Unavailable("LSP connection state is poisoned".to_string())
            })?
            .clone()
            .ok_or_else(|| LspRuntimeError::Unavailable("LSP transport unavailable".to_string()))
    }
}
