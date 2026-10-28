//! 一次 ACP 认证操作的 supervisor。
//!
//! 该任务独占：官方进程、业务管道、stderr 排空、进展 watch、取消令牌与真实 join 出口。协议
//! 结束并不等于收束完成：本任务先发布 busy 非终态 `Closing`，确认进程与管道真实停止（或等待
//! 结果已交付）之后才发布认证终态；未确认收束时保留 owner 并由 shutdown 阶段做有界 join，
//! 绝不用 drop/abort 冒充进程退出（见 design/28 §28.2–28.4）。

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use pl_protocol::studio::{AcpAuthAction, AcpAuthFailureCode, AcpAuthStage, AcpAuthState};
use tokio::sync::watch;

use super::mapping::{
    AcpFailure, map_auth_error, map_auth_methods, map_auth_server, map_progress, prepare_failure,
    prepare_probe_dir, protocol_action,
};
use super::registry::{AcpAuthInner, Operation};
use super::worker::{AcpSpawnError, AcpSpawnRequest, AcpWorker, Reclaim};

/// 清理仍待收束后的重试间隔；owner 保持存活，直到真实确认进程与管道退出。
const CLEANUP_RETRY_INTERVAL: Duration = Duration::from_secs(1);

/// 一次操作的启动意图；全部字段来自受理时的 canonical 配置快照与请求本身。
pub(super) struct OperationPlan {
    /// 已受理接入的 provider；固定发行身份由产品清单决定，配置与客户端都不能提交。
    pub provider: crate::config::AcpProvider,
    pub action: AcpAuthAction,
}

/// supervisor 主体；正常与失败路径都只在确认收尾后发布终态。
pub(super) async fn run(inner: Arc<AcpAuthInner>, operation: Arc<Operation>, plan: OperationPlan) {
    let account_id = operation.account_id.clone();
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
        );
        return;
    }

    // 1. 前置：只读验证产品固定发行的受管安装。缺失/损坏/不支持的平台都在这里给出 typed 失败，
    //    绝不隐式下载或修复；验证本身不派生进程，因此失败路径没有额外的物理收尾责任。
    let verified = match super::super::acp_install::verified_install(
        &inner.store,
        plan.provider,
        &operation.cancel,
    )
    .await
    {
        Ok(verified) => verified,
        Err(failure) => {
            let state = if operation.cancel.is_cancelled() {
                AcpAuthState::Cancelled
            } else {
                prepare_failure(failure).into_state()
            };
            inner.complete_operation(
                &account_id,
                operation.generation,
                operation.connection_revision,
                state,
            );
            return;
        }
    };
    // 只记录非密钥的安装事实，便于诊断"本次认证用的是哪一个受管安装"。
    tracing::debug!(
        installation = %verified.installation_id,
        version = %verified.release.version,
        target = %verified.release.target,
        "ACP auth uses a verified managed installation"
    );

    // 2. 探测目录与官方进程：探测目录在接入专属空目录内，进程只用已验证的冻结启动资格；
    //    spawn 自身在异步解析受监督 worker 之后、真正启动之前再次检查取消。
    let spawned = spawn_process(&inner, &account_id, &verified, &operation).await;
    let (mut worker, probe_dir) = match spawned {
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
        let cleanup_issue = reclaim_worker(&inner, &operation, &mut worker).await;
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
        cancellation: operation.cancel.clone(),
        progress: progress_sender,
        // 产品固定发行版本：由协议客户端在 initialize 之后、任何 Session/check/authenticate 之前
        // 与原字符串精确比较，版本不符时不会发出 `session/new` 或 `authenticate`。
        expected_server_version: super::super::acp_install::SERVER_VERSION.to_string(),
    };
    let mut authentication = Box::pin(pl_acp::auth::run_authentication(writer, reader, request));
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
        }
    }
    // 显式释放协议 future：关闭我们的 stdin 写半边，随后由 owner 终止并等待真实退出。
    drop(authentication);
    drop(progress_receiver);

    // 4. 物理收尾：进入 Closing（busy 非终态），确认资源停止后才发布终态。
    inner.publish_closing(
        &account_id,
        operation.generation,
        operation.connection_revision,
        None,
    );
    let cleanup_issue = reclaim_worker(&inner, &operation, &mut worker).await;
    let state = if cleanup_issue.is_some() {
        // 资源已确认停止（或等待结果已交付），如实报告收尾问题，绝不以认证成功掩盖。
        cleanup_failure()
    } else {
        terminal_state(protocol, &operation)
    };
    // 终态与"该账号已空闲"在同一把锁里提交，只发一次事件。
    inner.complete_operation(
        &account_id,
        operation.generation,
        operation.connection_revision,
        state,
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
) -> Option<String> {
    loop {
        match worker.reclaim().await {
            Reclaim::Stopped => return None,
            Reclaim::Settled(issue) => {
                tracing::warn!(
                    category = "acpAuthCleanup",
                    detail_bytes = issue.len(),
                    "ACP auth resource exited with a delivered cleanup failure"
                );
                return Some(issue);
            }
            Reclaim::Pending(issue) => {
                tracing::warn!(
                    category = "acpAuthCleanup",
                    detail_bytes = issue.len(),
                    "ACP auth resource is still closing; retaining owner"
                );
                let failure = AcpFailure {
                    code: AcpAuthFailureCode::Cleanup,
                    stage: AcpAuthStage::Cleanup,
                    retryable: true,
                }
                .failure();
                inner.publish_closing(
                    &operation.account_id,
                    operation.generation,
                    operation.connection_revision,
                    Some(failure),
                );
                tokio::time::sleep(CLEANUP_RETRY_INTERVAL).await;
            }
        }
    }
}

/// 协议结果到终态；取消优先于其它失败类别，其余按类型化失败呈现。
///
/// 版本闸门由协议客户端在 `initialize` 之后、任何探测会话与登录请求之前执行（它持有
/// `expected_server_version`）：版本不符时这里只会收到类型化失败，因此不再有第二套迟到比较
/// （design/28 §28.3）。
fn terminal_state(
    protocol: Option<Result<pl_acp::auth::AuthOutcome, pl_acp::auth::AuthError>>,
    operation: &Operation,
) -> AcpAuthState {
    match protocol {
        Some(Ok(pl_acp::auth::AuthOutcome::Verified { server })) => AcpAuthState::Verified {
            checked_at: crate::studio::unix_seconds(),
            server: map_auth_server(server),
        },
        Some(Ok(pl_acp::auth::AuthOutcome::Required { server, methods })) => {
            AcpAuthState::Required {
                methods: map_auth_methods(methods),
                server: map_auth_server(server),
            }
        }
        Some(Err(error)) => {
            if operation.cancel.is_cancelled()
                && matches!(error.kind(), pl_acp::auth::AuthFailureKind::Cancelled)
            {
                AcpAuthState::Cancelled
            } else {
                map_auth_error(&error).into_state()
            }
        }
        None => AcpFailure {
            code: AcpAuthFailureCode::Internal,
            stage: AcpAuthStage::Close,
            retryable: true,
        }
        .into_state(),
    }
}

/// 准备探测目录并启动已验证的官方程序；失败时映射为类型化阶段错误。
async fn spawn_process(
    inner: &Arc<AcpAuthInner>,
    account_id: &str,
    verified: &super::super::acp_install::VerifiedInstall,
    operation: &Operation,
) -> Result<(AcpWorker, PathBuf), AcpFailure> {
    let probe_dir = prepare_probe_dir(inner, account_id)
        .await
        .map_err(|_error| AcpFailure {
            code: AcpAuthFailureCode::Io,
            stage: AcpAuthStage::Config,
            retryable: true,
        })?;
    let request = AcpSpawnRequest {
        program: verified.program.clone(),
        args: verified.args.clone(),
        cwd: probe_dir.clone(),
    };
    match AcpWorker::spawn(request, &inner.workers, &operation.cancel).await {
        Ok(worker) => Ok((worker, probe_dir)),
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
