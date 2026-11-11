//! 一次 ACP 认证操作的 supervisor。
//!
//! 该任务独占：官方进程、业务管道、stderr 排空、进展 watch、取消令牌与真实 join 出口。协议
//! 结束并不等于收束完成：本任务先发布 busy 非终态 `Closing`，确认进程与管道真实停止（或等待
//! 结果已交付）之后才发布认证终态；未确认收束时保留 owner 并由 shutdown 阶段做有界 join，
//! 绝不用 drop/abort 冒充进程退出（见 design/28 §28.2–28.4）。

use std::path::PathBuf;
use std::sync::Arc;

use pl_protocol::studio::{AcpAuthAction, AcpAuthFailureCode, AcpAuthStage, AcpAuthState};
use tokio::sync::watch;

use super::super::acp_worker::{
    AcpSpawnError, AcpSpawnRequest, AcpWorker, PROCESS_CLEANUP_LIMIT, Reclaim,
};
use super::mapping::{
    AcpFailure, map_auth_error, map_auth_server, map_progress, prepare_failure, prepare_probe_dir,
    protocol_action,
};
use super::registry::{AcpAuthInner, Operation};

/// 一次操作的启动意图；全部字段来自受理时的 canonical 配置快照与请求本身。
pub(super) struct OperationPlan {
    /// 受理时冻结的用户定义；模板与通用 command 共用后续监督及认证通路。
    pub definition: crate::config::AcpServiceDefinition,
    pub action: AcpAuthAction,
    pub commands: pl_acp::auth::mpsc::Receiver<pl_acp::auth::AuthCommand>,
}

/// supervisor 主体；正常与失败路径都只在确认收尾后发布终态。
pub(super) async fn run(inner: Arc<AcpAuthInner>, operation: Arc<Operation>, plan: OperationPlan) {
    let account_id = operation.account_id.clone();
    let cleanup = pl_acp::auth::CleanupBudget::new(PROCESS_CLEANUP_LIMIT);
    let dispatch = |state: AcpAuthState| {
        inner.publish_progress(
            &account_id,
            operation.generation,
            operation.connection_revision,
            state,
        );
    };

    // 0. 受理后立刻被取消：不准备探测目录、不派生进程。
    if operation.cancel.is_cancelled() {
        inner.complete_operation(
            &account_id,
            operation.generation,
            operation.connection_revision,
            AcpAuthState::Cancelled,
            None,
        );
        return;
    }

    // Probe directories are owned here, never created by the generic worker.
    let spawned = spawn_process(&inner, &account_id, &plan.definition, &operation).await;
    let (mut worker, probe_dir, expected_server_version) = match spawned {
        Ok(value) => value,
        Err(failure) => {
            let state = if operation.cancel.is_cancelled() {
                AcpAuthState::Cancelled
            } else {
                failure.into_state()
            };
            inner.complete_operation(
                &account_id,
                operation.generation,
                operation.connection_revision,
                state,
                None,
            );
            return;
        }
    };

    let Some((writer, reader)) = worker.take_streams() else {
        // 没有交出管道说明进程状态不可信：先进入收束中并确认真实停止，再如实报告启动失败。
        let failure = AcpFailure {
            code: AcpAuthFailureCode::Startup,
            stage: AcpAuthStage::Process,
            retryable: true,
        };
        inner.publish_closing(
            &account_id,
            operation.generation,
            operation.connection_revision,
            None,
        );
        let cleanup_issue = reclaim_worker(&inner, &operation, &mut worker, &cleanup).await;
        let state = if cleanup_issue.is_some() {
            cleanup_failure()
        } else {
            failure.into_state()
        };
        inner.complete_operation(
            &account_id,
            operation.generation,
            operation.connection_revision,
            state,
            None,
        );
        return;
    };

    // 3. 把已协商的 IO、取消与进展通道交给协议客户端；它不启动进程、不读配置。
    let (progress_sender, mut progress_receiver) =
        watch::channel(pl_acp::auth::AuthProgress::Initializing);
    let request = pl_acp::auth::AuthRequest {
        // Windows 内部规范路径可能带设备前缀；官方 server 会将 cwd 转为 URI，不能直接
        // 编码该前缀。复用 dunce 仅转换可安全简化的路径，文件系统操作仍持有原始路径。
        probe_cwd: dunce::simplified(&probe_dir).to_string_lossy().into_owned(),
        action: protocol_action(&plan.action),
        commands: plan.commands,
        cleanup: cleanup.clone(),
        cancellation: operation.cancel.clone(),
        progress: progress_sender,
        // 只有托管模板要求固定发行版本；通用服务不要求 agentInfo 或版本。
        expected_server_version,
    };
    let mut authentication = Box::pin(pl_acp::auth::run_connection(writer, reader, request));
    let mut progress_open = true;
    let mut protocol: Option<Result<pl_acp::auth::AuthOutcome, pl_acp::auth::AuthError>> = None;
    while protocol.is_none() {
        tokio::select! {
            biased;
            changed = progress_receiver.changed(), if progress_open => {
                if changed.is_err() {
                    // 协议 future 已释放进展通道；等待它自己的结果。
                    progress_open = false;
                } else if let Some(state) = map_progress(
                    &progress_receiver.borrow_and_update(),
                    &operation.operation_id,
                    &plan.action,
                ) {
                    tracing::debug!(
                        operation_id = %operation.operation_id,
                        phase = match &state {
                            AcpAuthState::Checking { .. } => "initialize",
                            AcpAuthState::Required { .. } => "authRequired",
                            AcpAuthState::Authenticating { .. } => "authenticate",
                            AcpAuthState::Verifying { .. } => "session/new",
                            AcpAuthState::Closing { .. } => "close",
                            _ => "other",
                        },
                        "ACP connection phase observed"
                    );
                    // 协议侧收束进度只进入 busy 非终态，且不能覆盖已取消代次。
                    match state {
                        AcpAuthState::Closing { .. } => inner.publish_closing(
                            &account_id,
                            operation.generation,
                            operation.connection_revision,
                            None,
                        ),
                        other => dispatch(other),
                }
                }
            }
            result = &mut authentication => protocol = Some(result),
            exited = worker.observe_exit() => {
                tracing::debug!(operation_id = %operation.operation_id, wait_ok = exited.is_ok(), "ACP process exit observed during protocol flow");
                // 进程退出后仍驱动 SDK 消费已到达的响应/EOF；这只是一段资源排空预算。
                protocol = tokio::time::timeout_at(cleanup.deadline(), &mut authentication).await.ok();
                break;
            }
        }
    }
    // 显式释放协议 future：关闭我们的 stdin 写半边，随后由 owner 终止并等待真实退出。
    drop(authentication);
    let last_progress = progress_receiver.borrow().clone();
    drop(progress_receiver);
    tracing::debug!(
        operation_id = %operation.operation_id,
        protocol_ok = protocol.as_ref().is_some_and(Result::is_ok),
        failure_kind = ?protocol.as_ref().and_then(|r| r.as_ref().err()).map(pl_acp::auth::AuthError::kind),
        failure_stage = ?protocol.as_ref().and_then(|r| r.as_ref().err()).map(pl_acp::auth::AuthError::stage),
        rpc_code = protocol.as_ref().and_then(|r| r.as_ref().err()).and_then(pl_acp::auth::AuthError::rpc_code),
        "ACP connection protocol completed"
    );

    // 4. 物理收尾：进入 Closing（busy 非终态），确认资源停止后才发布终态。
    inner.publish_closing(
        &account_id,
        operation.generation,
        operation.connection_revision,
        None,
    );
    let cleanup_issue = reclaim_worker(&inner, &operation, &mut worker, &cleanup).await;
    let (state, usage_update) = if cleanup_issue.is_some() {
        // 资源已确认停止（或等待结果已交付），如实报告收尾问题，绝不以认证成功掩盖。
        (cleanup_failure(), None)
    } else {
        terminal_result(protocol, &operation, &plan.action, &last_progress)
    };
    // 终态与"该账号已空闲"在同一把锁里提交，只发一次事件。
    inner.complete_operation(
        &account_id,
        operation.generation,
        operation.connection_revision,
        state,
        usage_update,
    );
}

/// 本地进程/管道收尾失败的安全状态。
fn cleanup_failure() -> AcpAuthState {
    AcpFailure {
        code: AcpAuthFailureCode::Cleanup,
        stage: AcpAuthStage::Cleanup,
        retryable: true,
    }
    .into_state()
}

/// 收尾循环：直到资源确认停止或等待结果已交付才返回；期间保持 `Closing` 并附带安全摘要。
///
/// `Pending` 不是终态：owner 与句柄都保留，下一次收尾继续等待同一进程/管道。
async fn reclaim_worker(
    inner: &AcpAuthInner,
    operation: &Operation,
    worker: &mut AcpWorker,
    cleanup: &pl_acp::auth::CleanupBudget,
) -> Option<String> {
    let mut overdue = false;
    loop {
        let reclaim = worker.reclaim();
        tokio::pin!(reclaim);
        let result = match tokio::time::timeout_at(cleanup.deadline(), &mut reclaim).await {
            Ok(result) => result,
            Err(_) => {
                overdue = true;
                inner.publish_closing(
                    &operation.account_id,
                    operation.generation,
                    operation.connection_revision,
                    Some(
                        AcpFailure {
                            code: AcpAuthFailureCode::Cleanup,
                            stage: AcpAuthStage::Cleanup,
                            retryable: true,
                        }
                        .failure(),
                    ),
                );
                // 保留同一个 future、进程和读取任务，继续等实际完成事件。
                reclaim.await
            }
        };
        match result {
            Reclaim::Stopped => {
                return overdue.then(|| "ACP cleanup exceeded shutdown budget".to_string());
            }
            Reclaim::Settled(issue) => return Some(issue),
            Reclaim::Pending(_) => {
                overdue = true;
                inner.publish_closing(
                    &operation.account_id,
                    operation.generation,
                    operation.connection_revision,
                    Some(
                        AcpFailure {
                            code: AcpAuthFailureCode::Cleanup,
                            stage: AcpAuthStage::Cleanup,
                            retryable: true,
                        }
                        .failure(),
                    ),
                );
                operation.cleanup_retry.notified().await;
            }
        }
    }
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

/// 准备探测目录并启动已验证的官方程序；失败时映射为类型化阶段错误。
async fn spawn_process(
    inner: &Arc<AcpAuthInner>,
    account_id: &str,
    definition: &crate::config::AcpServiceDefinition,
    operation: &Operation,
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
        &operation.cancel,
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
    match AcpWorker::spawn(request, &inner.workers, &operation.cancel).await {
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
