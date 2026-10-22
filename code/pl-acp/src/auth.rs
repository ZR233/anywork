//! ACP 认证：协商、登录与受控探测。
//!
//! 调用方提供独占子进程的字节流（通常 stdout/stdin）与接入专属的空工作目录；本模块只编排
//! 协议步骤并返回类型化结果。物理进程、stderr 消费与最终回收不属于这里。
//!
//! 本阶段只实现 ACP v1 中已落地的能力：`initialize`、`session/new`、`authenticate` 与
//! `session/close`。文件系统、终端、MCP 与 elicitation 能力一律不声明，因此不存在被对端
//! 反向请求驱动的执行路径。

use std::fmt;

use agent_client_protocol::{
    ByteStreams, Client, Error as RpcError, ErrorCode, is_incoming_transport_closed,
};
use tokio_util::compat::{TokioAsyncReadCompatExt, TokioAsyncWriteCompatExt};

mod flow;
mod limits;

/// 宿主提供的字节流读端。
pub use tokio::io::AsyncRead;
/// 宿主提供的字节流写端。
pub use tokio::io::AsyncWrite;
/// 认证命令可观察的进度值。
pub use tokio::sync::watch;
/// 宿主导入的取消信号。
pub use tokio_util::sync::CancellationToken;

/// 一次认证命令。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthAction {
    /// 只协商并探测，不触发任何登录流程。
    Check,
    /// 使用服务端已声明的方法执行登录。
    Authenticate {
        /// 服务端在 `initialize` 中声明的方法 ID。
        method_id: String,
    },
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
/// ACP v1 允许对端省略 `agentInfo`；此时认证终态里的 `server` 就是 `None`，`ServerInfo`
/// 自身字段始终是真实观察值，本模块不用空串哨兵，也不用账号名冒充服务端身份。
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
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AuthProgress {
    /// 协商 ACP v1 能力。
    Initializing,
    /// 等待服务端完成登录。
    Authenticating,
    /// 用探测会话验证当前凭据。
    Verifying,
    /// 释放探测会话并收束连接。
    Closing,
}

/// 一次认证命令的终态。
///
/// `server` 是 `initialize` 实际观察到的身份：对端省略 `agentInfo`（ACP v1 允许）时为 `None`，
/// 不使用空字符串哨兵，也不以接入配置中的账号名代替服务端身份。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthOutcome {
    /// 服务端要求登录，附带其实际声明的方法。
    Required {
        /// 协商出的服务端身份。
        server: Option<ServerInfo>,
        /// 服务端实际声明的方法，可能包含本阶段不支持的 `Terminal`。
        methods: Vec<AuthMethod>,
    },
    /// 探测会话建立成功，证明当时凭据可用。
    Verified {
        /// 协商出的服务端身份。
        server: Option<ServerInfo>,
    },
}

/// 一次认证命令的输入。
#[derive(Debug)]
pub struct AuthRequest {
    /// 探测会话使用的绝对工作目录，由宿主提供接入专属空目录。
    pub probe_cwd: String,
    /// 要执行的命令。
    pub action: AuthAction,
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
        self.error.code == ErrorCode::AuthRequired
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

/// 在给定双向字节流上执行一次认证命令。
///
/// `outgoing`/`incoming` 由宿主提供，通常是独占子进程的 stdin/stdout。建立探测会话后，若
/// 服务端声明 `session/close` 能力则先关闭该会话（不观察取消，只受关闭预算限制）；未声明时
/// 由宿主回收独占进程。
///
/// 收束语义按官方 SDK 当前实现：前台协议步骤返回后，SDK 停止入站投递、把已接受的输出经协议
/// actor 排空并等待物理写出端完成（`ConnectionTo::drain_outgoing`），随后随连接 future 一起
/// 丢弃仍持有的入站读取端。本函数自己从不派发任务；若收束没能在预算内完成，连接 future（连同
/// 它持有的 SDK 任务与字节流）随返回一起被丢弃，而不是留在后台继续运行。物理进程、stderr 与
/// 管道仍由宿主在本函数返回后关闭。
///
/// 取消与阶段超时都是类型化失败；结果未知时不自动重发 `session/new`。
///
/// 预算分两段（实现常量，可按真实耗时调整）：前台协议步骤各自限时——协商 30 秒、探测 60 秒、
/// 人工登录 15 分钟、`session/close` 10 秒；**前台协议步骤返回并发布结论之后**才为 SDK 收束
/// 另起 10 秒预算，只覆盖排空与关闭写端，不从连接建立起算，因此不会截断人工登录。单次命令的
/// 入站字节上限为 8 MiB。
///
/// 收束（排空/flush/shutdown）超时或失败时，本函数放弃继续驱动连接 future：这是释放本地
/// future 与它持有的字节流，**不是**物理进程退出的证明，进程与管道回收仍由宿主负责。
///
/// 返回优先级由收束结果决定，前台结论不能盖过它：**只有 SDK 收束成功才返回前台协议结果**
/// （`Required`/`Verified`，或正常收束下的取消等失败）。收束超时一律为 `Timeout`@`Close`；
/// 其他收束失败按实际类别（`Transport`/`ResourceLimit`/`Protocol`）@`Close` 上报。协议取消
/// 不等于资源已经收束，因此收束失败不会被伪装成普通取消。每次调用只发布一个结果。
///
/// # Errors
/// 返回 [`AuthError`]；类别与阶段分别由 [`AuthError::kind`] 与 [`AuthError::stage`] 表达。
pub async fn run_authentication<W, R>(
    outgoing: W,
    incoming: R,
    request: AuthRequest,
) -> Result<AuthOutcome, AuthError>
where
    W: AsyncWrite + Unpin + Send + 'static,
    R: AsyncRead + Unpin + Send + 'static,
{
    let stream = limits::StreamGuard::new();
    let observed = request.progress.clone();
    let transport = ByteStreams::new(
        limits::GuardedWriter::new(outgoing, stream.clone()).compat_write(),
        limits::BudgetedReader::new(incoming, limits::INPUT_BYTE_BUDGET, stream.clone()).compat(),
    );
    let flow_stream = stream.clone();
    let (foreground_tx, mut foreground_rx) = tokio::sync::oneshot::channel();
    let connection = Client.builder().name("anywork-acp-auth").connect_with(
        transport,
        async move |connection| {
            let outcome = flow::negotiate(connection, request, flow_stream).await;
            // 前台结论只在这里发布一次；随后 SDK 的排空不再改动它。
            let _ = foreground_tx.send(outcome);
            Ok(())
        },
    );
    let mut connection = std::pin::pin!(connection);

    // 阶段一：等前台发布结论，期间必须持续驱动连接 future。
    let phase = tokio::select! {
        result = &mut foreground_rx => Phase::Published(result.ok()),
        result = &mut connection => Phase::Finished(result),
    };

    match phase {
        // 前台已结束：此后才为 SDK 收束另起预算。
        Phase::Published(Some(observed_outcome)) => {
            match tokio::time::timeout(limits::DRAIN_BUDGET, connection.as_mut()).await {
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
                match tokio::time::timeout(limits::DRAIN_BUDGET, connection.as_mut()).await {
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
    match *progress.borrow() {
        AuthProgress::Initializing => AuthStage::Initialize,
        AuthProgress::Authenticating => AuthStage::Authenticate,
        AuthProgress::Verifying => AuthStage::Probe,
        AuthProgress::Closing => AuthStage::Close,
    }
}
