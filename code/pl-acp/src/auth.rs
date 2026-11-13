//! ACP 认证：协商、登录与受控探测。
//!
//! 调用方提供独占子进程的字节流（通常 stdout/stdin）与接入专属的空工作目录；本模块只编排
//! 协议步骤并返回类型化结果。物理进程、stderr 消费与最终回收不属于这里。
//!
//! 本阶段只实现 ACP v1 中已落地的能力：`initialize`、`session/new`、`authenticate`、
//! 固定 `/usage` 与 `session/close`。文件系统、终端、MCP 与 elicitation 能力一律不声明，
//! 因此不存在被对端反向请求驱动的执行路径。

use std::fmt;
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use agent_client_protocol::{
    ByteStreams, Client, Error as RpcError, ErrorCode, is_incoming_transport_closed,
};
use tokio_util::compat::{TokioAsyncReadCompatExt, TokioAsyncWriteCompatExt};

mod flow;
mod limits;
pub(crate) use flow::declared_methods;

/// 宿主提供的字节流读端。
pub use tokio::io::AsyncRead;
/// 宿主提供的字节流写端。
pub use tokio::io::AsyncWrite;
/// 宿主向持续连接发送的类型化命令通道。
pub use tokio::sync::mpsc;
/// 认证命令可观察的进度值。
pub use tokio::sync::watch;
/// 宿主导入的取消信号。
pub use tokio_util::sync::CancellationToken;

/// 一次认证命令。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthAction {
    /// 只协商并探测，不触发任何登录流程。
    Check,
    /// 已由宿主核实版本的 server 原生处理 `/usage`，不进入模型执行。
    QueryUsage,
}

/// 在原连接上继续认证；不重新协商或启动第二条连接。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthCommand {
    Authenticate { method_id: String },
}

/// 服务端声明的认证方法类型。
///
/// `Agent` 与 `Terminal` 是协议的真实分类；`Unsupported` 表示本客户端本阶段还没有对应实现，
/// 包括 SDK 未实现或协议将来新增的方法类型。`Unsupported` 永远不会被发送 `authenticate`。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AuthMethodKind {
    /// Agent 自己处理登录，客户端可以调用 `authenticate`。
    Agent,
    /// 需要客户端以交互终端重新运行 Agent 程序；本阶段没有实现。
    Terminal,
    /// 本阶段没有对应实现的方法类型。
    Unsupported,
}

/// 服务端声明的单个认证方法。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuthMethod {
    /// 方法 ID，仅在服务端声明范围内有效。
    pub id: String,
    /// 展示名称。
    pub name: String,
    /// 可选描述。
    pub description: Option<String>,
    /// 方法类型；`Terminal` 与 `Unsupported` 都表示本阶段不能向它们发送 `authenticate`。
    pub kind: AuthMethodKind,
}

/// `initialize` 协商出的服务端身份。
///
/// ACP v1 允许对端省略 `agentInfo`；仅指定模板版本要求时拒绝缺失身份。
/// 字段始终是真实观察值，本模块不用空串哨兵，也不用账号名冒充服务端身份。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerInfo {
    /// 程序化名称。
    pub name: String,
    /// 面向用户的名称。
    pub title: Option<String>,
    /// 服务端版本。
    pub version: String,
}

/// 认证进度；只表达当前步骤，不表示结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthProgress {
    /// 协商 ACP v1 能力。
    Initializing,
    /// 原连接等待宿主选择服务端实际声明的方法，仍然可取消。
    Required {
        server: Option<ServerInfo>,
        methods: Vec<AuthMethod>,
    },
    /// 等待服务端完成登录。
    Authenticating { method_id: String },
    /// 用探测会话验证当前凭据。
    Verifying,
    /// 释放探测会话并收束连接。
    Closing,
}

/// 一次认证命令的终态。
///
/// `server` 是 `initialize` 实际观察到的身份；指定模板版本要求时须通过精确核对。
/// 不使用空字符串哨兵，也不以接入配置中的账号名代替。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthOutcome {
    /// 探测会话建立成功，证明当时凭据可用。
    Verified {
        /// 协商出的服务端身份。
        server: Option<ServerInfo>,
        /// 仅显式额度动作返回报告；普通检查、登录不发送 prompt。
        usage: Option<UsageReport>,
    },
}

/// 固定额度命令的文本报告或安全失败类别；由产品供应商边界解析文本。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UsageReport {
    Text(String),
    Failed(UsageFailure),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UsageFailure {
    Query,
    Timeout,
    Transport,
    ResourceLimit,
}

/// 一条连接的资源关闭预算；首次收束时启动，所有后续阶段共享同一期限。
///
/// 业务请求与人工授权不会读取此期限。期限耗尽只是清理失败，宿主仍保留未结束资源。
#[derive(Debug, Clone)]
pub struct CleanupBudget {
    timeout: Duration,
    deadline: Arc<OnceLock<tokio::time::Instant>>,
}

impl CleanupBudget {
    pub fn new(timeout: Duration) -> Self {
        Self {
            timeout,
            deadline: Arc::new(OnceLock::new()),
        }
    }

    /// 首次调用开始关闭；克隆对象共享该时刻，不能为下个阶段重新计时。
    pub fn deadline(&self) -> tokio::time::Instant {
        *self
            .deadline
            .get_or_init(|| tokio::time::Instant::now() + self.timeout)
    }
}

/// 一次认证命令的输入。
#[derive(Debug)]
pub struct AuthRequest {
    /// 可选的模板版本要求；`Some` 在任何认证或探测前按原字符串精确核对。
    /// `None` 不要求身份信息，但仍要求 ACP v1；不使用空字符串、trim 或版本回退。
    pub expected_server_version: Option<String>,
    /// 探测会话使用的绝对工作目录，由宿主提供接入专属空目录。
    pub probe_cwd: String,
    /// 要执行的命令。
    pub action: AuthAction,
    /// 仅在 `Required` 阶段接受的继续认证命令。
    pub commands: mpsc::Receiver<AuthCommand>,
    /// 宿主统一资源关闭预算；只约束会话关闭和 SDK 排空，不限制人工授权。
    pub cleanup: CleanupBudget,
    /// 宿主取消信号；命中后按类型化取消结束。
    pub cancellation: CancellationToken,
    /// 进度发布端；宿主用它驱动 UI 阶段，不参与结果判定。
    pub progress: watch::Sender<AuthProgress>,
}

/// 类型化失败类别。调用方据此选择恢复动作，不解析诊断文本。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AuthFailureKind {
    /// 字节流中断或写入失败。
    Transport,
    /// 对端响应不符合已实现的能力范围。
    Protocol,
    /// 对端协商出本客户端不支持的协议版本。
    UnsupportedVersion,
    /// 服务端身份缺失，或其版本与宿主要求的原字符串不相等；阶段固定为 [`AuthStage::Initialize`]。
    ServerVersionMismatch,
    /// 请求的认证方法不存在、类型不符或本阶段未实现。
    UnsupportedMethod,
    /// 登录流程本身失败。
    Authentication,
    /// 探测会话失败（非登录要求）。
    Probe,
    /// 阶段预算耗尽。
    Timeout,
    /// 宿主取消。
    Cancelled,
    /// 入站字节预算耗尽。
    ResourceLimit,
    /// 远端探测会话关闭失败，阶段固定为 [`AuthStage::Close`]。
    Cleanup,
}

impl fmt::Display for AuthFailureKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = match self {
            Self::Transport => "Transport",
            Self::Protocol => "Protocol",
            Self::UnsupportedVersion => "UnsupportedVersion",
            Self::ServerVersionMismatch => "ServerVersionMismatch",
            Self::UnsupportedMethod => "UnsupportedMethod",
            Self::Authentication => "Authentication",
            Self::Probe => "Probe",
            Self::Timeout => "Timeout",
            Self::Cancelled => "Cancelled",
            Self::ResourceLimit => "ResourceLimit",
            Self::Cleanup => "Cleanup",
        };
        f.write_str(name)
    }
}

/// 失败发生阶段。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AuthStage {
    /// ACP 协商。
    Initialize,
    /// 登录请求。
    Authenticate,
    /// 探测会话。
    Probe,
    /// 探测会话关闭与连接收束。
    Close,
}

impl fmt::Display for AuthStage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = match self {
            Self::Initialize => "Initialize",
            Self::Authenticate => "Authenticate",
            Self::Probe => "Probe",
            Self::Close => "Close",
        };
        f.write_str(name)
    }
}

/// 类型化认证失败。
///
/// 对外只暴露类别、阶段与可选 JSON-RPC 错误码。协议层失败原始对象由私有的脱敏包装持有：
/// 它保留 SDK 错误以便内部诊断与错误链归属，但没有公开 getter，`Debug`/`Display`/`source`
/// 都只显示码值，避免服务端消息、URL 与凭据提示经渲染进入 UI 或日志。面向用户的说明由类别
/// 与阶段映射生成。
pub struct AuthError {
    kind: AuthFailureKind,
    stage: AuthStage,
    source: Option<RedactedRpcFailure>,
}

impl AuthError {
    /// 失败类别。
    #[must_use]
    pub fn kind(&self) -> AuthFailureKind {
        self.kind
    }

    /// 失败阶段。
    #[must_use]
    pub fn stage(&self) -> AuthStage {
        self.stage
    }

    /// 服务端 JSON-RPC 错误码，仅用于安全诊断，不参与恢复决策。
    #[must_use]
    pub fn rpc_code(&self) -> Option<i32> {
        self.source.as_ref().map(RedactedRpcFailure::code)
    }

    /// 本次失败是否是服务端要求登录。
    pub(crate) fn is_auth_required(&self) -> bool {
        self.source
            .as_ref()
            .is_some_and(RedactedRpcFailure::is_auth_required)
    }

    fn new(kind: AuthFailureKind, stage: AuthStage) -> Self {
        Self {
            kind,
            stage,
            source: None,
        }
    }

    fn timeout(stage: AuthStage) -> Self {
        Self::new(AuthFailureKind::Timeout, stage)
    }

    fn cancelled(stage: AuthStage) -> Self {
        Self::new(AuthFailureKind::Cancelled, stage)
    }

    /// 对端协商出本客户端尚未实现的协议版本。
    fn unsupported_version() -> Self {
        Self::new(AuthFailureKind::UnsupportedVersion, AuthStage::Initialize)
    }

    /// 服务端身份缺失或版本不符；不保留或展示对端提供的不可信版本文本。
    fn server_version_mismatch() -> Self {
        Self::new(
            AuthFailureKind::ServerVersionMismatch,
            AuthStage::Initialize,
        )
    }

    /// 请求的方法不存在、类型不符或本阶段未实现；该失败在发送登录请求之前产生。
    fn unsupported_method() -> Self {
        Self::new(AuthFailureKind::UnsupportedMethod, AuthStage::Authenticate)
    }

    /// 记录协议层失败：原始 SDK 错误由私有包装对象保留，渲染只暴露类别与码值。
    fn rpc(stage: AuthStage, kind: AuthFailureKind, error: RpcError) -> Self {
        Self {
            kind,
            stage,
            source: Some(RedactedRpcFailure { error }),
        }
    }

    /// 对端或连接失败：入站预算耗尽按资源限制；流层已记录真实读/写失败或对端 EOF 按传输
    /// 失败；其余用调用方指定的阶段默认类别（如探测为 `Probe`、远端会话关闭为 `Cleanup`）。
    fn peer_failure(
        stage: AuthStage,
        peer_kind: AuthFailureKind,
        error: RpcError,
        stream: &limits::StreamGuard,
    ) -> Self {
        let kind = if stream.budget_exhausted() {
            AuthFailureKind::ResourceLimit
        } else if stream.io_failed() || is_incoming_transport_closed(&error) {
            AuthFailureKind::Transport
        } else {
            peer_kind
        };
        Self::rpc(stage, kind, error)
    }
}

impl fmt::Debug for AuthError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("AuthError")
            .field("kind", &self.kind)
            .field("stage", &self.stage)
            .field("rpc_code", &self.rpc_code())
            .finish_non_exhaustive()
    }
}

impl fmt::Display for AuthError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ACP 认证失败（阶段：{}，类别：{}）",
            self.stage, self.kind
        )?;
        if let Some(code) = self.rpc_code() {
            write!(f, "，RPC 码：{code}")?;
        }
        Ok(())
    }
}

impl std::error::Error for AuthError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.source
            .as_ref()
            .map(|source| source as &(dyn std::error::Error + 'static))
    }
}

/// 私有安全边界：真正拥有 SDK 原始错误，但任何渲染都只暴露码值。
///
/// 原始错误没有公开 getter，也不会进入日志或 UI；它的 `message`/`data` 可能包含服务端 URL、
/// 凭据提示或其他自由文本，因此不出现在 `Debug`/`Display` 中。`Error::source` 也不继续暴露
/// 内部原始对象，避免调用方（含 anyhow 之类会遍历 source 链的渲染）绕过脱敏边界。
struct RedactedRpcFailure {
    error: RpcError,
}

impl RedactedRpcFailure {
    fn code(&self) -> i32 {
        i32::from(self.error.code)
    }

    fn is_auth_required(&self) -> bool {
        self.error.code == ErrorCode::AUTH_REQUIRED
    }
}

impl fmt::Debug for RedactedRpcFailure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("RedactedRpcFailure")
            .field("code", &self.code())
            .finish_non_exhaustive()
    }
}

impl fmt::Display for RedactedRpcFailure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "ACP JSON-RPC 失败，码 {}", self.code())
    }
}

impl std::error::Error for RedactedRpcFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        // 原始错误只在此对象内部存在，不作为 source 继续外露。
        None
    }
}

/// 在给定字节流上驱动一条持续认证连接。
///
/// `AuthRequired` 通过进度发布，连接保留并等待宿主命令。初始化、人工授权与探测只等待
/// 实际响应、断连或取消；结果未知的请求不重发。前台结束后才使用宿主提供的统一关闭预算，
/// 等待 SDK 排空与写端关闭。清理失败优先于业务结果，物理进程仍由宿主负责回收。
///
/// # Errors
/// 返回带阶段与安全 RPC 错误码的 [`AuthError`]；版本不匹配时不会发送登录或探测请求。
pub async fn run_connection<W, R>(
    outgoing: W,
    incoming: R,
    request: AuthRequest,
) -> Result<AuthOutcome, AuthError>
where
    W: AsyncWrite + Unpin + Send + 'static,
    R: AsyncRead + Unpin + Send + 'static,
{
    let cleanup = request.cleanup.clone();
    let stream = limits::StreamGuard::new();
    let observed = request.progress.clone();
    let transport = ByteStreams::new(
        limits::GuardedWriter::new(outgoing, stream.clone()).compat_write(),
        limits::BudgetedReader::new(incoming, limits::INPUT_BYTE_BUDGET, stream.clone()).compat(),
    );
    let flow_stream = stream.clone();
    let (foreground_tx, mut foreground_rx) = tokio::sync::oneshot::channel();
    let connection =
        Client
            .v1()
            .name("anywork-acp-auth")
            .connect_with(transport, async move |connection| {
                let outcome = flow::negotiate(connection, request, flow_stream).await;
                // 前台结论只在这里发布一次；随后 SDK 的排空不再改动它。
                let _ = foreground_tx.send(outcome);
                Ok(())
            });
    let mut connection = std::pin::pin!(connection);

    // 阶段一：等前台发布结论，期间必须持续驱动连接 future。
    let phase = tokio::select! {
        result = &mut foreground_rx => Phase::Published(result.ok()),
        result = &mut connection => Phase::Finished(result),
    };

    match phase {
        // 前台已结束：此后才为 SDK 收束另起预算。
        Phase::Published(Some(observed_outcome)) => {
            match tokio::time::timeout_at(cleanup.deadline(), connection.as_mut()).await {
                // 只有 SDK 收束成功，才发布前台协议结果。
                Ok(Ok(())) => observed_outcome,
                // 收束失败按实际类别上报（真实读/写失败是 `Transport`，预算是 `ResourceLimit`）；
                // 前台结论被丢弃，不能被当作已收束。
                Ok(Err(error)) => Err(AuthError::peer_failure(
                    AuthStage::Close,
                    AuthFailureKind::Protocol,
                    error,
                    &stream,
                )),
                // 收束超时一律 `Timeout`@`Close`：协议取消或认证失败都不代表资源已收束。
                Err(_elapsed) => Err(AuthError::timeout(AuthStage::Close)),
            }
        }
        // 前台 future 被丢弃且没有发布结论：连接在得出结论前就终止了。
        Phase::Published(None) => {
            let stage = last_stage(&observed);
            let failure =
                match tokio::time::timeout_at(cleanup.deadline(), connection.as_mut()).await {
                    Ok(Ok(())) => AuthError::new(AuthFailureKind::Protocol, stage),
                    Ok(Err(error)) => {
                        AuthError::peer_failure(stage, AuthFailureKind::Protocol, error, &stream)
                    }
                    Err(_elapsed) => AuthError::timeout(AuthStage::Close),
                };
            Err(failure)
        }
        // 连接先结束：`main_fn` 先发布结论再返回，因此结论通常已经可取。
        Phase::Finished(result) => match (foreground_rx.await.ok(), result) {
            // 收束完整完成：可以发布前台结论。
            (Some(observed_outcome), Ok(())) => observed_outcome,
            // 收束失败优先于前台结论：前台结果（含取消）被丢弃。
            (Some(_observed), Err(error)) => Err(AuthError::peer_failure(
                AuthStage::Close,
                AuthFailureKind::Protocol,
                error,
                &stream,
            )),
            // 防御分支：`main_fn` 总是先发布再返回，因此连接正常结束时应已有结论；
            // 真到这里只说明结论没有被发布，按协议失败上报而不是伪造成功。
            (None, Ok(())) => Err(AuthError::new(
                AuthFailureKind::Protocol,
                last_stage(&observed),
            )),
            (None, Err(error)) => Err(AuthError::peer_failure(
                last_stage(&observed),
                AuthFailureKind::Protocol,
                error,
                &stream,
            )),
        },
    }
}

/// 阶段一的两个可能终局。
enum Phase {
    /// 前台发布了结论（`None` 表示发送端被丢弃、没有结论）。
    Published(Option<Result<AuthOutcome, AuthError>>),
    /// 连接 future 先结束。
    Finished(Result<(), RpcError>),
}

/// 把最后发布的进度还原为阶段，供连接级失败定位。
fn last_stage(progress: &watch::Sender<AuthProgress>) -> AuthStage {
    match &*progress.borrow() {
        AuthProgress::Initializing => AuthStage::Initialize,
        AuthProgress::Required { .. } | AuthProgress::Authenticating { .. } => {
            AuthStage::Authenticate
        }
        AuthProgress::Verifying => AuthStage::Probe,
        AuthProgress::Closing => AuthStage::Close,
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex, PoisonError};
    use std::time::Duration;

    use agent_client_protocol::schema::ProtocolVersion;
    use agent_client_protocol::v1::schema::{
        AgentCapabilities, AuthMethod as SdkAuthMethod, AuthMethodAgent, AuthMethodTerminal,
        AuthenticateRequest, AuthenticateResponse, CloseSessionRequest, CloseSessionResponse,
        ContentBlock, ContentChunk, Implementation, InitializeRequest, InitializeResponse,
        NewSessionRequest, NewSessionResponse, PromptRequest, PromptResponse, SessionCapabilities,
        SessionCloseCapabilities, SessionNotification, SessionUpdate, StopReason, TextContent,
    };
    use agent_client_protocol::v1::{ConnectionTo, Responder};
    use agent_client_protocol::{Agent, Client};

    use super::*;

    const VERSION: &str = "1.4.5";
    const METHOD: &str = "fixture-login";
    const REPORT: &str = "### Quota Limits\n- No quota limits reported.";

    #[derive(Clone, Copy, Default)]
    enum Choice {
        #[default]
        Authenticate,
        Cancel,
        Disconnect,
        Unsupported,
    }

    #[derive(Clone, Copy, Default)]
    struct Scenario {
        initialize_delay: Duration,
        probe_delay: Duration,
        authenticate_delay: Duration,
        human_delay: Duration,
        requires_login: bool,
        deny_after_auth: bool,
        close_failure: bool,
        prompt_failure: bool,
        cancel_at: Option<AuthStage>,
        choice: Choice,
        unrestricted_version: bool,
        omit_agent_info: bool,
        wrong_server_version: bool,
        terminal_method: bool,
    }

    #[derive(Default, Debug)]
    struct Observed {
        initializes: usize,
        probes: usize,
        authenticates: usize,
        closes: usize,
        prompts: Vec<Vec<ContentBlock>>,
        default_capabilities: bool,
        public_methods: Vec<AuthMethod>,
    }

    async fn run(
        action: AuthAction,
        scenario: Scenario,
    ) -> (Result<AuthOutcome, AuthError>, Observed) {
        let observed = Arc::new(Mutex::new(Observed::default()));
        let cancellation = CancellationToken::new();
        let disconnect = CancellationToken::new();
        let (client_writer, agent_reader) = tokio::io::duplex(64 * 1024);
        let (agent_writer, client_reader) = tokio::io::duplex(64 * 1024);
        let transport = ByteStreams::new(agent_writer.compat_write(), agent_reader.compat());
        let agent_observed = Arc::clone(&observed);
        let agent_cancel = cancellation.clone();
        let agent_disconnect = disconnect.clone();
        let agent = tokio::spawn(async move {
            Agent.v1()
            .on_receive_request({
                let observed = agent_observed.clone();
                let cancel = agent_cancel.clone();
                async move |request: InitializeRequest, responder: Responder<InitializeResponse>, _: ConnectionTo<Client>| {
                    {
                        let mut observed = observed.lock().unwrap_or_else(PoisonError::into_inner);
                        observed.initializes += 1;
                        observed.default_capabilities = request.client_capabilities == Default::default();
                    }
                    tokio::time::sleep(scenario.initialize_delay).await;
                    if scenario.cancel_at == Some(AuthStage::Initialize) { cancel.cancel(); }
                    responder.respond(InitializeResponse::new(ProtocolVersion::V1)
                        .agent_info((!scenario.omit_agent_info).then(|| Implementation::new(
                            "fixture", if scenario.wrong_server_version { "different" } else { VERSION },
                        )))
                        .auth_methods(if scenario.terminal_method {
                            vec![SdkAuthMethod::Terminal(AuthMethodTerminal::new(METHOD, "Terminal login"))]
                        } else {
                            vec![SdkAuthMethod::Agent(AuthMethodAgent::new(METHOD, "Fixture login"))]
                        })
                        .agent_capabilities(AgentCapabilities::new().session_capabilities(
                            SessionCapabilities::new().close(SessionCloseCapabilities::new()))))
                }
            }, agent_client_protocol::on_receive_request!())
            .on_receive_request({
                let observed = agent_observed.clone();
                let cancel = agent_cancel.clone();
                async move |_: NewSessionRequest, responder: Responder<NewSessionResponse>, _: ConnectionTo<Client>| {
                    let required = {
                        let mut observed = observed.lock().unwrap_or_else(PoisonError::into_inner);
                        observed.probes += 1;
                        scenario.requires_login && (observed.authenticates == 0 || scenario.deny_after_auth)
                    };
                    tokio::time::sleep(scenario.probe_delay).await;
                    if scenario.cancel_at == Some(AuthStage::Probe) { cancel.cancel(); }
                    if required { responder.respond_with_error(RpcError::auth_required()) }
                    else { responder.respond(NewSessionResponse::new("probe")) }
                }
            }, agent_client_protocol::on_receive_request!())
            .on_receive_request({
                let observed = agent_observed.clone();
                let cancel = agent_cancel.clone();
                async move |request: AuthenticateRequest, responder: Responder<AuthenticateResponse>, _: ConnectionTo<Client>| {
                    assert_eq!(request.method_id.to_string(), METHOD);
                    observed.lock().unwrap_or_else(PoisonError::into_inner).authenticates += 1;
                    tokio::time::sleep(scenario.authenticate_delay).await;
                    if scenario.cancel_at == Some(AuthStage::Authenticate) { cancel.cancel(); }
                    responder.respond(AuthenticateResponse::default())
                }
            }, agent_client_protocol::on_receive_request!())
            .on_receive_request({
                let observed = agent_observed.clone();
                async move |request: PromptRequest, responder: Responder<PromptResponse>, connection: ConnectionTo<Client>| {
                    observed.lock().unwrap_or_else(PoisonError::into_inner).prompts.push(request.prompt);
                    connection.send_notification(SessionNotification::new(request.session_id.clone(),
                        SessionUpdate::AgentThoughtChunk(ContentChunk::new(ContentBlock::Text(TextContent::new("not quota"))))))?;
                    connection.send_notification(SessionNotification::new(request.session_id,
                        SessionUpdate::AgentMessageChunk(ContentChunk::new(ContentBlock::Text(TextContent::new(REPORT))))))?;
                    if scenario.prompt_failure { responder.respond_with_error(RpcError::auth_required()) }
                    else { responder.respond(PromptResponse::new(StopReason::EndTurn)) }
                }
            }, agent_client_protocol::on_receive_request!())
            .on_receive_request({
                let observed = agent_observed.clone();
                async move |_: CloseSessionRequest, responder: Responder<CloseSessionResponse>, _: ConnectionTo<Client>| {
                    observed.lock().unwrap_or_else(PoisonError::into_inner).closes += 1;
                    if scenario.close_failure { responder.respond_with_error(RpcError::internal_error()) }
                    else { responder.respond(CloseSessionResponse::default()) }
                }
            }, agent_client_protocol::on_receive_request!())
            .connect_with(transport, async move |cx| {
                tokio::select! { () = cx.incoming_closed() => {}, () = agent_disconnect.cancelled() => {} }
                Ok(())
            }).await
        });
        let (progress, mut observer) = watch::channel(AuthProgress::Initializing);
        let (sender, commands) = mpsc::channel(1);
        let drive = async {
            let mut required_count = 0;
            while observer.changed().await.is_ok() {
                let required = if let AuthProgress::Required { methods, .. } =
                    &*observer.borrow_and_update()
                {
                    observed.lock().unwrap().public_methods = methods.clone();
                    true
                } else {
                    false
                };
                if !required {
                    continue;
                }
                required_count += 1;
                tokio::time::sleep(scenario.human_delay).await;
                if required_count > 1 {
                    cancellation.cancel();
                    continue;
                }
                match scenario.choice {
                    Choice::Authenticate => sender
                        .send(AuthCommand::Authenticate {
                            method_id: METHOD.into(),
                        })
                        .await
                        .expect("live connection"),
                    Choice::Unsupported => sender
                        .send(AuthCommand::Authenticate {
                            method_id: "undeclared".into(),
                        })
                        .await
                        .expect("live connection"),
                    Choice::Cancel => cancellation.cancel(),
                    Choice::Disconnect => disconnect.cancel(),
                }
            }
        };
        let flow = run_connection(
            client_writer,
            client_reader,
            AuthRequest {
                expected_server_version: (!scenario.unrestricted_version).then(|| VERSION.into()),
                probe_cwd: "/tmp".into(),
                action,
                commands,
                cleanup: CleanupBudget::new(Duration::from_secs(5)),
                cancellation: cancellation.clone(),
                progress,
            },
        );
        let (outcome, ()) = tokio::time::timeout(Duration::from_secs(4000), async {
            tokio::join!(flow, drive)
        })
        .await
        .expect("fixture must settle by events");
        agent
            .await
            .expect("fixture task joins")
            .expect("fixture SDK drains");
        let observed = Arc::into_inner(observed)
            .expect("fixture releases state")
            .into_inner()
            .unwrap_or_else(PoisonError::into_inner);
        (outcome, observed)
    }

    #[tokio::test]
    async fn generic_auth_accepts_missing_identity_but_templates_require_exact_version() {
        for (unrestricted_version, omit_agent_info, wrong_server_version, success) in [
            (true, true, false, true),
            (true, false, true, true),
            (false, true, false, false),
            (false, false, true, false),
        ] {
            let (outcome, observed) = run(
                AuthAction::Check,
                Scenario {
                    unrestricted_version,
                    omit_agent_info,
                    wrong_server_version,
                    ..Scenario::default()
                },
            )
            .await;
            if success {
                assert!(matches!(outcome, Ok(AuthOutcome::Verified { .. })));
                assert_eq!(observed.probes, 1);
            } else {
                let error = outcome.unwrap_err();
                assert_eq!(error.kind(), AuthFailureKind::ServerVersionMismatch);
                assert_eq!(observed.probes, 0);
                assert_eq!(observed.authenticates, 0);
            }
        }
    }

    #[tokio::test]
    async fn generic_auth_still_requires_v1_and_never_advertises_or_authenticates_terminal() {
        // Agent.v1() normalizes its outgoing initialize response to v1. Use the SDK's raw
        // role for a deliberately invalid peer, retaining SDK dispatch, responder and framing.
        use agent_client_protocol::UntypedRole;
        let (client_writer, agent_reader) = tokio::io::duplex(64 * 1024);
        let (agent_writer, client_reader) = tokio::io::duplex(64 * 1024);
        let peer = tokio::spawn(
        UntypedRole
            .builder()
            .on_receive_request(
                async |_: InitializeRequest,
                       responder: agent_client_protocol::Responder<InitializeResponse>,
                       _: agent_client_protocol::ConnectionTo<UntypedRole>| {
                    responder.respond(InitializeResponse::new(ProtocolVersion::V0))
                },
                agent_client_protocol::on_receive_request!(),
            )
            .on_receive_request(
                async |_: NewSessionRequest,
                       _: agent_client_protocol::Responder<NewSessionResponse>,
                       _: agent_client_protocol::ConnectionTo<UntypedRole>|
                       -> Result<(), RpcError> {
                    panic!("an unsupported protocol must fail before session/new")
                },
                agent_client_protocol::on_receive_request!(),
            )
            .connect_with(
                ByteStreams::new(agent_writer.compat_write(), agent_reader.compat()),
                async |connection| {
                    connection.incoming_closed().await;
                    Ok(())
                },
            ),
    );
        let (progress, _observer) = watch::channel(AuthProgress::Initializing);
        let (_commands, commands) = mpsc::channel(1);
        let outcome = run_connection(
            client_writer,
            client_reader,
            AuthRequest {
                expected_server_version: None,
                probe_cwd: "/unused-probe".into(),
                action: AuthAction::Check,
                commands,
                cleanup: CleanupBudget::new(Duration::from_secs(2)),
                cancellation: CancellationToken::new(),
                progress,
            },
        )
        .await;
        // The official v1 client rejects the response before returning a typed InitializeResponse.
        let error = outcome.unwrap_err();
        assert_eq!(error.kind(), AuthFailureKind::Protocol);
        assert_eq!(error.stage(), AuthStage::Initialize);
        assert_eq!(
            error.rpc_code(),
            Some(i32::from(agent_client_protocol::ErrorCode::INVALID_REQUEST))
        );
        peer.await.unwrap().unwrap();
        let (outcome, observed) = run(
            AuthAction::Check,
            Scenario {
                requires_login: true,
                terminal_method: true,
                ..Scenario::default()
            },
        )
        .await;
        assert_eq!(
            outcome.unwrap_err().kind(),
            AuthFailureKind::UnsupportedMethod
        );
        assert!(observed.public_methods.is_empty());
        assert_eq!(observed.authenticates, 0);
    }

    #[tokio::test(start_paused = true)]
    async fn slow_authorization_keeps_one_connection_past_all_former_deadlines() {
        let (outcome, observed) = run(
            AuthAction::Check,
            Scenario {
                initialize_delay: Duration::from_secs(181),
                probe_delay: Duration::from_secs(61),
                authenticate_delay: Duration::from_secs(901),
                human_delay: Duration::from_secs(901),
                requires_login: true,
                ..Scenario::default()
            },
        )
        .await;
        assert!(matches!(
            outcome,
            Ok(AuthOutcome::Verified { usage: None, .. })
        ));
        assert_eq!(
            (
                observed.initializes,
                observed.probes,
                observed.authenticates,
                observed.closes
            ),
            (1, 2, 1, 1)
        );
        assert!(observed.default_capabilities);
        assert!(observed.prompts.is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn successful_authenticate_still_requires_a_successful_session() {
        let (outcome, observed) = run(
            AuthAction::Check,
            Scenario {
                requires_login: true,
                deny_after_auth: true,
                ..Scenario::default()
            },
        )
        .await;
        assert_eq!(
            outcome
                .expect_err("rejected second probe must not verify")
                .kind(),
            AuthFailureKind::Cancelled
        );
        assert_eq!(
            (
                observed.initializes,
                observed.probes,
                observed.authenticates,
                observed.closes
            ),
            (1, 2, 1, 0)
        );
    }

    #[tokio::test(start_paused = true)]
    async fn cancellation_wins_over_responses_at_each_business_stage() {
        for stage in [
            AuthStage::Initialize,
            AuthStage::Authenticate,
            AuthStage::Probe,
        ] {
            let (outcome, _) = run(
                AuthAction::Check,
                Scenario {
                    requires_login: true,
                    cancel_at: Some(stage),
                    ..Scenario::default()
                },
            )
            .await;
            let error = outcome.expect_err("accepted cancellation wins");
            assert_eq!(
                (error.kind(), error.stage()),
                (AuthFailureKind::Cancelled, stage)
            );
        }
    }

    #[tokio::test(start_paused = true)]
    async fn required_state_can_cancel_without_sending_authenticate() {
        let (outcome, observed) = run(
            AuthAction::Check,
            Scenario {
                requires_login: true,
                choice: Choice::Cancel,
                ..Scenario::default()
            },
        )
        .await;
        assert_eq!(
            outcome.expect_err("cancelled").kind(),
            AuthFailureKind::Cancelled
        );
        assert_eq!(observed.authenticates, 0);
    }

    #[tokio::test(start_paused = true)]
    async fn connection_close_while_waiting_for_user_settles_without_another_command() {
        let (outcome, observed) = run(
            AuthAction::Check,
            Scenario {
                requires_login: true,
                choice: Choice::Disconnect,
                ..Scenario::default()
            },
        )
        .await;
        assert_eq!(
            outcome.expect_err("closed transport").kind(),
            AuthFailureKind::Transport
        );
        assert_eq!(observed.authenticates, 0);
    }

    #[tokio::test(start_paused = true)]
    async fn undeclared_method_is_never_sent_to_agent() {
        let (outcome, observed) = run(
            AuthAction::Check,
            Scenario {
                requires_login: true,
                choice: Choice::Unsupported,
                ..Scenario::default()
            },
        )
        .await;
        assert_eq!(
            outcome.expect_err("unsupported method").kind(),
            AuthFailureKind::UnsupportedMethod
        );
        assert_eq!(observed.authenticates, 0);
    }

    #[tokio::test(start_paused = true)]
    async fn close_failure_does_not_publish_verified() {
        let (outcome, observed) = run(
            AuthAction::Check,
            Scenario {
                close_failure: true,
                ..Scenario::default()
            },
        )
        .await;
        let error = outcome.expect_err("close failed");
        assert_eq!(
            (error.kind(), error.stage()),
            (AuthFailureKind::Cleanup, AuthStage::Close)
        );
        assert_eq!(observed.closes, 1);
    }

    #[tokio::test(start_paused = true)]
    async fn usage_prompt_error_remains_nested_and_the_probe_is_closed() {
        let (outcome, observed) = run(
            AuthAction::QueryUsage,
            Scenario {
                prompt_failure: true,
                ..Scenario::default()
            },
        )
        .await;
        assert!(matches!(
            outcome,
            Ok(AuthOutcome::Verified {
                usage: Some(UsageReport::Failed(UsageFailure::Query)),
                ..
            })
        ));
        assert_eq!(observed.probes, 1);
        assert_eq!(observed.authenticates, 0);
        assert_eq!(observed.closes, 1);
        assert_eq!(observed.prompts.len(), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn checks_never_prompt_and_explicit_usage_only_sends_fixed_command() {
        let (outcome, observed) = run(AuthAction::Check, Scenario::default()).await;
        assert!(matches!(
            outcome,
            Ok(AuthOutcome::Verified { usage: None, .. })
        ));
        assert!(observed.prompts.is_empty());
        let (outcome, observed) = run(
            AuthAction::QueryUsage,
            Scenario {
                requires_login: true,
                ..Scenario::default()
            },
        )
        .await;
        assert!(
            matches!(outcome, Ok(AuthOutcome::Verified { usage: Some(UsageReport::Text(ref text)), .. }) if text == REPORT)
        );
        assert_eq!(
            observed.prompts,
            vec![vec![ContentBlock::Text(TextContent::new("/usage"))]]
        );
        assert_eq!(
            (
                observed.initializes,
                observed.authenticates,
                observed.closes
            ),
            (1, 1, 1)
        );
    }
}
