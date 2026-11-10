//! A single, memory-only local CLI probe slot.
//!
//! Admission, cancellation and publication share one lock. The slot owns the
//! supervisor join and physical resources, including after a cancelled waiter.
//! Neither reads nor construction touch the executable or filesystem.

mod probe;
#[cfg(all(test, target_os = "linux"))]
mod tests;

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use anyhow::Result;
use futures::FutureExt;
use pl_protocol::studio::{
    AcpLocalDetectionFailure, AcpLocalDetectionFailureKind, AcpLocalDetectionSnapshot,
    AcpLocalDetectionState, CancelAcpLocalDetectionRequest, StartAcpLocalDetectionRequest,
    StudioError, StudioErrorCode,
};
use tokio::sync::Mutex as AsyncMutex;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::acp_worker::{AcpWorker, PROCESS_CLEANUP_LIMIT, Reclaim, WorkerSource};
use crate::studio::{ProductEventBus, StudioStore};
use crate::worker_assets::RemoteHelperSource;

#[derive(Clone)]
pub(crate) struct AcpLocalDetectionRuntime {
    inner: Arc<Inner>,
}

pub(crate) struct AcpLocalDetectionAcceptance {
    pub snapshot: AcpLocalDetectionSnapshot,
    pub changed: bool,
}

struct Inner {
    store: StudioStore,
    events: ProductEventBus,
    source: WorkerSource,
    slot: Mutex<Slot>,
    /// Test-only launch inputs, never a process-global PATH or user config edit.
    #[cfg(test)]
    fixture_definition: Mutex<Option<crate::config::AcpServiceDefinition>>,
}

struct Slot {
    closed: bool,
    snapshot: AcpLocalDetectionSnapshot,
    operation: Option<Arc<Operation>>,
}

struct Operation {
    id: String,
    cancel: CancellationToken,
    deadline: tokio::time::Instant,
    join: AsyncMutex<Option<JoinHandle<()>>>,
    resources: AsyncMutex<Resources>,
    resources_released: AtomicBool,
    /// Thin fault assembly around real resources; production has no such gates.
    #[cfg(test)]
    cleanup_pause: Mutex<Option<CancellationToken>>,
    #[cfg(test)]
    cleanup_pending: AtomicBool,
}

#[derive(Default)]
struct Resources {
    worker: Option<AcpWorker>,
    /// Owned empty probe cwd, never an account/workspace directory.
    directory: Option<PathBuf>,
}

impl AcpLocalDetectionRuntime {
    pub(crate) fn new(
        store: StudioStore,
        events: ProductEventBus,
        helper_source: RemoteHelperSource,
    ) -> Self {
        Self {
            inner: Arc::new(Inner {
                store,
                events,
                source: WorkerSource::new(helper_source),
                slot: Mutex::new(Slot {
                    closed: false,
                    snapshot: AcpLocalDetectionSnapshot {
                        revision: 0,
                        operation_id: None,
                        state: AcpLocalDetectionState::Idle,
                    },
                    operation: None,
                }),
                #[cfg(test)]
                fixture_definition: Mutex::new(None),
            }),
        }
    }

    pub(crate) fn read_state(&self) -> AcpLocalDetectionSnapshot {
        self.inner.lock().snapshot.clone()
    }

    pub(crate) fn start(
        &self,
        request: StartAcpLocalDetectionRequest,
    ) -> Result<AcpLocalDetectionAcceptance> {
        super::StudioRuntime::validate_operation_id(&request.operation_id)?;
        let mut slot = self.inner.lock();
        if slot.closed {
            return Err(command_error(
                StudioErrorCode::RuntimeStopped,
                "运行时正在关闭，不能开始本机检测",
            ));
        }
        if slot.snapshot.operation_id.as_deref() == Some(request.operation_id.as_str()) {
            return Ok(acceptance(&slot, false));
        }
        // Poll only a finished join, by reference, before recycling the one slot.
        // Completion of the domain state alone is not evidence of task termination.
        if let Some(operation) = slot.operation.clone() {
            let Ok(mut join) = operation.join.try_lock() else {
                return Err(busy());
            };
            if let Some(task) = join.as_mut() {
                if !task.is_finished() {
                    return Err(busy());
                }
                let Some(outcome) = task.now_or_never() else {
                    return Err(busy());
                };
                *join = None;
                if outcome.is_err() {
                    self.inner
                        .publish_locked(&mut slot, failed(AcpLocalDetectionFailureKind::Cleanup));
                }
            }
            if !operation.resources_released.load(Ordering::Acquire) {
                return Err(busy());
            }
            slot.operation = None;
        }

        let operation = Arc::new(Operation {
            id: request.operation_id,
            cancel: CancellationToken::new(),
            deadline: tokio::time::Instant::now() + std::time::Duration::from_secs(10),
            join: AsyncMutex::new(None),
            resources: AsyncMutex::new(Resources::default()),
            resources_released: AtomicBool::new(false),
            #[cfg(test)]
            cleanup_pause: Mutex::new(None),
            #[cfg(test)]
            cleanup_pending: AtomicBool::new(false),
        });
        slot.snapshot.operation_id = Some(operation.id.clone());
        slot.operation = Some(Arc::clone(&operation));
        self.inner
            .publish_locked(&mut slot, AcpLocalDetectionState::Checking);
        // Responsibility is visible before spawn, with no intervening await.
        let task = tokio::spawn(supervise(Arc::clone(&self.inner), Arc::clone(&operation)));
        *operation
            .join
            .try_lock()
            .expect("new detection join is idle") = Some(task);
        Ok(acceptance(&slot, true))
    }

    pub(crate) fn cancel(
        &self,
        request: CancelAcpLocalDetectionRequest,
    ) -> Result<AcpLocalDetectionAcceptance> {
        super::StudioRuntime::validate_operation_id(&request.operation_id)?;
        super::StudioRuntime::validate_operation_id(&request.target_operation_id)?;
        let mut slot = self.inner.lock();
        if slot.snapshot.operation_id.as_deref() != Some(request.target_operation_id.as_str()) {
            return Err(command_error(
                StudioErrorCode::Conflict,
                "检测操作已被替换，不能取消另一操作",
            ));
        }
        if request.operation_id == request.target_operation_id {
            return Err(command_error(
                StudioErrorCode::Conflict,
                "取消命令必须使用独立的 operationId",
            ));
        }
        if !matches!(
            slot.snapshot.state,
            AcpLocalDetectionState::Checking | AcpLocalDetectionState::Cancelling
        ) {
            return Ok(acceptance(&slot, false));
        }
        if let Some(operation) = &slot.operation {
            operation.cancel.cancel();
        }
        let changed = slot.snapshot.state != AcpLocalDetectionState::Cancelling;
        if changed {
            self.inner
                .publish_locked(&mut slot, AcpLocalDetectionState::Cancelling);
        }
        Ok(acceptance(&slot, changed))
    }

    /// Synchronous shutdown gate, before waiting for sibling resource owners.
    pub(crate) fn signal_cancel(&self) {
        let mut slot = self.inner.lock();
        slot.closed = true;
        if let Some(operation) = &slot.operation {
            operation.cancel.cancel();
            if slot.snapshot.state == AcpLocalDetectionState::Checking {
                self.inner
                    .publish_locked(&mut slot, AcpLocalDetectionState::Cancelling);
            }
        }
    }

    /// Close admission and borrow the retained join. A timed-out/dropped waiter
    /// leaves this same owner available to the existing shutdown retry.
    pub(crate) async fn close(&self) -> Result<()> {
        self.signal_cancel();
        let operation = self.inner.lock().operation.clone();
        let Some(operation) = operation else {
            return Ok(());
        };
        let joined = tokio::time::timeout(PROCESS_CLEANUP_LIMIT, async {
            let mut join = operation.join.lock().await;
            if let Some(task) = join.as_mut() {
                let outcome = task.await;
                *join = None;
                outcome.map_err(|_| ())?;
            }
            Ok::<(), ()>(())
        })
        .await;
        if joined.is_err() {
            anyhow::bail!("本机检测任务仍在收束，保留原 owner 待重试");
        }
        // Even a panicked task leaves its physical worker in Operation.resources.
        let cleaned = release_resources(&operation).await;
        if !matches!(joined, Ok(Ok(()))) || !cleaned {
            self.inner
                .finish(&operation, failed(AcpLocalDetectionFailureKind::Cleanup));
            anyhow::bail!("本机检测资源收束失败，请重试关闭");
        }
        Ok(())
    }
}

impl Inner {
    fn lock(&self) -> MutexGuard<'_, Slot> {
        self.slot.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn publish_locked(&self, slot: &mut Slot, state: AcpLocalDetectionState) {
        slot.snapshot.state = state;
        slot.snapshot.revision += 1;
        // The event bus only enqueues; publication shares admission ordering.
        self.events.emit(
            crate::StudioProductEventKind::AcpLocalDetectionStateChanged(Box::new(
                slot.snapshot.clone(),
            )),
        );
    }

    fn finish(&self, operation: &Arc<Operation>, state: AcpLocalDetectionState) {
        let mut slot = self.lock();
        if !slot
            .operation
            .as_ref()
            .is_some_and(|current| Arc::ptr_eq(current, operation))
        {
            return;
        }
        let state = if operation.cancel.is_cancelled()
            && !matches!(state, AcpLocalDetectionState::Failed { .. })
        {
            AcpLocalDetectionState::Cancelled
        } else {
            state
        };
        self.publish_locked(&mut slot, state);
    }
}

async fn supervise(inner: Arc<Inner>, operation: Arc<Operation>) {
    let outcome = std::panic::AssertUnwindSafe(probe::run(&inner, &operation))
        .catch_unwind()
        .await;
    let state = outcome.unwrap_or_else(|_| failed(AcpLocalDetectionFailureKind::Execution));
    let cleaned = release_resources(&operation).await;
    inner.finish(
        &operation,
        if cleaned {
            state
        } else {
            failed(AcpLocalDetectionFailureKind::Cleanup)
        },
    );
}

async fn release_resources(operation: &Operation) -> bool {
    #[cfg(test)]
    {
        let pause = operation
            .cleanup_pause
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone();
        if let Some(pause) = pause {
            pause.cancelled().await;
        }
        if operation.cleanup_pending.load(Ordering::Acquire) {
            return false;
        }
    }
    let mut resources = operation.resources.lock().await;
    let mut succeeded = true;
    if let Some(worker) = resources.worker.as_mut() {
        match tokio::time::timeout(PROCESS_CLEANUP_LIMIT, worker.reclaim()).await {
            Ok(Reclaim::Stopped) => resources.worker = None,
            Ok(Reclaim::Settled(_)) => {
                resources.worker = None;
                succeeded = false;
            }
            Ok(Reclaim::Pending(_)) | Err(_) => return false,
        }
    }
    if let Some(directory) = &resources.directory {
        match std::fs::remove_dir_all(directory) {
            Ok(()) => resources.directory = None,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                resources.directory = None;
            }
            Err(_) => return false,
        }
    }
    operation.resources_released.store(true, Ordering::Release);
    succeeded
}

fn acceptance(slot: &Slot, changed: bool) -> AcpLocalDetectionAcceptance {
    AcpLocalDetectionAcceptance {
        snapshot: slot.snapshot.clone(),
        changed,
    }
}

fn busy() -> anyhow::Error {
    command_error(
        StudioErrorCode::Busy,
        "已有本机检测操作或资源尚未收束，请等待后重新检测",
    )
}

fn command_error(code: StudioErrorCode, message: &str) -> anyhow::Error {
    StudioError::new(code, message, code == StudioErrorCode::Busy).into()
}

fn failed(kind: AcpLocalDetectionFailureKind) -> AcpLocalDetectionState {
    let message = match kind {
        AcpLocalDetectionFailureKind::Timeout => "本机检测超过 10 秒，请检查程序后重新检测",
        AcpLocalDetectionFailureKind::OutputLimit => {
            "本机检测输出超过 64 KiB，请检查程序后重新检测"
        }
        AcpLocalDetectionFailureKind::Execution => "无法完成本机检测，请检查程序是否可运行",
        AcpLocalDetectionFailureKind::Cleanup => "本机检测资源未正常收束，请重试关闭",
    };
    AcpLocalDetectionState::Failed {
        failure: AcpLocalDetectionFailure {
            kind,
            message: message.into(),
        },
    }
}
