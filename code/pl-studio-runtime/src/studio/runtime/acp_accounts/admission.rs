//! 认证命令入口：受理、取消与关闭回收，以及 Settings 提交观察者的接线。
//!
//! 受理与取消都是同步命令：它们只在 owner 锁内更新身份/准入事实并 spawn supervisor，绝不等待
//! 进程、登录或 IO。受理复用 [`crate::config::ConfigRuntime`] 的 Settings command 序列化边界，
//! 因此"canonical 提交 → 身份撤代 → 本次准入"是同一个不可分割的序列，不会有提交插在中间。

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::{
    AcpAuthSnapshot, AcpAuthState, CancelAcpAuthRequest, StartAcpAuthRequest, StudioErrorCode,
};
use anyhow::Result;

use super::super::acp_ops::{LedgerCheck, RetainedJoin, RetainedTask};
use super::super::acp_worker::PROCESS_CLEANUP_LIMIT;
use super::mapping::{acp_error, ensure_operation_id, ledger_rejection};
use super::operation::{self, OperationPlan};
use super::registry::{
    AcceptedAction, AcceptedIntent, AcpAccountInner, ConnectionIdentity, Operation,
};
use crate::config::{AcpDefinitionsSnapshot, ConfigRuntime, SettingsCommitObserver};
use crate::studio::{ProductEventBus, StudioStore};
use pl_remote_helper::Executor;

/// 认证 owner 本体；`Clone` 只克隆共享句柄，不复制事实。
#[derive(Clone)]
pub(crate) struct AcpAccountRuntime {
    pub(super) inner: Arc<AcpAccountInner>,
}

/// 认证命令的受理结果：canonical 快照与是否改变了领域事实。
///
/// 回执（receipt）由 runtime 用同一 `resource_stamp`/`command_receipt` 风格组装，owner 不复制
/// 第二套回执构造。
pub(crate) type AcpAccountAcceptance = super::super::acp_ops::TopicAcceptance<AcpAuthSnapshot>;

impl AcpAccountRuntime {
    pub(crate) fn new(
        store: StudioStore,
        config: ConfigRuntime,
        events: ProductEventBus,
        source: Executor,
        mcp_source: crate::host_mcp_assets::HostMcpSource,
    ) -> Self {
        Self {
            inner: Arc::new(AcpAccountInner::new(
                store, config, events, source, mcp_source,
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
        self.start_lifecycle_driver();
        Ok(())
    }

    /// 当前 canonical 认证快照；纯读取，不启动程序、不检查凭据。
    pub(crate) fn read_state(&self) -> AcpAuthSnapshot {
        self.inner.lock().snapshot()
    }

    /// 受理一次认证操作；命令立即返回受理身份，不等待人工登录或进程退出。
    pub(crate) fn start(&self, request: StartAcpAuthRequest) -> Result<AcpAccountAcceptance> {
        ensure_operation_id(&request.operation_id)?;
        let inner = Arc::clone(&self.inner);
        let requested = request.clone();
        // Settings command 边界：canonical 提交、身份撤代与本次准入共用同一串行序列。
        self.inner
            .config
            .with_acp_snapshot(move |revision, config| {
                AcpAccountInner::admit(inner, revision, config, requested)
            })?
    }

    /// 取消当前操作；只命中该接入当前 operation，重复取消是幂等受理。
    ///
    /// 已进入收束阶段（`Closing`）的操作不再接受取消：此时协议结果已确定，只等资源停止，UI 也
    /// 不再提供取消入口。
    pub(crate) fn cancel(&self, request: CancelAcpAuthRequest) -> Result<AcpAccountAcceptance> {
        ensure_operation_id(&request.operation_id)?;
        ensure_operation_id(&request.target_operation_id)?;
        let mut registry = self.inner.lock();
        let (target, cancel, already, closing, preserve_verified) = {
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
            let already = operation.cancel_requested.load(Ordering::Acquire)
                || operation.cancel.is_cancelled()
                || matches!(
                    &slot.state,
                    AcpAuthState::Cancelling { operation_id }
                        if operation_id == &request.target_operation_id
                );
            let closing = matches!(
                &slot.state,
                AcpAuthState::Closing { operation_id, .. }
                    if operation_id == &request.target_operation_id
            );
            let preserve_verified = matches!(operation.action, crate::AcpAuthAction::QueryUsage)
                && matches!(&slot.state, AcpAuthState::Verified { .. });
            (
                operation.operation_id.clone(),
                operation.cancel.clone(),
                already,
                closing,
                preserve_verified,
            )
        };
        if already {
            // 已经取消并发布：重复取消不推进 revision、不重复发信号。
            let snapshot = registry.snapshot();
            drop(registry);
            return Ok(AcpAccountAcceptance {
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
            if let Some(operation) = slot.operation.as_ref() {
                operation.cancel_requested.store(true, Ordering::Release);
            }
            if !preserve_verified {
                slot.state = AcpAuthState::Cancelling {
                    operation_id: target.clone(),
                };
            }
        }
        registry.bump();
        let snapshot = registry.snapshot();
        drop(registry);
        // 先发布取消中，再发信号：收尾与终态仍由 operation supervisor 在资源停止后发布。
        cancel.cancel();
        self.inner.emit(snapshot.clone());
        Ok(AcpAccountAcceptance {
            snapshot,
            changed: true,
        })
    }

    /// 原子封闭准入并只发取消信号（early-exit 广播与关闭编排的取消阶段）。
    ///
    /// 封闭发生在同一 owner 锁内、先于任何取消与 join 快照，因此不会有新 worker 在此期间登记。
    pub(crate) fn signal_cancel(&self) {
        let (operations, snapshot) = {
            let mut registry = self.inner.lock();
            let changed = !registry.closed;
            registry.closed = true;
            let retiring = registry
                .retiring
                .iter()
                .map(|account| account.account_id.clone())
                .collect::<std::collections::BTreeSet<_>>();
            for (id, slot) in &mut registry.slots {
                slot.lifecycle.retry_at = None;
                slot.lifecycle.state = if slot.connection.is_some() || retiring.contains(id) {
                    crate::AcpConnectionState::Stopping
                } else {
                    crate::AcpConnectionState::Stopped
                };
            }
            let operations = registry
                .slots
                .values()
                .filter_map(|slot| slot.operation.clone())
                .collect::<Vec<_>>();
            let snapshot = changed.then(|| {
                registry.bump();
                registry.snapshot()
            });
            (operations, snapshot)
        };
        if let Some(snapshot) = snapshot {
            self.inner.emit(snapshot);
        }
        for connection in self.connections() {
            connection.signal_cancel();
        }
        for operation in operations {
            operation.cancel.cancel();
        }
        self.inner.retirement_wake.notify_one();
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
        let deadline = tokio::time::Instant::now() + PROCESS_CLEANUP_LIMIT;
        let operation_issues =
            futures::future::join_all(operations.into_iter().map(|operation| async move {
                // 超时和取消只丢掉这个 waiter。句柄留在 owner 槽里，已观察的 join 错误
                // 不会在重试时变成“没有句柄”。
                match operation.join.join_until(deadline).await {
                    RetainedJoin::Observed(Ok(())) | RetainedJoin::Settled(Ok(())) => None,
                    RetainedJoin::Observed(Err(_)) | RetainedJoin::Settled(Err(_)) => {
                        Some(format!(
                            "ACP auth operation {} ended without a clean join",
                            operation.operation_id
                        ))
                    }
                    RetainedJoin::Absent => Some(format!(
                        "ACP auth operation {} has no join handle",
                        operation.operation_id
                    )),
                    RetainedJoin::TimedOut => Some(format!(
                        "ACP auth operation {} did not finish within the shutdown budget",
                        operation.operation_id
                    )),
                }
            }))
            .await;
        issues.extend(operation_issues.into_iter().flatten());
        let connection_issues = futures::future::join_all(self.connections().into_iter().map(
            |connection| async move {
                connection
                    .close_until(deadline)
                    .await
                    .err()
                    .map(|error| error.to_string())
            },
        ))
        .await;
        issues.extend(connection_issues.into_iter().flatten());
        if let Err(error) = self.join_lifecycle_driver(deadline).await {
            issues.push(error.to_string());
        }
        if let Some(issue) = self.inner.lock().retirement_issue.clone() {
            issues.push(issue);
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
    inner: std::sync::Weak<AcpAccountInner>,
}

impl SettingsCommitObserver for AcpSettingsObserver {
    fn settings_committed(&self, snapshot: &crate::ConfigRuntimeSnapshot) {
        if let Some(inner) = self.inner.upgrade() {
            inner.observe_committed(snapshot.revision, &snapshot.acp);
            AcpAccountRuntime { inner }.background_prepare(snapshot.revision, &snapshot.acp);
        }
    }
}

impl AcpAccountInner {
    /// 在 Settings command 边界内完成一次准入。
    ///
    /// `settings_revision` 与 `config` 来自同一串行边界，因此 plan、连接身份、期望 revision 与
    /// 登记都描述同一份配置事实；任何不匹配都是陈旧请求，返回 `StaleRevision` 而不派生进程。
    pub(super) fn admit(
        inner: Arc<Self>,
        settings_revision: u64,
        config: &AcpDefinitionsSnapshot,
        request: StartAcpAuthRequest,
    ) -> Result<AcpAccountAcceptance> {
        Self::admit_operation(inner, settings_revision, config, request, false)
    }

    pub(super) fn admit_background(
        inner: Arc<Self>,
        settings_revision: u64,
        config: &AcpDefinitionsSnapshot,
        request: StartAcpAuthRequest,
    ) -> Result<AcpAccountAcceptance> {
        Self::admit_operation(inner, settings_revision, config, request, true)
    }

    fn admit_operation(
        inner: Arc<Self>,
        settings_revision: u64,
        config: &AcpDefinitionsSnapshot,
        request: StartAcpAuthRequest,
        background: bool,
    ) -> Result<AcpAccountAcceptance> {
        let Some(account) = config.definitions.get(&request.account_id).cloned() else {
            return Err(acp_error(
                StudioErrorCode::NotFound,
                "ACP 接入不存在",
                false,
            ));
        };
        if !account.definition.enabled {
            return Err(acp_error(
                StudioErrorCode::Conflict,
                "ACP definition is disabled",
                false,
            ));
        }
        if matches!(request.action, crate::AcpAuthAction::QueryUsage)
            && !super::strategy::AcpAgentStrategy::for_definition(&account.definition)
                .supports_usage()
        {
            return Err(acp_error(
                StudioErrorCode::InvalidArgument,
                "usage is only available for the managed template",
                false,
            ));
        }
        let intent = AcceptedIntent {
            account_id: request.account_id.clone(),
            connection_revision: request.expected_connection_revision,
            action: AcceptedAction::Start(request.action.clone()),
        };
        let identity = ConnectionIdentity::of(&account);
        let (authentication, commands) = tokio::sync::mpsc::channel(1);
        let plan = OperationPlan {
            definition: account.definition.clone(),
            action: request.action.clone(),
            commands,
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
        let replay = match registry
            .accepted
            .check_or_replay(&request.operation_id, &intent)
        {
            Ok(LedgerCheck::Fresh) => None,
            Ok(LedgerCheck::Replay(recorded)) => Some(recorded),
            Err(error) => return Err(ledger_rejection(error)),
        };
        if let Some(recorded) = replay {
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
            return Ok(AcpAccountAcceptance {
                snapshot,
                changed: false,
            });
        }
        if !background && let Err(error) = registry.accepted.ensure_capacity() {
            return Err(ledger_rejection(error));
        }

        let (connection_revision, busy) = {
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
            // 忙碌切面与拒绝裁决同锁捕获：账号当前修订、快照修订与占用操作身份
            // 描述同一时刻，不能在解锁后重读或拼接较新修订（design/28 §28.9）。
            let busy = slot
                .operation
                .as_ref()
                .map(|operation| crate::AcpAuthBusyRejection {
                    acp_auth_busy: crate::AcpAuthBusyDetails {
                        account_id: request.account_id.clone(),
                        connection_revision: slot.revision,
                        snapshot_revision: registry.revision,
                        active_operation: operation.active_operation_view(),
                    },
                });
            (slot.revision, busy)
        };
        if let Some(busy) = busy {
            return Err(super::mapping::acp_busy_error(busy));
        }

        let generation = registry.mint_generation();
        let operation = Arc::new(Operation {
            operation_id: request.operation_id.clone(),
            account_id: request.account_id.clone(),
            connection_revision,
            generation,
            // 冻结准入意图：后续快照投影与收尾裁决都以此为准，不回读 state。
            action: request.action.clone(),
            cancel: tokio_util::sync::CancellationToken::new(),
            cancel_requested: AtomicBool::new(false),
            authentication,
            join: RetainedTask::empty(),
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
            let preserve_verified = matches!(request.action, crate::AcpAuthAction::QueryUsage)
                && matches!(slot.state, AcpAuthState::Verified { .. })
                && matches!(slot.lifecycle.state, crate::AcpConnectionState::Ready);
            slot.operation = Some(Arc::clone(&operation));
            if !preserve_verified {
                slot.state = initial;
            }
            // An explicit check/login supersedes a scheduled initial check, without a second
            // command identity or a second process. Background work has no public dedup entry.
            slot.background_scheduled = true;
            if !background {
                slot.lifecycle.retry_at = None;
                if !matches!(slot.lifecycle.state, crate::AcpConnectionState::Ready) {
                    slot.lifecycle.state = crate::AcpConnectionState::Starting;
                }
                if let Some(connection) = slot.connection.as_ref() {
                    connection.launch_now.notify_one();
                }
            }
        }
        if !background {
            registry
                .accepted
                .record(request.operation_id.clone(), intent)
                .expect("ACP auth identity capacity was checked under this lock");
        }
        registry.bump();
        let snapshot = registry.snapshot();
        let task = tokio::spawn(operation::run(
            Arc::clone(&inner),
            Arc::clone(&operation),
            plan,
        ));
        // 在持有 registry 锁时记录 join 出口：并发关闭不会看到“有操作但没有句柄”的中间态。
        operation.join.install(task);
        drop(registry);
        inner.emit(snapshot.clone());
        Ok(AcpAccountAcceptance {
            snapshot,
            changed: true,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::super::test_support::test_runtime;
    use super::*;
    use crate::StudioRuntime;
    use crate::config::{AcpProvider, AcpServiceDefinition};
    use crate::{
        AcpAuthAction, AcpAuthActiveOperation, AcpAuthBusyDetails, AcpAuthBusyRejection,
        StudioError,
    };
    use std::sync::Arc;
    use tokio_util::sync::CancellationToken;

    async fn test_account_runtime() -> Result<(tempfile::TempDir, StudioRuntime)> {
        test_runtime(|paths| {
            std::fs::create_dir_all(paths.acp_dir())?;
            std::fs::write(
                paths.acp_dir().join("account.toml"),
                AcpServiceDefinition::template(
                    "account".into(),
                    "Antigravity".into(),
                    AcpProvider::Antigravity,
                )
                .encode()?,
            )?;
            Ok(())
        })
        .await
    }

    /// 用真实受理身份的冻结字段占用槽位；busy 状态与占用操作保持一致。
    fn occupy_slot(runtime: &StudioRuntime, action: AcpAuthAction) -> (u64, u64) {
        let mut registry = runtime.acp_accounts.inner.lock();
        let generation = registry.mint_generation();
        let slot = registry
            .slots
            .get_mut("account")
            .expect("configured account");
        let frozen_revision = slot.revision;
        let (sender, _commands) = tokio::sync::mpsc::channel(1);
        slot.operation = Some(Arc::new(Operation {
            operation_id: "flow".into(),
            account_id: "account".into(),
            connection_revision: frozen_revision,
            generation,
            action,
            cancel: CancellationToken::new(),
            cancel_requested: AtomicBool::new(false),
            authentication: sender,
            join: RetainedTask::empty(),
        }));
        slot.state = AcpAuthState::Checking {
            operation_id: "flow".into(),
        };
        (frozen_revision, generation)
    }

    fn busy_rejection(
        runtime: &StudioRuntime,
        expected_connection_revision: u64,
    ) -> crate::AcpAuthBusyRejection {
        let error = match runtime.acp_accounts.start(StartAcpAuthRequest {
            operation_id: "second".into(),
            account_id: "account".into(),
            expected_connection_revision,
            action: AcpAuthAction::QueryUsage,
        }) {
            Ok(_) => panic!("occupied slot must reject a new start"),
            Err(error) => error,
        };
        let error = error
            .downcast_ref::<StudioError>()
            .expect("admission errors are typed StudioError");
        assert_eq!(error.code, StudioErrorCode::Busy);
        assert!(error.retryable);
        assert_eq!(error.message, "该接入已有进行中的认证操作");
        serde_json::from_value(
            error
                .details
                .as_deref()
                .expect("busy rejection carries details")
                .clone(),
        )
        .expect("typed busy rejection details")
    }

    #[tokio::test]
    async fn busy_rejection_carries_the_atomic_slot_slice() -> Result<()> {
        for action in [AcpAuthAction::Check, AcpAuthAction::QueryUsage] {
            let (home, runtime) = test_account_runtime().await?;
            let (revision, generation) = occupy_slot(&runtime, action.clone());
            let snapshot_revision = runtime.acp_accounts.inner.lock().revision;
            // 请求动作与占用方不同也只投影占用方的真实身份与动作。
            let rejection = busy_rejection(&runtime, revision);
            assert_eq!(
                rejection,
                AcpAuthBusyRejection {
                    acp_auth_busy: AcpAuthBusyDetails {
                        account_id: "account".into(),
                        connection_revision: revision,
                        snapshot_revision,
                        active_operation: AcpAuthActiveOperation {
                            operation_id: "flow".into(),
                            connection_revision: revision,
                            action,
                        },
                    },
                }
            );
            // fake 操作没有 supervisor 句柄：按真实终态路径释放槽位后再关闭运行时。
            runtime.acp_accounts.inner.complete_operation(
                "account",
                generation,
                revision,
                AcpAuthState::Verified {
                    checked_at: 1,
                    server: None,
                },
                None,
            );
            runtime.shutdown_runtime().await?;
            drop(home);
        }
        Ok(())
    }

    #[tokio::test]
    async fn busy_rejection_keeps_the_old_connection_slice_after_replacement() -> Result<()> {
        let (_home, runtime) = test_account_runtime().await?;
        let (frozen_revision, generation) = occupy_slot(&runtime, AcpAuthAction::QueryUsage);
        // 模拟 observe_committed 的身份变化分支：账号已换新修订，旧操作仍在收束。
        let current_revision = {
            let mut registry = runtime.acp_accounts.inner.lock();
            let slot = registry
                .slots
                .get_mut("account")
                .expect("configured account");
            let revision = slot.revision.checked_add(1).expect("test revision");
            slot.revision = revision;
            slot.state = AcpAuthState::Closing {
                operation_id: "flow".into(),
                failure: None,
            };
            revision
        };
        assert_ne!(current_revision, frozen_revision);
        let rejection = busy_rejection(&runtime, current_revision);
        // 账号修订是当前值，占用身份仍是旧连接的冻结修订与动作。
        assert_eq!(
            rejection.acp_auth_busy.connection_revision,
            current_revision
        );
        assert_eq!(
            rejection.acp_auth_busy.active_operation,
            AcpAuthActiveOperation {
                operation_id: "flow".into(),
                connection_revision: frozen_revision,
                action: AcpAuthAction::QueryUsage,
            }
        );
        // fake 操作没有 supervisor 句柄：按真实终态路径释放槽位后再关闭运行时。
        runtime.acp_accounts.inner.complete_operation(
            "account",
            generation,
            frozen_revision,
            AcpAuthState::Verified {
                checked_at: 1,
                server: None,
            },
            None,
        );
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn busy_slice_is_immutable_after_the_occupant_finishes() -> Result<()> {
        let (_home, runtime) = test_account_runtime().await?;
        let (revision, generation) = occupy_slot(&runtime, AcpAuthAction::Check);
        let snapshot_revision = runtime.acp_accounts.inner.lock().revision;
        let rejection = busy_rejection(&runtime, revision);
        // 占用方终态：快照修订前进、槽位释放。
        runtime.acp_accounts.inner.complete_operation(
            "account",
            generation,
            revision,
            AcpAuthState::Verified {
                checked_at: 20,
                server: None,
            },
            None,
        );
        let advanced = runtime.acp_accounts.inner.lock().revision;
        assert!(advanced > snapshot_revision);
        // 已返回的切面不被占用方后续终态改写。
        assert_eq!(rejection.acp_auth_busy.snapshot_revision, snapshot_revision);
        assert_eq!(
            rejection.acp_auth_busy.active_operation,
            AcpAuthActiveOperation {
                operation_id: "flow".into(),
                connection_revision: revision,
                action: AcpAuthAction::Check,
            }
        );
        // 槽位已释放：新的 start 不再被 Busy 拒绝。
        let accepted = runtime.acp_accounts.start(StartAcpAuthRequest {
            operation_id: "after-settle".into(),
            account_id: "account".into(),
            expected_connection_revision: revision,
            action: AcpAuthAction::Check,
        });
        assert!(accepted.is_ok());
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn idle_admission_and_non_busy_errors_carry_no_fabricated_details() -> Result<()> {
        let (_home, runtime) = test_account_runtime().await?;
        let revision = runtime.acp_accounts.inner.lock().slots["account"].revision;
        // 未占用：正常受理，没有任何错误详情。
        let accepted = runtime.acp_accounts.start(StartAcpAuthRequest {
            operation_id: "first".into(),
            account_id: "account".into(),
            expected_connection_revision: revision,
            action: AcpAuthAction::Check,
        })?;
        assert!(accepted.changed);
        // 非 Busy 拒绝不附加虚构字段。
        let stale = match runtime.acp_accounts.start(StartAcpAuthRequest {
            operation_id: "second".into(),
            account_id: "account".into(),
            expected_connection_revision: revision + 100,
            action: AcpAuthAction::Check,
        }) {
            Ok(_) => panic!("a stale connection revision must be rejected"),
            Err(error) => error,
        };
        let stale = stale
            .downcast_ref::<StudioError>()
            .expect("admission errors are typed StudioError");
        assert_eq!(stale.code, StudioErrorCode::StaleRevision);
        assert!(stale.details.is_none());
        runtime.shutdown_runtime().await?;
        Ok(())
    }
}
