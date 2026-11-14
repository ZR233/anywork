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
    #[cfg(test)]
    before_install: tokio::sync::Mutex<
        Option<(
            tokio::sync::oneshot::Sender<()>,
            tokio::sync::oneshot::Receiver<()>,
        )>,
    >,
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
            #[cfg(test)]
            before_install: tokio::sync::Mutex::new(None),
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
        self.reader.load_timeline_older(before, demand).await
    }
    pub async fn load_live_older(&self, before: &str, demand: ReadDemand) -> Result<TailSnapshot> {
        self.reader.load_live_older(before, demand).await
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
        #[cfg(test)]
        if let Some((entered, resume)) = self.before_install.lock().await.take() {
            let _ = entered.send(());
            let _ = resume.await;
        }
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
        initial: bool,
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
        let tokens = self.reader.presentation_tokens().await?;
        let mut delta = if initial {
            history(HistoryPlacement::Set, None, cut.published)
        } else {
            history(HistoryPlacement::Append, Some(cut.published), cut.published)
        };
        if initial && cut.published > 0 {
            delta.before = Some(tokens.before(cut.published, cut.published + 1)?);
        }
        let envelope = update(
            after,
            next,
            delta,
            TailUpdate::Replace {
                snapshot: empty.clone(),
            },
        );
        // cut_live budgets its own envelope; replace that reservation with the actual full response.
        let overhead = encoded_size(&envelope)?.saturating_sub(encoded_size(&empty)?);
        let max_bytes = (self.demand.max_bytes as usize)
            .checked_sub(overhead)
            .ok_or_else(invalid_demand)?;
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
                let tail = self.tail(&cut, after, next, true).await?;
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
                let tail_bytes = encoded_size(&response.tail)? - encoded_size(&TailUpdate::Keep)?;
                let mut bytes = 0;
                for head in heads.into_iter().rev() {
                    if response.history.blocks.len() + tail.blocks.len() == n {
                        break;
                    }
                    let before = (head.block_order > 1)
                        .then(|| tokens.before(cut.published, head.block_order))
                        .transpose()?;
                    let mut shell = update(
                        after,
                        next,
                        history(
                            response.history.placement,
                            response.history.from_order,
                            response.history.through_order,
                        ),
                        TailUpdate::Keep,
                    );
                    shell.history.before = before.clone();
                    let new_bytes = bytes
                        + encoded_size(&head)?
                        + usize::from(!response.history.blocks.is_empty());
                    if encoded_size(&shell)? + tail_bytes + new_bytes
                        > self.demand.max_bytes as usize
                    {
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
            if position.target.is_none()
                && let Some(source) = shared.current_progress()
            {
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
                        .capture_display(None, self.demand.max_items as usize, Some(u64::MAX), 0)
                        .await?;
                    let tail = self.tail(&cut, after, next, false).await?;
                    position.target = Some(Arc::new(tail));
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
                    let mut shell = update(
                        after,
                        next,
                        history(
                            response.history.placement,
                            response.history.from_order,
                            response.history.through_order,
                        ),
                        response.tail.clone(),
                    );
                    shell.history.before = response.history.before.clone();
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

    async fn single(h: &mut Harness, id: &str) -> Result<()> {
        let started = start(id, false);
        let visible = pl_core::model::ModelContentAvailableMember {
            turn_id: started.turn_id.clone(),
            attempt_id: started.attempt_id.clone(),
            generation: started.generation,
            identity: started.identity.clone(),
        };
        h.effect_phases(
            vec![started],
            vec![visible],
            vec![finish(id, false, "content")?],
            pl_core::thread::TurnState::Running,
        )
        .await?;
        Ok(())
    }

    #[tokio::test]
    async fn first_set_accounts_for_exact_envelope_at_decimal_boundaries_and_zero_history()
    -> Result<()> {
        let env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let mut h = Harness::new(&env).await?;
            for order in 1..=100 {
                single(&mut h, &format!("single-{order}")).await?;
                if [9, 10, 99, 100].contains(&order) {
                    exact_first_budget(&env, &h, false).await?;
                }
            }
            h.effect(vec![start("mandatory-current-work", true)], vec![])
                .await?;
            exact_first_budget(&env, &h, true).await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    async fn exact_first_budget(env: &Environment, h: &Harness, current_work: bool) -> Result<()> {
        let generous = env
            .runtime
            .open_timeline_reader(&h.thread.id, 6, 1, demand(1))
            .await?;
        let first = generous.next(generous.metadata().initial_cursor).await?;
        assert!(first.history.before.is_some());
        if current_work {
            assert!(first.history.blocks.is_empty());
            let TailUpdate::Replace { snapshot } = &first.tail else {
                anyhow::bail!("initial tail");
            };
            assert!(snapshot.current_work_id.is_some());
            assert_eq!(snapshot.blocks.len(), 1);
        }
        let bytes = encoded_size(&first)? as u32;
        generous.close().await?;
        let exact = ReadDemand {
            max_items: 1,
            max_bytes: bytes,
        };
        let reader = env
            .runtime
            .open_timeline_reader(&h.thread.id, 6, 1, exact)
            .await?;
        let after = reader.metadata().initial_cursor;
        let page = reader.next(after.clone()).await?;
        assert_eq!(encoded_size(&page)?, bytes as usize);
        assert_eq!(page, reader.next(after).await?);
        reader.close().await?;
        let small = env
            .runtime
            .open_timeline_reader(
                &h.thread.id,
                6,
                1,
                ReadDemand {
                    max_bytes: bytes - 1,
                    ..exact
                },
            )
            .await?;
        let after = small.metadata().initial_cursor;
        if current_work {
            assert!(small.next(after.clone()).await.is_err());
            assert!(small.state.lock().unwrap().pending.is_none());
            assert!(small.next(after).await.is_err());
        } else {
            let reduced = small.next(after.clone()).await?;
            assert!(reduced.history.blocks.is_empty());
            assert!(reduced.history.before.is_some());
            assert!(encoded_size(&reduced)? < bytes as usize);
            assert_eq!(reduced, small.next(after).await?);
        }
        small.close().await?;
        Ok(())
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
    #[tokio::test]
    async fn cancelled_candidate_keeps_initial_cut_and_status_reads_no_history() -> Result<()> {
        use super::super::conversation_feed::tests::state_activity;
        let env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let mut h = Harness::new(&env).await?;
            let mut thinking = state_activity::thinking(1)?;
            use pl_core::model::{ModelProgress, ObservedPart, ObservedPartIdentity, ProviderPartIdentity, ObservedItemKind, ObservedPartKind};
            thinking.model_progress.as_mut().unwrap().progress = ModelProgress::new(1, vec![ObservedPart::new(
                ObservedPartIdentity::Provider(ProviderPartIdentity { item_id: "summary".into(), output_index: None,
                    item_kind: ObservedItemKind::Reasoning, part: ObservedPartKind::SummaryText, content_index: 0 })
            ).appended("new title")]);
            state_activity::admit_thinking(&mut h, &thinking).await?;
            h.source.publish_test_conversation(&h.session, h.projection.current_state().context("started cut")?)?;
            let reader = Arc::new(env.runtime.open_timeline_reader(&h.thread.id, 6, 1, demand(1)).await?);
            let initial = reader.metadata().initial_cursor;
            let (entered, arrived) = tokio::sync::oneshot::channel();
            let (_resume, wait) = tokio::sync::oneshot::channel();
            *reader.before_install.lock().await = Some((entered, wait));
            let task_reader = reader.clone(); let after = initial.clone();
            let candidate = tokio::spawn(async move { task_reader.next(after).await });
            arrived.await?;
            candidate.abort(); assert!(candidate.await.unwrap_err().is_cancelled());
            assert!(reader.state.lock().unwrap().pending.is_none());
            let activity = state_activity::publish(&mut h, &thinking).await?.context("thinking activity")?;
            assert_eq!(activity.thinking_summary.as_deref(), Some("new title"));
            let first = reader.next(initial).await?;
            let TailUpdate::Replace { snapshot: tail } = first.tail else { anyhow::bail!("initial replacement"); };
            assert!(tail.blocks[0].thinking_summary.is_none(), "cancelled cut retains its captured Arc");
            let calls = h.history.reader_calls();
            let status = tokio::time::timeout(crate::runtime_test_support::integration_test_deadline()?, reader.next(first.next)).await??;
            assert_eq!(calls, h.history.reader_calls(), "summary does no SQL, COUNT or existence IO");
            assert!(status.history.blocks.is_empty());
            assert!(matches!(status.tail, TailUpdate::Status { base_layout_revision, thinking_summary: Some(ref text), .. }
                if base_layout_revision == tail.layout_revision && text == "new title"));
            reader.close().await?;
            Ok(())
        }.await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn continuous_writes_finish_fixed_target_before_new_layout_with_one_head_budget()
    -> Result<()> {
        let env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let mut h = Harness::new(&env).await?;
            h.effect(vec![start("old-work", true)], vec![]).await?;
            let reader = env
                .runtime
                .open_timeline_reader(&h.thread.id, 6, 1, demand(1))
                .await?;
            let first = reader.next(reader.metadata().initial_cursor).await?;
            single(&mut h, "single-1").await?;
            single(&mut h, "single-2").await?;
            single(&mut h, "single-3").await?;
            h.effect(vec![start("target-work", true)], vec![]).await?;
            let mut page = reader.next(first.next).await?;
            assert!(matches!(page.tail, TailUpdate::Keep));
            let old_target = reader
                .state
                .lock()
                .unwrap()
                .pending
                .as_ref()
                .unwrap()
                .position
                .target
                .as_ref()
                .unwrap()
                .clone();
            single(&mut h, "newer-single").await?;
            h.effect(vec![start("newer-work", true)], vec![]).await?;
            let mut orders = Vec::new();
            for _ in 0..6 {
                assert!(fits(&page, demand(1))?);
                orders.extend(page.history.blocks.iter().map(|b| b.block_order));
                assert!(page.history.through_order <= old_target.ready_frontier);
                if let TailUpdate::Replace { snapshot } = &page.tail {
                    assert_eq!(
                        snapshot,
                        old_target.as_ref(),
                        "final tail must be the original captured value"
                    );
                    break;
                }
                page = reader.next(page.next).await?;
            }
            assert_eq!(orders, vec![1, 2, 3, 4]);
            assert!(matches!(page.tail, TailUpdate::Replace { .. }));
            let newer = reader.next(page.next).await?;
            assert!(newer.history.through_order > old_target.ready_frontier);
            reader.close().await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }
}

#[cfg(test)]
mod scenarios;
