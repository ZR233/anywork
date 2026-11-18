#[path = "support/preparation.rs"]
mod preparation;
mod support;

use pl_core::{
    context::ContextSnapshot,
    model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, ModelTurnAction, PreparedModelCall,
    },
    thread::{
        ContinuationDisposition, ContinuationRead, ModelStepLimit, ResumeRequest, ThreadError,
        ThreadHandle, TurnOutcome, input::InputDriverOptions,
    },
};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};

struct ContinuingModel {
    requests: Arc<Mutex<Vec<ContextSnapshot>>>,
    calls: Arc<AtomicUsize>,
}
impl ModelSession for ContinuingModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.requests.lock().unwrap().push(request.context.clone());
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(PreparedModelCall::new(async move {
            let mut output = support::response(&request, vec![]);
            output.turn_action = ModelTurnAction::Continue;
            Ok(output)
        }))
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

fn options() -> InputDriverOptions {
    InputDriverOptions {
        max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
    }
}

async fn paused() -> (
    ThreadHandle,
    Arc<AtomicUsize>,
    Arc<Mutex<Vec<ContextSnapshot>>>,
) {
    let calls = Arc::new(AtomicUsize::new(0));
    let requests = Arc::new(Mutex::new(vec![]));
    let thread = ThreadHandle::start_current(
        "resume-control".into(),
        Some(DynModelSession::new(ContinuingModel {
            requests: requests.clone(),
            calls: calls.clone(),
        })),
    )
    .unwrap();
    let mut input = support::turn("first");
    input.max_model_steps = options().max_model_steps;
    let result = thread.run_turn(input).await.unwrap();
    assert_eq!(result.outcome, TurnOutcome::StepLimit);
    assert!(thread.snapshot().continuation.is_some());
    (thread, calls, requests)
}

fn request(thread: &ThreadHandle, id: &str) -> ResumeRequest {
    ResumeRequest {
        operation_id: id.into(),
        expected_continuation_token: thread.snapshot().continuation.as_ref().unwrap().id.clone(),
        request_digest: None,
    }
}

async fn settled(thread: &ThreadHandle) {
    let mut changes = thread.subscribe();
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        while thread.snapshot().execution.is_some() {
            changes.next().await.unwrap();
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn empty_pending_resume_uses_confirmed_context_and_replays_only_the_receipt() {
    let (thread, calls, requests) = paused().await;
    let request = request(&thread, "resume");
    assert_eq!(
        thread.read_resume(request.clone()).await.unwrap(),
        ContinuationRead::NotAccepted
    );
    let receipt = thread
        .resume_execution(request.clone(), options())
        .await
        .unwrap();
    assert_eq!(receipt.disposition, ContinuationDisposition::Scheduled);
    settled(&thread).await;
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    let snapshots = requests.lock().unwrap().clone();
    assert_eq!(
        snapshots[0]
            .records
            .iter()
            .filter(|r| matches!(r.source, pl_core::context::ContextSource::User))
            .count(),
        snapshots[1]
            .records
            .iter()
            .filter(|r| matches!(r.source, pl_core::context::ContextSource::User))
            .count()
    );
    assert!(thread.snapshot().inputs.is_empty());
    assert!(thread.snapshot().terminal_inputs.is_empty());
    let replay = thread
        .resume_execution(request.clone(), options())
        .await
        .unwrap();
    assert_eq!(replay.execution_id, receipt.execution_id);
    assert_eq!(replay.accepted_revision, receipt.accepted_revision);
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    let mut conflicting = request.clone();
    conflicting.expected_continuation_token.push('x');
    assert!(matches!(
        thread.resume_execution(conflicting, options()).await,
        Err(ThreadError::InvalidIdentity)
    ));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn cache_eviction_makes_an_old_token_stale_instead_of_not_accepted() {
    let (thread, calls, _) = paused().await;
    let first = request(&thread, "operation-0");
    for index in 0..65 {
        let request = request(&thread, &format!("operation-{index}"));
        thread.resume_execution(request, options()).await.unwrap();
        settled(&thread).await;
    }
    assert_eq!(thread.snapshot().continuation_operations.len(), 64);
    assert_eq!(calls.load(Ordering::SeqCst), 66);
    assert!(matches!(
        thread.read_resume(first.clone()).await,
        Err(ThreadError::StaleContinuation)
    ));
    assert!(matches!(
        thread.resume_execution(first, options()).await,
        Err(ThreadError::StaleContinuation)
    ));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn stop_before_admission_settles_scheduled_resume_without_calling_the_model() {
    let (thread, calls, _) = paused().await;
    let hold = preparation::HoldPreparation::install(&thread).await;
    let original = request(&thread, "scheduled");
    let accepted = thread
        .resume_execution(original.clone(), options())
        .await
        .unwrap();
    hold.entered().await;
    thread
        .interrupt_execution(accepted.execution_id.clone())
        .await
        .unwrap();
    settled(&thread).await;
    let ContinuationRead::Known(stopped) = thread.read_resume(original.clone()).await.unwrap()
    else {
        panic!("accepted receipt disappeared");
    };
    assert!(matches!(
        stopped.disposition,
        ContinuationDisposition::NotExecuted(pl_core::thread::ContinuationNotExecuted::Stopped)
    ));
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert_eq!(
        thread.resume_execution(original, options()).await.unwrap(),
        stopped
    );
    let fresh = request(&thread, "fresh");
    let next = thread.resume_execution(fresh, options()).await.unwrap();
    assert_ne!(next.execution_id, stopped.execution_id);
    settled(&thread).await;
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn restart_issues_a_fresh_token_and_retains_scheduled_feedback_without_execution() {
    let (thread, calls, _) = paused().await;
    let hold = preparation::HoldPreparation::install(&thread).await;
    let original = request(&thread, "before-restart");
    let scheduled = thread
        .resume_execution(original.clone(), options())
        .await
        .unwrap();
    hold.entered().await;
    let current = thread
        .capture_current(tokio_util::sync::CancellationToken::new())
        .await
        .unwrap();
    thread
        .interrupt_execution(scheduled.execution_id.clone())
        .await
        .unwrap();
    settled(&thread).await;
    thread.close().await.unwrap();
    assert_eq!(calls.load(Ordering::SeqCst), 1);

    let (model, requests) = support::ScriptedModel::new(&[]);
    let restored =
        ThreadHandle::restore_current(current, Some(DynModelSession::new(model))).unwrap();
    assert!(requests.lock().unwrap().is_empty());
    let ContinuationRead::Known(receipt) = restored.read_resume(original.clone()).await.unwrap()
    else {
        panic!("saved receipt lost");
    };
    assert_eq!(
        receipt.disposition,
        ContinuationDisposition::NotExecuted(
            pl_core::thread::ContinuationNotExecuted::RestoredPaused
        )
    );
    assert_eq!(
        restored
            .resume_execution(original.clone(), options())
            .await
            .unwrap(),
        receipt
    );
    assert!(requests.lock().unwrap().is_empty());
    let fresh = request(&restored, "after-restart");
    assert_ne!(
        fresh.expected_continuation_token,
        original.expected_continuation_token
    );
    let accepted = restored.resume_execution(fresh, options()).await.unwrap();
    assert_ne!(accepted.execution_id, scheduled.execution_id);
    settled(&restored).await;
    assert_eq!(requests.lock().unwrap().len(), 1);
    restored.close().await.unwrap();
}
