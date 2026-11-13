use std::fmt;
use std::future::Future;
use std::sync::Arc;
use std::time::Duration;

use pl_protocol::{PureError, Result};
use rmcp::handler::client::ClientHandler;
use rmcp::model::*;
use rmcp::service::{
    ClientInitializeError, NotificationContext, Peer, PeerRequestOptions, QuitReason,
    RunningService, RunningServiceCancellationToken, ServiceError,
};
use rmcp::{ClientCacheConfig, ClientLifecycleMode, ClientServiceExt, RoleClient};
use tokio::sync::RwLock;
use tokio_util::sync::CancellationToken;

use crate::command::ManagedCommand;
use crate::mcp::config::{
    EffectiveMcpServerConfig, McpExecutionContext, McpServerStartupMode, McpServerTransport,
};
use std::sync::atomic::{AtomicBool, Ordering};

pub(crate) mod executor_http;
mod observed_transport;
mod stderr_capture;
mod stdio;
mod stdio_program;

pub use executor_http::ExecutorStreamableHttpClient;

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
type ToolListChangedSink =
    Arc<dyn Fn(String, Arc<ConnectionIdentity>, ConnectionEvent) + Send + Sync>;

#[derive(Default)]
pub(crate) struct ConnectionIdentity {
    ended: AtomicBool,
    close_error: std::sync::Mutex<Option<observed_transport::TransportError>>,
}

#[derive(Clone, Copy)]
pub(crate) enum ConnectionEvent {
    ToolListChanged,
    Closed,
}

pub(crate) fn is_connection_failure(error: &ServiceError) -> bool {
    matches!(
        error,
        ServiceError::TransportSend(_) | ServiceError::TransportClosed
    )
}

#[derive(Clone, Default)]
pub struct McpConnector {
    tool_list_changed: Option<ToolListChangedSink>,
    close_timeout: Option<Duration>,
    host_executor: Option<pl_remote_helper::Executor>,
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
        let executor = match &request.server.execution_context {
            McpExecutionContext::Host => self
                .host_executor
                .clone()
                .map(Ok)
                .unwrap_or_else(pl_remote_helper::Executor::local)
                .map_err(|error| connection_error(&request.server_id, error))?,
            McpExecutionContext::Remote { commands } => commands.executor().clone(),
        };
        match request.server.config.transport {
            McpServerTransport::Stdio => {
                stdio::connect(
                    request,
                    executor,
                    self.tool_list_changed.clone(),
                    close_timeout,
                    cancel,
                )
                .await
            }
            McpServerTransport::StreamableHttp => {
                tokio::select! {
                    biased;
                    ()=cancel.cancelled()=>Err(connection_error(&request.server_id,"MCP HTTP connection cancelled")),
                    result=executor_http::connect(request.clone(),executor,self.tool_list_changed.clone(),close_timeout)=>result,
                }
            }
        }
    }

    /// Overrides the per-session close timeout (defaults to 5 seconds).
    pub fn with_close_timeout(mut self, timeout: Duration) -> Self {
        self.close_timeout = Some(timeout);
        self
    }

    pub fn with_executor(mut self, executor: pl_remote_helper::Executor) -> Self {
        self.host_executor = Some(executor);
        self
    }

    pub(crate) fn with_tool_list_changed(
        mut self,
        handler: impl Fn(String, Arc<ConnectionIdentity>, ConnectionEvent) + Send + Sync + 'static,
    ) -> Self {
        self.tool_list_changed = Some(Arc::new(handler));
        self
    }
}

#[derive(Clone)]
pub(super) struct McpClientHandler {
    info: ClientConfig,
    identity: Arc<ConnectionIdentity>,
    server_id: Arc<std::sync::RwLock<String>>,
    tool_list_changed: Arc<std::sync::RwLock<Option<ToolListChangedSink>>>,
}

impl McpClientHandler {
    async fn serve_observed<T: rmcp::transport::Transport<RoleClient> + 'static>(
        self,
        transport: T,
        lifecycle: ClientLifecycleMode,
    ) -> std::result::Result<RunningService<RoleClient, Self>, Box<ClientInitializeError>> {
        let transport =
            observed_transport::ObservedTransport::new(transport, self.identity.clone());
        self.serve_with_lifecycle(transport, lifecycle)
            .await
            .map_err(Box::new)
    }

    fn new(
        info: ClientConfig,
        server_id: String,
        tool_list_changed: Option<ToolListChangedSink>,
    ) -> Self {
        Self {
            info,
            identity: Arc::new(ConnectionIdentity::default()),
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
        let identity = self.identity.clone();
        async move {
            if let Some(handler) = handler {
                handler(server_id, identity, ConnectionEvent::ToolListChanged);
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
    pub(crate) identity: Arc<ConnectionIdentity>,
    closing: AtomicBool,
    close_timeout: Duration,
    owner: RwLock<Option<ServiceOwner>>,
    /// Tool-subscription owner shared with the close task so a subscription that cannot be
    /// confirmed stopped is re-inserted here instead of being dropped while still running.
    tool_subscription: Arc<tokio::sync::Mutex<Option<ToolListSubscription>>>,
    /// Serialized, reusable close progress. The spawned close task owns the subscription,
    /// the service and the concrete stdio process until their close results are
    /// confirmed, so a timeout retains — never silently drops — those owners.
    close: tokio::sync::Mutex<CloseProgress>,
    /// Executor-owned stdio command owned through `pl-remote-helper`.
    stdio_command: tokio::sync::Mutex<Option<ManagedCommand>>,
    /// Cancellation token for remote HTTP exchange / SSE streams.
    transport_cancel: Option<CancellationToken>,
}

struct ServiceOwner {
    cancel: Option<RunningServiceCancellationToken>,
    task: tokio::task::JoinHandle<std::result::Result<(), String>>,
}

/// Close bookkeeping shared by every `close()` caller on one [`ConnectedMcp`].
struct CloseProgress {
    /// In-flight close task; owns the service and concrete stdio command.
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
        let identity = service.service().identity.clone();
        let observed_identity = identity.clone();
        let handler = service.service().clone();
        let cancel = service.cancellation_token();
        // This is the sole waiter of RunningService. Both natural termination and explicit
        // close use this same owned task; no observer races close for the service handle.
        let task = tokio::spawn(async move {
            let result = match service.waiting().await {
                Ok(QuitReason::Closed | QuitReason::Cancelled) => Ok(()),
                Ok(QuitReason::JoinError(error)) | Err(error) => {
                    Err(format!("MCP service task failed: {error}"))
                }
                Ok(reason) => Err(format!("MCP service ended unsuccessfully: {reason:?}")),
            };
            let close_error = observed_identity
                .close_error
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone();
            let result = match (result, close_error) {
                (Ok(()), None) => Ok(()),
                (Err(message), None) => Err(message),
                (Ok(()), Some(error)) => Err(format!("MCP transport close failed: {error}")),
                (Err(message), Some(error)) => {
                    Err(format!("{message}; MCP transport close failed: {error}"))
                }
            };
            observed_identity.ended.store(true, Ordering::Release);
            let callback = handler
                .tool_list_changed
                .read()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone();
            if let Some(callback) = callback {
                let server_id = handler
                    .server_id
                    .read()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .clone();
                callback(server_id, observed_identity, ConnectionEvent::Closed);
            }
            result
        });
        Self {
            peer,
            identity,
            closing: AtomicBool::new(false),
            close_timeout,
            owner: RwLock::new(Some(ServiceOwner {
                cancel: Some(cancel),
                task,
            })),
            tool_subscription: Arc::new(tokio::sync::Mutex::new(tool_subscription)),
            close: tokio::sync::Mutex::new(CloseProgress {
                task: None,
                completed: None,
            }),
            stdio_command: tokio::sync::Mutex::new(None),
            transport_cancel: None,
        }
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

    pub(crate) fn has_ended(&self) -> bool {
        self.identity.ended.load(Ordering::Acquire) || self.peer.is_transport_closed()
    }

    pub(crate) async fn request(
        &self,
        request: ClientRequest,
        timeout: Duration,
    ) -> std::result::Result<ServerResult, ServiceError> {
        if self.closing.load(Ordering::Acquire) {
            return Err(ServiceError::TransportClosed);
        }
        let deadline = tokio::time::Instant::now() + timeout;
        // RMCP's option starts at await_response, not at its bounded channel send.
        // Tokio mpsc::Sender::send is cancellation-safe: an elapsed enqueue has not
        // submitted a request. Once it returns a handle, use only the remaining budget
        // and let RMCP send the request-specific cancellation on response timeout.
        let mut handle = tokio::time::timeout_at(
            deadline,
            self.peer
                .send_request_with_option(request, PeerRequestOptions::with_timeout(timeout)),
        )
        .await
        .map_err(|_| ServiceError::Timeout { timeout })??;
        handle.options.timeout =
            Some(deadline.saturating_duration_since(tokio::time::Instant::now()));
        // Poll RMCP's response timeout/cancellation first, but do not let waiting for
        // cancellation delivery or confirmation extend this request's original deadline.
        // An already queued notification remains owned by the service; dropping this
        // waiter neither resends it nor confirms remote cancellation or rollback.
        tokio::time::timeout_at(deadline, handle.await_response())
            .await
            .map_err(|_| ServiceError::Timeout { timeout })?
            .map_err(|error| match error {
                ServiceError::Timeout { .. } => ServiceError::Timeout { timeout },
                error => error,
            })
    }

    pub(crate) async fn call_tool_timed(
        &self,
        name: String,
        arguments: serde_json::Value,
        timeout: Duration,
    ) -> std::result::Result<CallToolResult, ServiceError> {
        let mut params = CallToolRequestParams::new(name);
        match arguments {
            serde_json::Value::Object(arguments) => params.arguments = Some(arguments),
            serde_json::Value::Null => {}
            _ => {
                return Err(ServiceError::McpError(rmcp::ErrorData::invalid_params(
                    "MCP tool arguments must be a JSON object",
                    None,
                )));
            }
        }
        match self
            .request(
                ClientRequest::CallToolRequest(CallToolRequest::new(params)),
                timeout,
            )
            .await?
        {
            ServerResult::CallToolResult(result) => Ok(result),
            _ => Err(ServiceError::UnexpectedResponse),
        }
    }

    /// Whether the server declared the MCP resources capability during discovery.
    pub fn supports_resources(&self) -> bool {
        self.peer
            .peer_info()
            .is_some_and(|info| info.capabilities.resources.is_some())
    }

    pub async fn list_tools(&self) -> Result<Vec<Tool>> {
        self.discover_tools()
            .await
            .map_err(|error| connection_error("tools/list", error))
    }

    pub(crate) async fn discover_tools(&self) -> std::result::Result<Vec<Tool>, ServiceError> {
        if self.closing.load(Ordering::Acquire) {
            return Err(ServiceError::TransportClosed);
        }
        // Runtime discovery must observe the server, not a still-fresh SDK TTL entry.
        // RMCP owns pagination and cache invalidation; clearing also prevents an older
        // in-flight response from repopulating the cache across this discovery boundary.
        self.peer.clear_response_cache().await;
        self.peer.list_all_tools().await
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

    /// 幂等、限时关闭 rmcp service、tool 订阅及其 transport owner，并确认协议 owner 与受管根进程退出。
    ///
    /// 关闭任务独占订阅、service 与具体执行器的 Child，先终止 stdio 进程再释放协议输入；超时不代表停止，任务被保留（owner 随任务结束或
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
    let identity = service.service().identity.clone();
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
                                identity.clone(),
                                ConnectionEvent::ToolListChanged,
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

/// Owns every closeable resource of one MCP session. Stdio root termination
/// precedes protocol teardown; independent close results are retained and aggregated.
async fn close_everything(
    subscription_slot: Arc<tokio::sync::Mutex<Option<ToolListSubscription>>>,
    mut service: Option<ServiceOwner>,
    stdio_command: Option<ManagedCommand>,
    transport_cancel: Option<CancellationToken>,
    close_timeout: Duration,
) -> std::result::Result<(), String> {
    let mut subscription = subscription_slot.lock().await.take();

    // Stop subscriptions immediately. For stdio, terminate the owned process before
    // dropping protocol stdin: EOF can otherwise let the root exit before its group
    // receives cancellation, leaving in-group descendants outside the root-only wait.
    if let Some(subscription) = subscription.as_mut() {
        subscription.cancel.cancel();
    }
    if let Some(command) = stdio_command.as_ref() {
        command.cancellation().cancel();
    }
    // The retained close task and its outer observation budget still own this wait.
    // Root exit does not wait for the protocol readers to drain.
    let command_result = close_stdio_command(stdio_command).await;
    if let Some(cancel) = service.as_mut().and_then(|service| service.cancel.take()) {
        cancel.cancel();
    }
    if let Some(cancel) = transport_cancel.as_ref() {
        cancel.cancel();
    }

    let subscription_join =
        close_tool_subscription(&subscription_slot, &mut subscription, close_timeout);
    let service_join = await_service_close(service);
    let (subscription_result, service_result) = tokio::join!(subscription_join, service_join);

    let mut failures = Vec::new();
    for result in [subscription_result, service_result, command_result] {
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
async fn await_service_close(service: Option<ServiceOwner>) -> std::result::Result<(), String> {
    let Some(service) = service else {
        return Ok(());
    };
    match service.task.await {
        Ok(result) => result,
        Err(join_error) => Err(format!("MCP service close task failed: {join_error}")),
    }
}

async fn close_stdio_command(command: Option<ManagedCommand>) -> std::result::Result<(), String> {
    let Some(mut command) = command else {
        return Ok(());
    };
    command.cancellation().cancel();
    command
        .wait()
        .await
        .map(|_| ())
        .map_err(|error| format!("MCP stdio root process exit was not confirmed: {error}"))
}

fn should_retry_http_with_initialize(
    mode: McpServerStartupMode,
    error: &ClientInitializeError,
) -> bool {
    mode == McpServerStartupMode::Auto
        && matches!(
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

fn startup_lifecycle(mode: McpServerStartupMode) -> (ProtocolVersion, ClientLifecycleMode) {
    let preferred_versions = vec![
        ProtocolVersion::V_2026_07_28,
        ProtocolVersion::V_2025_11_25,
        ProtocolVersion::V_2025_06_18,
        ProtocolVersion::V_2025_03_26,
        ProtocolVersion::V_2024_11_05,
    ];
    let lifecycle = match mode {
        McpServerStartupMode::Initialize => ClientLifecycleMode::Initialize,
        McpServerStartupMode::Discover => ClientLifecycleMode::Discover { preferred_versions },
        McpServerStartupMode::Auto => ClientLifecycleMode::Auto {
            preferred_versions,
            // Preserve the SDK's Auto negotiation for services that did not
            // explicitly choose a startup mode.
            legacy_version: Some(ProtocolVersion::V_2025_11_25),
        },
    };
    let protocol_version = match mode {
        McpServerStartupMode::Initialize => ProtocolVersion::V_2025_11_25,
        McpServerStartupMode::Auto | McpServerStartupMode::Discover => {
            ProtocolVersion::V_2026_07_28
        }
    };
    (protocol_version, lifecycle)
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

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use rmcp::transport::async_rw::AsyncRwTransport;
    use std::sync::atomic::AtomicUsize;
    use std::sync::{Condvar, Mutex};
    use tokio::sync::{Notify, mpsc};

    #[tokio::test]
    async fn legacy_initialize_accepts_captured_dart_sdk_response() {
        captured_dart_sdk_handshake(McpServerStartupMode::Auto, Duration::ZERO).await;
    }

    #[tokio::test]
    async fn explicit_initialize_accepts_cold_captured_dart_sdk_response() {
        captured_dart_sdk_handshake(McpServerStartupMode::Initialize, Duration::from_secs(11))
            .await;
    }

    #[tokio::test]
    #[ignore = "reproduces RMCP's fixed 10-second Auto discovery timeout"]
    async fn cold_legacy_initialize_accepts_captured_dart_sdk_response() {
        captured_dart_sdk_handshake(McpServerStartupMode::Auto, Duration::from_secs(11)).await;
    }

    async fn captured_dart_sdk_handshake(mode: McpServerStartupMode, startup_delay: Duration) {
        use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

        let (client, server) = tokio::io::duplex(16384);
        let (read, mut write) = tokio::io::split(server);
        let peer = tokio::spawn(async move {
            let mut lines = BufReader::new(read).lines();
            tokio::time::sleep(startup_delay).await;
            let responses = include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/tests/support/dart_mcp_1_2_2_initialize.jsonl"
            ))
            .lines();
            for response in responses.skip(usize::from(mode == McpServerStartupMode::Initialize)) {
                let request: serde_json::Value =
                    serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
                let mut response_value: serde_json::Value = serde_json::from_str(response).unwrap();
                if mode == McpServerStartupMode::Initialize {
                    assert_eq!(request["method"], "initialize");
                    assert_eq!(request["id"], 0);
                    assert_eq!(request["params"]["protocolVersion"], "2025-11-25");
                    // Only correlate the captured envelope with this session's first
                    // request. The captured initialize result stays completely intact.
                    response_value["id"] = request["id"].clone();
                } else {
                    assert_eq!(request["id"], response_value["id"]);
                }
                let response = if mode == McpServerStartupMode::Initialize {
                    serde_json::to_string(&response_value).unwrap()
                } else {
                    response.to_owned()
                };
                write.write_all(response.as_bytes()).await.unwrap();
                write.write_all(b"\n").await.unwrap();
            }
            let initialized: serde_json::Value =
                serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
            assert_eq!(initialized["method"], "notifications/initialized");
        });
        let (read, write) = tokio::io::split(client);
        let (protocol_version, lifecycle) = startup_lifecycle(mode);
        let result = tokio::time::timeout(
            startup_delay + Duration::from_secs(2),
            client_handler("captured-peer", protocol_version, None)
                .serve_observed(AsyncRwTransport::new(read, write), lifecycle),
        )
        .await
        .expect("handshake deadline");
        let service = result.unwrap_or_else(|error| panic!("typed initialize failure: {error:?}"));
        peer.await.unwrap();
        service.cancel().await.unwrap();
    }

    pub(crate) struct FaultTransport {
        pub(crate) panic_send: bool,
        pub(crate) fail_close: bool,
        pub(crate) closed: Arc<AtomicUsize>,
    }

    impl rmcp::transport::Transport<RoleClient> for FaultTransport {
        type Error = std::io::Error;

        fn send(
            &mut self,
            _: ClientJsonRpcMessage,
        ) -> impl Future<Output = std::io::Result<()>> + Send + 'static {
            let panic_send = self.panic_send;
            async move {
                assert!(!panic_send, "send-task-failed secret-close-token");
                Ok(())
            }
        }

        async fn receive(&mut self) -> Option<ServerJsonRpcMessage> {
            std::future::pending().await
        }

        async fn close(&mut self) -> std::io::Result<()> {
            self.closed.fetch_add(1, Ordering::SeqCst);
            if self.fail_close {
                Err(std::io::Error::other(
                    "transport-close-failed secret-close-token",
                ))
            } else {
                Ok(())
            }
        }
    }

    pub(crate) async fn fault_session(transport: FaultTransport) -> ConnectedMcp {
        let panic_send = transport.panic_send;
        let handler = client_handler("fault", ProtocolVersion::V_2025_11_25, None);
        let observed =
            observed_transport::ObservedTransport::new(transport, handler.identity.clone());
        let service = rmcp::service::serve_directly(handler, observed, None);
        let session = ConnectedMcp::from_running(service, Duration::from_secs(2)).await;
        if panic_send {
            tokio::time::timeout(
                Duration::from_secs(2),
                session
                    .peer
                    .send_request(ClientRequest::PingRequest(Default::default())),
            )
            .await
            .unwrap()
            .expect_err("send task panic must close the response channel");
        }
        session
    }

    pub(crate) fn retains_io_close_source(session: &ConnectedMcp) -> bool {
        let error = session.identity.close_error.lock().unwrap();
        let source = std::error::Error::source(error.as_ref().unwrap()).unwrap();
        source.downcast_ref::<std::io::Error>().is_some()
    }

    // Deliberately park the SDK consumer on a dedicated worker thread: pending send
    // futures alone do not stop RMCP, which spawns them concurrently. This fixture
    // reproduces consumer starvation without changing the real bounded SDK channel.
    struct BlockedSink {
        incoming: mpsc::UnboundedReceiver<ServerJsonRpcMessage>,
        sender: mpsc::UnboundedSender<ServerJsonRpcMessage>,
        entered: Arc<Notify>,
        release: Arc<(Mutex<bool>, Condvar)>,
        blocked: bool,
        tool_calls: Arc<AtomicUsize>,
    }

    impl rmcp::transport::Transport<RoleClient> for BlockedSink {
        type Error = std::io::Error;

        fn send(
            &mut self,
            item: ClientJsonRpcMessage,
        ) -> impl Future<Output = std::io::Result<()>> + Send + 'static {
            let sender = self.sender.clone();
            let tool_calls = self.tool_calls.clone();
            async move {
                if let ClientJsonRpcMessage::Request(request) = item {
                    if matches!(request.request, ClientRequest::CallToolRequest(_)) {
                        tool_calls.fetch_add(1, Ordering::SeqCst);
                    }
                    sender
                        .send(ServerJsonRpcMessage::response(
                            ServerResult::empty(()),
                            request.id,
                        ))
                        .unwrap();
                }
                Ok(())
            }
        }

        async fn receive(&mut self) -> Option<ServerJsonRpcMessage> {
            if !self.blocked {
                self.blocked = true;
                self.entered.notify_one();
                let (lock, wake) = &*self.release;
                let mut released = lock.lock().unwrap();
                while !*released {
                    released = wake.wait(released).unwrap();
                }
            }
            self.incoming.recv().await
        }

        async fn close(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    struct ReleaseOnDrop(Arc<(Mutex<bool>, Condvar)>);

    impl Drop for ReleaseOnDrop {
        fn drop(&mut self) {
            let (lock, wake) = &*self.0;
            *lock.lock().unwrap() = true;
            wake.notify_all();
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn request_deadline_bounds_sdk_enqueue_without_sending_or_replaying_the_tool() {
        let (sender, incoming) = mpsc::unbounded_channel();
        let entered = Arc::new(Notify::new());
        let release = Arc::new((Mutex::new(false), Condvar::new()));
        let release_on_drop = ReleaseOnDrop(release.clone());
        let tool_calls = Arc::new(AtomicUsize::new(0));
        let service = rmcp::service::serve_directly(
            client_handler("blocked", ProtocolVersion::V_2025_11_25, None),
            BlockedSink {
                incoming,
                sender: sender.clone(),
                entered: entered.clone(),
                release: release.clone(),
                blocked: false,
                tool_calls: tool_calls.clone(),
            },
            None,
        );
        let session = ConnectedMcp::from_running(service, Duration::from_secs(2)).await;
        tokio::time::timeout(Duration::from_secs(2), entered.notified())
            .await
            .unwrap();
        let mut handles = Vec::new();
        loop {
            // A cooperative-budget yield is not evidence that the channel is full.
            let enqueue = tokio::task::unconstrained(session.peer.send_request_with_option(
                ClientRequest::PingRequest(Default::default()),
                PeerRequestOptions::no_options(),
            ));
            tokio::pin!(enqueue);
            match futures::poll!(enqueue.as_mut()) {
                std::task::Poll::Ready(handle) => handles.push(handle.unwrap()),
                std::task::Poll::Pending => break,
            }
            assert!(handles.len() < 16_384, "the SDK channel must be bounded");
        }
        assert!(!handles.is_empty());
        let budget = Duration::from_millis(40);
        let result = tokio::time::timeout(
            Duration::from_secs(1),
            session.call_tool_timed("never-sent".into(), serde_json::json!({}), budget),
        )
        .await;
        // Always release the fixture before reporting an assertion failure.
        drop(release_on_drop);
        assert!(
            matches!(result, Ok(Err(ServiceError::Timeout { timeout })) if timeout == budget),
            "expected the enqueue deadline, got {result:?}",
        );
        session
            .request(
                ClientRequest::PingRequest(Default::default()),
                Duration::from_secs(2),
            )
            .await
            .unwrap();
        assert_eq!(
            tool_calls.load(Ordering::SeqCst),
            0,
            "a cancelled enqueue must not be sent later or replayed"
        );
        session.close().await.unwrap();
    }
}
