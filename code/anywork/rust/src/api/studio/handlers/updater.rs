use crate::api::studio::bridge_runtime::{
    active_bridge, exit_latch_armed, installed_bridge, lifecycle_gate,
};
use crate::api::studio::convert::runtime::bridge_update_state;
use crate::api::studio::types::{BridgeError, BridgeShutdownIssue, BridgeUpdaterStateSnapshot};
use crate::frb_generated::StreamSink;
use anyhow::Result;
use flutter_rust_bridge::frb;
use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_studio_runtime::{StudioUpdateCancellation, StudioUpdateError, StudioUpdateErrorCode};
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};
use tokio::sync::{Mutex, mpsc};
use tokio::task::JoinHandle;

/// Bound for taking the update registry lock during a broadcast so a contended registry can never
/// stall the early exit broadcast (or the native deadline) that owns the single first deadline.
const UPDATE_REGISTRY_LOCK_LIMIT: Duration = Duration::from_millis(100);

/// Owned, multi-observable completion of one update task (install or progress sink).
///
/// A `Shared` future keeps the real result so `cancel()` (Dart) and the exit observation both see
/// the same outcome; dropping a waiter on timeout never cancels the underlying task nor loses the
/// ability to observe it later.
type OperationCompletion = Shared<BoxFuture<'static, Result<(), Arc<String>>>>;

/// Which owned task a completion belongs to.
#[derive(Clone, Copy)]
enum OwnerTask {
    Install,
    Sink,
}

const TASK_PENDING: u8 = 0;
const TASK_SUCCEEDED: u8 = 1;
const TASK_FAILED: u8 = 2;
const SINK_NOT_OPENED: u8 = 0;
const SINK_PENDING: u8 = 1;
const SINK_SUCCEEDED: u8 = 2;
const SINK_FAILED: u8 = 3;

/// Owner-published completion facts for one update operation.
///
/// The values are written by the owned observer task the moment the real task ends, never by a
/// waiter's first poll. Preparation completion remains observable even when a Dart caller drops
/// its handle and application shutdown must join the retained owner.
///
/// `#[frb(ignore)]` keeps this pure internal ownership state out of the generated API: `cargo-expand`
/// turns `#[derive(Default)]` into an `impl Default`, and the code generator otherwise treats
/// `Default::default` as a public constructor and exports the private type as an opaque handle.
#[frb(ignore)]
#[derive(Default)]
struct OperationCompletionFacts {
    task: AtomicU8,
    sink: AtomicU8,
}

impl OperationCompletionFacts {
    fn task_ended(&self) -> bool {
        self.task.load(Ordering::SeqCst) != TASK_PENDING
    }

    fn sink_ended(&self) -> bool {
        self.sink.load(Ordering::SeqCst) != SINK_PENDING
    }

    /// No owned task is still running, so there is nothing left to cancel. A progress sink that
    /// was never opened counts as ended.
    fn is_quiescent(&self) -> bool {
        self.task_ended() && self.sink_ended()
    }

    /// Only a fully successful operation whose owners all confirmed is prunable. Timeouts, task
    /// panics and an unconfirmed progress sink keep the strong owner registered.
    fn is_settled(&self) -> bool {
        self.task.load(Ordering::SeqCst) == TASK_SUCCEEDED
            && matches!(
                self.sink.load(Ordering::SeqCst),
                SINK_NOT_OPENED | SINK_SUCCEEDED
            )
    }
}

/// Registry of live update operations. Entries are strong owners so a pending operation survives a
/// dropped Dart handle; they are pruned only once the install task has actually settled.
static UPDATE_OPERATIONS: OnceLock<Mutex<Vec<Arc<BridgeStudioUpdateOperationInner>>>> =
    OnceLock::new();
static NEXT_OPERATION_ID: AtomicU64 = AtomicU64::new(1);
static BACKGROUND_UPDATE_STARTED: AtomicBool = AtomicBool::new(false);
static BACKGROUND_OPERATION_ID: AtomicU64 = AtomicU64::new(0);

#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeStudioUpdateOperation {
    inner: Arc<BridgeStudioUpdateOperationInner>,
}

struct BridgeStudioUpdateOperationInner {
    id: u64,
    cancellation: StudioUpdateCancellation,
    /// Owned preparation completion; set once at spawn and retained for every later observer.
    task: Mutex<Option<OperationCompletion>>,
    /// Owned progress-sink task completion; set when Dart opens the progress stream.
    sink: Mutex<Option<OperationCompletion>>,
    /// Progress events plus the authoritative terminal failure the Dart stream must observe.
    progress_receiver:
        Mutex<Option<mpsc::Receiver<Result<BridgeUpdaterStateSnapshot, BridgeError>>>>,
    /// Owner-published completion facts for preparation and the progress sink.
    facts: Arc<OperationCompletionFacts>,
}

impl BridgeStudioUpdateOperationInner {
    fn is_settled(&self) -> bool {
        self.facts.is_settled()
    }

    fn is_quiescent(&self) -> bool {
        self.facts.is_quiescent()
    }
}

/// Wraps a spawned task into a shared completion and publishes its terminal fact from an owned
/// observer task.
///
/// The observer awaits the real `JoinHandle`, so the fact is recorded even when no waiter ever
/// polls the returned shared completion. A task that returns `Err` (its own inner failure, e.g. a
/// progress projection task) or panics is a real stop failure; only an aborted task reports
/// success, because cancellation is the expected terminal state.
fn owned_completion(
    handle: JoinHandle<Result<(), String>>,
    operation_id: u64,
    facts: Arc<OperationCompletionFacts>,
    owner: OwnerTask,
) -> OperationCompletion {
    // The observer owns the real `JoinHandle` and publishes the terminal fact the moment the task
    // ends, so completed preparation is observable even when no waiter polls the returned
    // completion before application shutdown. A one-shot
    // channel keeps the result buffered until some waiter observes it.
    let (published_tx, published_rx) = tokio::sync::oneshot::channel::<Result<(), Arc<String>>>();
    tokio::spawn(async move {
        let outcome = match handle.await {
            Ok(Ok(())) => Ok(()),
            Ok(Err(error)) => Err(Arc::new(error)),
            Err(error) if error.is_cancelled() => Ok(()),
            // Never propagate the raw panic payload: it can carry arbitrary caller-controlled text.
            // The global panic hook already persists the payload and backtrace to the crash log.
            Err(_) => Err(Arc::new(match owner {
                OwnerTask::Install => {
                    format!("Studio update operation {operation_id} install task panicked")
                }
                OwnerTask::Sink => {
                    format!("Studio update operation {operation_id} progress task panicked")
                }
            })),
        };
        if outcome.is_err() {
            // Record the key safety diagnostic the moment the owner actually fails, instead of
            // waiting for a future exit to observe it. Stable identifiers and a forced backtrace
            // only; the (possibly caller-controlled) error text is never written to the log.
            let failure_code = match owner {
                OwnerTask::Install => "installTaskFailed",
                OwnerTask::Sink => "progressTaskFailed",
            };
            let correlation_id = pl_protocol::studio::StudioError::internal().correlation_id;
            tracing::error!(
                pid = std::process::id(),
                stage = "updateOperations",
                code = failure_code,
                resource = operation_id,
                correlation_id = %correlation_id,
                backtrace = %std::backtrace::Backtrace::force_capture(),
                "Studio update operation owner task failed"
            );
        }
        let status = match (owner, outcome.is_ok()) {
            (OwnerTask::Install, true) => TASK_SUCCEEDED,
            (OwnerTask::Install, false) => TASK_FAILED,
            (OwnerTask::Sink, true) => SINK_SUCCEEDED,
            (OwnerTask::Sink, false) => SINK_FAILED,
        };
        match owner {
            OwnerTask::Install => facts.task.store(status, Ordering::SeqCst),
            OwnerTask::Sink => facts.sink.store(status, Ordering::SeqCst),
        }
        // The receiver may already be dropped; the fact above is still published.
        let _ = published_tx.send(outcome);
    });
    async move {
        published_rx.await.unwrap_or_else(|_| {
            // The observer ended without publishing; never report a clean stop.
            Err(Arc::new(
                "Studio update operation completion was never published".to_string(),
            ))
        })
    }
    .boxed()
    .shared()
}

fn prune_settled(registry: &mut Vec<Arc<BridgeStudioUpdateOperationInner>>) {
    registry.retain(|operation| !operation.is_settled());
}

impl BridgeStudioUpdateOperation {
    pub async fn progress_stream(
        &self,
        sink: StreamSink<BridgeUpdaterStateSnapshot>,
    ) -> Result<(), BridgeError> {
        let mut receiver = self
            .inner
            .progress_receiver
            .lock()
            .await
            .take()
            .ok_or_else(|| {
                BridgeError::invalid_argument("update progress stream can only be opened once")
            })?;
        self.inner.facts.sink.store(SINK_PENDING, Ordering::SeqCst);
        let inner = Arc::clone(&self.inner);
        let task = tokio::spawn(async move {
            while let Some(event) = receiver.recv().await {
                let sent = match event {
                    Ok(state) => sink.add(state),
                    // StreamSink's generated error decoder consumes AnyhowException,
                    // independently of the method's typed opening error.
                    Err(error) => sink.add_error(anyhow::anyhow!(
                        "{} ({})",
                        error.message,
                        error.correlation_id
                    )),
                };
                if sent.is_err() {
                    inner.cancellation.cancel();
                    break;
                }
            }
            Ok::<(), String>(())
        });
        *self.inner.sink.lock().await = Some(owned_completion(
            task,
            self.inner.id,
            Arc::clone(&self.inner.facts),
            OwnerTask::Sink,
        ));
        Ok(())
    }

    /// Cancels this operation and reports the *real* stop result.
    ///
    /// Cancellation signals preparation only; its task and progress owner must both confirm
    /// completion before a caller receives the acknowledgement.
    pub async fn cancel(&self) -> Result<(), BridgeError> {
        self.inner.cancellation.cancel();
        self.inner.wait().await.map_err(|error| {
            BridgeError::from(anyhow::anyhow!(
                "Studio update operation {} did not stop cleanly: {error}",
                self.inner.id
            ))
        })
    }

    /// 等待准备任务和进度流真实完成；调用方随后才可进入统一退出。
    pub async fn finish_preparation(&self) -> Result<(), BridgeError> {
        self.inner.wait().await.map_err(|error| {
            BridgeError::from(anyhow::anyhow!(
                "Studio update operation {} did not stop cleanly: {error}",
                self.inner.id
            ))
        })
    }
}

impl Drop for BridgeStudioUpdateOperation {
    fn drop(&mut self) {
        self.inner.cancellation.cancel();
    }
}

impl BridgeStudioUpdateOperationInner {
    /// Observes the operation's owned task completions; returns the first real failure.
    ///
    /// Both completions are shared and retained, so concurrent callers (Dart `cancel()` and the
    /// shutdown aggregation) observe the same outcome and a timeout never loses the owner.
    async fn wait(&self) -> Result<(), String> {
        let mut first_error: Option<String> = None;
        let task = self.task.lock().await.clone();
        let sink = self.sink.lock().await.clone();
        if let Some(completion) = task
            && let Err(error) = completion.await
        {
            first_error = Some((*error).clone());
        }
        if let Some(completion) = sink
            && let Err(error) = completion.await
            && first_error.is_none()
        {
            first_error = Some((*error).clone());
        }
        match first_error {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }
}

pub async fn check_studio_update() -> Result<BridgeUpdaterStateSnapshot, BridgeError> {
    let gate = lifecycle_gate().lock().await;
    let bridge = active_bridge().await?;
    let cancellation = StudioUpdateCancellation::new();
    let operation_id = NEXT_OPERATION_ID.fetch_add(1, Ordering::Relaxed);
    let task_cancellation = cancellation.clone();
    let (checked, result) = tokio::sync::oneshot::channel();
    register_update_operation(operation_id, cancellation, None, async move {
        let result = bridge.studio.check_studio_update(&task_cancellation).await;
        let completion = match &result {
            Ok(_) => Ok(()),
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
        let _ = checked.send(result.map(bridge_update_state).map_err(BridgeError::from));
        completion
    })
    .await;
    drop(gate);
    result
        .await
        .map_err(|error| anyhow::anyhow!("update check task ended without a result: {error}"))?
}

/// 所有更新入口在持有生命周期门时登记，登记完成且核对退出闩后才允许任务执行。
#[frb(ignore)]
async fn register_update_operation(
    operation_id: u64,
    cancellation: StudioUpdateCancellation,
    progress_receiver: Option<mpsc::Receiver<Result<BridgeUpdaterStateSnapshot, BridgeError>>>,
    task: impl std::future::Future<Output = Result<(), String>> + Send + 'static,
) -> Arc<BridgeStudioUpdateOperationInner> {
    let facts = Arc::new(OperationCompletionFacts::default());
    let inner = Arc::new(BridgeStudioUpdateOperationInner {
        id: operation_id,
        cancellation,
        task: Mutex::new(None),
        sink: Mutex::new(None),
        progress_receiver: Mutex::new(progress_receiver),
        facts: Arc::clone(&facts),
    });
    let (start, started) = tokio::sync::oneshot::channel();
    let task = tokio::spawn(async move {
        if started.await.is_err() {
            return Ok(());
        }
        task.await
    });
    *inner.task.lock().await = Some(owned_completion(
        task,
        operation_id,
        facts,
        OwnerTask::Install,
    ));
    {
        let mut registry = update_operations().lock().await;
        prune_settled(&mut registry);
        registry.push(Arc::clone(&inner));
    }
    if exit_latch_armed() {
        inner.cancellation.cancel();
    }
    let _ = start.send(());
    inner
}

pub async fn read_studio_update_state() -> Result<BridgeUpdaterStateSnapshot, BridgeError> {
    let bridge = installed_bridge()?;
    Ok(bridge_update_state(bridge.studio.read_update_state().await))
}

/// 首次桌面就绪后启动一次后台检查和下载；操作由桥端拥有，页面或 Dart 句柄不控制其存活。
pub async fn start_studio_background_update() -> Result<(), BridgeError> {
    // 最终退出必须先观察同一生命周期门，保证注册晚于早期取消时仍会被最终 collector 收束。
    let _gate = lifecycle_gate().lock().await;
    let bridge = active_bridge().await?;
    if BACKGROUND_UPDATE_STARTED.swap(true, Ordering::Relaxed) {
        return Ok(());
    }
    let cancellation = StudioUpdateCancellation::new();
    let operation_id = NEXT_OPERATION_ID.fetch_add(1, Ordering::Relaxed);
    let task_cancellation = cancellation.clone();
    let task = async move {
        if let Err(error) = bridge
            .studio
            .prepare_studio_update_on_start(task_cancellation)
            .await
        {
            tracing::warn!(error = %error, "Studio background update preparation failed");
            return Err(format!("Studio background update owner failed: {error:#}"));
        }
        // 业务失败已经发布为 canonical 状态；到此所有下载与投影 owner 均已真实完成。
        Ok(())
    };
    register_update_operation(operation_id, cancellation, None, task).await;
    BACKGROUND_OPERATION_ID.store(operation_id, Ordering::Relaxed);
    Ok(())
}

/// 请求后台下载取消并等待真实完成；完成的准备不再作为活动操作取消。
pub async fn cancel_studio_background_update() -> Result<(), BridgeError> {
    let id = BACKGROUND_OPERATION_ID.load(Ordering::Relaxed);
    let operation = update_operations()
        .lock()
        .await
        .iter()
        .find(|operation| operation.id == id)
        .cloned();
    if let Some(inner) = operation
        && !inner.is_quiescent()
    {
        let operation = BridgeStudioUpdateOperation { inner };
        operation.cancel().await?;
    }
    Ok(())
}

pub async fn prepare_studio_update(
    expected_revision: u64,
    version: String,
) -> Result<BridgeStudioUpdateOperation, BridgeError> {
    let _gate = lifecycle_gate().lock().await;
    let bridge = active_bridge().await?;
    let update = bridge
        .studio
        .verified_studio_update(expected_revision, &version)
        .await?;
    let background_id = BACKGROUND_OPERATION_ID.load(Ordering::Relaxed);
    let background = update_operations()
        .lock()
        .await
        .iter()
        .find(|operation| operation.id == background_id && !operation.is_quiescent())
        .cloned();
    // Manual requests join the same owner and cancellation token. The canonical updater
    // subscription keeps delivering real progress; this operation confirms final completion.
    let cancellation = background
        .as_ref()
        .map(|operation| operation.cancellation.clone())
        .unwrap_or_default();
    let (bridge_progress_tx, bridge_progress_rx) = mpsc::channel(64);
    let operation_id = NEXT_OPERATION_ID.fetch_add(1, Ordering::Relaxed);
    let task_cancellation = cancellation.clone();
    let task = async move {
        if let Some(background) = background {
            let result = background.wait().await;
            let _ = bridge_progress_tx
                .send(Ok(bridge_update_state(
                    bridge.studio.read_update_state().await,
                )))
                .await;
            return result;
        }
        let (progress_tx, mut progress_rx) = tokio::sync::mpsc::unbounded_channel();
        let final_progress_tx = bridge_progress_tx.clone();
        let forward_cancellation = task_cancellation.clone();
        let forward = tokio::spawn(async move {
            while let Some(state) = progress_rx.recv().await {
                let sent = tokio::select! {
                    _ = forward_cancellation.cancelled() => break,
                    sent = bridge_progress_tx.send(Ok(bridge_update_state(state))) => sent,
                };
                if sent.is_err() {
                    forward_cancellation.cancel();
                    break;
                }
            }
        });
        let result = bridge
            .studio
            .prepare_studio_update(update, progress_tx, task_cancellation)
            .await;
        if let Err(join) = forward.await
            && !join.is_cancelled()
        {
            let message = "Studio update progress projection task failed".to_string();
            let _ =
                final_progress_tx.try_send(Err(BridgeError::from(anyhow::anyhow!("{message}"))));
            return Err(message);
        }
        if let Err(error) = result {
            let message = format!("Studio update preparation owner failed: {error:#}");
            let _ = final_progress_tx.try_send(Err(BridgeError::from(error)));
            return Err(message);
        }
        Ok(())
    };
    let inner =
        register_update_operation(operation_id, cancellation, Some(bridge_progress_rx), task).await;
    Ok(BridgeStudioUpdateOperation { inner })
}

/// Live update operations captured by the broadcast phase and observed (joined) later within the
/// same shared deadline.
pub(crate) struct PendingUpdateOperations {
    owners: Vec<Arc<BridgeStudioUpdateOperationInner>>,
    issues: Vec<BridgeShutdownIssue>,
}

impl PendingUpdateOperations {
    /// Broadcast issues only; the captured owners are dropped without joining.
    pub(crate) fn into_issues(self) -> Vec<BridgeShutdownIssue> {
        self.issues
    }
}

/// 广播所有独立准备操作的取消，不等待；后续 collector 在同一期限观察真实完成。
/// 已完成的失败仍由最终退出 collector 收集，不把失败 owner 当作成功回收。
pub(crate) async fn collect_cancel_update_operations(
    include_stopped: bool,
) -> PendingUpdateOperations {
    let operations = {
        match tokio::time::timeout(UPDATE_REGISTRY_LOCK_LIMIT, update_operations().lock()).await {
            Ok(mut registry) => {
                prune_settled(&mut registry);
                registry.iter().cloned().collect::<Vec<_>>()
            }
            Err(_) => {
                return PendingUpdateOperations {
                    owners: Vec::new(),
                    issues: vec![update_issue(
                        "timeout",
                        "the Studio update registry lock was not acquired within the early exit budget",
                    )],
                };
            }
        }
    };
    let mut owners = Vec::new();
    for operation in operations {
        if operation.is_quiescent() {
            if include_stopped {
                owners.push(operation);
            }
            continue;
        }
        operation.cancellation.cancel();
        owners.push(operation);
    }
    PendingUpdateOperations {
        owners,
        issues: Vec::new(),
    }
}

/// Early-exit broadcast: signals every in-flight update operation, discarding the captured owners
/// because that entry point never joins them (the later desktop shutdown pass observes them).
pub(crate) async fn broadcast_cancel_update_operations() -> Vec<BridgeShutdownIssue> {
    collect_cancel_update_operations(false).await.into_issues()
}

/// Bounded-observes previously broadcast update operations within the shared first deadline.
///
/// A task failure or a timeout is reported
/// instead of swallowed; an operation that does not stop in time keeps its strong owner registered
/// so a later pass can still observe it.
pub(crate) async fn observe_update_operations(
    pending: PendingUpdateOperations,
    deadline: Instant,
) -> Vec<BridgeShutdownIssue> {
    let PendingUpdateOperations { owners, mut issues } = pending;
    // Observe every owner **concurrently** within the same first deadline: a slow operation must not
    // consume the budget before the remaining owners are observed. A timed-out or failed owner keeps
    // its strong registry entry so a later pass can still observe it.
    let outcomes = futures::future::join_all(owners.iter().map(|operation| async move {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return UpdateObservation::TimedOut;
        }
        match tokio::time::timeout(remaining, operation.wait()).await {
            Ok(Ok(())) => UpdateObservation::Stopped,
            Ok(Err(error)) => UpdateObservation::Failed(error),
            Err(_) => UpdateObservation::TimedOut,
        }
    }))
    .await;
    for outcome in outcomes {
        match outcome {
            UpdateObservation::Stopped => {}
            UpdateObservation::Failed(error) => issues.push(update_issue(
                "joinError",
                &format!("a Studio update operation task failed to stop: {error}"),
            )),
            UpdateObservation::TimedOut => issues.push(update_issue(
                "timeout",
                "a Studio update operation did not stop within the exit budget; its owner is retained",
            )),
        }
    }
    issues
}

/// Concurrent per-owner outcome of one bounded update-operation observation.
enum UpdateObservation {
    Stopped,
    Failed(String),
    TimedOut,
}

fn update_issue(code: &str, message: &str) -> BridgeShutdownIssue {
    update_issue_with_correlation(
        code,
        message,
        pl_protocol::studio::StudioError::internal().correlation_id,
    )
}

fn update_issue_with_correlation(
    code: &str,
    message: &str,
    correlation_id: String,
) -> BridgeShutdownIssue {
    BridgeShutdownIssue {
        stage: "updateOperations".to_string(),
        code: code.to_string(),
        message: message.to_string(),
        retryable: code == "timeout",
        correlation_id,
    }
}

fn update_operations() -> &'static Mutex<Vec<Arc<BridgeStudioUpdateOperationInner>>> {
    UPDATE_OPERATIONS.get_or_init(|| Mutex::new(Vec::new()))
}
