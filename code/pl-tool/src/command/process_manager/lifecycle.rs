use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio_util::sync::CancellationToken;

use crate::command::ManagedCommand;

use super::{CommandProcessEntry, CommandProcessTransition};

pub(super) async fn wait_for_process_activity(entry: &CommandProcessEntry, yield_time: Duration) {
    if yield_time.is_zero() {
        return;
    }
    let deadline = Instant::now() + yield_time;
    loop {
        let notified = entry.notify.notified();
        tokio::pin!(notified);
        notified.as_mut().enable();
        if entry.is_final().await {
            break;
        }
        let now = Instant::now();
        if now >= deadline {
            break;
        }
        let remaining = deadline.saturating_duration_since(now);
        if tokio::time::timeout(remaining, notified).await.is_err() {
            break;
        }
    }
}

#[derive(Clone)]
pub(super) struct CommandLifecycle {
    pub timeout: Duration,
    pub task_cancellation: Option<CancellationToken>,
    pub manager_cancellation: CancellationToken,
    /// Fires when the durable output capture could no longer continue; terminates the process but
    /// keeps it classified as an output failure rather than a user cancellation.
    pub output_failure: CancellationToken,
}

pub(super) fn spawn_lifecycle_task(
    entry: Arc<CommandProcessEntry>,
    mut child: ManagedCommand,
    lifecycle: CommandLifecycle,
) {
    tokio::spawn(async move {
        let separate_capture = child.has_capture_completion();
        let deadline = tokio::time::Instant::now() + lifecycle.timeout;
        let outcome = wait_for_lifecycle_outcome(&mut child, &lifecycle).await;
        let wait_result = match outcome {
            LifecycleOutcome::Exited(result) => result,
            LifecycleOutcome::TimedOut => {
                entry.input_stopped.cancel();
                apply_transition(&entry, CommandProcessTransition::TimeOut).await;
                child.cancellation().cancel();
                child.wait().await
            }
            LifecycleOutcome::Interrupted => {
                entry.input_stopped.cancel();
                apply_transition(&entry, CommandProcessTransition::Cancel).await;
                child.cancellation().cancel();
                child.wait().await
            }
            LifecycleOutcome::OutputFailed => {
                entry.input_stopped.cancel();
                // The read task already recorded the typed reason and applied the terminating
                // transition before it fired this token; terminate the tree and settle the wait so
                // the bytes already captured stay readable.
                child.cancellation().cancel();
                child.wait().await
            }
        };
        entry.input_stopped.cancel();
        // Poll the owned execution through cancellation before taking stdin: an in-flight
        // write may hold this mutex until the physical process closes its read end.
        {
            let mut stdin = entry.stdin.lock().await;
            stdin.writer.take();
        }
        match wait_result {
            Ok(status) => {
                {
                    let mut state = entry.state.lock().await;
                    state.exit = Some(status.clone());
                    if !separate_capture {
                        state.capture_completion_observed = true;
                    }
                }
                apply_transition(
                    &entry,
                    CommandProcessTransition::ProcessExited {
                        exit_code: status.exit_code,
                    },
                )
                .await;
                if separate_capture {
                    let cancelled = async {
                        match &lifecycle.task_cancellation {
                            Some(token) => token.cancelled().await,
                            None => std::future::pending().await,
                        }
                    };
                    let capture = tokio::select! {
                        result=child.finish_capture()=>result,
                        _=tokio::time::sleep_until(deadline)=>{
                            apply_transition(&entry,CommandProcessTransition::TimeOut).await;
                            entry.drain_stopped.cancel();child.finish_capture().await
                        }
                        _=cancelled=>{
                            apply_transition(&entry,CommandProcessTransition::Cancel).await;
                            entry.drain_stopped.cancel();child.finish_capture().await
                        }
                        _=lifecycle.manager_cancellation.cancelled()=>{
                            apply_transition(&entry,CommandProcessTransition::Cancel).await;
                            entry.drain_stopped.cancel();child.finish_capture().await
                        }
                    };
                    match capture {
                        Ok(Some(capture)) => entry.state.lock().await.observe_capture(capture),
                        Ok(None) => {
                            let mut state = entry.state.lock().await;
                            state.capture_completion_observed = true;
                            state.promote_drained_final();
                        }
                        Err(error) => {
                            let mut state = entry.state.lock().await;
                            state.capture_completion_observed = true;
                            state.record_capture_failure(super::CommandCaptureFailure::Write {
                                message: error,
                            });
                            state.promote_drained_final();
                        }
                    }

                    entry.notify.notify_waiters();
                }
            }
            Err(error) => {
                entry.drain_stopped.cancel();
                if separate_capture {
                    entry.state.lock().await.capture_completion_observed = true;
                }
                apply_transition(
                    &entry,
                    CommandProcessTransition::ProcessWaitFailed {
                        error: format!("failed to wait for process: {error}"),
                    },
                )
                .await;
            }
        }
    });
}

enum LifecycleOutcome {
    Exited(std::result::Result<crate::command::CommandExit, String>),
    TimedOut,
    Interrupted,
    OutputFailed,
}

async fn wait_for_lifecycle_outcome(
    child: &mut ManagedCommand,
    lifecycle: &CommandLifecycle,
) -> LifecycleOutcome {
    let cancelled = async {
        match &lifecycle.task_cancellation {
            Some(token) => token.cancelled().await,
            None => std::future::pending().await,
        }
    };
    tokio::select! {
        result = child.wait() => LifecycleOutcome::Exited(result),
        _ = tokio::time::sleep(lifecycle.timeout) => LifecycleOutcome::TimedOut,
        _ = cancelled => LifecycleOutcome::Interrupted,
        _ = lifecycle.output_failure.cancelled() => LifecycleOutcome::OutputFailed,
        _ = lifecycle.manager_cancellation.cancelled() => LifecycleOutcome::Interrupted,
    }
}

pub(super) async fn apply_transition(
    entry: &CommandProcessEntry,
    transition: CommandProcessTransition,
) {
    let mut state = entry.state.lock().await;
    state.apply_transition(transition);
    drop(state);
    entry.notify.notify_waiters();
}
