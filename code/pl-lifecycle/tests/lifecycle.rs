use std::{
    collections::VecDeque,
    future::Future,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    time::Duration,
};

use futures::poll;
use pl_lifecycle::{
    CancellationToken, CloseError, Handle, Instant, ManagedResource, OpenError, Phase,
    RegistrationError, ScopeOwner,
};
use tokio::sync::{mpsc, oneshot};

#[derive(Debug, PartialEq, Eq)]
struct Failure(&'static str); // Intentionally not Clone.

enum Outcome {
    Success,
    Failure,
    Panic,
}

struct Control {
    attempts: AtomicUsize,
    in_flight: AtomicUsize,
    maximum: AtomicUsize,
    requests: AtomicUsize,
    dropped: AtomicUsize,
    dropped_notify: tokio::sync::Notify,
    started: mpsc::UnboundedSender<usize>,
    responses: Mutex<VecDeque<oneshot::Receiver<Outcome>>>,
}

struct Resource(Arc<Control>);

struct Flight(Arc<Control>);
impl Drop for Flight {
    fn drop(&mut self) {
        self.0.in_flight.fetch_sub(1, Ordering::SeqCst);
    }
}

impl Drop for Resource {
    fn drop(&mut self) {
        self.0.dropped.fetch_add(1, Ordering::SeqCst);
        self.0.dropped_notify.notify_one();
    }
}

impl ManagedResource for Resource {
    type Error = Failure;
    fn request_close(&self) {
        self.0.requests.fetch_add(1, Ordering::SeqCst);
    }
    async fn close(&self) -> Result<(), Failure> {
        let attempt = self.0.attempts.fetch_add(1, Ordering::SeqCst) + 1;
        let in_flight = self.0.in_flight.fetch_add(1, Ordering::SeqCst) + 1;
        self.0.maximum.fetch_max(in_flight, Ordering::SeqCst);
        let _flight = Flight(Arc::clone(&self.0));
        let response = self
            .0
            .responses
            .lock()
            .unwrap()
            .pop_front()
            .expect("unexpected close attempt");
        self.0.started.send(attempt).unwrap();
        match response.await.expect("test must decide cleanup outcome") {
            Outcome::Success => Ok(()),
            Outcome::Failure => Err(Failure("cleanup")),
            Outcome::Panic => panic!("cleanup panic"),
        }
    }
}

fn controlled(
    count: usize,
) -> (
    Resource,
    Arc<Control>,
    mpsc::UnboundedReceiver<usize>,
    Vec<oneshot::Sender<Outcome>>,
) {
    let (started, receiver) = mpsc::unbounded_channel();
    let mut responses = VecDeque::new();
    let mut senders = Vec::new();
    for _ in 0..count {
        let (sender, response) = oneshot::channel();
        senders.push(sender);
        responses.push_back(response);
    }
    let control = Arc::new(Control {
        attempts: AtomicUsize::new(0),
        in_flight: AtomicUsize::new(0),
        maximum: AtomicUsize::new(0),
        requests: AtomicUsize::new(0),
        dropped: AtomicUsize::new(0),
        dropped_notify: tokio::sync::Notify::new(),
        started,
        responses: Mutex::new(responses),
    });
    (Resource(Arc::clone(&control)), control, receiver, senders)
}

async fn bounded<T>(future: impl Future<Output = T>) -> T {
    tokio::time::timeout(Duration::from_secs(5), future)
        .await
        .expect("operation did not finish")
}

fn deadline() -> Instant {
    Instant::now() + Duration::from_secs(5)
}

#[tokio::test]
async fn admission_and_late_factory_result_remain_owned() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let handle = root.handle();
    let (resource, control, mut started, mut outcomes) = controlled(1);
    let (factory_started, factory_seen) = oneshot::channel();
    let (finish_factory, factory_release) = oneshot::channel();
    let opening = tokio::spawn(async move {
        handle
            .open("late", move |_token| async move {
                factory_started.send(()).unwrap();
                factory_release.await.unwrap();
                Ok(resource)
            })
            .await
    });
    bounded(factory_seen).await.unwrap();
    root.request_close();
    finish_factory.send(()).unwrap();
    assert!(matches!(
        bounded(opening).await.unwrap(),
        Err(OpenError::Cancelled)
    ));
    assert_eq!(bounded(started.recv()).await, Some(1));
    let report = root.close(Instant::now()).await;
    assert!(!report.workers_finished);
    assert_eq!(report.pending.len(), 1);
    assert_eq!(report.pending[0].phase, Phase::Closing);
    outcomes.pop().unwrap().send(Outcome::Success).ok().unwrap();
    assert!(bounded(root.wait_closed()).await.is_clean());
    assert_eq!(control.attempts.load(Ordering::SeqCst), 1);
    assert_eq!(control.dropped.load(Ordering::SeqCst), 1);

    let called = Arc::new(AtomicBool::new(false));
    let called_factory = Arc::clone(&called);
    let rejected = root
        .handle()
        .open("rejected", move |_token| async move {
            called_factory.store(true, Ordering::SeqCst);
            Err::<Resource, _>(Failure("not called"))
        })
        .await;
    assert!(matches!(rejected, Err(OpenError::ScopeClosed)));
    assert!(!called.load(Ordering::SeqCst));
}

#[tokio::test]
async fn cancelling_open_and_dropping_managed_both_start_cleanup() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let handle = root.handle();
    let (resource, control, mut started, mut outcomes) = controlled(1);
    let (entered_tx, entered_rx) = oneshot::channel();
    let (release_tx, release_rx) = oneshot::channel();
    let task = tokio::spawn(async move {
        handle
            .open("cancelled", move |_token| async move {
                entered_tx.send(()).unwrap();
                release_rx.await.unwrap();
                Ok(resource)
            })
            .await
    });
    bounded(entered_rx).await.unwrap();
    task.abort();
    assert!(matches!(bounded(task).await, Err(error) if error.is_cancelled()));
    release_tx.send(()).unwrap();
    assert_eq!(bounded(started.recv()).await, Some(1));
    outcomes.pop().unwrap().send(Outcome::Success).ok().unwrap();
    assert!(bounded(root.wait_closed()).await.is_clean());
    assert_eq!(control.attempts.load(Ordering::SeqCst), 1);
    assert_eq!(control.dropped.load(Ordering::SeqCst), 1);

    let root = ScopeOwner::<Failure>::new("other", Handle::current());
    let (resource, control, mut started, mut outcomes) = controlled(1);
    let managed = root
        .handle()
        .open("owned", move |_| async move { Ok(resource) })
        .await
        .unwrap();
    drop(managed);
    assert_eq!(bounded(started.recv()).await, Some(1));
    outcomes.pop().unwrap().send(Outcome::Success).ok().unwrap();
    assert!(bounded(root.wait_closed()).await.is_clean());
    assert_eq!(control.dropped.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn attempts_are_shared_and_old_waiters_keep_their_result() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let (resource, control, mut started, outcomes) = controlled(2);
    let mut outcomes = outcomes.into_iter();
    let managed = root
        .handle()
        .open("resource", move |_| async move { Ok(resource) })
        .await
        .unwrap();
    let address = std::ptr::from_ref(managed.get());

    // retry_close on Active starts exactly one first attempt; a normal close
    // shares it. Neither waiting future owns the worker.
    let mut old = Box::pin(managed.retry_close());
    assert!(poll!(old.as_mut()).is_pending());
    assert_eq!(bounded(started.recv()).await, Some(1));
    let mut other = Box::pin(managed.close());
    assert!(poll!(other.as_mut()).is_pending());
    drop(other);
    let report = root.close(Instant::now()).await;
    assert_eq!(report.pending.len(), 1);
    outcomes
        .next()
        .unwrap()
        .send(Outcome::Failure)
        .ok()
        .unwrap();
    let first_report = bounded(root.wait_closed()).await;
    assert!(!first_report.is_clean());
    assert_eq!(first_report.failures.len(), 1);
    assert!(first_report.failures[0].retained);
    assert_eq!(first_report.failures[0].attempt_id.get(), 1);
    let _copy = first_report.clone(); // Does not require Failure: Clone.

    let mut retry = Box::pin(managed.retry_close());
    assert!(poll!(retry.as_mut()).is_pending());
    assert_eq!(bounded(started.recv()).await, Some(2));
    let mut parallel = Box::pin(managed.retry_close());
    assert!(poll!(parallel.as_mut()).is_pending());
    assert!(
        matches!(bounded(old).await, Err(CloseError::Resource(error)) if *error == Failure("cleanup"))
    );
    assert_eq!(address, std::ptr::from_ref(managed.get()));
    outcomes
        .next()
        .unwrap()
        .send(Outcome::Success)
        .ok()
        .unwrap();
    assert!(bounded(retry).await.is_ok());
    assert!(bounded(parallel).await.is_ok());
    assert!(managed.retry_close().await.is_ok());
    assert!(bounded(root.wait_closed()).await.is_clean());
    assert_eq!(control.attempts.load(Ordering::SeqCst), 2);
    assert_eq!(control.maximum.load(Ordering::SeqCst), 1);
    drop(managed);
    assert_eq!(control.dropped.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn first_retry_close_failure_is_not_retried_by_the_same_call() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let (resource, control, mut started, mut outcomes) = controlled(1);
    let managed = root
        .handle()
        .open("resource", move |_| async move { Ok(resource) })
        .await
        .unwrap();
    let future = managed.retry_close();
    tokio::pin!(future);
    assert!(poll!(future.as_mut()).is_pending());
    assert_eq!(bounded(started.recv()).await, Some(1));
    outcomes.pop().unwrap().send(Outcome::Failure).ok().unwrap();
    assert!(matches!(
        bounded(future).await,
        Err(CloseError::Resource(_))
    ));
    let report = bounded(root.wait_closed()).await;
    assert_eq!(report.failures.len(), 1);
    assert_eq!(control.attempts.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn panic_diagnostics_and_failed_resource_retry_have_distinct_lifetimes() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let normal = root
        .handle()
        .open("ordinary error", |_| async {
            Err::<Resource, _>(Failure("open"))
        })
        .await;
    assert!(matches!(normal, Err(OpenError::Resource(error)) if *error == Failure("open")));
    fn panic_factory() -> Result<Resource, Failure> {
        panic!("factory")
    }
    let panicked = root
        .handle()
        .open("panic", |_| async { panic_factory() })
        .await;
    assert!(matches!(panicked, Err(OpenError::Panicked)));
    let (resource, control, mut started, outcomes) = controlled(2);
    let mut outcomes = outcomes.into_iter();
    let managed = root
        .handle()
        .open("resource", move |_| async move { Ok(resource) })
        .await
        .unwrap();
    managed.request_close();
    assert_eq!(bounded(started.recv()).await, Some(1));
    outcomes.next().unwrap().send(Outcome::Panic).ok().unwrap();
    let report = bounded(root.wait_closed()).await;
    assert_eq!(report.failures.len(), 2);
    assert!(
        report
            .failures
            .iter()
            .any(|failure| failure.phase == Phase::Opening && !failure.retained)
    );
    assert!(
        report
            .failures
            .iter()
            .any(|failure| failure.phase == Phase::Closing && failure.retained)
    );
    let mut retry = Box::pin(root.retry_cleanup(deadline()));
    assert!(poll!(retry.as_mut()).is_pending());
    assert_eq!(bounded(started.recv()).await, Some(2));
    outcomes
        .next()
        .unwrap()
        .send(Outcome::Success)
        .ok()
        .unwrap();
    let retried = bounded(retry).await;
    assert_eq!(retried.failures.len(), 1);
    assert!(!retried.failures[0].retained);
    assert!(!retried.is_clean());
    assert_eq!(control.attempts.load(Ordering::SeqCst), 2);
    drop(managed);
    assert_eq!(control.dropped.load(Ordering::SeqCst), 1);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn synchronous_registration_executes_once_and_close_waits_for_callback() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let handle = root.handle();
    let calls = Arc::new(AtomicUsize::new(0));
    let calls_in_callback = Arc::clone(&calls);
    let (started_tx, started_rx) = oneshot::channel();
    let (release_tx, release_rx) = std::sync::mpsc::channel();
    let registration = handle
        .on_close("listener", move || {
            calls_in_callback.fetch_add(1, Ordering::SeqCst);
            started_tx.send(()).unwrap();
            release_rx.recv().unwrap();
        })
        .unwrap();
    let thread = std::thread::spawn(move || drop(registration));
    bounded(started_rx).await.unwrap();
    let report = root.close(Instant::now()).await;
    assert_eq!(report.pending.len(), 1);
    assert_eq!(report.pending[0].phase, Phase::Closing);
    assert!(!report.is_clean());
    release_tx.send(()).unwrap();
    thread.join().unwrap();
    assert!(bounded(root.wait_closed()).await.is_clean());
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    let rejected_calls = Arc::new(AtomicUsize::new(0));
    let rejected_callback = Arc::clone(&rejected_calls);
    assert!(matches!(
        handle.on_close("rejected", move || {
            rejected_callback.fetch_add(1, Ordering::SeqCst);
        }),
        Err(RegistrationError::ScopeClosed)
    ));
    assert_eq!(rejected_calls.load(Ordering::SeqCst), 1);
    assert!(matches!(
        handle.on_close("panic", || panic!("rejected")),
        Err(RegistrationError::RejectedCleanupPanicked)
    ));
}

#[tokio::test]
async fn children_are_isolated_and_parent_can_retry_a_failed_child() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let child = root.handle().child("child").unwrap();
    let sibling = root.handle().child("sibling").unwrap();
    let sibling_handle = sibling.handle();
    let (resource, control, mut started, outcomes) = controlled(2);
    let mut outcomes = outcomes.into_iter();
    let managed = child
        .handle()
        .open("resource", move |_| async move { Ok(resource) })
        .await
        .unwrap();
    child.request_close();
    assert_eq!(bounded(started.recv()).await, Some(1));
    outcomes
        .next()
        .unwrap()
        .send(Outcome::Failure)
        .ok()
        .unwrap();
    let report = bounded(child.wait_closed()).await;
    assert_eq!(report.failures.len(), 1);
    assert!(sibling_handle.child("grandchild").is_ok());
    drop(child);
    let mut retry = Box::pin(root.retry_cleanup(deadline()));
    assert!(poll!(retry.as_mut()).is_pending());
    assert_eq!(bounded(started.recv()).await, Some(2));
    outcomes
        .next()
        .unwrap()
        .send(Outcome::Success)
        .ok()
        .unwrap();
    assert!(bounded(retry).await.is_clean());
    assert!(sibling_handle.child("closed").is_err());
    drop(managed);
    drop(sibling);
    drop(root);
    assert!(sibling_handle.child("dead").is_err());
    assert_eq!(control.attempts.load(Ordering::SeqCst), 2);
}

#[test]
fn stopped_runtime_reports_unpolled_worker_and_foreign_thread_drop_is_safe() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let owner = ScopeOwner::<Failure>::new("stopped", runtime.handle().clone());
    drop(runtime);
    let observer = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    observer.block_on(async {
        let called = Arc::new(AtomicBool::new(false));
        let called_factory = Arc::clone(&called);
        let result = owner
            .handle()
            .open(
                "never polled",
                move |_token: CancellationToken| async move {
                    called_factory.store(true, Ordering::SeqCst);
                    Err::<Resource, _>(Failure("unreachable"))
                },
            )
            .await;
        assert!(matches!(result, Err(OpenError::WorkerStopped)));
        assert!(!called.load(Ordering::SeqCst));
        let report = bounded(owner.wait_closed()).await;
        assert!(report.workers_finished);
        assert_eq!(report.failures.len(), 1);
        assert_eq!(report.failures[0].phase, Phase::Opening);
        assert!(!report.failures[0].retained);
    });
    assert!(std::thread::spawn(move || drop(owner)).join().is_ok());
}

#[tokio::test]
async fn scope_retry_only_retries_preexisting_failures() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let (resource, control, mut started, outcomes) = controlled(2);
    let mut outcomes = outcomes.into_iter();
    let managed = root
        .handle()
        .open("resource", move |_| async move { Ok(resource) })
        .await
        .unwrap();
    let mut first = Box::pin(root.retry_cleanup(deadline()));
    assert!(poll!(first.as_mut()).is_pending());
    assert_eq!(bounded(started.recv()).await, Some(1));
    outcomes
        .next()
        .unwrap()
        .send(Outcome::Failure)
        .ok()
        .unwrap();
    let first_report = bounded(first).await;
    assert_eq!(first_report.failures.len(), 1);
    assert_eq!(control.attempts.load(Ordering::SeqCst), 1);
    let mut retry = Box::pin(root.retry_cleanup(deadline()));
    assert!(poll!(retry.as_mut()).is_pending());
    assert_eq!(bounded(started.recv()).await, Some(2));
    outcomes
        .next()
        .unwrap()
        .send(Outcome::Success)
        .ok()
        .unwrap();
    assert!(bounded(retry).await.is_clean());
    drop(managed);
}

#[tokio::test]
async fn cancelling_strict_wait_does_not_cancel_either_cleanup() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let (first, _, mut first_started, mut first_outcome) = controlled(1);
    let (second, _, mut second_started, mut second_outcome) = controlled(1);
    let first = root
        .handle()
        .open("first", move |_| async move { Ok(first) })
        .await
        .unwrap();
    let second = root
        .handle()
        .open("second", move |_| async move { Ok(second) })
        .await
        .unwrap();
    let mut wait = Box::pin(root.wait_closed());
    assert!(poll!(wait.as_mut()).is_pending());
    assert_eq!(bounded(first_started.recv()).await, Some(1));
    assert_eq!(bounded(second_started.recv()).await, Some(1));
    drop(wait);
    first_outcome
        .pop()
        .unwrap()
        .send(Outcome::Failure)
        .ok()
        .unwrap();
    let mut next = Box::pin(root.wait_closed());
    assert!(poll!(next.as_mut()).is_pending());
    second_outcome
        .pop()
        .unwrap()
        .send(Outcome::Success)
        .ok()
        .unwrap();
    let report = bounded(next).await;
    assert!(report.workers_finished);
    assert!(report.pending.is_empty());
    assert_eq!(report.failures.len(), 1);
    assert!(report.failures[0].retained);
    drop((first, second));
}

#[tokio::test]
async fn accepted_callback_panic_is_reported_without_blocking_other_callbacks() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let calls = Arc::new(AtomicUsize::new(0));
    let callback_calls = Arc::clone(&calls);
    let _panic_guard = root
        .handle()
        .on_close("panic", || panic!("cleanup"))
        .unwrap();
    let _other_guard = root
        .handle()
        .on_close("other", move || {
            callback_calls.fetch_add(1, Ordering::SeqCst);
        })
        .unwrap();
    let report = bounded(root.wait_closed()).await;
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert!(report.workers_finished);
    assert!(report.pending.is_empty());
    assert_eq!(report.failures.len(), 1);
    assert!(!report.failures[0].retained);
    assert!(matches!(report.failures[0].error, CloseError::Panicked));
    assert!(!report.is_clean());
}

#[tokio::test]
async fn runtime_shutdown_marks_an_inflight_cleanup_failed_and_retains_resource() {
    let (resource, control, mut started, _outcomes) = controlled(1);
    let (ready_tx, ready_rx) = oneshot::channel();
    let (stop_tx, stop_rx) = oneshot::channel();
    let thread = std::thread::spawn(move || {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        runtime.block_on(async move {
            let root = ScopeOwner::<Failure>::new("other runtime", Handle::current());
            let managed = root
                .handle()
                .open("resource", move |_| async move { Ok(resource) })
                .await
                .unwrap();
            managed.request_close();
            ready_tx.send((root, managed)).ok().unwrap();
            stop_rx.await.unwrap();
        });
    });
    let (root, managed) = bounded(ready_rx).await.unwrap();
    assert_eq!(bounded(started.recv()).await, Some(1));
    stop_tx.send(()).unwrap();
    thread.join().unwrap();
    let report = bounded(root.wait_closed()).await;
    assert!(report.workers_finished);
    assert_eq!(report.failures.len(), 1);
    assert!(report.failures[0].retained);
    assert!(matches!(
        report.failures[0].error,
        CloseError::WorkerStopped
    ));
    assert!(matches!(
        managed.close().await,
        Err(CloseError::WorkerStopped)
    ));
    assert!(matches!(
        managed.retry_close().await,
        Err(CloseError::WorkerStopped)
    ));
    assert_eq!(control.attempts.load(Ordering::SeqCst), 1);
    assert_eq!(control.dropped.load(Ordering::SeqCst), 0);
    drop(managed);
    drop(root);
    assert_eq!(control.dropped.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn cancelled_factory_token_never_publishes_the_resource() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let (resource, control, mut started, mut outcomes) = controlled(1);
    let result = root
        .handle()
        .open("cancelled by factory", move |token| async move {
            token.cancel();
            Ok(resource)
        })
        .await;
    assert!(matches!(result, Err(OpenError::Cancelled)));
    assert_eq!(bounded(started.recv()).await, Some(1));
    outcomes.pop().unwrap().send(Outcome::Success).ok().unwrap();
    assert!(bounded(root.wait_closed()).await.is_clean());
    assert_eq!(control.dropped.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn owner_and_managed_drop_from_foreign_threads_start_real_cleanup() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let handle = root.handle();
    let (resource, control, mut started, mut outcomes) = controlled(1);
    let managed = handle
        .open("foreign drop", move |_| async move { Ok(resource) })
        .await
        .unwrap();
    std::thread::spawn(move || drop(managed)).join().unwrap();
    assert_eq!(bounded(started.recv()).await, Some(1));
    std::thread::spawn(move || drop(root)).join().unwrap();
    outcomes.pop().unwrap().send(Outcome::Success).ok().unwrap();
    // Dropping the unique owner does not stop its already tracked worker.
    // The resource's own Drop is the observable acknowledgement here.
    bounded(control.dropped_notify.notified()).await;
    assert!(handle.child("after owner").is_err());
    assert_eq!(control.attempts.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn ordinary_factory_error_does_not_leave_a_failed_scope() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let result = root
        .handle()
        .open("failure", |_| async { Err::<Resource, _>(Failure("open")) })
        .await;
    assert!(matches!(result, Err(OpenError::Resource(error)) if *error == Failure("open")));
    assert!(bounded(root.wait_closed()).await.is_clean());
}

#[tokio::test]
async fn stopping_runtime_with_active_resource_requests_cancellation() {
    let (resource, control, _started, _outcomes) = controlled(0);
    let (ready_tx, ready_rx) = oneshot::channel();
    let (stop_tx, stop_rx) = oneshot::channel();
    let thread = std::thread::spawn(move || {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        runtime.block_on(async move {
            let root = ScopeOwner::<Failure>::new("other runtime", Handle::current());
            let managed = root
                .handle()
                .open("active", move |_| async move { Ok(resource) })
                .await
                .unwrap();
            ready_tx.send((root, managed)).ok().unwrap();
            stop_rx.await.unwrap();
        });
    });
    let (root, managed) = bounded(ready_rx).await.unwrap();
    assert_eq!(control.requests.load(Ordering::SeqCst), 0);
    stop_tx.send(()).unwrap();
    thread.join().unwrap();
    let report = bounded(root.wait_closed()).await;
    assert_eq!(report.failures.len(), 1);
    assert!(report.failures[0].retained);
    assert!(matches!(
        report.failures[0].error,
        CloseError::WorkerStopped
    ));
    assert!(control.requests.load(Ordering::SeqCst) > 0);
    assert_eq!(control.attempts.load(Ordering::SeqCst), 0);
    drop((managed, root));
    assert_eq!(control.dropped.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn synchronous_callback_is_not_preempted_by_scope_deadline() {
    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let (started_tx, started_rx) = oneshot::channel();
    let (release_tx, release_rx) = std::sync::mpsc::channel();
    let registration = root
        .handle()
        .on_close("callback", move || {
            started_tx.send(()).unwrap();
            release_rx.recv().unwrap();
        })
        .unwrap();
    let (result_tx, mut result_rx) = oneshot::channel();
    let thread = std::thread::spawn(move || {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let report = runtime.block_on(root.close(Instant::now()));
        result_tx.send(report).ok().unwrap();
    });
    bounded(started_rx).await.unwrap();
    assert!(matches!(
        result_rx.try_recv(),
        Err(oneshot::error::TryRecvError::Empty)
    ));
    release_tx.send(()).unwrap();
    assert!(bounded(result_rx).await.unwrap().is_clean());
    thread.join().unwrap();
    drop(registration);
}

#[tokio::test]
async fn panics_while_creating_factory_or_close_futures_are_observed() {
    fn panicking_factory(_: CancellationToken) -> std::future::Ready<Result<Resource, Failure>> {
        panic!("factory did not return a future")
    }
    struct PanickingClose(Arc<AtomicUsize>);
    impl ManagedResource for PanickingClose {
        type Error = Failure;
        fn request_close(&self) {}
        fn close(&self) -> impl Future<Output = Result<(), Failure>> + Send {
            assert!(
                self.0.fetch_add(1, Ordering::SeqCst) != 0,
                "close did not return a future"
            );
            std::future::ready(Ok(()))
        }
    }

    let root = ScopeOwner::<Failure>::new("root", Handle::current());
    let opening = root.handle().open("factory panic", panicking_factory).await;
    assert!(matches!(opening, Err(OpenError::Panicked)));
    let calls = Arc::new(AtomicUsize::new(0));
    let resource_calls = Arc::clone(&calls);
    let managed = root
        .handle()
        .open("close panic", move |_| async move {
            Ok(PanickingClose(resource_calls))
        })
        .await
        .unwrap();
    assert!(matches!(
        bounded(managed.close()).await,
        Err(CloseError::Panicked)
    ));
    assert!(bounded(managed.retry_close()).await.is_ok());
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    let report = bounded(root.wait_closed()).await;
    assert!(report.workers_finished);
    assert_eq!(report.failures.len(), 1);
    assert_eq!(report.failures[0].phase, Phase::Opening);
    assert!(!report.failures[0].retained);
}
