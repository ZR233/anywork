//! 保存观察只负责唤醒，完成判据始终重新读取 canonical input identity。

use super::owner::{CLAIM_RENEW_INTERVAL, IngressControl};
use crate::bots::protocol::error::FeishuError;
use crate::studio::{StudioRuntime, TimelineTailStream};
use std::time::Duration;

pub(super) struct InputWatch {
    tail: Option<TimelineTailStream>,
}

impl InputWatch {
    pub(super) fn new() -> Self {
        Self { tail: None }
    }

    /// A prepared input keeps its owner through temporary observation failures as well as
    /// ordinary wakes. Failing to open a read-only tail must not trigger a re-enqueue/GET.
    pub(super) async fn wait_prepared(
        &mut self,
        runtime: &StudioRuntime,
        thread_id: &str,
        control: &IngressControl,
        retry_at: Option<i64>,
    ) -> anyhow::Result<()> {
        if let Err(error) = self.wait(runtime, thread_id, control, retry_at).await {
            let error = FeishuError::history_read("prepared input observation failed", error);
            if !error.retryable() {
                return Err(error.into());
            }
            wait_before_reopen(control, retry_at).await;
        }
        Ok(())
    }

    pub(super) async fn wait(
        &mut self,
        runtime: &StudioRuntime,
        thread_id: &str,
        control: &IngressControl,
        retry_at: Option<i64>,
    ) -> anyhow::Result<()> {
        if self.tail.is_none() {
            // Opening the typed observer has an owner and is allowed to finish; no select drops
            // partially registered asynchronous work. Cancellation is checked by the caller.
            let mut tail = runtime.open_timeline_tail(thread_id).await?;
            // Consume the bounded, one-shot baseline before next(). Keep no uninitialized tail
            // on error, and derive no input/admission fact from the baseline's contents.
            let _ = tail.initial()?;
            self.tail = Some(tail);
            // Facts may have changed between the owner's last read and subscription capture.
            // Wake once now so it re-checks canonical input before waiting for later updates.
            return Ok(());
        }
        let Some(tail) = &mut self.tail else {
            unreachable!("the just-opened tail is retained by this observer");
        };
        // The persistent wall-clock deadline remains authoritative. Wake at least every lease
        // interval to re-read facts and account for clock changes; do not busy-loop after acceptance.
        let delay = retry_delay(retry_at);
        tokio::select! {
            _ = control.cancelled() => {}
            _ = tokio::time::sleep(delay) => {}
            update = tail.next() => {
                match update {
                    Ok(Some(_)) => {}
                    Ok(None) => {
                    self.tail = None;
                        // Observation ended, not the canonical input. Pace reopening even when
                        // the retry is already due; the owner still reads facts before admission.
                        wait_before_reopen(control, retry_at).await;
                }
                    Err(error) => {
                        self.tail = None;
                        // Preserve the real typed source for wait_prepared's classification.
                        return Err(error);
                    }
                }
            }
        }
        Ok(())
    }
}

async fn wait_before_reopen(control: &IngressControl, retry_at: Option<i64>) {
    // A past deadline is permission to re-check facts, not permission to spin on an ended/broken
    // observer. Retain the run and drafts, but allow shutdown/lost-claim to interrupt this pause.
    let delay = retry_delay(retry_at);
    let delay = if delay.is_zero() {
        CLAIM_RENEW_INTERVAL
    } else {
        delay
    };
    tokio::select! {
        _ = control.cancelled() => {}
        _ = tokio::time::sleep(delay) => {}
    }
}

fn retry_delay(retry_at: Option<i64>) -> Duration {
    retry_at.map_or(CLAIM_RENEW_INTERVAL, |at| {
        Duration::from_secs(at.saturating_sub(crate::studio::unix_seconds()).max(0) as u64)
            .min(CLAIM_RENEW_INTERVAL)
    })
}
