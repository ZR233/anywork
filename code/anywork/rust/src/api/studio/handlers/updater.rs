use crate::api::studio::bridge_runtime::{
    active_bridge, exit_latch_armed, installed_bridge, lifecycle_gate,
};
use crate::api::studio::convert::runtime::bridge_preparation_result;
use crate::api::studio::types::{BridgeError, BridgeShutdownIssue, BridgeUpdatePreparationResult};
use anyhow::Result;
use flutter_rust_bridge::frb;
use futures::{
    FutureExt,
    future::{BoxFuture, Shared},
};
use pl_studio_update::{StudioUpdateCancellation, StudioUpdateError, StudioUpdateErrorCode};
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

const UPDATE_REGISTRY_LOCK_LIMIT: Duration = Duration::from_millis(100);
type OperationCompletion = Shared<BoxFuture<'static, Result<(), Arc<String>>>>;
const TASK_PENDING: u8 = 0;
const TASK_SUCCEEDED: u8 = 1;
const TASK_FAILED: u8 = 2;
static UPDATE_OPERATIONS: OnceLock<Mutex<Vec<Arc<BridgeStudioUpdateOperationInner>>>> =
    OnceLock::new();
static NEXT_OPERATION_ID: AtomicU64 = AtomicU64::new(1);
static BACKGROUND_UPDATE_STARTED: AtomicBool = AtomicBool::new(false);
static BACKGROUND_OPERATION_ID: AtomicU64 = AtomicU64::new(0);

/// Owns a command completion. Canonical progress is delivered exclusively by UpdaterTopic.
pub struct BridgeStudioUpdateOperation {
    inner: Arc<BridgeStudioUpdateOperationInner>,
}

struct BridgeStudioUpdateOperationInner {
    id: u64,
    cancellation: StudioUpdateCancellation,
    task: Mutex<Option<OperationCompletion>>,
    status: AtomicU8,
    acknowledged: AtomicBool,
    result: Arc<Mutex<Option<BridgeUpdatePreparationResult>>>,
}

impl BridgeStudioUpdateOperationInner {
    fn is_quiescent(&self) -> bool {
        self.status.load(Ordering::Acquire) != TASK_PENDING
    }
    fn is_settled(&self) -> bool {
        self.status.load(Ordering::Acquire) == TASK_SUCCEEDED
    }
    async fn wait(&self) -> Result<(), String> {
        let task = self.task.lock().await.clone();
        if let Some(task) = task {
            task.await.map_err(|error| (*error).clone())
        } else {
            Err("update completion is missing".into())
        }
    }
}

impl BridgeStudioUpdateOperation {
    /// Acknowledges only after the real preparation task has ended.
    pub async fn cancel(&self) -> Result<(), BridgeError> {
        self.inner.cancellation.cancel();
        self.inner
            .wait()
            .await
            .map_err(|error| BridgeError::from(anyhow::anyhow!("{error}")))?;
        installed_bridge()?
            .studio
            .abort_cancelled_studio_update_installation()
            .await
            .map_err(BridgeError::from)
    }

    pub async fn finish_preparation(&self) -> Result<BridgeUpdatePreparationResult, BridgeError> {
        self.inner
            .wait()
            .await
            .map_err(|error| BridgeError::from(anyhow::anyhow!("{error}")))?;
        let result = self.inner.result.lock().await.clone().ok_or_else(|| {
            BridgeError::from(anyhow::anyhow!("preparation ended without a result"))
        })?;
        self.inner.acknowledged.store(true, Ordering::Release);
        Ok(result)
    }
}

impl Drop for BridgeStudioUpdateOperation {
    fn drop(&mut self) {
        if !self.inner.acknowledged.load(Ordering::Acquire) {
            self.inner.cancellation.cancel();
        }
    }
}

pub async fn check_studio_update() -> Result<(), BridgeError> {
    let gate = lifecycle_gate().lock().await;
    let bridge = active_bridge().await?;
    let cancellation = StudioUpdateCancellation::new();
    let token = cancellation.clone();
    let (checked, result) = tokio::sync::oneshot::channel();
    register_update_operation(cancellation, Arc::default(), async move {
        let result = bridge.studio.check_studio_update(&token).await;
        let completion = match &result {
            Ok(()) => Ok(()),
            Err(error)
                if error
                    .downcast_ref::<StudioUpdateError>()
                    .is_some_and(|error| {
                        error.code() == StudioUpdateErrorCode::InstallInProgress
                    }) =>
            {
                Ok(())
            }
            Err(error) => Err(format!("Studio update check owner failed: {error:#}")),
        };
        let _ = checked.send(result.map_err(BridgeError::from));
        completion
    })
    .await;
    drop(gate);
    result.await.map_err(|_| {
        BridgeError::from(anyhow::anyhow!("update check task ended without a result"))
    })?
}

/// Registration precedes execution and participates in the shared shutdown latch.
#[frb(ignore)]
async fn register_update_operation(
    cancellation: StudioUpdateCancellation,
    result: Arc<Mutex<Option<BridgeUpdatePreparationResult>>>,
    task: impl std::future::Future<Output = Result<(), String>> + Send + 'static,
) -> Arc<BridgeStudioUpdateOperationInner> {
    let id = NEXT_OPERATION_ID.fetch_add(1, Ordering::Relaxed);
    let inner = Arc::new(BridgeStudioUpdateOperationInner {
        id,
        cancellation,
        task: Mutex::new(None),
        status: AtomicU8::new(TASK_PENDING),
        acknowledged: AtomicBool::new(false),
        result,
    });
    let (published, received) = tokio::sync::oneshot::channel();
    *inner.task.lock().await = Some(
        async move {
            received
                .await
                .unwrap_or_else(|_| Err(Arc::new("update completion was never published".into())))
        }
        .boxed()
        .shared(),
    );
    {
        let mut registry = update_operations().lock().await;
        registry.retain(|operation| !operation.is_settled());
        registry.push(Arc::clone(&inner));
    }
    if exit_latch_armed() {
        inner.cancellation.cancel();
    }
    let handle = tokio::spawn(task);
    let owner = Arc::clone(&inner);
    tokio::spawn(async move {
        let outcome = match handle.await {
            Ok(result) => result.map_err(Arc::new),
            Err(_) => Err(Arc::new(format!(
                "Studio update operation {id} task panicked"
            ))),
        };
        if outcome.is_err() {
            tracing::error!(
                stage = "updateOperations",
                resource = id,
                "Studio update operation owner failed"
            );
        }
        owner.status.store(
            if outcome.is_ok() {
                TASK_SUCCEEDED
            } else {
                TASK_FAILED
            },
            Ordering::Release,
        );
        let _ = published.send(outcome);
    });
    inner
}

/// Idempotent process scheduler startup. It survives every individual round failure.
pub async fn start_studio_background_update() -> Result<(), BridgeError> {
    let _gate = lifecycle_gate().lock().await;
    let bridge = active_bridge().await?;
    if BACKGROUND_UPDATE_STARTED.swap(true, Ordering::Relaxed) {
        return Ok(());
    }
    let stop = StudioUpdateCancellation::new();
    let token = stop.clone();
    let owner = register_update_operation(stop, Arc::default(), async move {
        bridge.studio.run_studio_background_updates(token).await;
        Ok(())
    })
    .await;
    BACKGROUND_OPERATION_ID.store(owner.id, Ordering::Relaxed);
    Ok(())
}

/// Cancels only the current round; the process scheduler remains alive.
pub async fn cancel_current_update_preparation() -> Result<(), BridgeError> {
    let bridge = active_bridge().await?;
    bridge
        .studio
        .cancel_current_update_preparation()
        .await
        .map_err(BridgeError::from)
}

/// Process shutdown only: stop scheduling, cancel its round and await real completion.
pub async fn stop_studio_background_update() -> Result<(), BridgeError> {
    let id = BACKGROUND_OPERATION_ID.load(Ordering::Relaxed);
    let operation = update_operations()
        .lock()
        .await
        .iter()
        .find(|owner| owner.id == id)
        .cloned();
    if let Some(operation) = operation {
        operation.cancellation.cancel();
        operation
            .wait()
            .await
            .map_err(|error| BridgeError::from(anyhow::anyhow!("{error}")))?;
    }
    Ok(())
}

pub async fn prepare_studio_update(
    expected_revision: u64,
    version: String,
) -> Result<BridgeStudioUpdateOperation, BridgeError> {
    let _gate = lifecycle_gate().lock().await;
    let bridge = active_bridge().await?;
    let state = bridge.studio.read_update_state().await;
    if state.revision() < expected_revision
        || !state
            .update()
            .is_some_and(|update| update.version == version)
    {
        return Err(BridgeError::invalid_argument(
            "requested update is no longer available",
        ));
    }
    let cancellation = StudioUpdateCancellation::new();
    let token = cancellation.clone();
    let result = Arc::new(Mutex::new(None));
    let output = Arc::clone(&result);
    let inner = register_update_operation(cancellation, result, async move {
        let result = bridge
            .studio
            .prepare_studio_update(expected_revision, &version, token)
            .await
            .map_err(|error| format!("Studio update preparation owner failed: {error:#}"))?;
        *output.lock().await = Some(bridge_preparation_result(result));
        Ok(())
    })
    .await;
    Ok(BridgeStudioUpdateOperation { inner })
}

pub(crate) struct PendingUpdateOperations {
    owners: Vec<Arc<BridgeStudioUpdateOperationInner>>,
    issues: Vec<BridgeShutdownIssue>,
}

impl PendingUpdateOperations {
    pub(crate) fn into_issues(self) -> Vec<BridgeShutdownIssue> {
        self.issues
    }
}

pub(crate) async fn collect_cancel_update_operations(
    include_stopped: bool,
) -> PendingUpdateOperations {
    let operations =
        match tokio::time::timeout(UPDATE_REGISTRY_LOCK_LIMIT, update_operations().lock()).await {
            Ok(mut registry) => {
                registry.retain(|operation| !operation.is_settled());
                registry.clone()
            }
            Err(_) => {
                return PendingUpdateOperations {
                    owners: vec![],
                    issues: vec![update_issue(
                        "timeout",
                        "Studio update registry lock exceeded the exit budget",
                    )],
                };
            }
        };
    let mut owners = vec![];
    for operation in operations {
        if operation.is_quiescent() {
            if include_stopped {
                owners.push(operation);
            }
        } else {
            operation.cancellation.cancel();
            owners.push(operation);
        }
    }
    PendingUpdateOperations {
        owners,
        issues: vec![],
    }
}

pub(crate) async fn broadcast_cancel_update_operations() -> Vec<BridgeShutdownIssue> {
    collect_cancel_update_operations(false).await.into_issues()
}

pub(crate) async fn observe_update_operations(
    pending: PendingUpdateOperations,
    deadline: Instant,
) -> Vec<BridgeShutdownIssue> {
    let PendingUpdateOperations { owners, mut issues } = pending;
    let outcomes = futures::future::join_all(owners.iter().map(|operation| async move {
        let remaining = deadline.saturating_duration_since(Instant::now());
        match tokio::time::timeout(remaining, operation.wait()).await {
            Ok(Ok(())) => None,
            Ok(Err(_)) => Some(update_issue("joinError", "a Studio update operation owner failed")),
            Err(_) => Some(update_issue("timeout", "a Studio update operation did not stop within the exit budget; its owner is retained")),
        }
    })).await;
    issues.extend(outcomes.into_iter().flatten());
    issues
}

fn update_issue(code: &str, message: &str) -> BridgeShutdownIssue {
    BridgeShutdownIssue {
        stage: "updateOperations".into(),
        code: code.into(),
        message: message.into(),
        retryable: code == "timeout",
        correlation_id: pl_protocol::studio::StudioError::internal().correlation_id,
    }
}

fn update_operations() -> &'static Mutex<Vec<Arc<BridgeStudioUpdateOperationInner>>> {
    UPDATE_OPERATIONS.get_or_init(|| Mutex::new(Vec::new()))
}
