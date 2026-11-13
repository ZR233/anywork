use super::ClosePurpose;
use crate::{
    context::{ContextContent, OpaquePayload},
    model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput, ModelToolCall,
        PreparedModelCall,
    },
    thread::{
        ModelStepLimit, ThreadError, ThreadHandle, ThreadLifecycle, TurnInput,
        cold::{ColdStore, ColdStoreError, ColdStoreHandle, StoragePressure, ThreadWrite},
        input::{InputPurpose, ThreadInput},
    },
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use pl_agent_tool::{Tool, ToolDefinition, ToolHandle};
use std::sync::{
    Arc, LazyLock,
    atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
};
use tokio_util::sync::CancellationToken;

struct BackgroundModel {
    issued: bool,
    closed: Arc<AtomicUsize>,
}

impl ModelSession for BackgroundModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let tool_calls = if std::mem::replace(&mut self.issued, true) {
            vec![]
        } else {
            vec![ModelToolCall {
                presentation_contract: None,
                rejection: None,
                call_id: "held-call".into(),
                tool_id: "held".into(),
                arguments: OpaquePayload::text("held"),
            }]
        };
        Ok(PreparedModelCall::new(async move {
            Ok(ModelStepOutput {
                turn_action: Default::default(),
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: vec![ContextContent::Text {
                    text: "background work accepted".into(),
                }],
                tool_calls,
                private_context: None,
                usage: Default::default(),
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        self.closed.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }
}

#[derive(Debug, Default)]
struct HeldTool {
    started: CancellationToken,
    cancelled: CancellationToken,
    release: CancellationToken,
    joined: AtomicBool,
    close_attempts: AtomicUsize,
}

struct HeldToolInstance(Arc<HeldTool>);

impl Tool for HeldToolInstance {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        static DEFINITION: LazyLock<ToolDefinition> = LazyLock::new(|| {
            ToolDefinition::text("held", "Text tool for thread close tests")
                .expect("valid definition")
        });
        &DEFINITION
    }

    async fn execute(
        &self,
        _: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.0.started.cancel();
        context.cancellation.cancelled().await;
        self.0.cancelled.cancel();
        self.0.release.cancelled().await;
        self.0.joined.store(true, Ordering::SeqCst);
        Err(ToolError::new(ThreadError::Cancelled))
    }

    async fn close(&self) -> Result<(), ToolError> {
        assert!(self.0.joined.load(Ordering::SeqCst));
        if self.0.close_attempts.fetch_add(1, Ordering::SeqCst) == 0 {
            return Err(ToolError::new(std::io::Error::other(
                "resource close failed once",
            )));
        }
        Ok(())
    }
}

#[derive(Debug, Default)]
struct SaveProbe {
    admitted: AtomicU64,
    durable: AtomicU64,
    admissions: AtomicUsize,
    flushes: AtomicUsize,
    fail_flush: AtomicBool,
    block_flush: AtomicBool,
    flush_entered: CancellationToken,
    flush_exited: Arc<AtomicBool>,
}

impl ColdStore for Arc<SaveProbe> {
    fn admit(&self, _: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        self.admissions.fetch_add(1, Ordering::SeqCst);
        self.admitted
            .fetch_max(write.effect.sequence, Ordering::SeqCst);
        Ok(())
    }

    fn pressure(&self, _: &str) -> StoragePressure {
        StoragePressure {
            durable_sequence: self.durable.load(Ordering::SeqCst),
            ..Default::default()
        }
    }

    async fn flush(&self, _: &str, through: u64) -> Result<(), ColdStoreError> {
        self.flushes.fetch_add(1, Ordering::SeqCst);
        if self.block_flush.load(Ordering::SeqCst) {
            let _waiting = CallDrop(self.flush_exited.clone());
            self.flush_entered.cancel();
            return std::future::pending().await;
        }
        if self.fail_flush.load(Ordering::SeqCst) {
            Err(ColdStoreError {
                source: Box::new(std::io::Error::other(
                    "final save must be skipped for deletion",
                )),
            })
        } else {
            assert!(through <= self.admitted.load(Ordering::SeqCst));
            self.durable.fetch_max(through, Ordering::SeqCst);
            Ok(())
        }
    }
}

async fn close(thread: &ThreadHandle, purpose: ClosePurpose) -> Result<(), ThreadError> {
    match purpose {
        ClosePurpose::Preserve => thread.close().await,
        ClosePurpose::Delete => thread.close_for_deletion().await,
    }
}

async fn exercise_close(purpose: ClosePurpose) {
    let model_closed = Arc::new(AtomicUsize::new(0));
    let thread = ThreadHandle::start(
        "close-purpose".into(),
        DynModelSession::new(BackgroundModel {
            issued: false,
            closed: model_closed.clone(),
        }),
    )
    .unwrap();
    let store = Arc::new(SaveProbe::default());
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    let registration = Registration::prepare("held".into(), OpaquePayload::text("held")).unwrap();
    let tool = Arc::new(HeldTool::default());
    thread
        .register_tools(vec![
            registration.attach(ToolHandle::new(HeldToolInstance(tool.clone()))),
        ])
        .await
        .unwrap();
    thread
        .run_turn(TurnInput {
            turn_id: "background".into(),
            attempt_prefix: "attempt".into(),
            content: vec![ContextContent::Text {
                text: "start background work".into(),
            }],
            max_model_steps: ModelStepLimit::Limited(3.try_into().unwrap()),
            cancellation: CancellationToken::new(),
        })
        .await
        .unwrap();
    tool.started.cancelled().await;
    thread
        .submit_input(ThreadInput {
            id: "queued-before-close".into(),
            purpose: InputPurpose::Message,
            payload: OpaquePayload::text("pending work"),
            context: vec![ContextContent::Text {
                text: "pending work".into(),
            }],
        })
        .await
        .unwrap();
    assert!(thread.snapshot().continuation.is_none());
    let flushes = store.flushes.load(Ordering::SeqCst);
    let admissions = store.admissions.load(Ordering::SeqCst);
    store.fail_flush.store(true, Ordering::SeqCst);
    let mut closing = Box::pin(close(&thread, purpose));
    tokio::select! {
        result = &mut closing => panic!("close skipped the real task join: {result:?}"),
        () = tool.cancelled.cancelled() => {}
    }
    assert!(!tool.joined.load(Ordering::SeqCst));
    assert!(futures::poll!(&mut closing).is_pending());
    tool.release.cancel();
    assert!(closing.await.is_err(), "first resource close must fail");
    assert!(tool.joined.load(Ordering::SeqCst));
    assert_eq!(model_closed.load(Ordering::SeqCst), 1);
    assert_eq!(store.flushes.load(Ordering::SeqCst), flushes);

    match purpose {
        ClosePurpose::Delete => {
            close(&thread, purpose).await.unwrap();
            assert_eq!(store.flushes.load(Ordering::SeqCst), flushes);
            assert_eq!(store.admissions.load(Ordering::SeqCst), admissions);
            assert!(thread.snapshot().continuation.is_none());
        }
        ClosePurpose::Preserve => {
            assert!(
                close(&thread, purpose).await.is_err(),
                "save failure is retained"
            );
            assert!(store.flushes.load(Ordering::SeqCst) > flushes);
            assert!(thread.snapshot().continuation.is_some());
            store.fail_flush.store(false, Ordering::SeqCst);
            close(&thread, purpose).await.unwrap();
        }
    }
    assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Closed);
    assert!(tool.close_attempts.load(Ordering::SeqCst) >= 2);
    assert_eq!(model_closed.load(Ordering::SeqCst), 1);
    assert!(matches!(
        close(&thread, purpose).await,
        Err(ThreadError::Closed)
    ));
}

#[tokio::test]
async fn deletion_close_joins_background_and_retries_resources_without_final_save() {
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        exercise_close(ClosePurpose::Delete),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn preserving_close_joins_background_and_retains_final_save_failure() {
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        exercise_close(ClosePurpose::Preserve),
    )
    .await
    .unwrap();
}

struct ActiveModel {
    started: CancellationToken,
    call_dropped: Arc<AtomicBool>,
    closing: CancellationToken,
    release: CancellationToken,
    closed: Arc<AtomicBool>,
}

struct CallDrop(Arc<AtomicBool>);
impl Drop for CallDrop {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

impl ModelSession for ActiveModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let started = self.started.clone();
        let dropped = self.call_dropped.clone();
        Ok(PreparedModelCall::new(async move {
            let _call = CallDrop(dropped);
            started.cancel();
            request.cancellation.cancelled().await;
            Err(ModelError {
                kind: crate::model::ModelFailureKind::Cancelled,
                details: None,
                usage: Box::default(),
                source: None,
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        assert!(self.call_dropped.load(Ordering::SeqCst));
        self.closing.cancel();
        self.release.cancelled().await;
        self.closed.store(true, Ordering::SeqCst);
        Ok(())
    }
}

async fn exercise_active_turn_close(purpose: ClosePurpose) {
    let started = CancellationToken::new();
    let closing = CancellationToken::new();
    let release = CancellationToken::new();
    let call_dropped = Arc::new(AtomicBool::new(false));
    let model_closed = Arc::new(AtomicBool::new(false));
    let thread = ThreadHandle::start(
        "active-close".into(),
        DynModelSession::new(ActiveModel {
            started: started.clone(),
            call_dropped: call_dropped.clone(),
            closing: closing.clone(),
            release: release.clone(),
            closed: model_closed.clone(),
        }),
    )
    .unwrap();
    let store = Arc::new(SaveProbe::default());
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    let running = {
        let thread = thread.clone();
        tokio::spawn(async move {
            thread
                .run_turn(TurnInput {
                    turn_id: "still-running".into(),
                    attempt_prefix: "active-attempt".into(),
                    content: vec![ContextContent::Text {
                        text: "execute".into(),
                    }],
                    max_model_steps: ModelStepLimit::Limited(3.try_into().unwrap()),
                    cancellation: CancellationToken::new(),
                })
                .await
        })
    };
    started.cancelled().await;
    assert!(thread.snapshot().execution.is_some());
    let flushes = store.flushes.load(Ordering::SeqCst);
    let admissions = store.admissions.load(Ordering::SeqCst);
    store.fail_flush.store(true, Ordering::SeqCst);
    let mut closing_thread = Box::pin(close(&thread, purpose));
    tokio::select! {
        result = &mut closing_thread => panic!("close skipped model cleanup: {result:?}"),
        () = closing.cancelled() => {}
    }
    assert!(call_dropped.load(Ordering::SeqCst));
    assert!(!model_closed.load(Ordering::SeqCst));
    assert!(futures::poll!(&mut closing_thread).is_pending());
    assert!(matches!(
        running.await.unwrap(),
        Err(ThreadError::Cancelled)
    ));
    assert_eq!(
        thread.snapshot().continuation.is_some(),
        purpose == ClosePurpose::Preserve
    );
    release.cancel();
    let result = closing_thread.await;
    assert!(model_closed.load(Ordering::SeqCst));
    match purpose {
        ClosePurpose::Delete => {
            result.unwrap();
            assert_eq!(store.flushes.load(Ordering::SeqCst), flushes);
            assert_eq!(store.admissions.load(Ordering::SeqCst), admissions);
            assert!(thread.snapshot().continuation.is_none());
        }
        ClosePurpose::Preserve => {
            assert!(result.is_err());
            assert!(store.flushes.load(Ordering::SeqCst) > flushes);
            let continuation = thread.snapshot().continuation.clone().unwrap();
            assert_eq!(
                continuation.reason,
                Some(crate::thread::ContinuationReason::HostShutdown)
            );
            store.fail_flush.store(false, Ordering::SeqCst);
            thread.close().await.unwrap();
        }
    }
}

#[tokio::test]
async fn deletion_close_cancels_active_model_without_recovery_or_final_flush() {
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        exercise_active_turn_close(ClosePurpose::Delete),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn preserving_close_cancels_active_model_with_host_shutdown_and_final_flush() {
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        exercise_active_turn_close(ClosePurpose::Preserve),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn deletion_seal_releases_an_existing_preservation_wait_without_confirming_it() {
    tokio::time::timeout(std::time::Duration::from_secs(10), async {
        let thread = ThreadHandle::resume_without_model("blocked-flush".into(), None).unwrap();
        let store = Arc::new(SaveProbe::default());
        thread
            .attach_storage(ColdStoreHandle::new(store.clone()))
            .await
            .unwrap();
        thread
            .submit_input(ThreadInput {
                id: "owed-before-flush".into(),
                purpose: InputPurpose::Message,
                payload: OpaquePayload::text("unsaved input"),
                context: vec![ContextContent::Text {
                    text: "unsaved input".into(),
                }],
            })
            .await
            .unwrap();
        store.block_flush.store(true, Ordering::SeqCst);
        let flushing = {
            let thread = thread.clone();
            tokio::spawn(async move { thread.flush().await })
        };
        store.flush_entered.cancelled().await;
        assert!(
            !flushing.is_finished(),
            "ordinary preservation waits for the real backend"
        );
        let flushes = store.flushes.load(Ordering::SeqCst);
        thread.prepare_close_for_deletion();
        assert!(matches!(flushing.await.unwrap(), Err(ThreadError::Closed)));
        assert!(store.flush_exited.load(Ordering::SeqCst));
        thread.close_for_deletion().await.unwrap();
        assert_eq!(store.flushes.load(Ordering::SeqCst), flushes);
        assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Closed);
    })
    .await
    .unwrap();
}

#[derive(Debug)]
struct AdmissionRetryProbe {
    rejected: AtomicBool,
    admissions: AtomicUsize,
    durable: AtomicU64,
    changes: tokio::sync::watch::Sender<()>,
}

impl ColdStore for Arc<AdmissionRetryProbe> {
    fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        Some(self.changes.subscribe())
    }
    fn admit(&self, _: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        self.admissions.fetch_add(1, Ordering::SeqCst);
        if self.rejected.load(Ordering::SeqCst) {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("first batch was rejected")),
            });
        }
        self.durable.store(write.effect.sequence, Ordering::SeqCst);
        Ok(())
    }
    fn pressure(&self, _: &str) -> StoragePressure {
        StoragePressure {
            durable_sequence: self.durable.load(Ordering::SeqCst),
            ..Default::default()
        }
    }
    async fn flush(&self, _: &str, _: u64) -> Result<(), ColdStoreError> {
        Ok(())
    }
}

async fn pressure_after_close_seal(purpose: ClosePurpose) {
    let thread = ThreadHandle::resume_without_model("pressure-close-seal".into(), None).unwrap();
    let store = Arc::new(AdmissionRetryProbe {
        rejected: AtomicBool::new(true),
        admissions: AtomicUsize::new(0),
        durable: AtomicU64::new(0),
        changes: tokio::sync::watch::channel(()).0,
    });
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .submit_input(ThreadInput {
            id: "rejected-batch".into(),
            purpose: InputPurpose::Message,
            payload: OpaquePayload::text("pending deletion"),
            context: vec![],
        })
        .await
        .unwrap();
    let before = thread.snapshot();
    let admissions = store.admissions.load(Ordering::SeqCst);
    assert!(
        admissions > 0,
        "the first batch must really have been rejected"
    );
    assert!(before.persistence.error.is_some());
    let mut updates = thread.subscribe();
    let mut preserving_close = Box::pin(thread.close());
    match purpose {
        ClosePurpose::Delete => thread.prepare_close_for_deletion(),
        ClosePurpose::Preserve => assert!(futures::poll!(&mut preserving_close).is_pending()),
    }
    store.rejected.store(false, Ordering::SeqCst);
    store.changes.send_replace(());
    // Await the owner's real publication, rather than assuming a scheduler delay.
    loop {
        let update = updates.next().await.expect("pressure observation");
        if update.observation_revision > before.observation_revision {
            break;
        }
    }
    if purpose == ClosePurpose::Delete {
        assert_eq!(store.admissions.load(Ordering::SeqCst), admissions);
        assert_eq!(
            thread.snapshot().persistence.admitted_sequence,
            before.persistence.admitted_sequence
        );
        assert_eq!(store.durable.load(Ordering::SeqCst), 0);
        assert_eq!(
            thread.snapshot().persistence.durable_sequence,
            before.persistence.durable_sequence
        );
    } else {
        assert!(store.admissions.load(Ordering::SeqCst) > admissions);
        assert!(store.durable.load(Ordering::SeqCst) > 0);
    }
    match purpose {
        ClosePurpose::Delete => thread.close_for_deletion().await.unwrap(),
        ClosePurpose::Preserve => preserving_close.await.unwrap(),
    }
    if purpose == ClosePurpose::Delete {
        assert_eq!(store.admissions.load(Ordering::SeqCst), admissions);
        assert_eq!(store.durable.load(Ordering::SeqCst), 0);
    }
}

#[tokio::test]
async fn deletion_pressure_seal_does_not_readmit_a_rejected_pending_batch() {
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        pressure_after_close_seal(ClosePurpose::Delete),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn preserving_pressure_seal_still_retries_a_rejected_pending_batch() {
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        pressure_after_close_seal(ClosePurpose::Preserve),
    )
    .await
    .unwrap();
}
