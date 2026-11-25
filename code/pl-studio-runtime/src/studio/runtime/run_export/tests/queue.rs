use std::time::Duration;

use anyhow::Result;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

use super::super::queue::{BoundedExportQueue, ExportCommand};
use super::super::types::MAX_QUEUED_BATCHES;
use super::super::worker::await_finalize_with_budget;

fn command() -> ExportCommand {
    ExportCommand::SkillsDiscovered {
        thread_id: "t-root".into(),
        report: pl_tool::skill::SkillDiscoveryReport {
            source_fingerprint: "fingerprint".into(),
            sources: Vec::new(),
            winners: Vec::new(),
            warnings: Vec::new(),
            complete: true,
        },
    }
}

async fn fill(queue: &BoundedExportQueue) {
    for _ in 0..MAX_QUEUED_BATCHES {
        queue.admit(command(), 64).await.unwrap();
    }
}

#[tokio::test]
async fn freeing_a_queue_slot_unblocks_a_waiting_producer() {
    let cancellation = CancellationToken::new();
    let queue = BoundedExportQueue::new(cancellation.clone());
    fill(&queue).await;
    let mut waiting = Box::pin(queue.admit(command(), 64));
    assert!(futures::poll!(&mut waiting).is_pending());
    assert!(matches!(
        queue.pop().await,
        Some(ExportCommand::SkillsDiscovered { .. })
    ));
    assert!(matches!(
        futures::poll!(&mut waiting),
        std::task::Poll::Ready(Ok(()))
    ));
    assert!(!cancellation.is_cancelled());
}

#[tokio::test(start_paused = true)]
async fn finalize_deadline_rejects_a_waiting_producer_and_cancels_the_run() -> Result<()> {
    let cancellation = CancellationToken::new();
    let queue = BoundedExportQueue::new(cancellation.clone());
    fill(&queue).await;
    let mut waiting = Box::pin(queue.admit(command(), 64));
    assert!(futures::poll!(&mut waiting).is_pending());
    let result = queue.enqueue_finalize(false, false, Some(1)).await.unwrap();
    let deadline = Instant::now() + Duration::from_secs(1);
    let outcome = await_finalize_with_budget(&queue, result, Some(deadline)).await;
    assert!(!outcome.trace_complete);
    assert!(!outcome.trace.sealed);
    assert_eq!(outcome.failure.unwrap().code, "exportDeadlineExceeded");
    let std::task::Poll::Ready(Err(error)) = futures::poll!(&mut waiting) else {
        panic!("closing admission must wake blocked producers");
    };
    assert_eq!(error.code, "exportDeadlineExceeded");
    assert!(cancellation.is_cancelled());
    Ok(())
}
