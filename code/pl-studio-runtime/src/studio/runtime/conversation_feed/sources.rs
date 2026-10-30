//! Domain waits and publication gates over the feed's original owned handles.

use std::{
    pin::Pin,
    task::{Context, Poll},
};

use futures::Stream;

use super::*;

pub(super) type ActivityWait = BoxFuture<'static, (watch::Receiver<Arc<ActivitySnapshot>>, bool)>;

pub(super) enum SourceEvent {
    State(
        Box<StudioThreadSubscription>,
        Result<Option<ThreadSubscriptionUpdate>>,
    ),
    Content,
    ActivityChanged(watch::Receiver<Arc<ActivitySnapshot>>, bool),
    ActivityFrame(ActivityContentFrame),
}

pub(super) struct StateSource {
    pub wait: Option<StateWait>,
}

pub(super) struct ContentSource {
    pub slot: Option<ContentSlot>,
    pub allowed_through: u64,
}

/// A completed read replaces its original wait; it never coexists with a next read.
pub(super) enum ContentSlot {
    Waiting(ContentWait),
    Ready(Box<(TimelineTailStream, Result<Option<TimelineTailUpdate>>)>),
}

/// The only owner of activity input, encoding progress and completion handoff.
pub(super) struct ActivitySource {
    pub wait: Option<ActivityWait>,
    pub delivery: ActivityDelivery,
    pub frames: VecDeque<ActivityContentFrame>,
    pub through: u64,
    pub delivered_completion: u64,
    pub permitted_completion: u64,
    pub bootstrap: bool,
    pub had_source: bool,
}

impl ActivitySource {
    pub fn ensure_completion_has_activity(&self, through: u64) -> Result<()> {
        ensure!(
            !self.had_source
                || self.wait.is_some()
                || through <= self.permitted_completion.max(self.through),
            "completion batch lost its activity source"
        );
        Ok(())
    }

    pub fn completion_limit(&self) -> u64 {
        if !self.had_source {
            return u64::MAX;
        }
        if !self.bootstrap
            && matches!(
                self.frames.front(),
                Some(ActivityContentFrame::Commit { .. })
            )
        {
            self.permitted_completion.max(self.through)
        } else {
            self.permitted_completion
        }
    }

    pub fn commit_delivered(&mut self) {
        self.bootstrap = false;
        self.permitted_completion = self.permitted_completion.max(self.through);
    }

    pub fn commit_waits(&self) -> bool {
        matches!(
            self.frames.front(),
            Some(ActivityContentFrame::Commit { .. })
        ) && !self.bootstrap
            && self.delivered_completion < self.through
    }
}

// Empty slots and gated inputs are temporarily Pending, never Ready(None).
// recv alone decides overall exhaustion. Select may permanently retire a source
// after Ready(None); recv instead rearms a wait or retains its one gated result.
fn poll_wait<T>(slot: &mut Option<BoxFuture<'static, T>>, cx: &mut Context<'_>) -> Poll<T> {
    let Some(wait) = slot.as_mut() else {
        return Poll::Pending;
    };
    let result = std::task::ready!(wait.as_mut().poll(cx));
    *slot = None;
    Poll::Ready(result)
}

impl Stream for StateSource {
    type Item = SourceEvent;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        poll_wait(&mut self.wait, cx)
            .map(|(state, result)| Some(SourceEvent::State(Box::new(state), result)))
    }
}

impl Stream for ContentSource {
    type Item = SourceEvent;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let allowed_through = self.allowed_through;
        match self.slot.as_mut() {
            Some(ContentSlot::Waiting(wait)) => {
                let result = std::task::ready!(wait.as_mut().poll(cx));
                self.slot = Some(ContentSlot::Ready(Box::new(result)));
                // Inspect terminal/error outcomes even while data publication is gated.
                Poll::Ready(Some(SourceEvent::Content))
            }
            Some(ContentSlot::Ready(ready)) => {
                let publishable = match &ready.1 {
                    Ok(Some(TimelineTailUpdate::Batch { from_seq, .. })) => {
                        *from_seq < allowed_through
                    }
                    _ => true,
                };
                if publishable {
                    Poll::Ready(Some(SourceEvent::Content))
                } else {
                    Poll::Pending
                }
            }
            None => Poll::Pending,
        }
    }
}

impl Stream for ActivitySource {
    type Item = SourceEvent;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        if !self.frames.is_empty() {
            return if self.commit_waits() {
                Poll::Pending
            } else {
                Poll::Ready(self.frames.pop_front().map(SourceEvent::ActivityFrame))
            };
        }
        poll_wait(&mut self.wait, cx)
            .map(|(source, changed)| Some(SourceEvent::ActivityChanged(source, changed)))
    }
}

pub(super) fn wait_activity(
    mut source: watch::Receiver<Arc<ActivitySnapshot>>,
    cancel: CancellationToken,
) -> ActivityWait {
    Box::pin(async move {
        let changed = tokio::select! {
            biased;
            () = cancel.cancelled() => false,
            result = source.changed() => result.is_ok(),
        };
        (source, changed)
    })
}
