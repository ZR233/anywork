//! 认证命令的协议步骤编排。
//!
//! 每个步骤都在连接前台 future 中顺序执行：`initialize` 协商 v1 能力并核对宿主要求的
//! 服务端版本，随后按命令探测 `session/new` 或在核验方法后登录再探测，最后按已协商能力
//! 释放探测会话。普通检查与登录不发送 prompt；只有显式额度查询会在带 SDK session 路由的
//! 探测会话中发送固定 `/usage`。这里不安装工具，也不声明文件系统或终端能力。

use agent_client_protocol::v1::ConnectionTo;
use agent_client_protocol::v1::schema::{
    AuthMethod as SdkAuthMethod, AuthMethodId, AuthenticateRequest, ContentBlock, ContentChunk,
    Implementation, InitializeResponse, SessionNotification, SessionUpdate, StopReason,
};
use agent_client_protocol::{Agent, JsonRpcRequest};

use super::limits;
use super::{
    AuthAction, AuthCommand, AuthError, AuthFailureKind, AuthMethod, AuthMethodKind, AuthOutcome,
    AuthProgress, AuthRequest, AuthStage, CancellationToken, CleanupBudget, ServerInfo,
    UsageFailure, UsageReport, watch,
};

/// 执行一次认证命令，返回终态或类型化失败。
pub(super) async fn negotiate(
    account: crate::connection::Connection,
    connection: ConnectionTo<Agent>,
    initialize: InitializeResponse,
    request: AuthRequest,
) -> Result<AuthOutcome, AuthError> {
    let AuthRequest {
        expected_server_version: _,
        probe_cwd,
        action,
        mut commands,
        cleanup,
        cancellation,
        progress,
    } = request;
    let wire = Wire {
        connection: &connection,
        cancellation: &cancellation,
        account: &account,
    };

    let server = server_info(initialize.agent_info.as_ref());
    let methods = declared_methods(&initialize.auth_methods);
    let session = Session {
        wire,
        probe_cwd: &probe_cwd,
        server: &server,
        progress: &progress,
        cleanup,
    };

    loop {
        let outcome = match action {
            AuthAction::Check => session.probe_session(false).await?,
            AuthAction::QueryUsage => session.probe_session(true).await?,
        };
        if let Some(outcome) = outcome {
            return Ok(outcome);
        }
        publish(
            &progress,
            AuthProgress::Required {
                server: server.clone(),
                methods: methods.clone(),
            },
        );
        let command = tokio::select! {
            biased;
            () = account.cancelled() => return Err(AuthError::new(AuthFailureKind::Transport, AuthStage::Authenticate)),
            () = cancellation.cancelled() => return Err(AuthError::cancelled(AuthStage::Authenticate)),
            () = connection.incoming_closed() => return Err(AuthError::new(AuthFailureKind::Transport, AuthStage::Authenticate)),
            command = commands.recv() => command.ok_or_else(|| AuthError::cancelled(AuthStage::Authenticate))?,
        };
        match command {
            AuthCommand::Authenticate { method_id } => {
                session
                    .authenticate(&initialize.auth_methods, method_id)
                    .await?;
            }
        }
    }
}

/// 与对端交换请求的最小上下文。
struct Wire<'a> {
    connection: &'a ConnectionTo<Agent>,
    cancellation: &'a CancellationToken,
    account: &'a crate::connection::Connection,
}

impl Wire<'_> {
    /// 业务请求：发送一次并等待响应，同时观察宿主取消。
    ///
    /// 取消会丢弃等待中的响应 future；SDK 在 `SentRequestCancellation` 的 `Drop` 中向
    /// 对端补发一次 `$/cancel_request`，因此不会留下无人等待的在途请求，也不重发该请求。
    async fn send<Req>(
        &self,
        request: Req,
        stage: AuthStage,
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
            () = self.account.cancelled() => Err(AuthError::new(AuthFailureKind::Transport, stage)),
            () = self.cancellation.cancelled() => Err(AuthError::cancelled(stage)),
            outcome = self.exchange(request, stage, peer_kind) => outcome,
        }
    }

    /// 单次请求/响应的公共路径；由 SDK 在连接关闭时交付在途请求的失败。
    async fn exchange<Req>(
        &self,
        request: Req,
        stage: AuthStage,
        peer_kind: AuthFailureKind,
    ) -> Result<Req::Response, AuthError>
    where
        Req: JsonRpcRequest,
    {
        let pending = self.connection.send_request(request).block_task();
        match pending.await {
            Ok(response) => Ok(response),
            Err(error) => Err(AuthError::rpc(
                stage,
                if agent_client_protocol::is_incoming_transport_closed(&error) {
                    AuthFailureKind::Transport
                } else {
                    peer_kind
                },
                error,
            )),
        }
    }
}

/// 协商完成后的只读上下文。
struct Session<'a> {
    wire: Wire<'a>,
    probe_cwd: &'a str,
    server: &'a Option<ServerInfo>,
    progress: &'a watch::Sender<AuthProgress>,
    cleanup: CleanupBudget,
}

impl Session<'_> {
    /// 登录：核验实际方法后调用 `authenticate`，再用探测会话复核。
    async fn authenticate(
        &self,
        declared: &[SdkAuthMethod],
        method_id: String,
    ) -> Result<(), AuthError> {
        let wanted = AuthMethodId::new(method_id.as_str());
        let Some(method) = declared.iter().find(|method| method.id() == &wanted) else {
            return Err(AuthError::unsupported_method());
        };
        // 只有 agent 类型方法对应 `authenticate`；terminal 与未来新增类型都要求本阶段没有的
        // 专门实现，因此不发送登录请求。
        if !matches!(method, SdkAuthMethod::Agent(_)) {
            return Err(AuthError::unsupported_method());
        }

        publish(
            self.progress,
            AuthProgress::Authenticating {
                method_id: method_id.clone(),
            },
        );
        self.wire
            .send(
                AuthenticateRequest::new(method_id),
                AuthStage::Authenticate,
                AuthFailureKind::Authentication,
            )
            .await?;

        Ok(())
    }

    /// 独立、空 MCP 的探测 session。接收预算由原 session 观察窗口与报告预算共同约束，
    /// 不把业务历史字节计入认证额度，也不建立 SDK 的无界 ActiveSession 队列。
    async fn probe_session(&self, usage: bool) -> Result<Option<AuthOutcome>, AuthError> {
        use crate::session::{self, Open, OpenRequest};
        publish(self.progress, AuthProgress::Verifying);
        let (session, mut observer, driver) = session::channel(OpenRequest {
            cwd: self.probe_cwd.to_owned(),
            intent: Open::New,
            cleanup: self.cleanup.clone(),
            expected_server_version: None,
            prepare: None,
        });
        let foreground = async {
            let opened = tokio::select! {
                biased;
                () = self.wire.cancellation.cancelled() => Err(AuthError::cancelled(AuthStage::Probe)),
                result = session.opened() => result.map_err(|error| AuthError::from_session(error, AuthStage::Probe)),
            };
            let outcome = match opened {
                Err(error) if error.is_auth_required() => Ok(None),
                Err(error) => Err(error),
                Ok(_) => {
                    let report = if usage {
                        Some(self.query_turn(&session, &mut observer).await?)
                    } else {
                        None
                    };
                    Ok(Some(AuthOutcome::Verified {
                        server: self.server.clone(),
                        usage: report,
                    }))
                }
            };
            Ok::<_, AuthError>(outcome)
        };
        // No detached task: accepted probe, cancellation and local session driver remain owned
        // by this operation until the close budget or actual completion settles them.
        let foreground = async {
            let outcome = foreground.await;
            if session
                .snapshot()
                .await
                .is_ok_and(|snapshot| snapshot.ready)
            {
                publish(self.progress, AuthProgress::Closing);
            }
            let _ = session.close().await;
            outcome?
        };
        let (exit, outcome) = tokio::join!(driver.run(self.wire.account.clone()), foreground);
        if exit.cleanup_timed_out {
            return Err(AuthError::timeout(AuthStage::Close));
        }
        if let Some(error) = exit.close_error
            && !matches!(error, crate::session::Error::Unsupported)
        {
            return Err(AuthError::from_session(error, AuthStage::Close));
        }
        // Unknown open IDs and unsupported close remain explicit protocol limitations; neither
        // causes account cancellation or a second attempt at session/new.
        outcome
    }

    async fn query_turn(
        &self,
        session: &crate::session::Session,
        observer: &mut crate::session::Observer,
    ) -> Result<UsageReport, AuthError> {
        use crate::session::Event;
        session
            .submit(vec![ContentBlock::Text(
                agent_client_protocol::v1::schema::TextContent::new("/usage"),
            )])
            .await
            .map_err(|error| AuthError::from_session(error, AuthStage::Probe))?;
        let collect = async {
            let mut output = String::new();
            let mut exceeded = false;
            while let Some(event) = observer.recv().await {
                match event {
                    Event::Update(SessionNotification {
                        update:
                            SessionUpdate::AgentMessageChunk(ContentChunk {
                                content: ContentBlock::Text(text),
                                ..
                            }),
                        ..
                    }) => {
                        if output.len().saturating_add(text.text.len())
                            > limits::USAGE_REPORT_BYTE_BUDGET
                        {
                            exceeded = true;
                        } else if !exceeded {
                            output.push_str(&text.text);
                        }
                    }
                    Event::Completed(completed) => {
                        return match completed.result {
                            Ok(response)
                                if response.stop_reason == StopReason::EndTurn && !exceeded =>
                            {
                                UsageReport::Text(output)
                            }
                            _ if exceeded => UsageReport::Failed(UsageFailure::ResourceLimit),
                            _ => UsageReport::Failed(UsageFailure::Query),
                        };
                    }
                    Event::Permission { id, .. } => {
                        let _ = session.answer_permission(id, None).await;
                    }
                    Event::Gap(_) => return UsageReport::Failed(UsageFailure::ResourceLimit),
                    Event::Failed(_) => return UsageReport::Failed(UsageFailure::Transport),
                    _ => {}
                }
            }
            UsageReport::Failed(UsageFailure::Transport)
        };
        tokio::select! {
            biased;
            () = self.wire.cancellation.cancelled() => Err(AuthError::cancelled(AuthStage::Probe)),
            result = tokio::time::timeout(limits::USAGE_QUERY_BUDGET, collect) => Ok(result.unwrap_or(UsageReport::Failed(UsageFailure::Timeout))),
        }
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
pub(crate) fn declared_methods(declared: &[SdkAuthMethod]) -> Vec<AuthMethod> {
    declared
        .iter()
        .filter(|method| matches!(method, SdkAuthMethod::Agent(_)))
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
