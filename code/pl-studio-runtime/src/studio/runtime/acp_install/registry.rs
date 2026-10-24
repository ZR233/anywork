//! ACP 官方 server 安装 owner 的唯一可变事实与状态机。
//!
//! 这里持有：独立 `acpInstall` revision、关闭闸门、每 provider 当前宿主 target 的操作槽位，以及
//! 本 runtime 生命周期内的命令身份台账（start 与 cancel 共用一份，防止同 ID 改参数重放）。
//! 任务登记可见性、关闭准入、取消裁决、发布准入、最终状态与占用释放共用同一把 owner 锁，因此
//! "受理→取消→发布→终态→释放"是一条线性化序列（见 design/28 §28.6）。

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, PoisonError};

use pl_protocol::studio::{
    AcpInstallEntry, AcpInstallFailure, AcpInstallFailureCode, AcpInstallRelease,
    AcpInstallSnapshot, AcpInstallStage, AcpInstallState, AcpInstalledServer, AcpProvider,
};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::studio::{ProductEventBus, unix_seconds};

use super::mapping::failure;

/// 每操作独立的资源 owner：当前阻塞阶段任务与自有暂存都登记在这里，登记先于等待。
///
/// 该 owner 让 supervisor 即使在 `run` panic/abort 之后也能取回并 join 已启动的子任务，
/// 从而不会在旧写者仍运行时释放 busy。
#[derive(Default)]
pub(super) struct OperationResources {
    /// 阶段任务槽：显式区分"空闲 / 已登记 / 租约借用中"，空槽不再被当作“可以重建”。
    pub(super) stage: StageSlot,
    /// 本操作拥有的暂存目录；发布提交成功后清空（绝不清理已发布目录）。
    pub(super) staging: Option<PathBuf>,
    /// 发布是否已提交；一旦为真，暂存不再由本操作清理。
    pub(super) committed: bool,
    /// 该资产跨进程锁的唯一真实 hold：存活到所有阶段任务实际 join 且 cleanup 结果确认为止。
    pub(super) lock_file: Option<std::fs::File>,
}

/// 阶段任务槽的状态。
///
/// 转移（全部在 [`Operation::resources`] 的锁内完成，单线程顺序推进）：
/// `Idle --begin_stage--> Leased --install_stage--> Registered(handle)`
/// `Registered --take_stage--> Leased --(lease disarm)--> Idle`
/// `Leased --(lease drop)--> Registered(handle)`（等待被打断时把句柄放回 owner）
///
/// `Leased` 期间槽里没有句柄，但它**不是空闲**：任何"重建/覆盖"都必须先 `take_stage` 拿到
/// 失败并 fail-closed，避免创建后登记失败或双写者共存。
#[derive(Default)]
pub(super) enum StageSlot {
    #[default]
    Idle,
    Registered(JoinHandle<()>),
    Leased,
}

impl std::fmt::Debug for StageSlot {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Idle => formatter.write_str("Idle"),
            Self::Registered(_) => formatter.write_str("Registered"),
            Self::Leased => formatter.write_str("Leased"),
        }
    }
}

/// 一次进行中的安装操作；owner 只通过它取消与等待，不在锁内做 IO。
pub(super) struct Operation {
    pub(super) operation_id: String,
    pub(super) provider: AcpProvider,
    /// 本次操作冻结的宿主 target；同一 provider 的槽位按它隔离。
    pub(super) target: String,
    pub(super) generation: u64,
    pub(super) cancel: CancellationToken,
    /// supervisor 任务的真实 join 出口；`None` 只出现在任务已收束后的短暂窗口。
    pub(super) join: Mutex<Option<JoinHandle<()>>>,
    /// supervisor 的 JoinHandle 是否**真的被 await 到终止**。
    /// 只有关闭 owner 在拿到真实句柄并观测到终态后才置位；supervisor 自己不能声明。
    pub(super) supervisor_joined: std::sync::atomic::AtomicBool,
    /// 本操作的阶段任务/暂存/资产锁资源 owner。
    pub(super) resources: Mutex<OperationResources>,
}

impl std::fmt::Debug for Operation {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("AcpInstallOperation")
            .field("provider", &self.provider)
            .field("target", &self.target)
            .field("generation", &self.generation)
            .finish_non_exhaustive()
    }
}

impl Operation {
    /// supervisor 是否已被观测到终止。
    pub(super) fn supervisor_joined(&self) -> bool {
        self.supervisor_joined
            .load(std::sync::atomic::Ordering::SeqCst)
    }

    /// 由**关闭 owner** 在真实 JoinHandle await 返回终态后调用；supervisor 自身不置位。
    pub(super) fn mark_supervisor_joined(&self) {
        self.supervisor_joined
            .store(true, std::sync::atomic::Ordering::SeqCst);
    }

    /// 终态发布时释放重型资源（资产锁/暂存路径），但**保留** supervisor 句柄归属。
    pub(super) fn release_heavy_resources(&self) {
        let mut resources = self
            .resources
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        resources.lock_file = None;
    }
}

/// 阶段槽的占位凭据：先占槽、再 spawn、最后 `install`。
///
/// 占位与装填之间没有任何 `await`/`?`，因此句柄一旦创建就必然进入槽；若占位后因任何原因没有
/// 装填，`Drop` 把槽还原为 `Idle`，不会留下永久 `Leased`。
pub(super) struct StageReservation<'a> {
    operation: &'a Operation,
    installed: bool,
}

impl StageReservation<'_> {
    /// 装填已启动的任务句柄；这是唯一释放占位的方式。
    pub(super) fn install(mut self, task: JoinHandle<()>) {
        let mut resources = self
            .operation
            .resources
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        resources.stage = StageSlot::Registered(task);
        self.installed = true;
    }
}

impl Drop for StageReservation<'_> {
    fn drop(&mut self) {
        if self.installed {
            return;
        }
        let mut resources = self
            .operation
            .resources
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        if matches!(resources.stage, StageSlot::Leased) {
            resources.stage = StageSlot::Idle;
        }
    }
}

/// 先占位再 spawn：在创建任务之前就把槽标记为 `Leased`，避免“创建后登记失败丢句柄”。
pub(super) fn begin_stage(
    operation: &Operation,
    stage: AcpInstallStage,
) -> Result<StageReservation<'_>, AcpInstallFailure> {
    let mut resources = operation
        .resources
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    match resources.stage {
        StageSlot::Idle => {
            resources.stage = StageSlot::Leased;
            Ok(StageReservation {
                operation,
                installed: false,
            })
        }
        // 槽里已有登记的句柄或正被租约借用：拒绝重入，保留原有责任。
        StageSlot::Registered(_) | StageSlot::Leased => {
            Err(failure(AcpInstallFailureCode::ResourceClose, stage, false))
        }
    }
}

/// 阶段任务的 join 租约（网络下载 / 阻塞校验、解压、发布 / 暂存清理共用）。
///
/// `take_stage` 只从 `Registered` 取句柄并把槽改成 `Leased`；成功等待后 `disarm` 置 `Idle`，
/// 若等待中途被丢弃，`drop` 把句柄放回 `Registered`。因此责任永远在 owner 手里，"槽为空"从不
/// 被解释成"任务已退出"。
pub(super) struct StageLease {
    operation: Arc<Operation>,
    handle: Option<JoinHandle<()>>,
}

impl StageLease {
    pub(super) fn handle_mut(&mut self) -> &mut JoinHandle<()> {
        self.handle
            .as_mut()
            .expect("stage lease holds a handle until disarm")
    }

    pub(super) fn disarm(&mut self) {
        if self.handle.take().is_some() {
            let mut resources = self
                .operation
                .resources
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            resources.stage = StageSlot::Idle;
        }
    }
}

impl Drop for StageLease {
    fn drop(&mut self) {
        if let Some(handle) = self.handle.take() {
            let mut resources = self
                .operation
                .resources
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            resources.stage = StageSlot::Registered(handle);
        }
    }
}

/// 取走阶段任务：`Ok(Some(lease))` 取到；`Ok(None)` 槽空闲；`Err` 槽正被借用（不变式破坏）。
pub(super) fn take_stage(
    operation: &Arc<Operation>,
    stage: AcpInstallStage,
) -> Result<Option<StageLease>, AcpInstallFailure> {
    let taken = {
        let mut resources = operation
            .resources
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        match std::mem::take(&mut resources.stage) {
            StageSlot::Registered(handle) => {
                resources.stage = StageSlot::Leased;
                Some(handle)
            }
            StageSlot::Idle => None,
            // 已经被另一个租约借用：不能并发等待同一任务，也不覆盖。
            slot @ StageSlot::Leased => {
                resources.stage = slot;
                return Err(failure(AcpInstallFailureCode::ResourceClose, stage, false));
            }
        }
    };
    Ok(taken.map(|handle| StageLease {
        operation: Arc::clone(operation),
        handle: Some(handle),
    }))
}

/// 把资产锁交给本操作的资源 owner（唯一真实 hold）。
pub(super) fn register_lock_file(
    operation: &Operation,
    lock: std::fs::File,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    let mut resources = operation
        .resources
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    if resources.lock_file.is_some() {
        return Err(failure(AcpInstallFailureCode::ResourceClose, stage, false));
    }
    resources.lock_file = Some(lock);
    Ok(())
}

/// 一次操作留下的、owner 仍**真正持有**的资源保管。
///
/// 这里直接保 [`Operation`] 引用：未确认删除的暂存路径就在 `operation.resources.staging` 里，
/// 不建立平行的路径账本；`Operation` 不反向引用 registry，因此没有 Arc 环。保管之前会把已完成的
/// supervisor join 句柄摘掉，避免对已完成的句柄二次 await。业务结果一并保管，只有在清理**真正
/// 成功**之后才补发终态并释放槽位（design/28 §28.6 "收束未完成保持非终态"，保留重试责任）。
pub(super) struct ResidueHold {
    pub(super) operation: Arc<Operation>,
    pub(super) operation_id: String,
    /// 已算出但尚未发布的业务结果。
    pub(super) business: BusinessOutcome,
    /// 清理失败的安全 typed 摘要（阶段 Close、类别 ResourceClose 一类），不含路径。
    pub(super) cleanup_failure: AcpInstallFailure,
}

/// 尚未发布的业务结果。
pub(super) enum BusinessOutcome {
    Ready(AcpInstalledServer),
    Failed(AcpInstallFailure),
}

/// 一个 provider 当前 target 的槽位（只描述**当前在途业务**）。
///
/// - `busy`：准入占用；终态发布时释放（与契约"终态发布与 busy 释放同一提交"一致）。
/// - `operation`：只在操作在途/收束中（含 residue）时存在。业务终态发布后，句柄归属移交给
///   [`Registry::retired`]，因此"旧句柄"不会占用准入，而真实 task 回收责任仍有唯一 owner。
pub(super) struct Slot {
    pub(super) state: AcpInstallState,
    pub(super) operation: Option<Arc<Operation>>,
    pub(super) busy: bool,
}

/// 一条命令身份绑定的意图；同 ID 只允许同一意图，start 与 cancel 共享容量与台账。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum CommandIntent {
    Start {
        provider: AcpProvider,
        target: String,
    },
    Cancel {
        provider: AcpProvider,
        target_operation_id: String,
    },
}

/// owner 的可变事实。
#[derive(Default)]
pub(super) struct Registry {
    pub(super) revision: u64,
    pub(super) updated_at: i64,
    pub(super) next_generation: u64,
    /// 关闭闸门：与 start 登记同锁，一旦封闭不再接受新操作，也不再准入发布提交。
    pub(super) closed: bool,
    pub(super) slots: BTreeMap<AcpProvider, Slot>,
    /// 已受理命令身份（含 start 与 cancel，含已完成）；容量有界、只增不减。
    pub(super) commands: BTreeMap<String, CommandIntent>,
    /// 清理未确认收束的资源保管：每个 provider 一条，随 runtime 生命周期存在（有界，不重试膨胀）。
    pub(super) residue: BTreeMap<AcpProvider, ResidueHold>,
    /// **已结束业务操作**的 supervisor 句柄回收登记（以 operationId 为键）。
    ///
    /// 业务终态发布、准入释放后，句柄（以及 identity）移交到这里，等待 runtime 关闭时真实 join。
    /// 这里的 Operation 只保句柄与 identity：资产锁/暂存等重型资源已在业务清理确认后释放，
    /// 因此登记不会阻塞业务；容量受"已受理命令身份 ≤ MAX_ACCEPTED_COMMANDS"这一既有预算约束
    /// （每条 retired 都对应一条已受理 start 命令），没有后台 reaper 或第二张任务表。
    pub(super) retired: BTreeMap<String, Arc<Operation>>,
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

    /// 已发布快照：每个有槽位的 provider 一条，终态保留 operation 身份。
    pub(super) fn snapshot(&self) -> AcpInstallSnapshot {
        AcpInstallSnapshot {
            revision: self.revision,
            updated_at: self.updated_at,
            installations: self
                .slots
                .iter()
                .map(|(provider, slot)| AcpInstallEntry {
                    provider: *provider,
                    state: slot.state.clone(),
                })
                .collect(),
        }
    }
}

/// 进入发布提交被拒绝的原因；调用方据此决定终态，而不是靠 bool 猜测。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum PublishRejection {
    /// 该操作已被更新的代次取代。
    Superseded,
    /// 关闭已线性化在先，或有接受的取消在先：绝不发布。
    Cancelled,
}

pub(super) struct AcpInstallInner {
    pub(super) store: crate::studio::StudioStore,
    events: ProductEventBus,
    registry: Mutex<Registry>,
}

impl AcpInstallInner {
    pub(super) fn new(store: crate::studio::StudioStore, events: ProductEventBus) -> Self {
        Self {
            store,
            events,
            registry: Mutex::new(Registry::default()),
        }
    }

    pub(super) fn lock(&self) -> std::sync::MutexGuard<'_, Registry> {
        self.registry.lock().unwrap_or_else(PoisonError::into_inner)
    }

    pub(super) fn emit(&self, snapshot: AcpInstallSnapshot) {
        self.events
            .emit(crate::StudioProductEventKind::AcpInstallStateChanged(
                Box::new(snapshot),
            ));
    }

    /// 在当前操作代次内应用一次状态转换；任何代次不匹配都是迟到结果，直接丢弃。
    fn transition_state(
        &self,
        provider: AcpProvider,
        generation: u64,
        apply: impl FnOnce(&AcpInstallState) -> Option<AcpInstallState>,
    ) {
        let snapshot = {
            let mut registry = self.lock();
            let Some(slot) = registry.slots.get_mut(&provider) else {
                return;
            };
            let current = slot
                .operation
                .as_ref()
                .is_some_and(|operation| operation.generation == generation);
            if !current {
                tracing::debug!(
                    provider = ?provider,
                    "dropping ACP install result for a superseded operation"
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

    /// 发布阶段进展：只允许从活跃阶段推进；取消中/收束中/终态一律不被覆盖。
    pub(super) fn publish_progress(
        &self,
        provider: AcpProvider,
        generation: u64,
        state: AcpInstallState,
    ) {
        self.transition_state(provider, generation, |current| match current {
            AcpInstallState::Resolving { .. }
            | AcpInstallState::Waiting { .. }
            | AcpInstallState::Downloading { .. }
            | AcpInstallState::Verifying { .. }
            | AcpInstallState::Extracting { .. } => Some(state),
            _ => None,
        });
    }

    /// 进入/更新收束中：busy 非终态，且绝不覆盖已取消代次。
    pub(super) fn publish_closing(
        &self,
        provider: AcpProvider,
        generation: u64,
        failure: Option<AcpInstallFailure>,
    ) {
        self.transition_state(provider, generation, |current| match current {
            AcpInstallState::Resolving { operation_id }
            | AcpInstallState::Waiting { operation_id, .. }
            | AcpInstallState::Downloading { operation_id, .. }
            | AcpInstallState::Verifying { operation_id, .. }
            | AcpInstallState::Extracting { operation_id, .. }
            | AcpInstallState::Publishing { operation_id, .. }
            | AcpInstallState::Cancelling { operation_id }
            | AcpInstallState::Closing { operation_id, .. } => Some(AcpInstallState::Closing {
                operation_id: operation_id.clone(),
                failure,
            }),
            _ => None,
        });
    }

    /// 在同一把 owner 锁内裁决"能否进入不可回滚的发布提交"，并原子地推进到 `Publishing`。
    ///
    /// 只有身份匹配、未关闭、未收到取消时才返回 `Ok(snapshot)`；任何被接受的取消或关闭都在
    /// 这里先线性化，因此调用方不能在拿到 `Err` 之后仍然执行 `rename`。进入 `Publishing` 之后
    /// 业务取消被拒绝，shutdown 也必须等待提交真相。
    pub(super) fn try_enter_publish(
        &self,
        provider: AcpProvider,
        generation: u64,
        release: &AcpInstallRelease,
    ) -> Result<AcpInstallSnapshot, PublishRejection> {
        let mut registry = self.lock();
        let operation_id = {
            let Some(slot) = registry.slots.get(&provider) else {
                return Err(PublishRejection::Superseded);
            };
            let Some(operation) = slot.operation.as_ref() else {
                return Err(PublishRejection::Superseded);
            };
            if operation.generation != generation {
                return Err(PublishRejection::Superseded);
            }
            if registry.closed || operation.cancel.is_cancelled() {
                return Err(PublishRejection::Cancelled);
            }
            match &slot.state {
                AcpInstallState::Cancelling { .. } | AcpInstallState::Closing { .. } => {
                    return Err(PublishRejection::Cancelled);
                }
                state if state.is_terminal() => return Err(PublishRejection::Superseded),
                _ => {}
            }
            operation.operation_id.clone()
        };
        let Some(slot) = registry.slots.get_mut(&provider) else {
            return Err(PublishRejection::Superseded);
        };
        slot.state = AcpInstallState::Publishing {
            operation_id,
            release: release.clone(),
        };
        registry.bump();
        let snapshot = registry.snapshot();
        drop(registry);
        self.emit(snapshot.clone());
        Ok(snapshot)
    }

    /// 提交一次操作的终态并**在同一把锁里**释放占用，随后只发一次事件。
    ///
    /// 取消与迟到终态的竞争在这里收敛：已受理取消（`Cancelling`）时，`Ready` 与"取消本身"都不
    /// 会变成 `Failed`——非失败终态收敛为 `Cancelled`，取消类别也归一为 `Cancelled`；只有真实
    /// 的 IO/清理/校验失败保留 `Failed`。已发布事实不回滚。
    pub(super) fn complete_operation(
        &self,
        provider: AcpProvider,
        generation: u64,
        terminal: AcpInstallState,
    ) {
        let snapshot = {
            let mut registry = self.lock();
            let Some(slot) = registry.slots.get_mut(&provider) else {
                return;
            };
            let Some(operation) = slot.operation.as_ref().map(Arc::clone) else {
                return;
            };
            if operation.generation != generation {
                return;
            }
            let operation_id = operation.operation_id.clone();
            let cancelling = matches!(
                &slot.state,
                AcpInstallState::Cancelling { operation_id: current } if current == &operation_id
            );
            let terminal = match terminal {
                AcpInstallState::Failed { failure, .. }
                    if failure.code == AcpInstallFailureCode::Cancelled =>
                {
                    AcpInstallState::Cancelled {
                        operation_id: operation_id.clone(),
                    }
                }
                other => other,
            };
            let decided = if cancelling && !matches!(&terminal, AcpInstallState::Failed { .. }) {
                AcpInstallState::Cancelled {
                    operation_id: operation_id.clone(),
                }
            } else {
                terminal
            };
            // 终态、准入释放与句柄移交同一提交：业务清理已确认完成，重型资源释放，句柄与 identity
            // 移交给 retired 登记（关闭时真实 join），因此新 start 不再因旧句柄被拒。
            let retired = Arc::clone(&operation);
            slot.busy = false;
            slot.state = decided;
            slot.operation = None;
            retired.release_heavy_resources();
            // 终态提交时已经 joined 的 operation（例如关闭阶段 residue 收束后补发终态）不再退休：
            // 它的句柄已被关闭 owner 观测到终止，再登记只会留下一个 join=None 的 stale Arc。
            if !retired.supervisor_joined() {
                registry
                    .retired
                    .insert(retired.operation_id.clone(), retired);
            }
            registry.bump();
            registry.snapshot()
        };
        self.emit(snapshot);
    }

    /// 监督任务异常终止（panic）时的收尾：清理句柄槽、释放 busy 并发布可观察失败。
    ///
    /// JoinError 是句柄终态，不能作为"仍在收束"重试；这里保留诊断类别但只发布安全摘要。
    pub(super) fn fail_operation(
        &self,
        provider: AcpProvider,
        generation: u64,
        failure: AcpInstallFailure,
    ) {
        let snapshot = {
            let mut registry = self.lock();
            let Some(slot) = registry.slots.get_mut(&provider) else {
                return;
            };
            let Some(operation) = slot.operation.as_ref().map(Arc::clone) else {
                return;
            };
            if operation.generation != generation {
                return;
            }
            let operation_id = operation.operation_id.clone();
            let retired = Arc::clone(&operation);
            slot.busy = false;
            slot.state = AcpInstallState::Failed {
                operation_id,
                failure,
            };
            slot.operation = None;
            retired.release_heavy_resources();
            if !retired.supervisor_joined() {
                registry
                    .retired
                    .insert(retired.operation_id.clone(), retired);
            }
            registry.bump();
            registry.snapshot()
        };
        self.emit(snapshot);
    }

    /// 把清理未收束的操作交给 owner 保管：保持 `Closing` 非终态、占住该 provider 的准入，并保
    /// 真实资源 owner（含资产锁与未删除的暂存）。
    ///
    /// **不触碰** `operation.join`：本函数可能在 supervisor 仍在 await worker 时被调用（正常路径在
    /// `run` 内、panic 路径在 supervisor 自身），此时句柄仍是活的。终止事实由
    /// `Operation::mark_supervisor_finished` 记录，关闭阶段据此判断。
    pub(super) fn hold_residue(&self, provider: AcpProvider, hold: ResidueHold) {
        let snapshot = {
            let mut registry = self.lock();
            if let Some(slot) = registry.slots.get_mut(&provider)
                && slot
                    .operation
                    .as_ref()
                    .is_some_and(|current| Arc::ptr_eq(current, &hold.operation))
            {
                slot.busy = true;
                slot.state = AcpInstallState::Closing {
                    operation_id: hold.operation_id.clone(),
                    failure: Some(hold.cleanup_failure.clone()),
                };
            }
            registry.residue.insert(provider, hold);
            registry.bump();
            registry.snapshot()
        };
        self.emit(snapshot);
    }

    /// 该 provider 是否还有未收束的资源保管。
    pub(super) fn has_residue(&self, provider: AcpProvider) -> bool {
        self.lock().residue.contains_key(&provider)
    }

    /// 取该 provider 保管中的真实资源 owner（只克隆 Arc，不把责任从 owner 移走）。
    ///
    /// 关闭阶段的收束尝试用它在预算内直接操作同一份资源；即使尝试被预算打断，保管仍在 owner
    /// 手里，不会出现"责任被取出后丢失"的窗口。
    pub(super) fn residue_operation(&self, provider: AcpProvider) -> Option<Arc<Operation>> {
        self.lock()
            .residue
            .get(&provider)
            .map(|hold| Arc::clone(&hold.operation))
    }

    /// 收束尝试失败：保持保管，只刷新最新清理失败摘要与 `Closing` 事实。
    pub(super) fn note_residue_failure(&self, provider: AcpProvider, failure: AcpInstallFailure) {
        let snapshot = {
            let mut registry = self.lock();
            let updated = {
                let Some(hold) = registry.residue.get_mut(&provider) else {
                    return;
                };
                hold.cleanup_failure = failure;
                (
                    hold.operation_id.clone(),
                    Arc::clone(&hold.operation),
                    hold.cleanup_failure.clone(),
                )
            };
            let (operation_id, operation, cleanup_failure) = updated;
            if let Some(slot) = registry.slots.get_mut(&provider)
                && slot
                    .operation
                    .as_ref()
                    .is_some_and(|current| Arc::ptr_eq(current, &operation))
            {
                slot.state = AcpInstallState::Closing {
                    operation_id,
                    failure: Some(cleanup_failure),
                };
            }
            registry.bump();
            registry.snapshot()
        };
        self.emit(snapshot);
    }

    /// 清理真正成功：移除保管，补发被推迟的业务终态并在同一提交里释放准入。
    pub(super) fn finish_residue(&self, provider: AcpProvider) {
        let Some(hold) = self.lock().residue.remove(&provider) else {
            return;
        };
        let terminal = match hold.business {
            BusinessOutcome::Ready(server) => AcpInstallState::Ready {
                operation_id: hold.operation_id.clone(),
                server,
            },
            BusinessOutcome::Failed(failure) => AcpInstallState::Failed {
                operation_id: hold.operation_id.clone(),
                failure,
            },
        };
        self.complete_operation(provider, hold.operation.generation, terminal);
    }

    /// 关闭阶段：已结束业务操作的句柄快照（只克隆 Arc，不把回收责任移出 owner）。
    pub(super) fn retired_operations(&self) -> Vec<Arc<Operation>> {
        self.lock().retired.values().map(Arc::clone).collect()
    }

    /// 只有真的 join 到终态之后，才从退休登记移除（句柄随之释放）。
    pub(super) fn remove_retired(&self, operation_id: &str) {
        self.lock().retired.remove(operation_id);
    }

    /// 当前仍有保管的 provider 列表。
    pub(super) fn residue_providers(&self) -> Vec<AcpProvider> {
        self.lock().residue.keys().copied().collect()
    }
}
