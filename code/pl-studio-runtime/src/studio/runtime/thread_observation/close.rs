//! Closing observes exact original workers, fixed fences and independent read owners.
use std::sync::{Arc, Mutex};

use futures::FutureExt;
use pl_core::thread::ThreadLifecycle;
use pl_protocol::studio::{CleanupRecovery, FeedCloseIssue};

use super::failure::{
    ObservationCloseFailure, ObservationCloseIssue, ObservationPendingStep, ProgressFailure,
};
use super::fences::{HistoryFence, ObservationFence, WriteFence};
use super::{Observation, ThreadObservations};

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum CloseKind {
    Synchronize,
    Drain,
    Finish,
}

pub(super) struct OriginalTarget {
    id: String,
    observation: Arc<Observation>,
    fence: Arc<ObservationFence>,
}

pub(super) struct CloseRequest {
    owner: ThreadObservations,
    kind: CloseKind,
    targets: Vec<OriginalTarget>,
    global_scopes: Mutex<Option<Vec<FeedCloseIssue>>>,
    empty_write: Mutex<Option<Arc<WriteFence>>>,
}

impl CloseRequest {
    pub(super) fn owner(&self) -> &ThreadObservations {
        &self.owner
    }
}

impl ThreadObservations {
    pub(super) fn close_request(
        &self,
        kind: CloseKind,
        entries: &[(String, Arc<Observation>)],
    ) -> Arc<CloseRequest> {
        let targets = entries
            .iter()
            .map(|(id, observation)| {
                let mut slot = observation
                    .state
                    .fence
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let reusable = slot.as_ref().is_some_and(|fence| {
                    !fence
                        .state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .synchronized
                });
                if !reusable {
                    let snapshot = observation.thread.snapshot();
                    *slot = Some(ObservationFence::new(
                        snapshot.commit_sequence,
                        snapshot.lifecycle,
                    ));
                }
                OriginalTarget {
                    id: id.clone(),
                    observation: observation.clone(),
                    fence: slot
                        .as_ref()
                        .expect("original observation fence installed")
                        .clone(),
                }
            })
            .collect();
        Arc::new(CloseRequest {
            owner: self.clone(),
            kind,
            targets,
            global_scopes: Mutex::new(None),
            empty_write: Mutex::new(None),
        })
    }

    pub(super) async fn execute_close_request(
        &self,
        request: Arc<CloseRequest>,
        previous: Option<&ObservationCloseFailure>,
    ) -> Result<(), ObservationCloseFailure> {
        let reads = async {
            if request.kind != CloseKind::Finish {
                return Vec::new();
            }
            let old = request
                .global_scopes
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone();
            let issues = if let Some(old) = old
                && old
                    .iter()
                    .all(|issue| issue.recovery == CleanupRecovery::Terminal)
            {
                old
            } else {
                self.0.reads.close().await
            };
            *request
                .global_scopes
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(issues.clone());
            issues
        };
        let (result, global_scope_issues) = futures::join!(
            self.execute_observation_close(request.clone(), previous),
            reads
        );
        if global_scope_issues.is_empty() {
            return result;
        }
        let mut failure = result.err().unwrap_or_else(|| ObservationCloseFailure {
            request,
            observations: Vec::new(),
            write_behind: Vec::new(),
            scope_issues: Vec::new(),
            global_scope_issues: Vec::new(),
            retry_request: None,
        });
        extend_issues(&mut failure.scope_issues, global_scope_issues.clone());
        failure.global_scope_issues = global_scope_issues;
        Err(failure)
    }

    async fn execute_observation_close(
        &self,
        request: Arc<CloseRequest>,
        previous: Option<&ObservationCloseFailure>,
    ) -> Result<(), ObservationCloseFailure> {
        let retry_request = if let Some(previous) = previous {
            previous.retry_request.clone()
        } else if request.kind == CloseKind::Synchronize {
            // The pre-existing explicit synchronization request remains separate from permission
            // to resume a fence. An original failed request is never automatically replayed here.
            self.0.projector.writer.retry_now().await.err()
        } else {
            None
        };
        let kind = request.kind;
        let services = &self.0.projector;
        let outcomes = futures::future::join_all(request.targets.iter().enumerate().map(
            |(index, target)| async move {
                let previous = previous.and_then(|failure| failure.observations.get(index));
                let (mut issue, issues) = futures::join!(
                    observe_target(services, target, kind, previous),
                    close_scopes(target, kind)
                );
                if !issues.is_empty() {
                    issue.pending.push(ObservationPendingStep::Scopes);
                }
                (issue, issues)
            },
        ))
        .await;
        let mut scope_issues = Vec::new();
        let mut observations = Vec::new();
        for (issue, issues) in outcomes {
            observations.push(issue);
            extend_issues(&mut scope_issues, issues);
        }
        let projected = observations.iter().all(|issue| {
            !issue.pending.contains(&ObservationPendingStep::Projection)
                && !issue.pending.contains(&ObservationPendingStep::History)
        });
        let mut write_behind = Vec::new();
        if projected {
            // Capture one new product fence only after the original projection/history targets
            // have settled. Install it before awaiting, so cancellation cannot replace its ticket.
            let needs_write = request.targets.iter().any(|target| {
                target
                    .fence
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .write
                    .is_none()
            });
            let new_write = needs_write.then(|| WriteFence::capture(&self.0.projector.writer));
            let mut writes = Vec::new();
            for target in &request.targets {
                let write = {
                    let mut state = target
                        .fence
                        .state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    if state.write.is_none() {
                        state.write = new_write.clone();
                    }
                    state.write.clone()
                };
                if let Some(write) = write
                    && !writes.iter().any(|old| Arc::ptr_eq(old, &write))
                {
                    writes.push(write);
                }
            }
            if request.targets.is_empty() {
                let write = {
                    let mut original = request
                        .empty_write
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    if original.is_none() {
                        let mut slot = self
                            .0
                            .empty_fence
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner);
                        if slot.is_none() {
                            *slot = Some(WriteFence::capture(&self.0.projector.writer));
                        }
                        *original = slot.clone();
                    }
                    original
                        .as_ref()
                        .expect("empty observation barrier installed")
                        .clone()
                };
                writes.push(write);
            }
            for result in futures::future::join_all(writes.iter().map(|write| write.wait())).await {
                if let Err(failure) = result {
                    write_behind.push(failure);
                }
            }
        }
        if projected && write_behind.is_empty() {
            for issue in &mut observations {
                issue
                    .pending
                    .retain(|step| *step != ObservationPendingStep::WriteBehind);
            }
        }
        // A sibling history/read/write wait may let the original outer join settle after its
        // progress failure was captured. Keep that raw progress cause and the real join together.
        for (target, issue) in request.targets.iter().zip(&mut observations) {
            if let Some(completion) = target.observation.task.join().now_or_never() {
                if completion.is_ok() {
                    let current = target.observation.state.progress.borrow().clone();
                    issue.ended_before_final_state = !current.initialized
                        || current.applied < target.fence.target
                        || (request.kind != CloseKind::Synchronize
                            || target.fence.lifecycle == ThreadLifecycle::Closed)
                            && !current.finished;
                }
                issue.completion = Some(completion);
                issue
                    .pending
                    .retain(|step| *step != ObservationPendingStep::Completion);
                target
                    .fence
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .completion_observed = true;
            }
        }
        let clean = retry_request.is_none()
            && write_behind.is_empty()
            && scope_issues.is_empty()
            && observations.iter().all(|issue| !issue.failed());
        // Only exact, wholly Clean owners are retired. A sibling failure does not remove or
        // replace a different incarnation and does not discard this one's actual terminal cause.
        for (target, issue) in request.targets.iter().zip(&observations) {
            let local_clean = !issue.failed() && write_behind.is_empty();
            if local_clean {
                if request.kind != CloseKind::Synchronize
                    && let Ok(facets) = &target.observation.feed.facets
                {
                    facets.close(if request.kind == CloseKind::Drain {
                        pl_protocol::thread_facets::identity::FeedClosedReason::OwnerReplaced
                    } else {
                        pl_protocol::thread_facets::identity::FeedClosedReason::RuntimeStopped
                    });
                }
                target
                    .fence
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .synchronized = true;
                if request.kind == CloseKind::Drain {
                    self.retire_original(target);
                }
            }
        }
        if clean {
            if request.targets.is_empty() {
                let original = request
                    .empty_write
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .clone();
                let retired = {
                    let mut slot = self
                        .0
                        .empty_fence
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    if slot
                        .as_ref()
                        .zip(original.as_ref())
                        .is_some_and(|(left, right)| Arc::ptr_eq(left, right))
                    {
                        slot.take()
                    } else {
                        None
                    }
                };
                drop(retired);
            }
            Ok(())
        } else {
            Err(ObservationCloseFailure {
                request,
                observations,
                write_behind,
                scope_issues,
                global_scope_issues: Vec::new(),
                retry_request,
            })
        }
    }

    fn retire_original(&self, target: &OriginalTarget) {
        let retired = {
            let mut all = self
                .0
                .observations
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let mut retired = Vec::new();
            if let Some(entries) = all.get_mut(&target.id) {
                if let Some(index) = entries
                    .iter()
                    .position(|entry| Arc::ptr_eq(entry, &target.observation))
                {
                    retired.push(entries.remove(index));
                }
                if entries.is_empty() {
                    all.remove(&target.id);
                }
            }
            retired
        };
        drop(retired);
        let retired = {
            let mut live = self
                .0
                .live
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if live
                .get(&target.id)
                .is_some_and(|feed| Arc::ptr_eq(feed, &target.observation.feed))
            {
                live.remove(&target.id)
            } else {
                None
            }
        };
        drop(retired);
    }
}

async fn close_scopes(target: &OriginalTarget, kind: CloseKind) -> Vec<FeedCloseIssue> {
    if kind == CloseKind::Synchronize {
        return Vec::new();
    }
    let (done, old) = {
        let state = target
            .fence
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        (state.scopes_done, state.scope_issues.clone())
    };
    if done {
        return Vec::new();
    }
    let issues = if !old.is_empty()
        && old
            .iter()
            .all(|issue| issue.recovery == CleanupRecovery::Terminal)
    {
        old
    } else {
        match &target.observation.feed.facets {
            Ok(facets) => facets.reads.close().await,
            Err(_) => Vec::new(),
        }
    };
    let mut state = target
        .fence
        .state
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    state.scopes_done = issues.is_empty();
    state.scope_issues = issues.clone();
    issues
}

fn extend_issues(target: &mut Vec<FeedCloseIssue>, issues: Vec<FeedCloseIssue>) {
    for issue in issues {
        if !target.contains(&issue) {
            target.push(issue);
        }
    }
}

impl ObservationCloseIssue {
    fn failed(&self) -> bool {
        self.projection_failed
            || self.ended_before_final_state
            || self.progress_closed.is_some()
            || matches!(&self.completion, Some(Err(_)))
            || self.history.is_some()
            || !self.pending.is_empty()
    }
}

fn can_retry_progress(
    services: &super::ObservationServices,
    observation: &Observation,
    failure: &Arc<ProgressFailure>,
) -> bool {
    if failure.retry_point().is_none() || observation.task.join().now_or_never().is_some() {
        return false;
    }
    let current = observation.state.progress.borrow().clone();
    if !current
        .error
        .as_ref()
        .is_some_and(|error| Arc::ptr_eq(error, failure))
    {
        return false;
    }
    match failure.as_ref() {
        ProgressFailure::ProjectionPanicked => false,
        ProgressFailure::FinalWriteBehind(failure) => {
            services.writer.saved_watermark() >= failure.through
                || services.writer.can_reobserve_original_flush(failure)
        }
        ProgressFailure::Retry { cause, .. } => {
            if let Some(failure) = cause.downcast_ref::<super::fences::HistoryFenceFailure>() {
                failure.can_resume(services)
            } else if let Some(failure) =
                cause.downcast_ref::<crate::studio::agent_host::WriteBehindFlushFailure>()
            {
                services.writer.saved_watermark() >= failure.through
                    || services.writer.can_reobserve_original_flush(failure)
            } else {
                true
            }
        }
    }
}

async fn observe_target(
    services: &super::ObservationServices,
    target: &OriginalTarget,
    kind: CloseKind,
    previous: Option<&ObservationCloseIssue>,
) -> ObservationCloseIssue {
    let observation = &target.observation;
    let mut progress = observation.state.progress.subscribe();
    let initial = progress.borrow().clone();
    let needs_projection = !initial.initialized
        || initial.applied < target.fence.target
        || (kind != CloseKind::Synchronize || target.fence.lifecycle == ThreadLifecycle::Closed)
            && !initial.finished;
    let retry = initial
        .error
        .as_ref()
        .filter(|failure| {
            needs_projection
                && previous.is_none_or(|old| {
                    old.progress_closed.is_none()
                        && old
                            .progress
                            .error
                            .as_ref()
                            .is_some_and(|error| {
                                Arc::ptr_eq(error, failure)
                                    // This original worker has one final WriteFence. Re-publishing
                                    // its cached error may allocate a new wrapper, but an already
                                    // durable fixed ticket permits observing completion, not a new
                                    // grant to retry an unfinished or unrelated failure.
                                    || matches!(
                                        (error.as_ref(), failure.as_ref()),
                                        (ProgressFailure::FinalWriteBehind(old),
                                         ProgressFailure::FinalWriteBehind(current))
                                            if old.through == current.through
                                                && services.writer.saved_watermark() >= current.through
                                    )
                            })
                })
                && can_retry_progress(services, observation, failure)
        })
        .cloned();
    // Only an original retry point can receive a retry notification. Keep its old error visible
    // until the producer publishes another result, including if that producer panics meanwhile.
    if retry.is_some() {
        observation.state.retry.notify_one();
    }
    let mut awaited_retry = retry;
    let mut progress_closed = previous.and_then(|issue| issue.progress_closed.clone());
    let mut completion;
    let state = loop {
        let state = progress.borrow_and_update().clone();
        completion = observation.task.join().now_or_never();
        let terminal = matches!(&completion, Some(Err(_)))
            || matches!(
                state.error.as_deref(),
                Some(ProgressFailure::ProjectionPanicked)
            );
        let reached = state.initialized && state.applied >= target.fence.target;
        if reached {
            target
                .fence
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .history
                .get_or_insert_with(|| HistoryFence {
                    channel: observation.state.channel.clone(),
                    through: state.handoff,
                });
        }
        if terminal {
            break state;
        }
        if let Some(error) = &state.error {
            let waiting = awaited_retry
                .as_ref()
                .is_some_and(|original| Arc::ptr_eq(error, original));
            if !waiting {
                break state;
            }
        } else {
            awaited_retry = None;
        }
        if reached
            && (kind == CloseKind::Synchronize && target.fence.lifecycle != ThreadLifecycle::Closed
                || state.finished)
        {
            break state;
        }
        if state.finished || completion.is_some() {
            break state;
        }
        // Finish cannot invent a final frame for a Thread whose upstream close is still pending.
        if kind != CloseKind::Synchronize
            && target.fence.lifecycle != ThreadLifecycle::Closed
            && observation.thread.snapshot().lifecycle != ThreadLifecycle::Closed
            && state.error.is_none()
        {
            break state;
        }
        tokio::select! {
            result = observation.task.join() => { completion = Some(result); break progress.borrow().clone(); }
            result = progress.changed() => {
                if let Err(error) = result { progress_closed = Some(Arc::new(error)); break progress.borrow().clone(); }
            }
        }
    };
    let projected = state.initialized && state.applied >= target.fence.target;
    let require_final =
        kind != CloseKind::Synchronize || target.fence.lifecycle == ThreadLifecycle::Closed;
    let mut pending = Vec::new();
    if !projected {
        pending.push(ObservationPendingStep::Projection);
    }
    if require_final && !state.finished {
        pending.push(ObservationPendingStep::FinalState);
    }
    let terminal_projection = matches!(
        state.error.as_deref(),
        Some(ProgressFailure::ProjectionPanicked)
    );
    let projection_failed =
        terminal_projection || state.error.is_some() && (!projected || require_final);
    if require_final && state.finished && !projection_failed && completion.is_none() {
        completion = Some(observation.task.join().await);
    }
    {
        let mut original = target
            .fence
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        original.finished_observed |= state.finished;
        original.completion_observed |= completion.is_some();
    }
    if require_final && completion.is_none() {
        pending.push(ObservationPendingStep::Completion);
    }
    let ended_before_final_state =
        matches!(&completion, Some(Ok(()))) && (!projected || require_final && !state.finished);
    let history = if projected {
        let (fence, final_fence) = {
            let mut original = target
                .fence
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let fence = original
                .history
                .get_or_insert_with(|| HistoryFence {
                    channel: observation.state.channel.clone(),
                    through: state.handoff,
                })
                .clone();
            // A pending live synchronize may precede this drain. Keep that original prefix and
            // separately pin the one final-frame handoff before awaiting either history fence.
            if require_final && state.finished && original.final_history.is_none() {
                original.final_history = Some(HistoryFence {
                    channel: observation.state.channel.clone(),
                    through: state.handoff,
                });
            }
            (fence, original.final_history.clone())
        };
        let done = target
            .fence
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .history_done;
        let mut failure = if done {
            None
        } else {
            let may_wait = previous
                .and_then(|issue| issue.history.as_ref())
                .is_none_or(|failure| failure.can_resume(services));
            let result = if may_wait {
                fence.wait(&target.id).await.err()
            } else {
                previous.and_then(|issue| issue.history.clone())
            };
            if result.is_none() {
                target
                    .fence
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .history_done = true;
            }
            result
        };
        if failure.is_none()
            && let Some(final_fence) = final_fence
        {
            let done = target
                .fence
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .final_history_done;
            if !done {
                let may_wait = previous
                    .and_then(|issue| issue.history.as_ref())
                    .is_none_or(|failure| failure.can_resume(services));
                failure = if may_wait {
                    final_fence.wait(&target.id).await.err()
                } else {
                    previous.and_then(|issue| issue.history.clone())
                };
                if failure.is_none() {
                    target
                        .fence
                        .state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .final_history_done = true;
                }
            }
        }
        failure
    } else {
        pending.push(ObservationPendingStep::History);
        None
    };
    if history.is_some() {
        pending.push(ObservationPendingStep::History);
    }
    pending.push(ObservationPendingStep::WriteBehind);
    ObservationCloseIssue {
        thread_id: target.id.clone(),
        target: target.fence.target,
        progress: state,
        completion,
        progress_closed,
        ended_before_final_state,
        projection_failed,
        history,
        pending,
    }
}

impl ObservationCloseFailure {
    /// Pure eligibility over this failure's original owners, never a lookup by current Thread ID.
    pub(crate) fn can_resume_original(&self) -> bool {
        let services = &self.request.owner.0.projector;
        let write_ready = self.request.targets.iter().all(|target| {
            let state = target
                .fence
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.history_done && (state.final_history.is_none() || state.final_history_done)
        });
        self.request
            .targets
            .iter()
            .zip(&self.observations)
            .any(|(target, issue)| {
                let (
                    history_pending,
                    history_uncaptured,
                    write,
                    scopes,
                    finished_observed,
                    completion_observed,
                ) = {
                    let state = target
                        .fence
                        .state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    (
                        !state.history_done
                            || state.final_history.is_some() && !state.final_history_done,
                        state.history.is_none(),
                        state.write.clone(),
                        state.scope_issues.clone(),
                        state.finished_observed,
                        state.completion_observed,
                    )
                };
                let current = target.observation.state.progress.borrow().clone();
                let completion = target.observation.task.join().now_or_never();
                let panicked = matches!(
                    current.error.as_deref(),
                    Some(ProgressFailure::ProjectionPanicked)
                );
                let reached = current.initialized && current.applied >= target.fence.target;
                let require_final = self.request.kind != CloseKind::Synchronize
                    || target.fence.lifecycle == ThreadLifecycle::Closed;
                let needs_projection = !reached || require_final && !current.finished;
                let progress_ready = needs_projection
                    && issue.progress_closed.is_none()
                    && current.error.as_ref().is_some_and(|failure| {
                        can_retry_progress(services, &target.observation, failure)
                    });
                // A running original producer may already have left the captured retry point. A
                // newly failed point is only captured by this attempt, not automatically retried.
                let progressing = needs_projection
                    && issue.projection_failed
                    && current.error.is_none()
                    && issue.progress_closed.is_none()
                    && completion.is_none();
                progress_ready
                    || progressing
                    || reached
                        && history_pending
                        && (history_uncaptured
                            || issue
                                .history
                                .as_ref()
                                .is_none_or(|failure| failure.can_resume(services)))
                    || write
                        .as_ref()
                        .is_some_and(|write| write.can_resume() || write.is_pending())
                    || write.is_none() && write_ready
                    || !completion_observed && completion.is_some()
                    || !panicked
                        && issue.pending.contains(&ObservationPendingStep::FinalState)
                        && (current.finished && !finished_observed
                            || completion.is_none()
                                && current.error.is_none()
                                && target.observation.thread.snapshot().lifecycle
                                    == ThreadLifecycle::Closed)
                    || !panicked
                        && issue.pending.contains(&ObservationPendingStep::Completion)
                        && current.finished
                        && completion.is_none()
                    || scopes
                        .iter()
                        .any(|issue| issue.recovery != CleanupRecovery::Terminal)
            })
            || self
                .request
                .empty_write
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .as_ref()
                .is_some_and(|write| write.can_resume() || write.is_pending())
            || self
                .request
                .global_scopes
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .as_ref()
                .is_some_and(|issues| {
                    issues
                        .iter()
                        .any(|issue| issue.recovery != CleanupRecovery::Terminal)
                })
    }

    /// One caller-driven continuation of the retained request. Terminal facts remain present and
    /// only original eligible leaves advance; no worker, writer or source is reconstructed.
    pub(crate) async fn resume_original(&self) -> Result<(), Self> {
        if !self.can_resume_original() {
            return Err(self.clone());
        }
        self.request
            .owner
            .execute_close_request(self.request.clone(), Some(self))
            .await
    }
}
