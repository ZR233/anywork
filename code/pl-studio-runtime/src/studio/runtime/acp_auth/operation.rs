//! 一次认证/额度操作租用账户连接，独占操作身份与探测 session。
//! 进程、SDK 汇合及物理回收只属于账户连接 owner。

use std::sync::Arc;

use pl_protocol::studio::{AcpAuthAction, AcpAuthFailureCode, AcpAuthStage, AcpAuthState};
use tokio::sync::watch;

use super::super::acp_worker::PROCESS_CLEANUP_LIMIT;
use super::mapping::{AcpFailure, map_auth_error, map_auth_server, map_progress, protocol_action};
use super::registry::{AcpAuthInner, Operation};

/// 一次操作的启动意图；全部字段来自受理时的 canonical 配置快照与请求本身。
pub(super) struct OperationPlan {
    /// 受理时冻结的用户定义；模板与通用 command 共用后续监督及认证通路。
    pub definition: crate::config::AcpServiceDefinition,
    pub action: AcpAuthAction,
    pub commands: pl_acp::auth::mpsc::Receiver<pl_acp::auth::AuthCommand>,
}

/// 操作只租用账户连接；结束不取消或回收共享进程。
pub(super) async fn run(inner: Arc<AcpAuthInner>, operation: Arc<Operation>, plan: OperationPlan) {
    if operation.cancel.is_cancelled() {
        inner.complete_operation(
            &operation.account_id,
            operation.generation,
            operation.connection_revision,
            AcpAuthState::Cancelled,
            None,
        );
        return;
    }
    let runtime = super::admission::AcpAuthRuntime {
        inner: inner.clone(),
    };
    let connection = runtime.connection(&plan.definition);
    let prepared = match connection.as_ref() {
        Ok(connection) => tokio::select! {
            biased;
            () = operation.cancel.cancelled() => Err(AcpFailure { code: AcpAuthFailureCode::Cancelled, stage: AcpAuthStage::Config, retryable: false }),
            result = connection.prepared() => result,
        },
        Err(_) => Err(AcpFailure {
            code: AcpAuthFailureCode::ConfigChanged,
            stage: AcpAuthStage::Config,
            retryable: false,
        }),
    };
    let prepared = match prepared {
        Ok(value) => value,
        Err(failure) => {
            if let Ok(connection) = connection.as_ref()
                && connection.is_closing()
            {
                inner.publish_closing(
                    &operation.account_id,
                    operation.generation,
                    operation.connection_revision,
                    Some(failure.failure()),
                );
                let _ = connection.wait().await;
            }
            inner.complete_operation(
                &operation.account_id,
                operation.generation,
                operation.connection_revision,
                if operation.cancel.is_cancelled() {
                    AcpAuthState::Cancelled
                } else {
                    failure.into_state()
                },
                None,
            );
            let runtime = super::admission::AcpAuthRuntime {
                inner: inner.clone(),
            };
            let _ = inner.config.with_acp_snapshot(|revision, snapshot| {
                runtime.background_prepare(revision, snapshot)
            });
            return;
        }
    };
    if let Ok(initialize) = prepared.protocol.initialized().await
        && initialize
            .agent_capabilities
            .session_capabilities
            .close
            .is_none()
    {
        tracing::warn!(account_id = %operation.account_id,
            "ACP server does not support independent probe session close; remote resources remain until account shutdown");
    }
    let (progress, mut receiver) = watch::channel(pl_acp::auth::AuthProgress::Initializing);
    let request = pl_acp::auth::AuthRequest {
        probe_cwd: dunce::simplified(&prepared.probe_dir)
            .to_string_lossy()
            .into_owned(),
        action: protocol_action(&plan.action),
        commands: plan.commands,
        cleanup: pl_acp::auth::CleanupBudget::new(PROCESS_CLEANUP_LIMIT),
        cancellation: operation.cancel.clone(),
        progress,
        expected_server_version: prepared.expected_version,
    };
    let mut flow = Box::pin(pl_acp::auth::run(prepared.protocol, request));
    let mut progress_open = true;
    let protocol = loop {
        tokio::select! {
            biased;
            changed = receiver.changed(), if progress_open => {
                if changed.is_err() { progress_open = false; }
                else if let Some(state) = map_progress(&receiver.borrow_and_update(), &operation.operation_id, &plan.action) {
                    match state {
                        AcpAuthState::Closing { .. } => inner.publish_closing(&operation.account_id, operation.generation, operation.connection_revision, None),
                        state => inner.publish_progress(&operation.account_id, operation.generation, operation.connection_revision, state),
                    }
                }
            }
            result = &mut flow => break result,
        }
    };
    drop(flow);
    if let Ok(connection) = connection.as_ref()
        && connection.is_closing()
    {
        inner.publish_closing(
            &operation.account_id,
            operation.generation,
            operation.connection_revision,
            None,
        );
        let _ = connection.wait().await;
    }
    let (state, usage) =
        terminal_result(Some(protocol), &operation, &plan.action, &receiver.borrow());
    inner.complete_operation(
        &operation.account_id,
        operation.generation,
        operation.connection_revision,
        state,
        usage,
    );
    let runtime = super::admission::AcpAuthRuntime {
        inner: inner.clone(),
    };
    let _ = inner
        .config
        .with_acp_snapshot(|revision, snapshot| runtime.background_prepare(revision, snapshot));
}

/// 协议结果到终态；取消优先于其它失败类别，其余按类型化失败呈现。
///
/// 版本闸门由协议客户端在 `initialize` 之后、任何探测会话与登录请求之前执行（它持有
/// `expected_server_version`）：版本不符时这里只会收到类型化失败，因此不再有第二套迟到比较
/// （design/28 §28.3）。
fn terminal_result(
    protocol: Option<Result<pl_acp::auth::AuthOutcome, pl_acp::auth::AuthError>>,
    operation: &Operation,
    action: &AcpAuthAction,
    last_progress: &pl_acp::auth::AuthProgress,
) -> (
    AcpAuthState,
    Option<pl_protocol::studio::AcpUsageObservation>,
) {
    match protocol {
        Some(Ok(pl_acp::auth::AuthOutcome::Verified { server, usage })) => {
            let checked_at = crate::studio::unix_seconds();
            let state = AcpAuthState::Verified {
                checked_at,
                server: map_auth_server(server),
            };
            let usage_update = matches!(action, AcpAuthAction::QueryUsage).then(|| {
                pl_protocol::studio::AcpUsageObservation {
                    checked_at,
                    state: usage.map_or(
                        pl_protocol::studio::AcpUsageState::Failed {
                            code: pl_protocol::studio::AcpUsageFailureCode::InvalidResponse,
                        },
                        super::usage::map_report,
                    ),
                }
            });
            (state, usage_update)
        }
        Some(Err(error)) => {
            let state = if operation.cancel.is_cancelled()
                && matches!(error.kind(), pl_acp::auth::AuthFailureKind::Cancelled)
            {
                AcpAuthState::Cancelled
            } else {
                map_auth_error(&error).into_state()
            };
            (state, None)
        }
        None => (
            AcpFailure {
                code: AcpAuthFailureCode::Transport,
                stage: match last_progress {
                    pl_acp::auth::AuthProgress::Initializing => AcpAuthStage::Initialize,
                    pl_acp::auth::AuthProgress::Required { .. }
                    | pl_acp::auth::AuthProgress::Authenticating { .. } => {
                        AcpAuthStage::Authenticate
                    }
                    pl_acp::auth::AuthProgress::Verifying => AcpAuthStage::Probe,
                    pl_acp::auth::AuthProgress::Closing => AcpAuthStage::Close,
                },
                retryable: true,
            }
            .into_state(),
            None,
        ),
    }
}
