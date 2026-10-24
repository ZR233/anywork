//! 认证命令的协议步骤编排。
//!
//! 每个步骤都在连接前台 future 中顺序执行：`initialize` 协商 v1 能力并核对宿主要求的
//! 服务端版本，随后按命令探测 `session/new` 或在核验方法后登录再探测，最后按已协商能力
//! 释放探测会话。这里不发送 prompt、不调用模型、不安装工具，也不等待需要同连接消息才能
//! 完成的回调。

use std::time::Duration;

use agent_client_protocol::schema::ProtocolVersion;
use agent_client_protocol::schema::v1::{
    AuthMethod as SdkAuthMethod, AuthMethodId, AuthenticateRequest, CloseSessionRequest,
    Implementation, InitializeRequest, NewSessionRequest, SessionId,
};
use agent_client_protocol::{Agent, ConnectionTo, JsonRpcRequest};

use super::limits::{self, StreamGuard};
use super::{
    AuthAction, AuthError, AuthFailureKind, AuthMethod, AuthMethodKind, AuthOutcome, AuthProgress,
    AuthRequest, AuthStage, CancellationToken, ServerInfo, watch,
};

/// 参与 v1 协商的客户端名称。
const CLIENT_NAME: &str = "anywork";

/// 执行一次认证命令，返回终态或类型化失败。
pub(super) async fn negotiate(
    connection: ConnectionTo<Agent>,
    request: AuthRequest,
    stream: StreamGuard,
) -> Result<AuthOutcome, AuthError> {
    let AuthRequest {
        expected_server_version,
        probe_cwd,
        action,
        cancellation,
        progress,
    } = request;
    let wire = Wire {
        connection: &connection,
        cancellation: &cancellation,
        stream: &stream,
    };

    publish(&progress, AuthProgress::Initializing);
    let initialize = wire
        .send(
            InitializeRequest::new(ProtocolVersion::V1)
                .client_info(Implementation::new(CLIENT_NAME, env!("CARGO_PKG_VERSION"))),
            AuthStage::Initialize,
            limits::INITIALIZE_BUDGET,
            AuthFailureKind::Protocol,
        )
        .await?;

    if initialize.protocol_version != ProtocolVersion::V1 {
        return Err(AuthError::unsupported_version());
    }
    if initialize
        .agent_info
        .as_ref()
        .map(|info| info.version.as_str())
        != Some(expected_server_version.as_str())
    {
        return Err(AuthError::server_version_mismatch());
    }

    let server = server_info(initialize.agent_info.as_ref());
    let methods = declared_methods(&initialize.auth_methods);
    let session = Session {
        wire,
        probe_cwd: &probe_cwd,
        server: &server,
        methods: &methods,
        close_supported: initialize
            .agent_capabilities
            .session_capabilities
            .close
            .is_some(),
        progress: &progress,
    };

    match action {
        AuthAction::Check => session.check().await,
        AuthAction::Authenticate { method_id } => {
            session
                .authenticate(&initialize.auth_methods, method_id)
                .await
        }
    }
}

/// 与对端交换请求的最小上下文。
struct Wire<'a> {
    connection: &'a ConnectionTo<Agent>,
    cancellation: &'a CancellationToken,
    stream: &'a StreamGuard,
}

impl Wire<'_> {
    /// 业务请求：发送一次并等待响应，同时观察宿主取消。
    ///
    /// 取消或超时会丢弃等待中的响应 future；SDK 在 `SentRequestCancellation` 的 `Drop` 中向
    /// 对端补发一次 `$/cancel_request`，因此不会留下无人等待的在途请求，也不重发该请求。
    async fn send<Req>(
        &self,
        request: Req,
        stage: AuthStage,
        budget: Duration,
        peer_kind: AuthFailureKind,
    ) -> Result<Req::Response, AuthError>
    where
        Req: JsonRpcRequest,
    {
        if self.cancellation.is_cancelled() {
            return Err(AuthError::cancelled(stage));
        }
        tokio::select! {
            biased;
            () = self.cancellation.cancelled() => Err(AuthError::cancelled(stage)),
            outcome = self.exchange(request, stage, budget, peer_kind) => outcome,
        }
    }

    /// 清理请求：只受自身阶段预算约束，不观察业务取消。
    ///
    /// 已经建立探测会话时必须给它一次关闭机会，否则取消会让远端 session 无人释放。这里仍然
    /// 只尝试一次，不重发，也不把取消信号转成第二次请求。
    async fn send_cleanup<Req>(
        &self,
        request: Req,
        stage: AuthStage,
        budget: Duration,
        peer_kind: AuthFailureKind,
    ) -> Result<Req::Response, AuthError>
    where
        Req: JsonRpcRequest,
    {
        self.exchange(request, stage, budget, peer_kind).await
    }

    /// 单次请求/响应的公共路径：发布请求、应用阶段预算、把对端错误映射为类型化失败。
    async fn exchange<Req>(
        &self,
        request: Req,
        stage: AuthStage,
        budget: Duration,
        peer_kind: AuthFailureKind,
    ) -> Result<Req::Response, AuthError>
    where
        Req: JsonRpcRequest,
    {
        let pending = self.connection.send_request(request).block_task();
        match tokio::time::timeout(budget, pending).await {
            Ok(Ok(response)) => Ok(response),
            Ok(Err(error)) => Err(AuthError::peer_failure(
                stage,
                peer_kind,
                error,
                self.stream,
            )),
            Err(_elapsed) => Err(AuthError::timeout(stage)),
        }
    }
}

/// 协商完成后的只读上下文。
struct Session<'a> {
    wire: Wire<'a>,
    probe_cwd: &'a str,
    server: &'a Option<ServerInfo>,
    methods: &'a [AuthMethod],
    close_supported: bool,
    progress: &'a watch::Sender<AuthProgress>,
}

impl Session<'_> {
    /// 只探测：探测会话成功即认证可用，`AuthRequired` 转为需要登录。
    async fn check(self) -> Result<AuthOutcome, AuthError> {
        publish(self.progress, AuthProgress::Verifying);
        let session = self.probe().await?;
        self.finish(session).await
    }

    /// 登录：核验实际方法后调用 `authenticate`，再用探测会话复核。
    async fn authenticate(
        self,
        declared: &[SdkAuthMethod],
        method_id: String,
    ) -> Result<AuthOutcome, AuthError> {
        let wanted = AuthMethodId::new(method_id.as_str());
        let Some(method) = declared.iter().find(|method| method.id() == &wanted) else {
            return Err(AuthError::unsupported_method());
        };
        // 只有 agent 类型方法对应 `authenticate`；terminal 与未来新增类型都要求本阶段没有的
        // 专门实现，因此不发送登录请求。
        if !matches!(method, SdkAuthMethod::Agent(_)) {
            return Err(AuthError::unsupported_method());
        }

        publish(self.progress, AuthProgress::Authenticating);
        self.wire
            .send(
                AuthenticateRequest::new(method_id),
                AuthStage::Authenticate,
                limits::AUTHENTICATE_BUDGET,
                AuthFailureKind::Authentication,
            )
            .await?;

        publish(self.progress, AuthProgress::Verifying);
        // 登录响应成功但复核仍要求登录时，`finish` 返回 `Required` 而不是 `Verified`。
        let session = self.probe().await?;
        self.finish(session).await
    }

    /// 在接入专属空工作区建立探测会话；`None` 表示服务端要求登录。
    ///
    /// 取消或超时会让本次结果不可知；此时不重发 `session/new`，由宿主回收独占进程。
    async fn probe(&self) -> Result<Option<SessionId>, AuthError> {
        // `new` 已保证 `mcpServers` 为空，本阶段不向对端提供任何工具。
        let request = NewSessionRequest::new(self.probe_cwd);
        match self
            .wire
            .send(
                request,
                AuthStage::Probe,
                limits::PROBE_BUDGET,
                AuthFailureKind::Probe,
            )
            .await
        {
            Ok(response) => Ok(Some(response.session_id)),
            Err(error) if error.is_auth_required() => Ok(None),
            Err(error) => Err(error),
        }
    }

    /// 收束：发布关闭阶段，按已协商能力释放探测会话，再返回终态。
    ///
    /// 已知探测会话必须拿到一次关闭尝试。这一路径不观察业务取消，只受 `CLOSE_BUDGET` 限制：
    /// 用户取消登录不等于可以遗留远端 session。关闭只尝试一次，不重发；真实失败保留原类别
    /// （Transport/Timeout/ResourceLimit），其余远端关闭失败按 `Cleanup` 上报，整体不返回
    /// `Verified`。
    async fn finish(&self, session: Option<SessionId>) -> Result<AuthOutcome, AuthError> {
        publish(self.progress, AuthProgress::Closing);
        let Some(session) = session else {
            return Ok(AuthOutcome::Required {
                server: self.server.clone(),
                methods: self.methods.to_vec(),
            });
        };
        if self.close_supported {
            self.wire
                .send_cleanup(
                    CloseSessionRequest::new(session),
                    AuthStage::Close,
                    limits::CLOSE_BUDGET,
                    AuthFailureKind::Cleanup,
                )
                .await?;
        }
        // 服务端未声明 `session/close` 时，探测会话由宿主回收独占进程。
        Ok(AuthOutcome::Verified {
            server: self.server.clone(),
        })
    }
}

/// 发布进度；接收端不在或已被替换都不影响协议结果。
fn publish(progress: &watch::Sender<AuthProgress>, value: AuthProgress) {
    let _ = progress.send_replace(value);
}

/// 从 `initialize` 响应投影服务端身份；对端省略 `agentInfo` 时保持 `None`。
fn server_info(agent_info: Option<&Implementation>) -> Option<ServerInfo> {
    agent_info.map(|info| ServerInfo {
        name: info.name.clone(),
        title: info.title.clone(),
        version: info.version.clone(),
    })
}

/// 把服务端声明的方法投影为公开类型。
fn declared_methods(declared: &[SdkAuthMethod]) -> Vec<AuthMethod> {
    declared
        .iter()
        .map(|method| AuthMethod {
            id: method.id().to_string(),
            name: method.name().to_owned(),
            description: method.description().map(str::to_owned),
            kind: method_kind(method),
        })
        .collect()
}

fn method_kind(method: &SdkAuthMethod) -> AuthMethodKind {
    match method {
        SdkAuthMethod::Agent(_) => AuthMethodKind::Agent,
        SdkAuthMethod::Terminal(_) => AuthMethodKind::Terminal,
        // 协议将来可能新增方法类型：本阶段没有对应实现，因此明确标记为 `Unsupported`，
        // 不伪装成 terminal；登录路径只认 SDK 的 agent 变体。
        _ => AuthMethodKind::Unsupported,
    }
}
