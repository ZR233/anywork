//! ACP 认证 owner 的唯一可变事实与状态机。
//!
//! 这里持有：独立 `acpAuth` revision、已观察的 Settings revision 水位、关闭闸门、每条接入的
//! 连接身份与操作槽位、本 runtime 生命周期内的已受理操作身份。接入记录的**创建与退役只发生在
//! [`AcpAuthInner::observe_committed`]**；其它路径（读取、投影、命令准入）都只消费这些事实。

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, PoisonError};

use pl_protocol::studio::{
    AcpAuthAccount, AcpAuthActiveOperation, AcpAuthFailure, AcpAuthSnapshot, AcpAuthState,
    AcpUsageObservation,
};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::config::{AcpDefinitionEntry, AcpDefinitionsSnapshot, ConfigRuntime};
use crate::studio::{ProductEventBus, StudioStore, unix_seconds};

use super::super::acp_worker::WorkerSource;

/// 每条接入在认证 owner 中的代次记录。
pub(super) struct Slot {
    pub(super) identity: ConnectionIdentity,
    /// 该连接身份的非密钥 revision；名称编辑不改变它。
    pub(super) revision: u64,
    pub(super) state: AcpAuthState,
    /// 当前连接代次最近一次额度观察；只存在内存中。
    pub(super) usage: Option<AcpUsageObservation>,
    /// 已从配置删除但仍持有资源责任的退役记录；不进入已发布快照。
    pub(super) retired: bool,
    pub(super) operation: Option<Arc<Operation>>,
}

impl Slot {
    /// 从操作槽位里真正 operation 的冻结身份投影进行中操作。
    ///
    /// 与 state 在同一把 registry 锁内读取：连接已替换但旧操作仍在收束时，保留旧操作
    /// 的真实修订与动作，不按当前 state、时间或 usage 推测（design/28 §28.9）。
    fn active_operation(&self) -> Option<AcpAuthActiveOperation> {
        self.operation
            .as_ref()
            .map(|operation| operation.active_operation_view())
    }

    /// 在 slot 内裁决匹配操作并释放占用；返回该记录是否已退役。
    fn finish_operation(
        &mut self,
        generation: u64,
        connection_revision: u64,
        terminal: AcpAuthState,
        usage_update: Option<AcpUsageObservation>,
    ) -> Option<bool> {
        let operation = self.operation.as_ref()?;
        if operation.generation != generation {
            return None;
        }
        let cancelling = operation.cancel.is_cancelled()
            || matches!(
                &self.state,
                AcpAuthState::Cancelling { operation_id }
                    if operation_id == &operation.operation_id
            );
        let cleanup_failed = matches!(&terminal, AcpAuthState::Failed { failure }
            if matches!(failure.stage, pl_protocol::studio::AcpAuthStage::Close | pl_protocol::studio::AcpAuthStage::Cleanup));
        let decided = if cancelling && !cleanup_failed {
            AcpAuthState::Cancelled
        } else {
            terminal
        };
        let same_connection = self.revision == connection_revision;
        self.operation = None;
        if !self.retired {
            self.state = if same_connection {
                decided
            } else {
                AcpAuthState::Unchecked
            };
            if same_connection
                && !cancelling
                && let Some(usage) = usage_update
            {
                self.usage = Some(usage);
            }
        }
        Some(self.retired)
    }
}

/// ConfigRuntime owns connection revisions; auth only tracks its admitted identity and enabled state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct ConnectionIdentity {
    revision: u64,
    enabled: bool,
    release: Option<super::super::acp_install::ReleaseIdentity>,
}
impl ConnectionIdentity {
    pub(super) fn of(entry: &AcpDefinitionEntry) -> Self {
        Self {
            revision: entry.connection_revision,
            enabled: entry.definition.enabled,
            release: entry
                .definition
                .template_kind()
                .and_then(super::super::acp_install::release_identity),
        }
    }
}

/// 一次进行中的认证操作；owner 只通过它取消与等待，不在此持有进程。
pub(super) struct Operation {
    pub(super) operation_id: String,
    pub(super) account_id: String,
    pub(super) connection_revision: u64,
    pub(super) generation: u64,
    /// 受理时冻结的启动意图；快照投影与收尾裁决都消费它，不重新读取 state。
    pub(super) action: pl_protocol::studio::AcpAuthAction,
    pub(super) cancel: CancellationToken,
    pub(super) authentication: tokio::sync::mpsc::Sender<pl_acp::auth::AuthCommand>,
    /// 关闭编排显式重试实际清理错误；不按固定间隔轮询。
    pub(super) cleanup_retry: tokio::sync::Notify,
    /// supervisor 的真实 join 出口。借用等待，关闭 future 被取消也不会取走句柄。
    pub(super) join: tokio::sync::Mutex<Option<JoinHandle<()>>>,
}

impl Operation {
    /// 该操作冻结身份的活动操作投影；快照投影与 `Busy` 拒绝切面共用同一来源。
    pub(super) fn active_operation_view(&self) -> AcpAuthActiveOperation {
        AcpAuthActiveOperation {
            operation_id: self.operation_id.clone(),
            connection_revision: self.connection_revision,
            action: self.action.clone(),
        }
    }
}

impl std::fmt::Debug for Operation {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("AcpAuthOperation")
            .field("account_id", &self.account_id)
            .field("generation", &self.generation)
            .field("connection_revision", &self.connection_revision)
            .finish_non_exhaustive()
    }
}

/// 一个已受理 operation ID 绑定的完整意图；同 ID 只允许同一意图。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct AcceptedIntent {
    pub(super) account_id: String,
    pub(super) connection_revision: u64,
    pub(super) action: AcceptedAction,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum AcceptedAction {
    Start(pl_protocol::studio::AcpAuthAction),
    Continue {
        target_operation_id: String,
        method_id: String,
    },
}

/// owner 的可变事实：独立 revision、Settings 水位、关闭闸门、连接身份、操作槽位与已受理身份。
#[derive(Default)]
pub(super) struct Registry {
    pub(super) revision: u64,
    pub(super) updated_at: i64,
    pub(super) next_generation: u64,
    /// 已观察过的 Settings revision；只接受不旧于它的快照，绝不回退。
    pub(super) settings_revision: u64,
    /// 关闭闸门：与 start 登记同锁，一旦封闭不再接受新操作。
    pub(super) closed: bool,
    pub(super) slots: BTreeMap<String, Slot>,
    /// 已受理操作身份（含已完成）；容量有界、只增不减，重启运行时才重置。
    pub(super) accepted: BTreeMap<String, AcceptedIntent>,
}

impl Registry {
    pub(super) fn bump(&mut self) {
        self.revision = self.revision.saturating_add(1);
        self.updated_at = unix_seconds();
    }

    pub(super) fn mint_generation(&mut self) -> u64 {
        self.next_generation = self.next_generation.saturating_add(1);
        self.next_generation
    }

    /// 已发布快照：只含当前仍存在于配置中的接入。
    pub(super) fn snapshot(&self) -> AcpAuthSnapshot {
        AcpAuthSnapshot {
            revision: self.revision,
            updated_at: self.updated_at,
            accounts: self
                .slots
                .iter()
                .filter(|(_, slot)| !slot.retired)
                .map(|(account_id, slot)| AcpAuthAccount {
                    account_id: account_id.clone(),
                    connection_revision: slot.revision,
                    state: slot.state.clone(),
                    usage: slot.usage.clone(),
                    active_operation: slot.active_operation(),
                })
                .collect(),
        }
    }
}

pub(super) struct AcpAuthInner {
    pub(super) store: StudioStore,
    pub(super) config: ConfigRuntime,
    events: ProductEventBus,
    pub(super) workers: WorkerSource,
    registry: Mutex<Registry>,
}

impl AcpAuthInner {
    pub(super) fn new(
        store: StudioStore,
        config: ConfigRuntime,
        events: ProductEventBus,
        workers: WorkerSource,
    ) -> Self {
        Self {
            store,
            config,
            events,
            workers,
            registry: Mutex::new(Registry::default()),
        }
    }

    pub(super) fn lock(&self) -> std::sync::MutexGuard<'_, Registry> {
        self.registry.lock().unwrap_or_else(PoisonError::into_inner)
    }

    pub(super) fn emit(&self, snapshot: AcpAuthSnapshot) {
        self.events
            .emit(crate::StudioProductEventKind::AcpAuthStateChanged(
                Box::new(snapshot),
            ));
    }

    /// 与已提交的 canonical Settings 对齐连接身份：新接入登记、身份变化撤旧代次、删除标记退役。
    ///
    /// 由 [`crate::config::SettingsCommitObserver`] 在 Settings command 锁内调用，因此这里看到的
    /// revision 与 canonical 配置是一对不可分割的事实；只接受不旧于已观察水位的快照，迟到的旧
    /// 快照直接忽略，绝不回退 registry 或误取消当前有效操作。
    ///
    /// 只发取消信号，不 join 也不清理进程——真正的收束由操作 supervisor 完成。
    pub(super) fn observe_committed(
        &self,
        settings_revision: u64,
        config: &AcpDefinitionsSnapshot,
    ) {
        let snapshot = {
            let mut registry = self.lock();
            if settings_revision < registry.settings_revision {
                tracing::debug!(
                    observed = registry.settings_revision,
                    incoming = settings_revision,
                    "ignoring stale ACP settings observation"
                );
                return;
            }
            registry.settings_revision = settings_revision;
            let mut changed = false;
            let mut cancelled = 0usize;
            for (account_id, account) in &config.definitions {
                let identity = ConnectionIdentity::of(account);
                if !registry.slots.contains_key(account_id) {
                    let revision = account.connection_revision;
                    registry.slots.insert(
                        account_id.clone(),
                        Slot {
                            identity,
                            revision,
                            state: AcpAuthState::Unchecked,
                            usage: None,
                            retired: false,
                            operation: None,
                        },
                    );
                    changed = true;
                    continue;
                }
                let stale = registry
                    .slots
                    .get(account_id)
                    .is_some_and(|slot| slot.retired || slot.identity != identity);
                if !stale {
                    continue;
                }
                // 定义连接身份或启用资格变化：旧认证操作立即撤销，但保留真实收束责任。
                let revision = account.connection_revision;
                let Some(slot) = registry.slots.get_mut(account_id) else {
                    continue;
                };
                let pending = slot
                    .operation
                    .as_ref()
                    .map(|operation| operation.operation_id.clone());
                slot.identity = identity;
                slot.retired = false;
                slot.revision = revision;
                slot.usage = None;
                // 旧 owner 仍被占用时，新代次显示为 busy 非终态，不能谎称空闲。
                slot.state = match pending.as_ref() {
                    Some(operation_id) => AcpAuthState::Closing {
                        operation_id: operation_id.clone(),
                        failure: None,
                    },
                    None => AcpAuthState::Unchecked,
                };
                if pending.is_some() {
                    if let Some(operation) = slot.operation.as_ref() {
                        operation.cancel.cancel();
                    }
                    cancelled += 1;
                }
                changed = true;
            }
            let known: std::collections::BTreeSet<&String> = config.definitions.keys().collect();
            let removed: Vec<String> = registry
                .slots
                .keys()
                .filter(|account_id| !known.contains(account_id))
                .cloned()
                .collect();
            for account_id in removed {
                let Some(slot) = registry.slots.get_mut(&account_id) else {
                    continue;
                };
                if slot.retired {
                    continue;
                }
                slot.retired = true;
                if let Some(operation) = slot.operation.as_ref() {
                    operation.cancel.cancel();
                    cancelled += 1;
                }
                changed = true;
            }
            // 已退役且没有在途操作的记录不再持有任何资源责任。
            registry
                .slots
                .retain(|_, slot| !(slot.retired && slot.operation.is_none()));
            if cancelled > 0 {
                tracing::info!(
                    accounts = cancelled,
                    "cancelled ACP auth operations after connection identity change"
                );
            }
            if !changed {
                return;
            }
            registry.bump();
            registry.snapshot()
        };
        self.emit(snapshot);
    }

    /// 在当前操作代次内应用一次状态转换；任何身份/代次不匹配都是迟到或过期结果，直接丢弃。
    fn transition_state(
        &self,
        account_id: &str,
        generation: u64,
        connection_revision: u64,
        apply: impl FnOnce(&AcpAuthState) -> Option<AcpAuthState>,
    ) {
        let snapshot = {
            let mut registry = self.lock();
            let Some(slot) = registry.slots.get_mut(account_id) else {
                return;
            };
            if slot.retired || slot.revision != connection_revision {
                tracing::debug!(
                    account = %account_id,
                    "dropping ACP auth result for a stale connection identity"
                );
                return;
            }
            let current = slot
                .operation
                .as_ref()
                .is_some_and(|operation| operation.generation == generation);
            if !current {
                tracing::debug!(
                    account = %account_id,
                    "dropping ACP auth result for a superseded operation"
                );
                return;
            }
            let Some(next) = apply(&slot.state) else {
                return;
            };
            if slot.state == next {
                return;
            }
            slot.state = next;
            registry.bump();
            registry.snapshot()
        };
        self.emit(snapshot);
    }

    /// 发布协议进度：只允许从活跃阶段推进，取消中/收束中/终态一律不被覆盖。
    pub(super) fn publish_progress(
        &self,
        account_id: &str,
        generation: u64,
        connection_revision: u64,
        state: AcpAuthState,
    ) {
        self.transition_state(
            account_id,
            generation,
            connection_revision,
            |current| match current {
                AcpAuthState::Checking { .. }
                | AcpAuthState::Required { .. }
                | AcpAuthState::Authenticating { .. }
                | AcpAuthState::Verifying { .. } => Some(state),
                _ => None,
            },
        );
    }

    /// 进入/更新收束中：busy 非终态，且绝不覆盖已取消代次。
    pub(super) fn publish_closing(
        &self,
        account_id: &str,
        generation: u64,
        connection_revision: u64,
        failure: Option<AcpAuthFailure>,
    ) {
        self.transition_state(
            account_id,
            generation,
            connection_revision,
            |current| match current {
                AcpAuthState::Checking { operation_id }
                | AcpAuthState::Required { operation_id, .. }
                | AcpAuthState::Authenticating { operation_id, .. }
                | AcpAuthState::Verifying { operation_id }
                | AcpAuthState::Closing { operation_id, .. } => Some(AcpAuthState::Closing {
                    operation_id: operation_id.clone(),
                    failure,
                }),
                _ => None,
            },
        );
    }

    /// 提交一次操作的终态并**在同一把锁里**释放匹配的 operation 占用，随后只发一次事件。
    ///
    /// 已受理的取消在同一把锁内最终裁决：业务终态一律收敛为 `Cancelled`（取消胜过迟到成功
    /// 和协议失败），而真实清理失败保留 `Failed` 不被掩盖；退役接入直接移除记录且不
    /// 回显；连接身份在收束期间已变化时，旧结果不回写新代次，而是把新代次重置为 `Unchecked`。
    pub(super) fn complete_operation(
        &self,
        account_id: &str,
        generation: u64,
        connection_revision: u64,
        terminal: AcpAuthState,
        usage_update: Option<AcpUsageObservation>,
    ) {
        let snapshot = {
            let mut registry = self.lock();
            let Some(slot) = registry.slots.get_mut(account_id) else {
                return;
            };
            let Some(retired) =
                slot.finish_operation(generation, connection_revision, terminal, usage_update)
            else {
                return;
            };
            // 退役记录不再回显，资源确认停止后直接移除。
            if retired {
                registry.slots.remove(account_id);
            }
            registry.bump();
            registry.snapshot()
        };
        self.emit(snapshot);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::studio::{AcpUsageFailureCode, AcpUsageState};

    fn operation(
        generation: u64,
        revision: u64,
        action: pl_protocol::studio::AcpAuthAction,
    ) -> Arc<Operation> {
        Arc::new(Operation {
            operation_id: "op".into(),
            account_id: "account".into(),
            connection_revision: revision,
            generation,
            action,
            cancel: CancellationToken::new(),
            authentication: tokio::sync::mpsc::channel(1).0,
            cleanup_retry: tokio::sync::Notify::new(),
            join: tokio::sync::Mutex::new(None),
        })
    }

    fn observation(checked_at: i64, state: AcpUsageState) -> AcpUsageObservation {
        AcpUsageObservation { checked_at, state }
    }

    fn slot(state: AcpAuthState, usage: Option<AcpUsageObservation>) -> Slot {
        Slot {
            identity: ConnectionIdentity {
                revision: 7,
                enabled: true,
                release: None,
            },
            revision: 7,
            state,
            usage,
            retired: false,
            operation: Some(operation(
                3,
                7,
                pl_protocol::studio::AcpAuthAction::QueryUsage,
            )),
        }
    }

    #[test]
    fn snapshot_projects_the_real_operation_identity_for_both_actions() {
        for action in [
            pl_protocol::studio::AcpAuthAction::Check,
            pl_protocol::studio::AcpAuthAction::QueryUsage,
        ] {
            let mut registry = Registry::default();
            registry.slots.insert(
                "account".into(),
                Slot {
                    identity: ConnectionIdentity {
                        provider: AcpProvider::Antigravity,
                        release: None,
                    },
                    revision: 7,
                    state: AcpAuthState::Checking {
                        operation_id: "op".into(),
                    },
                    usage: None,
                    retired: false,
                    operation: Some(operation(3, 7, action.clone())),
                },
            );
            let snapshot = registry.snapshot();
            let account = &snapshot.accounts[0];
            // 忙碌状态的 operationId 与活动操作身份一致；类型来自准入冻结的意图。
            assert_eq!(account.state.operation_id(), Some("op"));
            assert_eq!(
                account.active_operation,
                Some(AcpAuthActiveOperation {
                    operation_id: "op".into(),
                    connection_revision: 7,
                    action: action.clone(),
                })
            );
        }
    }

    #[test]
    fn replaced_connection_keeps_the_old_operation_revision_and_action() {
        let mut registry = Registry::default();
        registry.slots.insert(
            "account".into(),
            Slot {
                identity: ConnectionIdentity {
                    provider: AcpProvider::Antigravity,
                    release: None,
                },
                // observe_committed 的身份变化分支：新修订 + 旧操作仍在收束（Closing）。
                revision: 8,
                state: AcpAuthState::Closing {
                    operation_id: "op".into(),
                    failure: None,
                },
                usage: None,
                retired: false,
                operation: Some(operation(
                    3,
                    7,
                    pl_protocol::studio::AcpAuthAction::QueryUsage,
                )),
            },
        );
        let snapshot = registry.snapshot();
        let account = &snapshot.accounts[0];
        assert_eq!(account.connection_revision, 8);
        // 当前修订与活动操作修订可以不同：保留旧操作的真实类型与修订，不误写新连接。
        assert_eq!(
            account.active_operation,
            Some(AcpAuthActiveOperation {
                operation_id: "op".into(),
                connection_revision: 7,
                action: pl_protocol::studio::AcpAuthAction::QueryUsage,
            })
        );
    }

    #[test]
    fn finishing_or_lacking_an_operation_clears_the_projection() {
        let mut finishing = slot(
            AcpAuthState::Verifying {
                operation_id: "op".into(),
            },
            None,
        );
        finishing.finish_operation(
            3,
            7,
            AcpAuthState::Verified {
                checked_at: 20,
                server: None,
            },
            None,
        );
        assert_eq!(finishing.active_operation(), None);

        let mut registry = Registry::default();
        let mut idle = slot(AcpAuthState::Unchecked, None);
        idle.operation = None;
        registry.slots.insert("account".into(), idle);
        let snapshot = registry.snapshot();
        assert_eq!(snapshot.accounts[0].active_operation, None);
    }

    #[test]
    fn completion_preserves_usage_without_an_explicit_refresh() {
        let previous = observation(10, AcpUsageState::Unavailable);
        let mut slot = slot(
            AcpAuthState::Checking {
                operation_id: "op".into(),
            },
            Some(previous.clone()),
        );
        assert_eq!(
            slot.finish_operation(
                3,
                7,
                AcpAuthState::Verified {
                    checked_at: 20,
                    server: None,
                },
                None,
            ),
            Some(false)
        );
        assert_eq!(slot.usage, Some(previous));
        assert!(slot.operation.is_none());
    }

    #[test]
    fn matching_refresh_replaces_usage_but_cancellation_does_not() {
        let previous = observation(10, AcpUsageState::Unavailable);
        let refreshed = observation(
            20,
            AcpUsageState::Failed {
                code: AcpUsageFailureCode::Query,
            },
        );
        let mut active = slot(
            AcpAuthState::Verifying {
                operation_id: "op".into(),
            },
            Some(previous.clone()),
        );
        active.finish_operation(
            3,
            7,
            AcpAuthState::Verified {
                checked_at: 20,
                server: None,
            },
            Some(refreshed.clone()),
        );
        assert_eq!(active.usage, Some(refreshed.clone()));

        let mut cancelling = slot(
            AcpAuthState::Cancelling {
                operation_id: "op".into(),
            },
            Some(previous.clone()),
        );
        cancelling.finish_operation(
            3,
            7,
            AcpAuthState::Verified {
                checked_at: 20,
                server: None,
            },
            Some(refreshed),
        );
        assert_eq!(cancelling.state, AcpAuthState::Cancelled);
        assert_eq!(cancelling.usage, Some(previous));
    }

    #[test]
    fn stale_connection_completion_does_not_publish_usage() {
        let refreshed = observation(
            20,
            AcpUsageState::Failed {
                code: AcpUsageFailureCode::Query,
            },
        );
        let mut stale = slot(
            AcpAuthState::Verifying {
                operation_id: "op".into(),
            },
            None,
        );
        stale.finish_operation(
            3,
            6,
            AcpAuthState::Verified {
                checked_at: 20,
                server: None,
            },
            Some(refreshed),
        );
        assert_eq!(stale.state, AcpAuthState::Unchecked);
        assert_eq!(stale.usage, None);
        assert!(stale.operation.is_none());
    }

    #[test]
    fn accepted_cancel_wins_business_results_but_preserves_cleanup_failure() {
        use pl_protocol::studio::{AcpAuthFailureCode, AcpAuthStage};
        for stage in [
            AcpAuthStage::Authenticate,
            AcpAuthStage::Probe,
            AcpAuthStage::Close,
            AcpAuthStage::Cleanup,
        ] {
            let mut cancelling = slot(
                AcpAuthState::Cancelling {
                    operation_id: "op".into(),
                },
                None,
            );
            let failure = AcpAuthState::Failed {
                failure: AcpAuthFailure {
                    code: AcpAuthFailureCode::Transport,
                    stage,
                    message: "safe".into(),
                    retryable: true,
                },
            };
            cancelling.finish_operation(3, 7, failure.clone(), None);
            assert_eq!(
                cancelling.state,
                if matches!(stage, AcpAuthStage::Close | AcpAuthStage::Cleanup) {
                    failure
                } else {
                    AcpAuthState::Cancelled
                }
            );
            assert!(cancelling.operation.is_none());
        }
    }
}
