//! 认证命令入口：受理、取消与关闭回收，以及 Settings 提交观察者的接线。
//!
//! 受理与取消都是同步命令：它们只在 owner 锁内更新身份/准入事实并 spawn supervisor，绝不等待
//! 进程、登录或 IO。受理复用 [`crate::config::ConfigRuntime`] 的 Settings command 序列化边界，
//! 因此"canonical 提交 → 身份撤代 → 本次准入"是同一个不可分割的序列，不会有提交插在中间。

use std::sync::{Arc, PoisonError};

use anyhow::Result;
use pl_protocol::studio::{
    AcpAuthFailureCode, AcpAuthSnapshot, AcpAuthState, CancelAcpAuthRequest, StartAcpAuthRequest,
    StudioErrorCode,
};

use super::mapping::{acp_error, acp_failure_error, ensure_operation_id};
use super::operation::{self, OperationPlan};
use super::registry::{AcceptedIntent, AcpAuthInner, ConnectionIdentity, Operation};
use super::worker::{PROCESS_CLEANUP_LIMIT, WorkerSource};
use crate::config::{ConfigRuntime, SettingsCommitObserver, StudioConfig};
use crate::studio::{ProductEventBus, StudioStore};

/// 本 runtime 生命周期内保留的已受理操作身份上限。
///
/// 达到上限后拒绝新的 operation ID，绝不淘汰旧 ID 再重放其副作用（见 design/28 §28.2）。
pub(super) const MAX_ACCEPTED_STARTS: usize = 4096;

/// 认证 owner 本体；`Clone` 只克隆共享句柄，不复制事实。
#[derive(Clone)]
pub(crate) struct AcpAuthRuntime {
    pub(super) inner: Arc<AcpAuthInner>,
}

/// 认证命令的受理结果：canonical 快照与是否改变了领域事实。
///
/// 回执（receipt）由 runtime 用同一 `resource_stamp`/`command_receipt` 风格组装，owner 不复制
/// 第二套回执构造。
pub(crate) struct AcpAuthAcceptance {
    pub snapshot: AcpAuthSnapshot,
    pub changed: bool,
}

impl AcpAuthRuntime {
    pub(crate) fn new(
        store: StudioStore,
        config: ConfigRuntime,
        events: ProductEventBus,
        source: crate::worker_assets::RemoteHelperSource,
    ) -> Self {
        Self {
            inner: Arc::new(AcpAuthInner::new(
                store,
                config,
                events,
                WorkerSource::new(source),
            )),
        }
    }

    /// 安装 Settings 提交观察者，并立即取得当前 canonical 快照的接入身份。
    ///
    /// 安装与首次观察都在 Settings command 锁内完成：不会有提交落在两者之间。
    pub(crate) fn install_settings_observer(&self, config: &ConfigRuntime) -> Result<()> {
        config.install_settings_observer(Arc::new(AcpSettingsObserver {
            inner: Arc::downgrade(&self.inner),
        }))?;
        Ok(())
    }

    /// 当前 canonical 认证快照；纯读取，不启动程序、不检查凭据。
    pub(crate) fn read_state(&self) -> AcpAuthSnapshot {
        self.inner.lock().snapshot()
    }

    /// 受理一次认证操作；命令立即返回受理身份，不等待人工登录或进程退出。
    pub(crate) fn start(&self, request: StartAcpAuthRequest) -> Result<AcpAuthAcceptance> {
        ensure_operation_id(&request.operation_id)?;
        let inner = Arc::clone(&self.inner);
        let requested = request.clone();
        // Settings command 边界：canonical 提交、身份撤代与本次准入共用同一串行序列。
        self.inner
            .config
            .with_canonical_snapshot(move |revision, config| {
                AcpAuthInner::admit(inner, revision, config, requested)
            })?
    }

    /// 取消当前操作；只命中该接入当前 operation，重复取消是幂等受理。
    ///
    /// 已进入收束阶段（`Closing`）的操作不再接受取消：此时协议结果已确定，只等资源停止，UI 也
    /// 不再提供取消入口。
    pub(crate) fn cancel(&self, request: CancelAcpAuthRequest) -> Result<AcpAuthAcceptance> {
        ensure_operation_id(&request.operation_id)?;
        ensure_operation_id(&request.target_operation_id)?;
        let mut registry = self.inner.lock();
        let (target, cancel, already, closing) = {
            let Some(slot) = registry.slots.get(&request.account_id) else {
                return Err(acp_error(
                    StudioErrorCode::NotFound,
                    "ACP 接入不存在",
                    false,
                ));
            };
            let Some(operation) = slot.operation.as_ref() else {
                return Err(acp_error(
                    StudioErrorCode::Conflict,
                    "该接入没有进行中的认证操作",
                    false,
                ));
            };
            if operation.operation_id != request.target_operation_id {
                return Err(acp_error(
                    StudioErrorCode::Conflict,
                    "目标认证操作已不是当前操作",
                    false,
                ));
            }
            let already = matches!(
                &slot.state,
                AcpAuthState::Cancelling { operation_id }
                    if operation_id == &request.target_operation_id
            );
            let closing = matches!(
                &slot.state,
                AcpAuthState::Closing { operation_id, .. }
                    if operation_id == &request.target_operation_id
            );
            (
                operation.operation_id.clone(),
                operation.cancel.clone(),
                already,
                closing,
            )
        };
        if already {
            // 已经取消并发布：重复取消不推进 revision、不重复发信号。
            let snapshot = registry.snapshot();
            drop(registry);
            return Ok(AcpAuthAcceptance {
                snapshot,
                changed: false,
            });
        }
        if closing {
            // 已在收束：取消截止点已过，不先置 Cancelling 再成功。
            return Err(acp_error(
                StudioErrorCode::Conflict,
                "认证已进入收束阶段，不能再取消",
                false,
            ));
        }
        {
            let Some(slot) = registry.slots.get_mut(&request.account_id) else {
                return Err(acp_error(
                    StudioErrorCode::NotFound,
                    "ACP 接入不存在",
                    false,
                ));
            };
            slot.state = AcpAuthState::Cancelling {
                operation_id: target.clone(),
            };
        }
        registry.bump();
        let snapshot = registry.snapshot();
        drop(registry);
        // 先发布取消中，再发信号：收尾与终态仍由 operation supervisor 在资源停止后发布。
        cancel.cancel();
        self.inner.emit(snapshot.clone());
        Ok(AcpAuthAcceptance {
            snapshot,
            changed: true,
        })
    }

    /// 原子封闭准入并只发取消信号（early-exit 广播与关闭编排的取消阶段）。
    ///
    /// 封闭发生在同一 owner 锁内、先于任何取消与 join 快照，因此不会有新 worker 在此期间登记。
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
        for operation in operations {
            let handle = operation
                .join
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .take();
            let Some(mut handle) = handle else {
                issues.push(format!(
                    "ACP auth operation {} has no join handle",
                    operation.operation_id
                ));
                continue;
            };
            let deadline = tokio::time::sleep(PROCESS_CLEANUP_LIMIT);
            tokio::pin!(deadline);
            let completed = tokio::select! {
                result = &mut handle => Some(result.is_ok()),
                _ = &mut deadline => None,
            };
            match completed {
                Some(true) => {}
                Some(false) => issues.push(format!(
                    "ACP auth operation {} ended without a clean join",
                    operation.operation_id
                )),
                None => {
                    // 预算内未收束：句柄放回 owner，下一次关闭/重试继续 join 同一任务。
                    *operation
                        .join
                        .lock()
                        .unwrap_or_else(PoisonError::into_inner) = Some(handle);
                    issues.push(format!(
                        "ACP auth operation {} did not finish within the shutdown budget",
                        operation.operation_id
                    ));
                }
            }
        }
        if issues.is_empty() {
            Ok(())
        } else {
            Err(anyhow::Error::msg(issues.join("; ")))
        }
    }
}

/// Settings 提交观察者适配器：只持有 owner 的 `Weak`，避免 ConfigRuntime ↔ 运行时 owner 的
/// `Arc` 环。
struct AcpSettingsObserver {
    inner: std::sync::Weak<AcpAuthInner>,
}

impl SettingsCommitObserver for AcpSettingsObserver {
    fn settings_committed(&self, revision: u64, config: &StudioConfig) {
        if let Some(inner) = self.inner.upgrade() {
            inner.observe_committed(revision, config);
        }
    }
}

impl AcpAuthInner {
    /// 在 Settings command 边界内完成一次准入。
    ///
    /// `settings_revision` 与 `config` 来自同一串行边界，因此 plan、连接身份、期望 revision 与
    /// 登记都描述同一份配置事实；任何不匹配都是陈旧请求，返回 `StaleRevision` 而不派生进程。
    pub(super) fn admit(
        inner: Arc<Self>,
        settings_revision: u64,
        config: &StudioConfig,
        request: StartAcpAuthRequest,
    ) -> Result<AcpAuthAcceptance> {
        let Some(account) = config.acp.accounts.get(&request.account_id).cloned() else {
            return Err(acp_error(
                StudioErrorCode::NotFound,
                "ACP 接入不存在",
                false,
            ));
        };
        if !std::path::Path::new(account.program.trim()).is_absolute() {
            return Err(acp_failure_error(
                AcpAuthFailureCode::MissingExecutable,
                "ACP server 程序必须是绝对路径",
            ));
        }
        if let pl_protocol::studio::AcpAuthAction::Authenticate { method_id } = &request.action
            && method_id.trim().is_empty()
        {
            return Err(acp_failure_error(
                AcpAuthFailureCode::UnsupportedMethod,
                "ACP 认证方法不能为空",
            ));
        }
        let intent = AcceptedIntent {
            account_id: request.account_id.clone(),
            connection_revision: request.expected_connection_revision,
            action: request.action.clone(),
        };
        let identity = ConnectionIdentity::of(&account);
        let plan = OperationPlan {
            program: account.program,
            args: account.args,
            action: request.action.clone(),
        };

        let mut registry = inner.lock();
        // 关闭闸门与 start 登记共用同一把锁：关闭之后不会再准入任何新进程。
        if registry.closed {
            return Err(acp_error(
                StudioErrorCode::RuntimeStopped,
                "运行时正在关闭，不能开始新的 ACP 认证",
                false,
            ));
        }
        if registry.settings_revision != settings_revision {
            return Err(acp_error(
                StudioErrorCode::StaleRevision,
                "设置已变化，请重新读取设置后再开始认证",
                false,
            ));
        }
        if let Some(recorded) = registry.accepted.get(&request.operation_id).cloned() {
            if recorded != intent {
                return Err(acp_error(
                    StudioErrorCode::Conflict,
                    "该 operationId 已绑定另一个 ACP 认证意图",
                    false,
                ));
            }
            let Some(slot) = registry.slots.get(&request.account_id) else {
                return Err(acp_error(
                    StudioErrorCode::NotFound,
                    "ACP 接入不存在",
                    false,
                ));
            };
            if slot.retired {
                return Err(acp_error(
                    StudioErrorCode::NotFound,
                    "ACP 接入不存在",
                    false,
                ));
            }
            if slot.revision != recorded.connection_revision {
                return Err(acp_error(
                    StudioErrorCode::StaleRevision,
                    "ACP 接入的连接身份已变化，请重新检查",
                    false,
                ));
            }
            // 同一意图重试：返回当前 canonical 快照，不再产生任何副作用。
            let snapshot = registry.snapshot();
            drop(registry);
            return Ok(AcpAuthAcceptance {
                snapshot,
                changed: false,
            });
        }
        if registry.accepted.len() >= MAX_ACCEPTED_STARTS {
            return Err(acp_error(
                StudioErrorCode::Overloaded,
                "已受理的 ACP 认证操作身份过多，请重启运行时后重试",
                true,
            ));
        }

        let (connection_revision, occupied) = {
            let Some(slot) = registry.slots.get(&request.account_id) else {
                return Err(acp_error(
                    StudioErrorCode::NotFound,
                    "ACP 接入不存在",
                    false,
                ));
            };
            if slot.retired {
                return Err(acp_error(
                    StudioErrorCode::NotFound,
                    "ACP 接入不存在",
                    false,
                ));
            }
            if slot.identity != identity || slot.revision != request.expected_connection_revision {
                return Err(acp_error(
                    StudioErrorCode::StaleRevision,
                    "ACP 接入的连接身份已变化，请重新检查",
                    false,
                ));
            }
            (slot.revision, slot.operation.is_some())
        };
        if occupied {
            return Err(acp_error(
                StudioErrorCode::Busy,
                "该接入已有进行中的认证操作",
                true,
            ));
        }

        let generation = registry.mint_generation();
        let operation = Arc::new(Operation {
            operation_id: request.operation_id.clone(),
            account_id: request.account_id.clone(),
            connection_revision,
            generation,
            cancel: tokio_util::sync::CancellationToken::new(),
            join: std::sync::Mutex::new(None),
        });
        let initial = super::mapping::initial_state(&request.action, &request.operation_id);
        {
            let Some(slot) = registry.slots.get_mut(&request.account_id) else {
                return Err(acp_error(
                    StudioErrorCode::Internal,
                    "ACP 接入在受理期间消失",
                    true,
                ));
            };
            slot.operation = Some(Arc::clone(&operation));
            slot.state = initial;
        }
        registry
            .accepted
            .insert(request.operation_id.clone(), intent);
        registry.bump();
        let snapshot = registry.snapshot();
        let task = tokio::spawn(operation::run(
            Arc::clone(&inner),
            Arc::clone(&operation),
            plan,
        ));
        // 在持有 registry 锁时记录 join 出口：并发关闭不会看到“有操作但没有句柄”的中间态。
        *operation
            .join
            .lock()
            .unwrap_or_else(PoisonError::into_inner) = Some(task);
        drop(registry);
        inner.emit(snapshot.clone());
        Ok(AcpAuthAcceptance {
            snapshot,
            changed: true,
        })
    }
}
