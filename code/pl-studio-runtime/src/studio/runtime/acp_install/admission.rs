//! 安装命令入口：受理、取消与关闭回收。
//!
//! 受理与取消都是同步命令：只在 owner 锁内更新命令台账/准入事实并 spawn supervisor，绝不等待
//! 网络、文件或发布。任务登记、关闭准入、取消裁决、发布准入、终态与占用释放共用同一把锁。
//! 监督任务被单独观测：JoinError（panic）会清槽并发布可观察失败，不会让 busy 永久悬挂
//! （见 design/28 §28.6）。

use std::sync::{Arc, PoisonError};

use anyhow::Result;
use pl_protocol::studio::{
    AcpInstallFailure, AcpInstallFailureCode, AcpInstallSnapshot, AcpInstallStage, AcpInstallState,
    AcpProvider, CancelAcpInstallRequest, StartAcpInstallRequest, StudioErrorCode,
};
use tokio_util::sync::CancellationToken;

use super::mapping::{command_error, ensure_operation_id, failure, failure_command_error};
use super::operation::{self, JOIN_BUDGET, OperationPlan};
use super::registry::{
    AcpInstallInner, BusinessOutcome, CommandIntent, Operation, ResidueHold, Slot,
};
use super::source;

/// 本 runtime 生命周期内保留的命令身份上限（start 与 cancel 共用）。
pub(super) const MAX_ACCEPTED_COMMANDS: usize = 4096;

/// 安装 owner 本体；`Clone` 只克隆共享句柄，不复制事实。
#[derive(Clone)]
pub(crate) struct AcpInstallRuntime {
    pub(super) inner: Arc<AcpInstallInner>,
}

/// 安装命令的受理结果：canonical 快照与是否改变了领域事实。
pub(crate) struct AcpInstallAcceptance {
    pub snapshot: AcpInstallSnapshot,
    pub changed: bool,
}

impl AcpInstallRuntime {
    pub(crate) fn new(
        store: crate::studio::StudioStore,
        events: crate::studio::ProductEventBus,
    ) -> Self {
        Self {
            inner: Arc::new(AcpInstallInner::new(store, events)),
        }
    }

    /// 当前 canonical 安装快照；纯读取，不联网、不扫描、不启动。
    pub(crate) fn read_state(&self) -> AcpInstallSnapshot {
        self.inner.lock().snapshot()
    }

    /// 受理一次准备操作；命令立即返回受理身份，不等待下载或发布。
    pub(crate) fn start(&self, request: StartAcpInstallRequest) -> Result<AcpInstallAcceptance> {
        ensure_operation_id(&request.operation_id)?;
        let target = source::current_target().ok_or_else(|| {
            failure_command_error(&failure(
                AcpInstallFailureCode::UnsupportedPlatform,
                AcpInstallStage::Resolve,
                false,
            ))
        })?;
        let intent = CommandIntent::Start {
            provider: request.provider,
            target: target.to_string(),
        };
        let mut registry = self.inner.lock();
        if registry.closed {
            return Err(command_error(
                StudioErrorCode::RuntimeStopped,
                "运行时正在关闭，不能开始新的 ACP server 准备",
                false,
            ));
        }
        if let Some(recorded) = registry.commands.get(&request.operation_id) {
            if recorded != &intent {
                return Err(command_error(
                    StudioErrorCode::Conflict,
                    "该 operationId 已绑定另一条 ACP 准备命令",
                    false,
                ));
            }
            // 同一意图重试：返回当前 canonical 快照，不再产生任何副作用。
            let snapshot = registry.snapshot();
            drop(registry);
            return Ok(AcpInstallAcceptance {
                snapshot,
                changed: false,
            });
        }
        if registry.commands.len() >= MAX_ACCEPTED_COMMANDS {
            return Err(command_error(
                StudioErrorCode::Overloaded,
                "已受理的 ACP 准备命令身份过多，请重启运行时后重试",
                true,
            ));
        }
        // 上一次操作的资源保管尚未收束时不受理新操作：owner 仍持有真实 Operation，准入占用保持，
        // 关闭阶段会用同一份责任再试。这条检查先于普通 Busy，给出与实际原因一致的提示。
        if let Some(residue) = registry.residue.get(&request.provider) {
            return Err(command_error(
                StudioErrorCode::Conflict,
                &format!(
                    "该平台上一次准备的本地资源未确认收束（{}），请重启运行时后重试",
                    residue.cleanup_failure.message
                ),
                false,
            ));
        }
        if registry
            .slots
            .get(&request.provider)
            .is_some_and(|slot| slot.busy)
        {
            return Err(command_error(
                StudioErrorCode::Busy,
                "该平台已有进行中的 ACP server 准备操作",
                true,
            ));
        }

        let generation = registry.mint_generation();
        let operation = Arc::new(Operation {
            operation_id: request.operation_id.clone(),
            provider: request.provider,
            target: target.to_string(),
            generation,
            cancel: CancellationToken::new(),
            join: std::sync::Mutex::new(None),
            supervisor_joined: std::sync::atomic::AtomicBool::new(false),
            resources: std::sync::Mutex::new(super::registry::OperationResources::default()),
        });
        registry.slots.insert(
            request.provider,
            Slot {
                state: AcpInstallState::Resolving {
                    operation_id: request.operation_id.clone(),
                },
                operation: Some(Arc::clone(&operation)),
                busy: true,
            },
        );
        registry
            .commands
            .insert(request.operation_id.clone(), intent);
        registry.bump();
        let snapshot = registry.snapshot();
        let inner = Arc::clone(&self.inner);
        let task = tokio::spawn(supervise(
            Arc::clone(&inner),
            Arc::clone(&operation),
            OperationPlan {
                provider: request.provider,
            },
        ));
        // 在持有 registry 锁时记录 join 出口：并发关闭不会看到"有操作但没有句柄"的中间态。
        *operation
            .join
            .lock()
            .unwrap_or_else(PoisonError::into_inner) = Some(task);
        drop(registry);
        inner.emit(snapshot.clone());
        Ok(AcpInstallAcceptance {
            snapshot,
            changed: true,
        })
    }

    /// 取消当前操作；只命中该 provider 的当前 operation，重复取消与命令重放都幂等。
    ///
    /// `Publishing` 是已进入提交阶段的不可回滚点，`Closing` 时资源结果也已确定，两者都拒绝取消。
    pub(crate) fn cancel(&self, request: CancelAcpInstallRequest) -> Result<AcpInstallAcceptance> {
        ensure_operation_id(&request.operation_id)?;
        ensure_operation_id(&request.target_operation_id)?;
        let intent = CommandIntent::Cancel {
            provider: request.provider,
            target_operation_id: request.target_operation_id.clone(),
        };
        let mut registry = self.inner.lock();
        if let Some(recorded) = registry.commands.get(&request.operation_id) {
            if recorded != &intent {
                return Err(command_error(
                    StudioErrorCode::Conflict,
                    "该 operationId 已绑定另一条 ACP 准备命令",
                    false,
                ));
            }
            // 同一取消命令重放（含操作已完成）：返回当前 canonical 快照，不产生副作用。
            let snapshot = registry.snapshot();
            drop(registry);
            return Ok(AcpInstallAcceptance {
                snapshot,
                changed: false,
            });
        }
        if registry.commands.len() >= MAX_ACCEPTED_COMMANDS {
            return Err(command_error(
                StudioErrorCode::Overloaded,
                "已受理的 ACP 准备命令身份过多，请重启运行时后重试",
                true,
            ));
        }
        let Some(slot) = registry.slots.get(&request.provider) else {
            return Err(no_active_operation());
        };
        // 已发布终态的操作只是"句柄归属还在"，不是可取消的活动操作。
        if !slot.busy {
            return Err(no_active_operation());
        }
        let Some(operation) = slot.operation.as_ref() else {
            return Err(no_active_operation());
        };
        if operation.operation_id != request.target_operation_id {
            return Err(command_error(
                StudioErrorCode::Conflict,
                "目标准备操作已不是当前操作",
                false,
            ));
        }
        let already = matches!(
            &slot.state,
            AcpInstallState::Cancelling { operation_id }
                if operation_id == &request.target_operation_id
        );
        let published = matches!(
            &slot.state,
            AcpInstallState::Publishing { operation_id, .. }
                if operation_id == &request.target_operation_id
        );
        let closing = matches!(
            &slot.state,
            AcpInstallState::Closing { operation_id, .. }
                if operation_id == &request.target_operation_id
        );
        if already {
            let snapshot = registry.snapshot();
            drop(registry);
            return Ok(AcpInstallAcceptance {
                snapshot,
                changed: false,
            });
        }
        if published {
            return Err(command_error(
                StudioErrorCode::Conflict,
                "准备已进入发布阶段，不能再取消",
                false,
            ));
        }
        if closing {
            return Err(command_error(
                StudioErrorCode::Conflict,
                "准备已进入收束阶段，不能再取消",
                false,
            ));
        }
        let cancel = operation.cancel.clone();
        if let Some(slot) = registry.slots.get_mut(&request.provider) {
            slot.state = AcpInstallState::Cancelling {
                operation_id: request.target_operation_id.clone(),
            };
        }
        registry
            .commands
            .insert(request.operation_id.clone(), intent);
        registry.bump();
        let snapshot = registry.snapshot();
        drop(registry);
        // 先发布取消中，再发信号：收尾与终态仍由 supervisor 在资源收束后发布。
        cancel.cancel();
        self.inner.emit(snapshot.clone());
        Ok(AcpInstallAcceptance {
            snapshot,
            changed: true,
        })
    }

    /// 原子封闭准入并只发取消信号（early-exit 广播与关闭编排的取消阶段）。
    pub(crate) fn signal_cancel(&self) {
        let operations: Vec<Arc<Operation>> = {
            let mut registry = self.inner.lock();
            registry.closed = true;
            registry
                .slots
                .values()
                .filter_map(|slot| slot.operation.clone())
                .collect()
        };
        for operation in operations {
            operation.cancel.cancel();
        }
    }

    /// 取消并等待所有在途操作收束；超时保留 join 句柄，绝不伪报已回收。
    pub(crate) async fn cancel_and_join(&self) -> Result<()> {
        self.signal_cancel();
        let operations: Vec<Arc<Operation>> = {
            let registry = self.inner.lock();
            registry
                .slots
                .values()
                .filter_map(|slot| slot.operation.clone())
                .collect()
        };
        let mut issues: Vec<String> = Vec::new();
        // 本轮不允许做残留收束的 provider：supervisor 终止事实未被确认（join 超时或句柄缺失）。
        let mut skip_residue: std::collections::BTreeSet<AcpProvider> =
            std::collections::BTreeSet::new();
        for operation in operations {
            let provider = operation.provider;
            let Some(mut lease) = JoinLease::take(&operation) else {
                // 句柄不在 owner 手里：只有**确实 joined 过**（由关闭 owner 置位）才算正常结束；
                // 否则是状态未知，fail-closed 并跳过本轮残留收束，保留责任给下一轮。
                if operation.supervisor_joined() {
                    // 句柄已 joined，但该 operation 仍挂在活动 slot 上：说明业务终态/清理责任
                    // 尚未在这一轮之外被确认（可能是并发关闭正在收尾）。存在资源保管则交给残留
                    // 阶段；否则如实报非 Clean，绝不因为"joined"就判整个关闭完成。
                    if self.inner.has_residue(provider) {
                        continue;
                    }
                    skip_residue.insert(provider);
                    issues.push(format!(
                        "ACP install supervisor {} is joined but its closure is not confirmed",
                        operation.operation_id
                    ));
                    continue;
                }
                skip_residue.insert(provider);
                issues.push(format!(
                    "ACP install supervisor {} is neither joined nor confirmed finished",
                    operation.operation_id
                ));
                continue;
            };
            let deadline = tokio::time::sleep(JOIN_BUDGET);
            tokio::pin!(deadline);
            let joined = tokio::select! {
                result = &mut lease.handle_mut() => Some(result),
                _ = &mut deadline => None,
            };
            match joined {
                Some(Ok(())) => {
                    // 真实 await 到终态：这里才允许发布 joined 事实；随后释放句柄归属。
                    operation.mark_supervisor_joined();
                    lease.disarm();
                    self.inner.remove_retired(&operation.operation_id);
                }
                Some(Err(error)) => {
                    // JoinError 是句柄终态，但"业务终态 + 资源收束"都还没确认。这里**不做** cleanup
                    // await：先把清理责任与业务 typed 失败一起登记为残留（同一 owner 提交），随后
                    // 由下面的统一残留阶段收束。这样并发关闭或预算取消都不会看到"joined 但既无
                    // residue、也无 cleanup"的缝。
                    operation.mark_supervisor_joined();
                    lease.disarm();
                    if self.inner.has_residue(provider) {
                        // 已有资源保管：由残留阶段在当前预算内再试。
                        continue;
                    }
                    let business = if error.is_panic() {
                        failure(AcpInstallFailureCode::Io, AcpInstallStage::Close, true)
                    } else {
                        failure(
                            AcpInstallFailureCode::ResourceClose,
                            AcpInstallStage::Close,
                            true,
                        )
                    };
                    // `cleanup_failure` 初值为业务失败的 typed 摘要；清理真正失败时由
                    // `note_residue_failure` 刷新为 ResourceClose/Close。
                    self.inner.hold_residue(
                        provider,
                        ResidueHold {
                            operation: Arc::clone(&operation),
                            operation_id: operation.operation_id.clone(),
                            business: BusinessOutcome::Failed(business.clone()),
                            cleanup_failure: business,
                        },
                    );
                }
                None => {
                    // 预算内未收束：租约 drop 把句柄放回 owner；本轮不做该 provider 的残留收束与
                    // 终态释放，责任留给下一轮。
                    skip_residue.insert(provider);
                    issues.push(format!(
                        "ACP install operation {} did not finish within the shutdown budget",
                        operation.operation_id
                    ));
                }
            }
        }
        // 已结束业务操作的 supervisor 句柄：退休登记是它们唯一的 task owner，这里逐个真实 join。
        // 业务终态早已发布，因此这一步只确认 task 收束，不再改业务状态。
        for operation in self.inner.retired_operations() {
            let operation_id = operation.operation_id.clone();
            let Some(mut lease) = JoinLease::take(&operation) else {
                if operation.supervisor_joined() {
                    self.inner.remove_retired(&operation_id);
                    continue;
                }
                issues.push(format!(
                    "ACP install retired supervisor {operation_id} is neither joined nor confirmed finished"
                ));
                continue;
            };
            let deadline = tokio::time::sleep(JOIN_BUDGET);
            tokio::pin!(deadline);
            let joined = tokio::select! {
                result = &mut lease.handle_mut() => Some(result),
                _ = &mut deadline => None,
            };
            match joined {
                Some(Ok(())) => {
                    operation.mark_supervisor_joined();
                    lease.disarm();
                    self.inner.remove_retired(&operation_id);
                }
                Some(Err(_)) => {
                    // 终态已发布但 task 异常结束：不吞，如实报告非 Clean。
                    operation.mark_supervisor_joined();
                    lease.disarm();
                    self.inner.remove_retired(&operation_id);
                    issues.push(format!(
                        "ACP install retired supervisor {operation_id} terminated without a clean join"
                    ));
                }
                None => {
                    // 租约 drop 把句柄放回 owner，登记保留到下一次关闭。
                    issues.push(format!(
                        "ACP install retired supervisor {operation_id} did not finish within the shutdown budget"
                    ));
                }
            }
        }

        // 清理未收束的残留：owner 仍持有真实 Operation（含未删除的暂存与资产锁）。这里在本 stage 的
        // 预算内用同一份责任做**一次**有界收束尝试：成功才补发终态并释放准入；失败则原样放回，
        // 让关闭保持非 Clean 并保留下一轮重试责任（不做无界后台清理、不静默删除未知目录）。
        for provider in self.inner.residue_providers() {
            if skip_residue.contains(&provider) {
                continue;
            }
            let Some(operation) = self.inner.residue_operation(provider) else {
                continue;
            };
            // 只有已确认 supervisor 终止、且子阶段已 join 的记录才允许进入收束。
            if !operation.supervisor_joined() {
                skip_residue.insert(provider);
                issues.push(format!(
                    "ACP install residue for {} is retained: supervisor termination is not confirmed",
                    provider.as_str()
                ));
                continue;
            }
            match operation::release_staging(&self.inner, &operation).await {
                Ok(()) => self.inner.finish_residue(provider),
                Err(residue_failure) => {
                    issues.push(format!(
                        "ACP install residue for {} from operation {} is not confirmed reclaimed ({} / {})",
                        provider.as_str(),
                        operation.operation_id,
                        residue_failure.code.label(),
                        residue_failure.stage.label()
                    ));
                    // 保管留在 owner 手里；只刷新最新的 typed 摘要与 Closing 事实。
                    self.inner.note_residue_failure(provider, residue_failure);
                }
            }
        }
        // 关闭判据：活动 slot 必须真的不再 busy（终态发布或残留收束成功），否则不能报 Clean。
        for (provider, slot) in self.inner.lock().slots.iter() {
            if slot.busy {
                issues.push(format!(
                    "ACP install operation on {} is still in flight after shutdown",
                    provider.as_str()
                ));
            }
        }
        if issues.is_empty() {
            Ok(())
        } else {
            Err(anyhow::Error::msg(issues.join("; ")))
        }
    }
}

fn no_active_operation() -> anyhow::Error {
    command_error(
        StudioErrorCode::Conflict,
        "该平台没有进行中的 ACP server 准备操作",
        false,
    )
}

/// 观测 supervisor 的 JoinError：panic/取消都是句柄终态，必须清槽并发布可观察失败。
async fn supervise(inner: Arc<AcpInstallInner>, operation: Arc<Operation>, plan: OperationPlan) {
    let provider = operation.provider;
    let generation = operation.generation;
    let worker = tokio::spawn(operation::run(
        Arc::clone(&inner),
        Arc::clone(&operation),
        plan,
    ));
    // 注意：这里**不**记录“已终止”事实。supervisor 自己不能声明自己结束了；只有关闭 owner
    // 真的 await 到这个 JoinHandle 返回，才由它发布 joined 事实。
    let joined = worker.await;
    match joined {
        Ok(()) => {}
        Err(error) => {
            // 句柄终态：先取消并发信号、join 已登记的子任务、清理本操作暂存，最后才释放 busy。
            operation.cancel.cancel();
            let business = if error.is_panic() {
                failure(AcpInstallFailureCode::Io, AcpInstallStage::Close, true)
            } else {
                failure(
                    AcpInstallFailureCode::ResourceClose,
                    AcpInstallStage::Close,
                    true,
                )
            };
            match cleanup_resources(&inner, &operation).await {
                Ok(()) => inner.fail_operation(provider, generation, business),
                Err(cleanup_failure) => {
                    // 清理未收束：把真实资源 owner（含未删除的暂存路径）交给 owner 保管，
                    // 槽位保持 Closing 非终态，关闭时用同一份责任再试。
                    inner.hold_residue(
                        provider,
                        ResidueHold {
                            operation: Arc::clone(&operation),
                            operation_id: operation.operation_id.clone(),
                            business: BusinessOutcome::Failed(business),
                            cleanup_failure,
                        },
                    );
                }
            }
        }
    }
}

/// join 已登记的阻塞阶段任务，并清理本操作拥有的暂存（绝不清理已发布目录）。
async fn cleanup_resources(
    inner: &Arc<AcpInstallInner>,
    operation: &Arc<Operation>,
) -> Result<(), AcpInstallFailure> {
    // 阶段任务（网络下载或阻塞校验/解压/发布）必须真正 join 完才允许释放 busy：这里等它自然
    // 结束，不设"到点就走"的假收束。句柄经租约持有，本函数被丢弃时租约会把句柄放回 owner，
    // 不会变成局部可 detach 的句柄；槽正被借用时 fail-closed。
    operation::join_stage(operation, AcpInstallStage::Close).await?;
    // 暂存释放与正常路径共用同一实现，避免第二套清理事实源。
    operation::release_staging(inner, operation).await
}

/// 关闭等待用的 join 租约：`drop` 时把句柄放回 owner，绝不 detach。
struct JoinLease {
    operation: Arc<Operation>,
    handle: Option<tokio::task::JoinHandle<()>>,
}

impl JoinLease {
    fn take(operation: &Arc<Operation>) -> Option<Self> {
        let handle = operation
            .join
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .take()?;
        Some(Self {
            operation: Arc::clone(operation),
            handle: Some(handle),
        })
    }

    fn handle_mut(&mut self) -> &mut tokio::task::JoinHandle<()> {
        self.handle
            .as_mut()
            .expect("join lease holds a handle until disarm")
    }

    fn disarm(&mut self) {
        self.handle = None;
    }
}

impl Drop for JoinLease {
    fn drop(&mut self) {
        if let Some(handle) = self.handle.take() {
            *self
                .operation
                .join
                .lock()
                .unwrap_or_else(PoisonError::into_inner) = Some(handle);
        }
    }
}
