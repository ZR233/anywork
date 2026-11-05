use std::collections::HashMap;
use std::fmt;
use std::future::Future;
#[cfg(not(target_os = "linux"))]
use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;

use pl_protocol::{PureError, Result};
use reqwest::header::{HeaderName, HeaderValue};
use rmcp::handler::client::ClientHandler;
use rmcp::model::*;
use rmcp::service::{ClientInitializeError, NotificationContext, Peer, RunningService};
use rmcp::transport::StreamableHttpClientTransport;
use rmcp::transport::async_rw::AsyncRwTransport;
use rmcp::transport::streamable_http_client::StreamableHttpClientTransportConfig;
use rmcp::{ClientCacheConfig, ClientLifecycleMode, ClientServiceExt, RoleClient};
#[cfg(not(target_os = "linux"))]
use tokio::process::Command;
use tokio::sync::RwLock;
use tokio_util::sync::CancellationToken;

#[cfg(target_os = "linux")]
use crate::command::LocalWorkerExecutable;
use crate::command::ManagedCommand;
use crate::mcp::config::{EffectiveMcpServerConfig, McpExecutionContext, McpServerTransport};
#[cfg(target_os = "linux")]
use pl_remote_helper::client::ManagedWorker;
#[cfg(target_os = "linux")]
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

pub(crate) mod remote_http;
mod remote_stdio;
mod stderr_capture;
mod stdio_program;

pub use remote_http::RemoteStreamableHttpClient;

use stderr_capture::StderrCapture;

const CLOSE_TIMEOUT: Duration = Duration::from_secs(5);

/// 建立 MCP transport 所需的完整、仅进程内可见配置。
///
/// 该值可能包含已解析凭证，禁止序列化、trace 或日志输出。
#[derive(Clone)]
pub struct McpConnectRequest {
    pub server_id: String,
    pub server: EffectiveMcpServerConfig,
}

/// 唯一的 MCP 连接入口。
///
/// Connector 只把 PL 的有效配置投影为 rmcp transport 并启动 client service；
/// reconcile、generation、健康和权限不属于该边界。
type ToolListChangedSink = Arc<dyn Fn(String) + Send + Sync>;

#[derive(Clone, Default)]
pub struct McpConnector {
    tool_list_changed: Option<ToolListChangedSink>,
    close_timeout: Option<Duration>,
    /// Bundled supervisor for local stdio servers. On Linux every stdio server is
    /// started through the same per-child supervisor as the local command tool so a
    /// GUI that is force-killed still reclaims the whole language/tool process tree.
    #[cfg(target_os = "linux")]
    stdio_worker: Option<Arc<dyn LocalWorkerExecutable>>,
}

impl fmt::Debug for McpConnector {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("McpConnector")
            .field("tool_list_changed", &self.tool_list_changed.is_some())
            .finish_non_exhaustive()
    }
}

impl McpConnector {
    /// 按执行环境与 transport 选择兼容的 MCP 启动协商并建立连接。
    pub async fn connect(&self, request: McpConnectRequest) -> Result<ConnectedMcp> {
        self.connect_cancellable(request, CancellationToken::new())
            .await
    }

    pub(crate) async fn connect_cancellable(
        &self,
        request: McpConnectRequest,
        cancel: CancellationToken,
    ) -> Result<ConnectedMcp> {
        let close_timeout = self.close_timeout.unwrap_or(CLOSE_TIMEOUT);
        match (
            &request.server.execution_context,
            request.server.config.transport,
        ) {
            (McpExecutionContext::Host, McpServerTransport::Stdio) => {
                self.connect_stdio(request, cancel).await
            }
            (McpExecutionContext::Host, McpServerTransport::StreamableHttp) => {
                tokio::select! {
                    biased;
                    () = cancel.cancelled() => Err(connection_error(
                        &request.server_id,
                        "MCP HTTP connection cancelled",
                    )),
                    res = connect_http(request.clone(), self.tool_list_changed.clone(), close_timeout) => res,
                }
            }
            (McpExecutionContext::Remote { commands }, McpServerTransport::Stdio) => {
                let commands = commands.clone();
                remote_stdio::connect_remote_stdio(
                    request,
                    commands,
                    self.tool_list_changed.clone(),
                    close_timeout,
                    cancel,
                )
                .await
            }
            (McpExecutionContext::Remote { commands }, McpServerTransport::StreamableHttp) => {
                let client = commands.client().clone();
                tokio::select! {
                    biased;
                    () = cancel.cancelled() => Err(connection_error(
                        &request.server_id,
                        "MCP remote HTTP connection cancelled",
                    )),
                    res = remote_http::connect_remote_http(
                        request.clone(),
                        client,
                        self.tool_list_changed.clone(),
                        close_timeout,
                    ) => res,
                }
            }
        }
    }

    /// Overrides the per-session close timeout (defaults to 5 seconds).
    pub fn with_close_timeout(mut self, timeout: Duration) -> Self {
        self.close_timeout = Some(timeout);
        self
    }

    /// Retains the bundled per-child supervisor used to start local stdio servers.
    ///
    /// The value owns the executable resource; the connector keeps it alive for every
    /// server it starts. Without it Linux stdio servers fail loudly instead of falling
    /// back to an unsupervised spawn.
    #[cfg(target_os = "linux")]
    pub fn with_stdio_worker<P>(mut self, executable: P) -> Self
    where
        P: AsRef<Path> + std::fmt::Debug + Send + Sync + 'static,
    {
        self.stdio_worker = Some(Arc::new(executable));
        self
    }

    pub(crate) fn with_tool_list_changed(
        mut self,
        handler: impl Fn(String) + Send + Sync + 'static,
    ) -> Self {
        self.tool_list_changed = Some(Arc::new(handler));
        self
    }

    /// Linux routes local stdio servers through the bundled per-child supervisor so a
    /// force-killed GUI still reclaims the whole process tree. Without a supervisor the
    /// connector fails loudly instead of falling back to an unsupervised spawn.
    #[cfg(target_os = "linux")]
    async fn connect_stdio(
        &self,
        request: McpConnectRequest,
        cancel: CancellationToken,
    ) -> Result<ConnectedMcp> {
        let (command_name, program) = resolve_stdio_program(&request)?;
        let worker = self.stdio_worker.clone().ok_or_else(|| {
            connection_error(
                &request.server_id,
                format!(
                    "local stdio command {command_name} requires the bundled \
                     pl-remote-helper supervisor"
                ),
            )
        })?;
        connect_stdio_supervised(
            request,
            self.tool_list_changed.clone(),
            command_name,
            program,
            worker,
            self.close_timeout.unwrap_or(CLOSE_TIMEOUT),
            cancel,
        )
        .await
    }

    /// Other platforms keep the native child-process transport, which the background
    /// factory already wraps in a Windows Job Object / Unix process group.
    #[cfg(not(target_os = "linux"))]
    async fn connect_stdio(
        &self,
        request: McpConnectRequest,
        cancel: CancellationToken,
    ) -> Result<ConnectedMcp> {
        let (command_name, program) = resolve_stdio_program(&request)?;
        connect_stdio_child_process(
            request,
            self.tool_list_changed.clone(),
            command_name,
            program,
            self.close_timeout.unwrap_or(CLOSE_TIMEOUT),
            cancel,
        )
        .await
    }
}

#[derive(Clone)]
pub(super) struct McpClientHandler {
    info: ClientConfig,
    server_id: Arc<std::sync::RwLock<String>>,
    tool_list_changed: Arc<std::sync::RwLock<Option<ToolListChangedSink>>>,
}

impl McpClientHandler {
    fn new(
        info: ClientConfig,
        server_id: String,
        tool_list_changed: Option<ToolListChangedSink>,
    ) -> Self {
        Self {
            info,
            server_id: Arc::new(std::sync::RwLock::new(server_id)),
            tool_list_changed: Arc::new(std::sync::RwLock::new(tool_list_changed)),
        }
    }
}

impl ClientHandler for McpClientHandler {
    fn get_info(&self) -> ClientConfig {
        self.info.clone()
    }

    fn on_tool_list_changed(
        &self,
        _context: NotificationContext<RoleClient>,
    ) -> impl Future<Output = ()> + Send + '_ {
        let server_id = self
            .server_id
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let handler = self
            .tool_list_changed
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        async move {
            if let Some(handler) = handler {
                handler(server_id);
            }
        }
    }
}

/// 一个已启动的 rmcp client service。
///
/// `Peer` 可并发克隆；`RunningService` 只由本对象持有，并在最后一个 generation
/// lease 释放后通过 [`Self::close`] 显式关闭。
pub struct ConnectedMcp {
    peer: Peer<RoleClient>,
    closing: AtomicBool,
    close_timeout: Duration,
    owner: RwLock<Option<RunningService<RoleClient, McpClientHandler>>>,
    /// Tool-subscription owner shared with the close task so a subscription that cannot be
    /// confirmed stopped is re-inserted here instead of being dropped while still running.
    tool_subscription: Arc<tokio::sync::Mutex<Option<ToolListSubscription>>>,
    /// Serialized, reusable close progress. The spawned close task owns the subscription,
    /// the service, the Linux supervisor and the worker image lease until the whole tree is
    /// confirmed reclaimed, so a timeout retains — never silently drops — those owners.
    close: tokio::sync::Mutex<CloseProgress>,
    /// Per-child supervisor for a Linux local stdio server. Moved into the close task so
    /// cancellation and full tree reclamation never depend on dropping a pipe.
    #[cfg(target_os = "linux")]
    stdio_worker: tokio::sync::Mutex<Option<ManagedWorker>>,
    /// Linux worker image lease for the local stdio supervisor; keeps the anonymous
    /// executable alive and is moved into the close task with the supervisor.
    #[cfg(target_os = "linux")]
    worker_owner: Option<Arc<dyn LocalWorkerExecutable>>,
    /// Supervised local or remote stdio command owned through `pl-remote-helper`.
    stdio_command: tokio::sync::Mutex<Option<ManagedCommand>>,
    /// Cancellation token for remote HTTP exchange / SSE streams.
    transport_cancel: Option<CancellationToken>,
}

/// Close bookkeeping shared by every `close()` caller on one [`ConnectedMcp`].
struct CloseProgress {
    /// In-flight close task; owns the service, supervisor and executable lease.
    task: Option<tokio::task::JoinHandle<std::result::Result<(), String>>>,
    /// Terminal result, cached only once every owned resource is confirmed released so a
    /// retry can never replay a merely-suspected outcome as if it were reliable.
    completed: Option<std::result::Result<(), String>>,
}

impl fmt::Debug for ConnectedMcp {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ConnectedMcp")
            .field("peer", &self.peer)
            .finish_non_exhaustive()
    }
}

impl ConnectedMcp {
    pub(super) async fn from_running(
        service: RunningService<RoleClient, McpClientHandler>,
        close_timeout: Duration,
    ) -> Self {
        let peer = service.peer().clone();
        peer.set_response_cache_config(
            ClientCacheConfig::default().with_serve_stale_on_error(false),
        )
        .await;
        let tool_subscription = start_tool_list_subscription(&service).await;
        Self {
            peer,
            closing: AtomicBool::new(false),
            close_timeout,
            owner: RwLock::new(Some(service)),
            tool_subscription: Arc::new(tokio::sync::Mutex::new(tool_subscription)),
            close: tokio::sync::Mutex::new(CloseProgress {
                task: None,
                completed: None,
            }),
            #[cfg(target_os = "linux")]
            stdio_worker: tokio::sync::Mutex::new(None),
            #[cfg(target_os = "linux")]
            worker_owner: None,
            stdio_command: tokio::sync::Mutex::new(None),
            transport_cancel: None,
        }
    }

    /// Attaches the per-child supervisor that owns the stdio server's process tree, plus
    /// the executable image lease the supervisor was started from.
    #[cfg(target_os = "linux")]
    pub(super) async fn from_running_with_stdio_worker(
        service: RunningService<RoleClient, McpClientHandler>,
        worker: ManagedWorker,
        worker_owner: Arc<dyn LocalWorkerExecutable>,
        close_timeout: Duration,
    ) -> Self {
        let mut connected = Self::from_running(service, close_timeout).await;
        *connected.stdio_worker.lock().await = Some(worker);
        connected.worker_owner = Some(worker_owner);
        connected
    }

    pub(super) async fn from_running_with_stdio_command(
        service: RunningService<RoleClient, McpClientHandler>,
        command: ManagedCommand,
        close_timeout: Duration,
    ) -> Self {
        let connected = Self::from_running(service, close_timeout).await;
        *connected.stdio_command.lock().await = Some(command);
        connected
    }

    pub(super) async fn from_running_with_transport_cancel(
        service: RunningService<RoleClient, McpClientHandler>,
        transport_cancel: CancellationToken,
        close_timeout: Duration,
    ) -> Self {
        let mut connected = Self::from_running(service, close_timeout).await;
        connected.transport_cancel = Some(transport_cancel);
        connected
    }

    /// 返回可克隆的 typed rmcp peer。
    pub fn peer(&self) -> Peer<RoleClient> {
        self.peer.clone()
    }

    /// Whether the server declared the MCP resources capability during discovery.
    pub fn supports_resources(&self) -> bool {
        self.peer
            .peer_info()
            .is_some_and(|info| info.capabilities.resources.is_some())
    }

    pub async fn list_tools(&self) -> Result<Vec<Tool>> {
        self.ensure_running("tools/list")?;
        self.peer
            .list_all_tools()
            .await
            .map_err(|error| connection_error("tools/list", error))
    }

    pub async fn call_tool(
        &self,
        name: String,
        arguments: serde_json::Value,
    ) -> Result<CallToolResult> {
        let mut request = CallToolRequestParams::new(name);
        match arguments {
            serde_json::Value::Object(arguments) => request.arguments = Some(arguments),
            serde_json::Value::Null => {}
            _ => {
                return Err(PureError::ToolExecutionFailed {
                    tool: "mcp".to_string(),
                    error: "MCP tool arguments must be a JSON object".to_string(),
                });
            }
        }
        self.ensure_running("tools/call")?;
        self.peer
            .call_tool(request)
            .await
            .map_err(|error| connection_error("tools/call", error))
    }

    pub async fn list_resources(&self, cursor: Option<String>) -> Result<ListResourcesResult> {
        self.ensure_running("resources/list")?;
        self.peer
            .list_resources(Some(PaginatedRequestParams::default().with_cursor(cursor)))
            .await
            .map_err(|error| connection_error("resources/list", error))
    }

    pub async fn list_resource_templates(
        &self,
        cursor: Option<String>,
    ) -> Result<ListResourceTemplatesResult> {
        self.ensure_running("resources/templates/list")?;
        self.peer
            .list_resource_templates(Some(PaginatedRequestParams::default().with_cursor(cursor)))
            .await
            .map_err(|error| connection_error("resources/templates/list", error))
    }

    pub async fn read_resource(&self, uri: String) -> Result<ReadResourceResult> {
        self.ensure_running("resources/read")?;
        self.peer
            .read_resource(ReadResourceRequestParams::new(uri))
            .await
            .map_err(|error| connection_error("resources/read", error))
    }

    /// 幂等、限时关闭 rmcp service、tool 订阅及其 transport owner，并确认整棵进程树已回收。
    ///
    /// 关闭任务独占订阅、service、Linux supervisor 与可执行镜像 lease，并先同步发出所有
    /// 取消、再独立 join 聚合并发错误；超时不代表停止，任务被保留（owner 随任务结束或
    /// 进程终止回收），而不是静默 clean。只有确认全部 owner 已释放才缓存终态结果供
    /// 幂等重放；仍有 owner 未确认时保留可重试状态。
    pub async fn close(&self) -> Result<()> {
        self.closing.store(true, Ordering::Release);
        if let Some(cancel) = &self.transport_cancel {
            cancel.cancel();
        }
        let mut progress = self.close.lock().await;
        if let Some(result) = &progress.completed {
            return result
                .clone()
                .map_err(|message| connection_error("mcp", message));
        }
        if progress.task.is_none() {
            let subscription = self.tool_subscription.clone();
            let service = self.owner.write().await.take();
            let stdio_command = self.stdio_command.lock().await.take();
            let transport_cancel = self.transport_cancel.clone();
            let close_timeout = self.close_timeout;
            #[cfg(target_os = "linux")]
            let worker = self.stdio_worker.lock().await.take();
            #[cfg(target_os = "linux")]
            let executable = self.worker_owner.clone();
            #[cfg(target_os = "linux")]
            let task = tokio::spawn(close_everything(
                subscription,
                service,
                stdio_command,
                transport_cancel,
                close_timeout,
                worker,
                executable,
            ));
            #[cfg(not(target_os = "linux"))]
            let task = tokio::spawn(close_everything(
                subscription,
                service,
                stdio_command,
                transport_cancel,
                close_timeout,
            ));
            progress.task = Some(task);
        }
        let outcome = {
            let task = progress.task.as_mut().expect("MCP close task must exist");
            tokio::time::timeout(self.close_timeout, task).await
        };
        match outcome {
            Ok(Ok(result)) => {
                progress.task = None;
                // Cache the terminal fact only when nothing remains owned for a retry: an
                // unconfirmed subscription is re-inserted below and must stay retryable.
                if self.tool_subscription.lock().await.is_none() {
                    progress.completed = Some(result.clone());
                }
                result.map_err(|message| connection_error("mcp", message))
            }
            Ok(Err(join_error)) => {
                progress.task = None;
                let message = format!("MCP close task panicked: {join_error}");
                progress.completed = Some(Err(message.clone()));
                Err(connection_error("mcp", message))
            }
            Err(_elapsed) => Err(connection_error(
                "mcp",
                "MCP session did not confirm closure within the timeout",
            )),
        }
    }

    fn ensure_running(&self, operation: &str) -> Result<()> {
        if self.closing.load(Ordering::Acquire) {
            return Err(PureError::ToolExecutionFailed {
                tool: "mcp".to_string(),
                error: format!("MCP service is closed during {operation}"),
            });
        }
        Ok(())
    }
}

struct ToolListSubscription {
    cancel: CancellationToken,
    task: tokio::task::JoinHandle<std::result::Result<(), String>>,
}

async fn start_tool_list_subscription(
    service: &RunningService<RoleClient, McpClientHandler>,
) -> Option<ToolListSubscription> {
    let peer_info = service.peer().peer_info()?;
    let supports_list_changed = peer_info
        .capabilities
        .tools
        .as_ref()
        .and_then(|tools| tools.list_changed)
        == Some(true);
    if peer_info.protocol_version != ProtocolVersion::V_2026_07_28 || !supports_list_changed {
        return None;
    }
    let mut subscription = match service
        .peer()
        .listen(SubscriptionFilter::builder().tools_list_changed().build())
        .await
    {
        Ok(subscription) => subscription,
        Err(error) => {
            tracing::warn!(%error, "failed to subscribe to MCP tools/list_changed");
            return None;
        }
    };
    let server_id = service.service().server_id.clone();
    let handler = service.service().tool_list_changed.clone();
    let cancel = CancellationToken::new();
    let task_cancel = cancel.clone();
    let task = tokio::spawn(async move {
        loop {
            tokio::select! {
                () = task_cancel.cancelled() => {
                    return subscription
                        .cancel()
                        .await
                        .map_err(|error| format!("MCP tool subscription cancel failed: {error}"));
                }
                notification = subscription.next() => match notification {
                    Ok(Some(_notification)) => {
                        let callback = handler
                            .read()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .clone();
                        if let Some(callback) = callback {
                            callback(
                                server_id
                                    .read()
                                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                                    .clone(),
                            );
                        }
                    }
                    Ok(None) => return Ok(()),
                    Err(error) => {
                        return Err(format!("MCP tools/list_changed subscription ended: {error}"));
                    }
                }
            }
        }
    });
    Some(ToolListSubscription { cancel, task })
}

/// Resolves the model-visible stdio command to a spawnable program and its prefix args.
fn resolve_stdio_program(
    request: &McpConnectRequest,
) -> Result<(String, stdio_program::ResolvedStdioProgram)> {
    let command_name =
        request.server.config.command.clone().ok_or_else(|| {
            connection_config_error(&request.server_id, "stdio command is required")
        })?;
    let program = stdio_program::resolve(&command_name).map_err(|error| {
        connection_error(
            &request.server_id,
            format!("failed to resolve stdio command {command_name}: {error}"),
        )
    })?;
    Ok((command_name, program))
}

#[cfg(not(target_os = "linux"))]
async fn connect_stdio_child_process(
    request: McpConnectRequest,
    tool_list_changed: Option<ToolListChangedSink>,
    command_name: String,
    program: stdio_program::ResolvedStdioProgram,
    close_timeout: Duration,
    cancel: CancellationToken,
) -> Result<ConnectedMcp> {
    if cancel.is_cancelled() {
        return Err(connection_error(
            &request.server_id,
            "MCP stdio connection cancelled",
        ));
    }
    let config = &request.server.config;
    let mut command = Command::new(program.executable);
    command
        .args(program.prefix_args)
        .args(&config.args)
        .envs(&config.env)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(cwd) = config.cwd.as_deref() {
        command.current_dir(cwd);
    }
    let mut command = pl_remote_helper::process::wrap_background_command(command);
    let child =
        pl_remote_helper::process::spawn_background_command(&mut command).map_err(|error| {
            connection_error(
                &request.server_id,
                format!("failed to start stdio command {command_name}: {error}"),
            )
        })?;
    let mut process = ManagedCommand::from_background_child(child);
    let stdin = process.take_stdin();
    let stdout = process.take_stdout();
    let stderr = process.take_stderr();
    let (Some(stdin), Some(stdout)) = (stdin, stdout) else {
        close_stdio_command(Some(process))
            .await
            .map_err(|error| connection_error(&request.server_id, error))?;
        return Err(connection_error(
            &request.server_id,
            "MCP stdio pipes missing",
        ));
    };
    // Use the SDK's framing with the shared native I/O driver and command owner.
    let transport = AsyncRwTransport::new_client(stdout, stdin);
    let stderr = stderr.map(|stderr| StderrCapture::spawn(stderr, &config.env));
    let handshake = client_handler(
        &request.server_id,
        ProtocolVersion::V_2026_07_28,
        tool_list_changed,
    )
    .serve_with_lifecycle(transport, discovery_lifecycle());
    let service = tokio::select! {
        biased;
        () = cancel.cancelled() => {
            close_stdio_command(Some(process)).await.map_err(|error| connection_error(&request.server_id, error))?;
            return Err(connection_error(
                &request.server_id,
                "MCP stdio connection cancelled during handshake",
            ));
        }
        result = handshake => match result {
            Ok(service) => service,
            Err(error) => {
                tokio::task::yield_now().await;
                let error = stderr.as_ref().and_then(StderrCapture::render).map_or_else(
                    || error.to_string(),
                    |stderr| format!("{error}; stderr: {stderr}"),
                );
                close_stdio_command(Some(process)).await.map_err(|cleanup| connection_error(&request.server_id, format!("{error}; cleanup: {cleanup}")))?;
                return Err(connection_error(&request.server_id, error));
            }
        }
    };
    Ok(ConnectedMcp::from_running_with_stdio_command(service, process, close_timeout).await)
}

/// Starts a Linux local stdio server under the bundled per-child supervisor.
///
/// The server's `argv`, working directory and environment are forwarded verbatim to the
/// worker; `stderr` stays on the shared bounded capture. The supervisor owner is retained
/// until the rmcp service closes, then cancelled and awaited so the whole tree is reclaimed
/// even when the GUI is force-killed.
#[cfg(target_os = "linux")]
async fn connect_stdio_supervised(
    request: McpConnectRequest,
    tool_list_changed: Option<ToolListChangedSink>,
    command_name: String,
    program: stdio_program::ResolvedStdioProgram,
    worker_executable: Arc<dyn LocalWorkerExecutable>,
    close_timeout: Duration,
    cancel: CancellationToken,
) -> Result<ConnectedMcp> {
    use pl_remote_helper::client::ProcessCommand;

    if cancel.is_cancelled() {
        return Err(connection_error(
            &request.server_id,
            "MCP stdio connection cancelled",
        ));
    }
    let config = &request.server.config;
    let mut specification = ProcessCommand::new(program.executable.into_os_string())
        .args(program.prefix_args)
        .args(config.args.iter().cloned());
    if let Some(cwd) = config.cwd.as_deref() {
        specification = specification.current_dir(cwd);
    }
    for (key, value) in &config.env {
        specification = specification.env(key.clone(), value.clone());
    }
    let start_control = crate::command::CommandStartControl::new(
        tokio::time::Instant::now() + Duration::from_secs(3600),
        cancel.clone(),
        CancellationToken::new(),
    );
    let mut worker = ManagedWorker::spawn_controlled(
        worker_executable.worker_path(),
        specification,
        &start_control,
    )
    .await
    .map_err(|error| {
        connection_error(
            &request.server_id,
            format!("failed to start stdio command {command_name}: {error}"),
        )
    })?;
    let stdin = worker.take_stdin();
    let stdout = worker.take_stdout();
    let stderr = worker.take_stderr();
    let (Some(stdin), Some(stdout)) = (stdin, stdout) else {
        cancel_and_wait_worker(worker).await;
        return Err(connection_error(
            &request.server_id,
            format!("stdio command {command_name} did not expose piped stdio"),
        ));
    };
    let stderr = stderr.map(|stderr| StderrCapture::spawn(stderr, &config.env));
    let transport = AsyncRwTransport::new_client(stdout, stdin);
    let handshake = client_handler(
        &request.server_id,
        ProtocolVersion::V_2026_07_28,
        tool_list_changed,
    )
    .serve_with_lifecycle(transport, discovery_lifecycle());
    let service = tokio::select! {
        biased;
        () = cancel.cancelled() => {
            cancel_and_wait_worker(worker).await;
            return Err(connection_error(
                &request.server_id,
                "MCP stdio connection cancelled during handshake",
            ));
        }
        result = handshake => match result {
            Ok(service) => service,
            Err(error) => {
                tokio::task::yield_now().await;
                let error = stderr.as_ref().and_then(StderrCapture::render).map_or_else(
                    || error.to_string(),
                    |stderr| format!("{error}; stderr: {stderr}"),
                );
                cancel_and_wait_worker(worker).await;
                return Err(connection_error(&request.server_id, error));
            }
        }
    };
    Ok(ConnectedMcp::from_running_with_stdio_worker(
        service,
        worker,
        worker_executable,
        close_timeout,
    )
    .await)
}

/// Requests cancellation of one stdio supervisor and waits for its complete tree exit.
#[cfg(target_os = "linux")]
async fn cancel_and_wait_worker(mut worker: ManagedWorker) {
    let control = worker.control();
    if control.cancel().await.is_err() {
        control.close();
    }
    let _ = worker.wait().await;
}

/// Owns every closeable resource of one MCP session and reclaims them concurrently.
///
/// All cancellations are issued before either join so a service that never acknowledges can
/// never starve the supervisor cancel (and vice versa). Subscription, service and supervisor
/// results are joined independently and aggregated; a recoverable issue never aborts the
/// other independent cleanups.
async fn close_everything(
    subscription_slot: Arc<tokio::sync::Mutex<Option<ToolListSubscription>>>,
    service: Option<RunningService<RoleClient, McpClientHandler>>,
    stdio_command: Option<ManagedCommand>,
    transport_cancel: Option<CancellationToken>,
    close_timeout: Duration,
    #[cfg(target_os = "linux")] worker: Option<ManagedWorker>,
    #[cfg(target_os = "linux")] executable: Option<Arc<dyn LocalWorkerExecutable>>,
) -> std::result::Result<(), String> {
    let mut subscription = subscription_slot.lock().await.take();

    // Issue every cancellation up front. The rmcp token and the subscription cancel are
    // synchronous; the supervisor cancel is the first step of `close_worker`, polled
    // concurrently with the service join below, so neither can starve the other.
    if let Some(subscription) = subscription.as_mut() {
        subscription.cancel.cancel();
    }
    if let Some(service) = service.as_ref() {
        service.cancellation_token().cancel();
    }
    if let Some(cancel) = transport_cancel.as_ref() {
        cancel.cancel();
    }
    if let Some(command) = stdio_command.as_ref() {
        command.cancellation().cancel();
    }

    let subscription_join =
        close_tool_subscription(&subscription_slot, &mut subscription, close_timeout);
    let service_join = await_service_close(service);
    let command_join = close_stdio_command(stdio_command);
    #[cfg(target_os = "linux")]
    let worker_join = close_worker(worker, executable);
    #[cfg(not(target_os = "linux"))]
    let worker_join = async { Ok::<(), String>(()) };

    let (subscription_result, service_result, command_result, worker_result) =
        tokio::join!(subscription_join, service_join, command_join, worker_join);

    let mut failures = Vec::new();
    for result in [
        subscription_result,
        service_result,
        command_result,
        worker_result,
    ] {
        if let Err(error) = result {
            failures.push(error);
        }
    }
    if failures.is_empty() {
        Ok(())
    } else {
        Err(failures.join("; "))
    }
}

/// Cancels one tool subscription and confirms its task stopped; a task that never confirms
/// stopping is re-inserted into `slot` so a live owner is never dropped untracked.
async fn close_tool_subscription(
    slot: &tokio::sync::Mutex<Option<ToolListSubscription>>,
    subscription: &mut Option<ToolListSubscription>,
    close_timeout: Duration,
) -> std::result::Result<(), String> {
    if subscription.is_none() {
        return Ok(());
    }
    let first = {
        let active = subscription
            .as_mut()
            .expect("checked MCP subscription owner");
        tokio::time::timeout(close_timeout, &mut active.task).await
    };
    match first {
        Ok(Ok(Ok(()))) => {
            *subscription = None;
            return Ok(());
        }
        Ok(Ok(Err(message))) => {
            *subscription = None;
            return Err(message);
        }
        Ok(Err(join_error)) => {
            *subscription = None;
            return Err(format!("MCP tool subscription task failed: {join_error}"));
        }
        Err(_elapsed) => {}
    }
    let second = {
        let active = subscription
            .as_mut()
            .expect("checked MCP subscription owner");
        active.task.abort();
        tokio::time::timeout(close_timeout, &mut active.task).await
    };
    match second {
        Ok(Ok(Ok(()))) => {
            *subscription = None;
            Err("MCP tool subscription was force-aborted after the close timeout".to_string())
        }
        Ok(Ok(Err(message))) => {
            *subscription = None;
            Err(message)
        }
        Ok(Err(join_error)) => {
            *subscription = None;
            Err(format!(
                "MCP tool subscription aborted after the close timeout: {join_error}"
            ))
        }
        Err(_aborted) => {
            // Retain the owner so a live subscription task is never dropped untracked.
            *slot.lock().await = subscription.take();
            Err("MCP tool subscription did not confirm stop within the timeout".to_string())
        }
    }
}

/// Owns the rmcp service until its background task terminates; a join error is a real
/// failure to confirm closure, not a warning. The caller already cancelled the token.
async fn await_service_close(
    service: Option<RunningService<RoleClient, McpClientHandler>>,
) -> std::result::Result<(), String> {
    let Some(service) = service else {
        return Ok(());
    };
    match service.waiting().await {
        Ok(_quit_reason) => Ok(()),
        Err(join_error) => Err(format!("MCP service close task failed: {join_error}")),
    }
}

async fn close_stdio_command(command: Option<ManagedCommand>) -> std::result::Result<(), String> {
    let Some(mut command) = command else {
        return Ok(());
    };
    command.cancellation().cancel();
    match command.wait().await {
        Ok(exit) => match exit.supervision_failure {
            Some(failure) => Err(format!(
                "MCP stdio process did not confirm tree exit: {failure}"
            )),
            None => Ok(()),
        },
        Err(error) => Err(format!(
            "MCP stdio process did not confirm tree exit: {error}"
        )),
    }
}

/// Owns the Linux stdio supervisor (and its executable image lease) until the whole process
/// tree is confirmed exited. A failed cancel request is preserved as a degraded result even
/// when the follow-up seal + wait reclaims the tree, so nothing is silently clean.
#[cfg(target_os = "linux")]
async fn close_worker(
    worker: Option<ManagedWorker>,
    _executable: Option<Arc<dyn LocalWorkerExecutable>>,
) -> std::result::Result<(), String> {
    let Some(mut worker) = worker else {
        return Ok(());
    };
    let control = worker.control();
    let cancel_result = control.cancel().await;
    if cancel_result.is_err() {
        // Seal the lease so cleanup still proceeds even though the cancel request failed.
        control.close();
    }
    let wait_result = worker.wait().await;
    match (cancel_result, wait_result) {
        (Ok(()), Ok(_termination)) => Ok(()),
        (Err(cancel_error), Ok(_termination)) => Err(format!(
            "MCP stdio supervisor tree was reclaimed after the cancel request failed: {cancel_error}"
        )),
        (Ok(()), Err(wait_error)) => Err(format!(
            "MCP stdio supervisor did not confirm tree exit: {wait_error}"
        )),
        (Err(cancel_error), Err(wait_error)) => Err(format!(
            "MCP stdio supervisor cancel failed ({cancel_error}) and tree exit was not confirmed: {wait_error}"
        )),
    }
}

async fn connect_http(
    request: McpConnectRequest,
    tool_list_changed: Option<ToolListChangedSink>,
    close_timeout: Duration,
) -> Result<ConnectedMcp> {
    let config = &request.server.config;
    let uri = config.url.as_deref().ok_or_else(|| {
        connection_config_error(&request.server_id, "streamable HTTP url is required")
    })?;
    let custom_headers = config
        .headers
        .iter()
        .map(|(name, value)| {
            let name = HeaderName::from_bytes(name.as_bytes())
                .map_err(|error| connection_error(&request.server_id, error))?;
            let value = HeaderValue::from_str(value)
                .map_err(|error| connection_error(&request.server_id, error))?;
            Ok((name, value))
        })
        .collect::<Result<HashMap<_, _>>>()?;
    let mut transport_config = StreamableHttpClientTransportConfig::with_uri(uri.to_string())
        .custom_headers(custom_headers)
        .reinit_on_expired_session(true);
    if let Some(token) = request.server.bearer_token.as_deref() {
        transport_config = transport_config.auth_header(token);
    } else if let Some(env_var) = config.bearer_token_env_var.as_deref() {
        let token = std::env::var(env_var)
            .ok()
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                connection_config_error(
                    &request.server_id,
                    &format!("missing bearer token environment variable '{env_var}'"),
                )
            })?;
        transport_config = transport_config.auth_header(token);
    }
    let transport = StreamableHttpClientTransport::from_config(transport_config.clone());
    let service = match client_handler(
        &request.server_id,
        ProtocolVersion::V_2026_07_28,
        tool_list_changed.clone(),
    )
    .serve_with_lifecycle(transport, discovery_lifecycle())
    .await
    {
        Ok(service) => service,
        Err(discovery_error) if should_retry_http_with_initialize(&discovery_error) => {
            // rmcp 会先耗尽 startup SSE，只转发成功 response；传统服务返回的
            // METHOD_NOT_FOUND error 因而表现为关闭 discover response。失败的 worker
            // 不可复用，必须用一个全新的 transport 走标准 initialize。
            let transport = StreamableHttpClientTransport::from_config(transport_config);
            client_handler(
                &request.server_id,
                ProtocolVersion::V_2025_11_25,
                tool_list_changed,
            )
                .serve_with_lifecycle(transport, ClientLifecycleMode::Initialize)
                .await
                .map_err(|initialize_error| {
                    connection_error(
                        &request.server_id,
                        format!(
                            "discovery failed ({discovery_error}); standard initialize failed ({initialize_error})"
                        ),
                    )
                })?
        }
        Err(error) => return Err(connection_error(&request.server_id, error)),
    };
    Ok(ConnectedMcp::from_running(service, close_timeout).await)
}

fn should_retry_http_with_initialize(error: &ClientInitializeError) -> bool {
    matches!(
        error,
        ClientInitializeError::ConnectionClosed(context) if context == "discover response"
    )
}

fn client_info(protocol_version: ProtocolVersion) -> ClientConfig {
    ClientConfig::new(
        ClientCapabilities::default(),
        Implementation::new("pure-lang", env!("CARGO_PKG_VERSION")),
    )
    .with_protocol_version(protocol_version)
}

fn client_handler(
    server_id: &str,
    protocol_version: ProtocolVersion,
    tool_list_changed: Option<ToolListChangedSink>,
) -> McpClientHandler {
    McpClientHandler::new(
        client_info(protocol_version),
        server_id.to_string(),
        tool_list_changed,
    )
}

fn discovery_lifecycle() -> ClientLifecycleMode {
    ClientLifecycleMode::Auto {
        preferred_versions: vec![
            ProtocolVersion::V_2026_07_28,
            ProtocolVersion::V_2025_11_25,
            ProtocolVersion::V_2025_06_18,
            ProtocolVersion::V_2025_03_26,
            ProtocolVersion::V_2024_11_05,
        ],
        // 不支持 `server/discover` 的标准 MCP 服务仍通过传统 initialize
        // 协商具体版本；只在对端明确返回 METHOD_NOT_FOUND 时走这条路径。
        legacy_version: Some(ProtocolVersion::V_2025_11_25),
    }
}

fn connection_config_error(server_id: &str, error: &str) -> PureError {
    PureError::ToolExecutionFailed {
        tool: server_id.to_string(),
        error: error.to_string(),
    }
}

fn connection_error(server_id: &str, error: impl fmt::Display) -> PureError {
    PureError::ToolExecutionFailed {
        tool: server_id.to_string(),
        error: error.to_string(),
    }
}
