//! ACP 认证 owner 的唯一可变事实与状态机。
//!
//! 这里持有：独立 `acpAuth` revision、已观察的 Settings revision 水位、关闭闸门、每条接入的
//! 连接身份与操作槽位、本 runtime 生命周期内的已受理操作身份。接入记录的**创建与退役只发生在
//! [`AcpAuthInner::observe_committed`]**；其它路径（读取、投影、命令准入）都只消费这些事实。

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, PoisonError};

use pl_protocol::studio::{AcpAuthAccount, AcpAuthFailure, AcpAuthSnapshot, AcpAuthState};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::config::{AcpAccountConfig, AcpProvider, ConfigRuntime, StudioConfig};
use crate::studio::{ProductEventBus, StudioStore, unix_seconds};

use super::worker::WorkerSource;

/// 每条接入在认证 owner 中的代次记录。
pub(super) struct Slot {
    pub(super) identity: ConnectionIdentity,
    /// 该连接身份的非密钥 revision；名称编辑不改变它。
    pub(super) revision: u64,
    pub(super) state: AcpAuthState,
    /// 已从配置删除但仍持有资源责任的退役记录；不进入已发布快照。
    pub(super) retired: bool,
    pub(super) operation: Option<Arc<Operation>>,
}

/// 真正决定连接语义的身份：provider、程序与字面参数。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct ConnectionIdentity {
    pub(super) provider: AcpProvider,
    pub(super) program: String,
    pub(super) args: Vec<String>,
}

impl ConnectionIdentity {
    pub(super) fn of(account: &AcpAccountConfig) -> Self {
        Self {
            provider: account.provider,
            program: account.program.clone(),
            args: account.args.clone(),
        }
    }
}

/// 一次进行中的认证操作；owner 只通过它取消与等待，不在此持有进程。
pub(super) struct Operation {
    pub(super) operation_id: String,
    pub(super) account_id: String,
    pub(super) connection_revision: u64,
    pub(super) generation: u64,
    pub(super) cancel: CancellationToken,
    /// supervisor 任务的真实 join 出口；`None` 只出现在任务已收束后的短暂窗口。
    pub(super) join: Mutex<Option<JoinHandle<()>>>,
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
    pub(super) action: pl_protocol::studio::AcpAuthAction,
}

/// owner 的可变事实：独立 revision、Settings 水位、关闭闸门、连接身份、操作槽位与已受理身份。
#[derive(Default)]
pub(super) struct Registry {
    pub(super) revision: u64,
    pub(super) updated_at: i64,
    pub(super) next_generation: u64,
    pub(super) next_connection_revision: u64,
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

    pub(super) fn mint_connection_revision(&mut self) -> u64 {
        self.next_connection_revision = self.next_connection_revision.saturating_add(1);
        self.next_connection_revision
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
    pub(super) fn observe_committed(&self, settings_revision: u64, config: &StudioConfig) {
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
            for (account_id, account) in &config.acp.accounts {
                let identity = ConnectionIdentity::of(account);
                if !registry.slots.contains_key(account_id) {
                    let revision = registry.mint_connection_revision();
                    registry.slots.insert(
                        account_id.clone(),
                        Slot {
                            identity,
                            revision,
                            state: AcpAuthState::Unchecked,
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
                // 程序、参数或 provider 变化：旧代次立即失效，已有操作被撤消。
                let revision = registry.mint_connection_revision();
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
            let known: std::collections::BTreeSet<&String> = config.acp.accounts.keys().collect();
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
    /// 已受理的取消在同一把锁内最终裁决：非失败终态一律收敛为 `Cancelled`（取消胜过迟到的
    /// `Required`/`Verified`），而真实清理失败保留 `Failed` 不被掩盖；退役接入直接移除记录且不
    /// 回显；连接身份在收束期间已变化时，旧结果不回写新代次，而是把新代次重置为 `Unchecked`。
    pub(super) fn complete_operation(
        &self,
        account_id: &str,
        generation: u64,
        connection_revision: u64,
        terminal: AcpAuthState,
    ) {
        let snapshot = {
            let mut registry = self.lock();
            let Some(slot) = registry.slots.get_mut(account_id) else {
                return;
            };
            let Some(operation) = slot.operation.as_ref() else {
                return;
            };
            if operation.generation != generation {
                return;
            }
            let cancelling = matches!(
                &slot.state,
                AcpAuthState::Cancelling { operation_id }
                    if operation_id == &operation.operation_id
            );
            let decided = if cancelling && !matches!(&terminal, AcpAuthState::Failed { .. }) {
                AcpAuthState::Cancelled
            } else {
                terminal
            };
            let retired = slot.retired;
            let same_generation = slot.revision == connection_revision;
            slot.operation = None;
            if !retired {
                slot.state = if same_generation {
                    decided
                } else {
                    // 旧代次的协议结果不得回写新连接身份。
                    AcpAuthState::Unchecked
                };
            }
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
