//! Cursor-driven presentation reads over the original conversation capability.
//! No producer, event queue, persistence acknowledgement or UI credit is involved.
use std::sync::{Arc, Mutex};

use anyhow::{Result, ensure};
use pl_core::chat::ChatError;
use pl_protocol::{
    DisplayBlockRef, DisplayMemberWindow, HistoryDelta, HistoryPlacement, OpenTimeline,
    PRESENTATION_VERSION, ReadDemand, TIMELINE_READER_PROTOCOL_VERSION, TailSnapshot, TailUpdate,
    TimelinePage, ViewCursor, ViewUpdate,
    studio::{StudioError, StudioErrorCode, StudioErrorReason},
};
use tokio_util::sync::CancellationToken;

use super::presentation_reader::{DisplayReadCut, encoded_size};
use super::{ConversationFeed, ConversationReader, DisplayMembers, StudioRuntime};

pub struct TimelineReader {
    reader: ConversationReader,
    shared: tokio::sync::Mutex<ConversationFeed>,
    next_gate: tokio::sync::Mutex<()>,
    close_gate: tokio::sync::Mutex<()>,
    state: Mutex<State>,
    initial: ViewCursor,
    initial_cut: Mutex<Option<Arc<DisplayReadCut>>>,
    demand: ReadDemand,
    cancel: CancellationToken,
}

#[derive(Clone, Default)]
struct Position {
    through: Option<u64>,
    target: Option<Arc<TailSnapshot>>,
    tail: Option<Arc<TailSnapshot>>,
}
struct Pending {
    update: Arc<ViewUpdate>,
    position: Position,
}
struct State {
    confirmed: ViewCursor,
    position: Position,
    pending: Option<Pending>,
}

fn cursor() -> ViewCursor {
    ViewCursor(uuid::Uuid::new_v4().to_string())
}
fn conflict(reason: StudioErrorReason, message: &str) -> anyhow::Error {
    StudioError::new(StudioErrorCode::Conflict, message, false)
        .with_reason(reason, serde_json::Value::Null)
        .into()
}
fn invalid_demand() -> anyhow::Error {
    ChatError::InvalidDemand(
        "timeline demand cannot fit the required view envelope and heads".into(),
    )
    .into()
}
fn update(
    after: &ViewCursor,
    next: &ViewCursor,
    history: HistoryDelta,
    tail: TailUpdate,
) -> ViewUpdate {
    ViewUpdate {
        presentation_version: PRESENTATION_VERSION,
        reader_protocol_version: TIMELINE_READER_PROTOCOL_VERSION,
        after: after.clone(),
        next: next.clone(),
        history,
        tail,
    }
}
fn history(placement: HistoryPlacement, from: Option<u64>, through: u64) -> HistoryDelta {
    HistoryDelta {
        placement,
        from_order: from,
        through_order: through,
        blocks: Vec::new(),
        before: None,
    }
}
fn fits(update: &ViewUpdate, demand: ReadDemand) -> Result<bool> {
    let count = update.history.blocks.len()
        + match &update.tail {
            TailUpdate::Replace { snapshot } => snapshot.blocks.len(),
            _ => 0,
        };
    Ok(count <= demand.max_items as usize && encoded_size(update)? <= demand.max_bytes as usize)
}

impl StudioRuntime {
    pub async fn open_timeline_reader(
        &self,
        thread_id: &str,
        presentation_version: u32,
        reader_protocol_version: u32,
        demand: ReadDemand,
    ) -> Result<TimelineReader> {
        pl_protocol::validate_timeline_versions(presentation_version, reader_protocol_version)?;
        demand.validate(1)?;
        // Registers observation before any display query, without executing the Thread.
        let shared = self
            .open_feed_resources(thread_id, pl_protocol::ChatScope::Main, demand, false)
            .await?;
        let initial = cursor();
        Ok(TimelineReader {
            reader: shared.reader().clone(),
            cancel: shared.cancellation_token(),
            shared: tokio::sync::Mutex::new(shared),
            next_gate: tokio::sync::Mutex::new(()),
            close_gate: tokio::sync::Mutex::new(()),
            state: Mutex::new(State {
                confirmed: initial.clone(),
                position: Position::default(),
                pending: None,
            }),
            initial,
            demand,
            initial_cut: Mutex::new(None),
        })
    }
}

impl TimelineReader {
    pub fn metadata(&self) -> OpenTimeline {
        OpenTimeline {
            reader_id: self.reader.subscription_id().to_owned(),
            presentation_version: PRESENTATION_VERSION,
            reader_protocol_version: TIMELINE_READER_PROTOCOL_VERSION,
            initial_cursor: self.initial.clone(),
        }
    }
    pub fn thread_id(&self) -> &str {
        self.reader.thread_id()
    }
    pub fn reader(&self) -> &ConversationReader {
        &self.reader
    }
    pub fn cancellation_token(&self) -> CancellationToken {
        self.cancel.clone()
    }
    pub fn request_close(&self) {
        self.cancel.cancel();
        self.reader.request_close();
    }
    pub async fn close(&self) -> Result<()> {
        self.request_close();
        let _close = self.close_gate.lock().await;
        // Cancellation wakes the generation wait. Query permits independently drain below.
        self.shared.lock().await.close().await?;
        self.reader.close().await?;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.pending = None;
        state.position = Position::default();
        Ok(())
    }
    pub async fn load_older(&self, before: &str, demand: ReadDemand) -> Result<TimelinePage> {
        let batch = self.reader.load_timeline_older(before, demand).await?;
        let database_id = self
            .reader
            .resources()
            .await?
            .as_ref()
            .and_then(|r| r.database_id.clone())
            .unwrap_or_default();
        let page = TimelinePage {
            presentation_version: PRESENTATION_VERSION,
            database_id,
            ceiling: batch.through_order,
            blocks: batch.blocks,
            before: batch.before,
        };
        ensure!(
            encoded_size(&page)? <= demand.max_bytes as usize,
            invalid_demand()
        );
        Ok(page)
    }
    pub async fn load_live_older(&self, before: &str, demand: ReadDemand) -> Result<TailSnapshot> {
        demand.validate(1)?;
        let first = self
            .reader
            .capture_display(None, 0, Some(u64::MAX), 0)
            .await?;
        let boundary = self
            .reader
            .live_display_boundary(before, first.layout_revision)
            .await?;
        let cut = self
            .reader
            .capture_display(Some(boundary), demand.max_items as usize, Some(u64::MAX), 0)
            .await?;
        ensure!(
            cut.layout_revision == first.layout_revision,
            ChatError::StaleContent
        );
        // Older pages carry the canonical identity as qualification only; it need not be in this page.
        let tokens = self.reader.presentation_tokens().await?;
        let live = self.reader.cut_live(&cut, demand, &tokens)?;
        let tail = TailSnapshot {
            revision: cut.revision,
            layout_revision: cut.layout_revision,
            ready_frontier: cut.published,
            execution_present: cut.execution_present,
            current_work_id: first.current_work_id,
            blocks: live.blocks,
            older: live.older,
        };
        ensure!(
            encoded_size(&tail)? <= demand.max_bytes as usize,
            invalid_demand()
        );
        self.reader.ensure()?;
        Ok(tail)
    }
    pub async fn open_members(
        &self,
        reference: DisplayBlockRef,
        window: DisplayMemberWindow,
        demand: ReadDemand,
    ) -> Result<DisplayMembers> {
        self.reader
            .open_display_members(reference, window, demand)
            .await
    }

    pub async fn next(&self, after: ViewCursor) -> Result<ViewUpdate> {
        let _next = self.next_gate.try_lock().map_err(|_| {
            conflict(
                StudioErrorReason::ConcurrentNext,
                "A timeline next is already in progress",
            )
        })?;
        self.reader.ensure()?;
        ensure!(!self.cancel.is_cancelled(), ChatError::Cancelled);
        let mut position = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(pending) = &state.pending {
                if after == pending.update.after {
                    return Ok((*pending.update).clone());
                }
                ensure!(
                    after == pending.update.next,
                    conflict(
                        StudioErrorReason::StaleViewCursor,
                        "Unknown or stale timeline cursor"
                    )
                );
                let pending = state.pending.take().expect("checked pending response");
                state.position = pending.position;
                state.confirmed = pending.update.next.clone();
            }
            ensure!(
                after == state.confirmed,
                conflict(
                    StudioErrorReason::StaleViewCursor,
                    "Unknown or stale timeline cursor"
                )
            );
            state.position.clone()
        };
        let next = cursor();
        let mut shared = self.shared.lock().await;
        let generated = tokio::select! { biased;
            _ = self.cancel.cancelled() => return Err(ChatError::Cancelled.into()),
            result = self.generate(&mut shared, &after, &next, &mut position) => result?,
        };
        self.reader.ensure()?;
        ensure!(!self.cancel.is_cancelled(), ChatError::Cancelled);
        // No await after installing. Dropping this Future cannot strand a partly advanced cursor.
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.pending = Some(Pending {
            update: Arc::new(generated.clone()),
            position,
        });
        self.initial_cut
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        Ok(generated)
    }

    async fn tail(
        &self,
        cut: &DisplayReadCut,
        after: &ViewCursor,
        next: &ViewCursor,
    ) -> Result<TailSnapshot> {
        let empty = TailSnapshot {
            revision: cut.revision,
            layout_revision: cut.layout_revision,
            ready_frontier: cut.published,
            execution_present: cut.execution_present,
            current_work_id: cut.current_work_id.clone(),
            blocks: Vec::new(),
            older: None,
        };
        let envelope = update(
            after,
            next,
            history(HistoryPlacement::Append, Some(cut.published), cut.published),
            TailUpdate::Replace {
                snapshot: empty.clone(),
            },
        );
        // cut_live budgets its own envelope; replace that reservation with the actual full response.
        let live_envelope = pl_protocol::LiveDisplayWindow {
            revision: cut.revision,
            ready_frontier: cut.published,
            execution_present: cut.execution_present,
            current_work_id: cut.current_work_id.clone(),
            blocks: Vec::new(),
            older: None,
        };
        let overhead = encoded_size(&envelope)?.saturating_sub(encoded_size(&live_envelope)?);
        let max_bytes = (self.demand.max_bytes as usize)
            .checked_sub(overhead)
            .ok_or_else(invalid_demand)?;
        let tokens = self.reader.presentation_tokens().await?;
        let live = self.reader.cut_live(
            cut,
            ReadDemand {
                max_bytes: max_bytes as u32,
                ..self.demand
            },
            &tokens,
        )?;
        Ok(TailSnapshot {
            blocks: live.blocks,
            older: live.older,
            ..empty
        })
    }

    async fn generate(
        &self,
        shared: &mut ConversationFeed,
        after: &ViewCursor,
        next: &ViewCursor,
        position: &mut Position,
    ) -> Result<ViewUpdate> {
        loop {
            self.reader.ensure()?;
            if position.through.is_none() {
                let n = self.demand.max_items as usize;
                let captured = self
                    .initial_cut
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .clone();
                let cut = match captured {
                    Some(cut) => cut,
                    None => {
                        let cut = Arc::new(self.reader.capture_display(None, n, None, n).await?);
                        *self
                            .initial_cut
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(cut.clone());
                        cut
                    }
                };
                self.reader.bind_presentation_ceiling(cut.published)?;
                let tail = self.tail(&cut, after, next).await?;
                let mut response = update(
                    after,
                    next,
                    history(HistoryPlacement::Set, None, cut.published),
                    TailUpdate::Replace {
                        snapshot: tail.clone(),
                    },
                );
                let tokens = self.reader.presentation_tokens().await?;
                let heads = self
                    .reader
                    .history_heads(&cut, cut.published, None, n)
                    .await?;
                response.history.before = (cut.published > 0)
                    .then(|| tokens.before(cut.published, cut.published + 1))
                    .transpose()?;
                ensure!(fits(&response, self.demand)?, invalid_demand());
                let mut bytes = 0;
                for head in heads.into_iter().rev() {
                    if response.history.blocks.len() + tail.blocks.len() == n {
                        break;
                    }
                    let before = (head.block_order > 1)
                        .then(|| tokens.before(cut.published, head.block_order))
                        .transpose()?;
                    let mut shell = response.clone();
                    shell.history.blocks.clear();
                    shell.history.before = before.clone();
                    let new_bytes = bytes
                        + encoded_size(&head)?
                        + usize::from(!response.history.blocks.is_empty());
                    if encoded_size(&shell)? + new_bytes > self.demand.max_bytes as usize {
                        break;
                    }
                    bytes = new_bytes;
                    response.history.blocks.push(head);
                    response.history.before = before;
                }
                response.history.blocks.reverse();
                ensure!(fits(&response, self.demand)?, invalid_demand());
                position.through = Some(cut.published);
                position.tail = Some(Arc::new(tail));
                return Ok(response);
            }
            let through = position.through.expect("initialized history position");
            if position.target.is_none() {
                if let Some(source) = shared.current_progress() {
                    let (revision, layout, frontier, work, summary) = source
                        .presentation
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .view_status();
                    let execution_present = source.current.projection().execution_present;
                    drop(source);
                    if let Some(previous) = &position.tail
                        && previous.layout_revision == layout
                        && previous.ready_frontier == frontier
                        && previous.execution_present == execution_present
                        && previous.current_work_id == work
                    {
                        if previous.revision != revision {
                            let response = update(
                                after,
                                next,
                                history(HistoryPlacement::Append, Some(through), through),
                                TailUpdate::Status {
                                    base_layout_revision: layout,
                                    revision,
                                    current_work_id: work,
                                    thinking_summary: summary.clone(),
                                },
                            );
                            ensure!(fits(&response, self.demand)?, invalid_demand());
                            let mut tail = (**previous).clone();
                            tail.revision = revision;
                            if let Some(block) = tail
                                .blocks
                                .iter_mut()
                                .find(|b| Some(&b.id) == tail.current_work_id.as_ref())
                            {
                                block.thinking_summary = summary;
                            }
                            position.tail = Some(Arc::new(tail));
                            return Ok(response);
                        }
                    } else {
                        let cut = self
                            .reader
                            .capture_display(
                                None,
                                self.demand.max_items as usize,
                                Some(u64::MAX),
                                0,
                            )
                            .await?;
                        let tail = self.tail(&cut, after, next).await?;
                        position.target = Some(Arc::new(tail));
                    }
                }
            }
            if let Some(target) = position.target.clone() {
                ensure!(
                    target.ready_frontier >= through,
                    super::conversation_reader::resync()
                );
                let heads = if through < target.ready_frontier {
                    self.reader
                        .timeline_append_heads(through, target.ready_frontier, self.demand)
                        .await?
                } else {
                    Vec::new()
                };
                let exhausted = heads.len() < self.demand.max_items as usize;
                let total = heads.len();
                let mut response = update(
                    after,
                    next,
                    history(HistoryPlacement::Append, Some(through), through),
                    TailUpdate::Keep,
                );
                let mut bytes = 0;
                for head in heads {
                    let mut shell = response.clone();
                    shell.history.blocks.clear();
                    shell.history.through_order = head.block_order;
                    let new_bytes = bytes
                        + encoded_size(&head)?
                        + usize::from(!response.history.blocks.is_empty());
                    if encoded_size(&shell)? + new_bytes > self.demand.max_bytes as usize {
                        break;
                    }
                    bytes = new_bytes;
                    response.history.through_order = head.block_order;
                    response.history.blocks.push(head);
                }
                ensure!(
                    total == 0 || !response.history.blocks.is_empty(),
                    invalid_demand()
                );
                if exhausted && response.history.blocks.len() == total {
                    response.history.through_order = target.ready_frontier;
                }
                if response.history.through_order == target.ready_frontier {
                    response.tail = TailUpdate::Replace {
                        snapshot: (*target).clone(),
                    };
                    if fits(&response, self.demand)? {
                        position.tail = Some(target);
                        position.target = None;
                    } else {
                        response.tail = TailUpdate::Keep;
                    }
                }
                ensure!(fits(&response, self.demand)?, invalid_demand());
                position.through = Some(response.history.through_order);
                return Ok(response);
            }
            shared.wait_change().await?;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime_test_support::Environment;
    use crate::studio::runtime::conversation_feed::tests::completed_runs::{
        Harness, finish, start,
    };
    use anyhow::Context;
    use futures::poll;
    use std::task::Poll;

    fn demand(items: u32) -> ReadDemand {
        ReadDemand {
            max_items: items,
            max_bytes: 16 * 1024,
        }
    }
    fn reason(error: &anyhow::Error) -> Option<&str> {
        error
            .downcast_ref::<StudioError>()
            .and_then(StudioError::reason)
    }

    #[tokio::test]
    async fn retry_confirms_only_next_cursor_and_close_wakes_its_reader() -> Result<()> {
        let env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = env
                .runtime
                .create_thread(&env.project.id, "pull reader")
                .await?;
            assert!(
                env.runtime
                    .open_timeline_reader(&thread.id, 5, 1, demand(2))
                    .await
                    .is_err()
            );
            let reader = env
                .runtime
                .open_timeline_reader(&thread.id, 6, 1, demand(2))
                .await?;
            let initial = reader.metadata();
            let first = reader.next(initial.initial_cursor.clone()).await?;
            assert_eq!(first, reader.next(initial.initial_cursor.clone()).await?);
            assert_eq!(first.history.placement, HistoryPlacement::Set);
            assert_eq!(
                reason(&reader.next(cursor()).await.unwrap_err()),
                Some("staleViewCursor")
            );
            {
                let waiting = reader.next(first.next.clone());
                tokio::pin!(waiting);
                assert!(matches!(poll!(&mut waiting), Poll::Pending));
                assert_eq!(
                    reason(&reader.next(first.next.clone()).await.unwrap_err()),
                    Some("concurrentNext")
                );
                reader.reader().read_business_refs().await?;
                reader.request_close();
                assert!(waiting.await.is_err());
            }
            reader.close().await?;
            assert!(reader.next(first.next).await.is_err());
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn cancellation_after_confirm_keeps_progress_and_fixed_target() -> Result<()> {
        let env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let mut h = Harness::new(&env).await?;
            h.effect(vec![start("work", true)], vec![]).await?;
            let reader = env
                .runtime
                .open_timeline_reader(&h.thread.id, 6, 1, demand(1))
                .await?;
            let first = reader.next(reader.metadata().initial_cursor).await?;
            let TailUpdate::Replace { snapshot } = &first.tail else {
                anyhow::bail!("initial tail");
            };
            let original = snapshot.current_work_id.clone().context("open work")?;
            {
                let waiting = reader.next(first.next.clone());
                tokio::pin!(waiting);
                assert!(matches!(poll!(&mut waiting), Poll::Pending));
                // Dropping the unproduced read must keep first.next as the confirmed cursor.
            }
            assert_eq!(
                reason(&reader.next(first.after.clone()).await.unwrap_err()),
                Some("staleViewCursor")
            );
            h.effect(vec![], vec![finish("work", true, "done")?])
                .await?;
            let second = reader.next(first.next.clone()).await?;
            assert_eq!(second.history.from_order, Some(first.history.through_order));
            assert_eq!(second, reader.next(first.next).await?);
            let TailUpdate::Replace { snapshot } = second.tail else {
                anyhow::bail!("member completion changes layout");
            };
            assert_eq!(snapshot.current_work_id.as_deref(), Some(original.as_str()));
            reader.close().await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }
}
