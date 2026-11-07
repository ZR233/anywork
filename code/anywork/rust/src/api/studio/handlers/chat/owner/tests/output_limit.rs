//! A paced single-item output proves the production FRB producer, facade content mapping and
//! credit ACKs keep consuming one 256000-byte body while its original Turn and execution run.
use std::{collections::HashSet, time::Duration};

use anyhow::{Context, Result, ensure};
use pl_protocol::{AgentExecutionPhase, ThreadSnapshot, TurnState};
use pl_provider_fixture::{GUI_STREAMING_OUTPUT_REFERENCE_TOKENS, gui_streaming_output_reply};
use pl_studio_runtime::StudioRuntime;

use super::*;
use crate::api::studio::types::{
    BridgeChatEntry, BridgeChatPlacement, BridgeContentOwner, BridgeContentRange, BridgeContentRef,
    BridgeContentTarget, BridgeContentWindow, BridgeCurrentContentRole, BridgeCurrentProjection,
    BridgeThreadNotification, BridgeThreadSubscriptionUpdate, BridgeTurnState,
};

/// `gui_streaming_output_reply(1, 1)` streams one item of 128000 reference tokens as " a" pairs.
const BODY_BYTES: u64 = (GUI_STREAMING_OUTPUT_REFERENCE_TOKENS * 2) as u64;
const WINDOW_MAX: u32 = 64 * 1024;

#[derive(Clone, Debug)]
struct LiveBodyTarget {
    reference: BridgeContentRef,
    preview_id: String,
    display_id: String,
    turn_id: String,
}

impl LiveBodyTarget {
    fn same_identity(&self, other: &LiveBodyTarget) -> bool {
        self.preview_id == other.preview_id
            && self.reference == other.reference
            && self.display_id == other.display_id
            && self.turn_id == other.turn_id
    }
}

fn live_body_target(current: &BridgeCurrentProjection) -> Result<Option<LiveBodyTarget>> {
    let Some(turn) = &current.active_turn else {
        return Ok(None);
    };
    let Some(preview) = current.previews.iter().find(|preview| {
        preview.role == BridgeCurrentContentRole::Response && !preview.text.is_empty()
    }) else {
        return Ok(None);
    };
    ensure!(matches!(
        &preview.reference.target,
        BridgeContentTarget::Body {
            owner: BridgeContentOwner::Item { .. },
            ..
        }
    ));
    let item = current
        .items
        .iter()
        .find(|item| {
            item.contents
                .iter()
                .any(|content| content.reference == preview.reference)
        })
        .context("live response omitted its original Timeline item")?;
    Ok(Some(LiveBodyTarget {
        reference: preview.reference.clone(),
        preview_id: preview.id.clone(),
        display_id: item.id.clone(),
        turn_id: turn.id.clone(),
    }))
}

async fn next_frame(
    owner: &ConversationOwner,
    port: &mut mpsc::Receiver<BridgeConversationFrame>,
    sent: &mut u64,
) -> Result<BridgeConversationFrame> {
    let frame = receive(port).await?;
    ensure!(frame.thread_id == owner.thread_id);
    ensure!(frame.subscription_id == owner.subscription_id);
    if matches!(
        frame.event,
        BridgeConversationEvent::Failure { .. } | BridgeConversationEvent::Closed
    ) {
        ensure!(
            frame.delivery_sequence == *sent,
            "terminal changed the last sent prefix: expected {}, got {}; event={:?}",
            *sent,
            frame.delivery_sequence,
            frame.event
        );
        anyhow::bail!("Main ended before observation completed: {:?}", frame.event);
    }
    ensure!(
        frame.delivery_sequence == *sent + 1,
        "duplicated or skipped sent prefix: expected {}, got {}",
        *sent + 1,
        frame.delivery_sequence
    );
    *sent = frame.delivery_sequence;
    Ok(frame)
}

fn inspect_state(
    update: &BridgeThreadSubscriptionUpdate,
    terminal: &mut Option<String>,
) -> Result<()> {
    let BridgeThreadSubscriptionUpdate::Notification { notification } = update else {
        return Ok(());
    };
    match &notification.notification {
        BridgeThreadNotification::TurnCompleted { turn } => {
            // Only the followup Turn is tracked; the subscription may still replay the
            // initial Turn's historical completion notification.
            if turn.input_id.as_deref() == Some("input-bridge-live") {
                ensure!(
                    matches!(turn.state, BridgeTurnState::Completed { .. }),
                    "real output Turn failed: {:?}",
                    turn.state
                );
                ensure!(
                    terminal.replace(turn.id.clone()).is_none(),
                    "duplicate typed terminal for Turn {}",
                    turn.id
                );
            }
        }
        BridgeThreadNotification::Lagged { dropped } => {
            anyhow::bail!("Main subscription lagged and dropped {dropped} notifications");
        }
        _ => {}
    }
    Ok(())
}

fn running_execution<'a>(snapshot: &'a ThreadSnapshot, turn_id: &str) -> Option<&'a str> {
    let turn = snapshot.active_turn.as_ref()?;
    if turn.id != turn_id || !matches!(turn.state, TurnState::Running(_)) {
        return None;
    }
    let execution = snapshot.runtime.as_ref()?.execution.as_ref()?;
    (execution.phase() == AgentExecutionPhase::Running && execution.turn_id() == Some(turn_id))
        .then_some(execution.id())
}

async fn next_window(
    facade: &BridgeConversationFeed,
    watch: &str,
    stage: &str,
) -> Result<Option<BridgeContentWindow>> {
    tokio::time::timeout(
        Duration::from_secs(5),
        facade.next_content_window(watch.to_owned()),
    )
    .await
    .map_err(|error| {
        anyhow::anyhow!("{stage}: next_content_window timeout; watch={watch}: {error:?}")
    })?
    .map_err(|error| anyhow::anyhow!("{stage}: next_content_window; watch={watch}: {error:?}"))
}

#[derive(Debug)]
struct LiveBodyConsumption {
    target: LiveBodyTarget,
    execution_id: String,
    generation: String,
    bytes: u64,
    windows: usize,
    live_reads: usize,
    live_bytes: u64,
    peak_window: usize,
    peak_suffix: usize,
}

async fn consume_live_body(
    runtime: &StudioRuntime,
    thread_id: &str,
    facade: &BridgeConversationFeed,
    target: LiveBodyTarget,
) -> Result<LiveBodyConsumption> {
    let first = runtime.thread_snapshot(thread_id).await?;
    let execution_id = running_execution(&first, &target.turn_id)
        .context("first live body arrived after its original execution ended")?
        .to_owned();
    let watch = facade
        .open_content_watch(
            target.reference.clone(),
            BridgeContentRange {
                offset: 0,
                max_bytes: WINDOW_MAX,
            },
        )
        .await
        .map_err(|error| {
            anyhow::anyhow!("watch.open: reference={:?}: {error:?}", target.reference)
        })?;
    let result = async {
        let mut cursor = 0;
        let mut available = 0;
        let mut generation = None;
        let mut windows = 0;
        let mut live_reads = 0;
        let mut live_bytes = 0;
        let mut peak_window = 0;
        let mut peak_suffix = 0;
        loop {
            // Fresh hot snapshots bracket the actual read. A pending Main notification alone
            // cannot prove that the original Turn/execution was still running.
            let before = runtime.thread_snapshot(thread_id).await?;
            let window = next_window(facade, &watch, "consume.next")
                .await
                .with_context(|| {
                    format!(
                        "live body before next window: cursor={cursor}; available={available}; \
                         generation={generation:?}; windows={windows}"
                    )
                })?
                .context("content watch ended before a sealed body")?;
            ensure!(window.offset == 0 && window.bytes.len() as u32 <= WINDOW_MAX);
            ensure!(window.bytes.len() as u64 <= window.available_through);
            ensure!(
                window.available_through >= available && window.available_through <= BODY_BYTES,
                "window available_through {} regressed past {available} or exceeded {BODY_BYTES}",
                window.available_through
            );
            ensure!(
                generation
                    .as_ref()
                    .is_none_or(|value| value == &window.generation),
                "append-only body changed generation mid-stream"
            );
            generation = Some(window.generation.clone());
            available = window.available_through;
            let sealed = window.sealed;
            let previous = cursor;
            peak_window = peak_window.max(window.bytes.len());
            let (parts, remainder) = window.bytes.as_chunks::<2>();
            ensure!(remainder.is_empty() && parts.iter().all(|part| part == b" a"));
            if cursor < window.bytes.len() as u64 {
                cursor = window.bytes.len() as u64;
            }
            // Retain only the cursor/generation; windows are pull-consumed, no second body queue.
            drop(window);
            while cursor < available {
                let request = (available - cursor).min(WINDOW_MAX as u64);
                let suffix = facade
                    .read_content(
                        target.reference.clone(),
                        BridgeContentRange {
                            offset: cursor,
                            max_bytes: request as u32,
                        },
                    )
                    .await
                    .map_err(|error| anyhow::anyhow!("suffix.read offset={cursor}: {error:?}"))?;
                ensure!(suffix.offset == cursor && !suffix.bytes.is_empty());
                ensure!(
                    suffix.bytes.len() as u64 <= request && request <= WINDOW_MAX as u64,
                    "suffix read returned {} bytes over the bounded request {request}",
                    suffix.bytes.len()
                );
                ensure!(suffix.bytes.len() as u64 <= available - cursor);
                ensure!(suffix.available_through >= available && suffix.available_through <= BODY_BYTES);
                ensure!(generation.as_ref() == Some(&suffix.generation));
                let (parts, remainder) = suffix.bytes.as_chunks::<2>();
                ensure!(remainder.is_empty() && parts.iter().all(|part| part == b" a"));
                peak_suffix = peak_suffix.max(suffix.bytes.len());
                cursor += suffix.bytes.len() as u64;
            }
            let after = runtime.thread_snapshot(thread_id).await?;
            windows += 1;
            if cursor > previous
                && running_execution(&before, &target.turn_id) == Some(execution_id.as_str())
                && running_execution(&after, &target.turn_id) == Some(execution_id.as_str())
            {
                live_reads += 1;
                live_bytes += cursor - previous;
            }
            if sealed {
                ensure!(
                    cursor == BODY_BYTES,
                    "continuous reader did not consume the complete body: {cursor}/{BODY_BYTES}"
                );
                let end = facade
                    .read_content(
                        target.reference.clone(),
                        BridgeContentRange {
                            offset: cursor,
                            max_bytes: 1,
                        },
                    )
                    .await?;
                ensure!(end.offset == cursor && end.bytes.is_empty() && end.sealed);
                ensure!(end.available_through == BODY_BYTES && generation.as_ref() == Some(&end.generation));
                ensure!(
                    live_reads >= 2 && live_bytes > 0,
                    "no repeated original-running body reads: windows={windows}, live_reads={live_reads}, live_bytes={live_bytes}"
                );
                ensure!(
                    next_window(facade, &watch, "consume.terminal")
                        .await?
                        .is_none(),
                    "watch delivered another window after its sealed EOF"
                );
                break;
            }
        }
        Ok(LiveBodyConsumption {
            execution_id,
            generation: generation.context("sealed body lacked a generation")?,
            target,
            bytes: cursor,
            windows,
            live_reads,
            live_bytes,
            peak_window,
            peak_suffix,
        })
    }
    .await;
    let closed = facade.close_content_watch(watch).await;
    let result = result.with_context(|| format!("live content-watch cleanup: {closed:?}"))?;
    closed?;
    Ok(result)
}

#[tokio::test]
async fn output_limit_single_item_streams_body_while_original_turn_runs() -> Result<()> {
    // This current-thread runtime keeps the scoped subscriber on the producer's execution
    // thread too, preserving the original continuity failure without changing global logging.
    let _tracing = tracing::subscriber::set_default(
        tracing_subscriber::fmt()
            .with_env_filter("conversation_continuity=debug")
            .with_test_writer()
            .with_ansi(false)
            .without_time()
            .finish(),
    );
    let env =
        Environment::with_output_limit_followup(Some(gui_streaming_output_reply(1, 1))).await?;
    // The real owner and facade stay strongly referenced outside the bounded observation so
    // success, failure and timeout exits all await the same close instead of async Drop.
    let feed = match env.feed().await {
        Ok(feed) => feed,
        Err(error) => return env.finish(Err(error)).await,
    };
    let owner = managed(feed);
    let facade = BridgeConversationFeed {
        inner: Arc::clone(&owner),
    };
    let mut port = start_port(&owner).await;
    let mut sent = 0;
    let observation = tokio::time::timeout(Duration::from_secs(120), async {
        // Reliable Main first: the initial real Set must arrive before the followup is submitted.
        let mut ignored_terminal = None;
        let initial = loop {
            let frame = next_frame(&owner, &mut port, &mut sent).await?;
            match frame.event {
                BridgeConversationEvent::State { update } => {
                    inspect_state(&update, &mut ignored_terminal)?;
                    owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                }
                BridgeConversationEvent::Chat { batch } => {
                    ensure!(batch.placement == BridgeChatPlacement::Set);
                    ensure!(batch.current.is_some());
                    break *batch;
                }
                event => anyhow::bail!("unexpected initial event: {event:?}"),
            }
        };
        let mut item_ids = HashSet::new();
        let mut last_position = None;
        for entry in &initial.entries {
            let BridgeChatEntry::Item(item) = entry else {
                anyhow::bail!("initial Main delivered a raw member instead of an item");
            };
            ensure!(item_ids.insert(item.id.clone()), "initial Main repeated item");
            let position = item.position.context("initial item lacked its position")?;
            ensure!(
                last_position.is_none_or(|last| position > last),
                "initial Main changed item order"
            );
            last_position = Some(position);
        }
        owner.acknowledge(&owner.subscription_id, sent)?;
        env.submit_followup().await?;

        // One oneshot identity handoff; body IO never queues on the reliable Main port.
        let (offer, received) = oneshot::channel::<LiveBodyTarget>();
        let mut offer = Some(offer);
        let runtime = &env.runtime;
        let thread_id = env.thread_id.clone();
        let consume = async {
            let target = received
                .await
                .context("Main never published an original live body")?;
            consume_live_body(runtime, &thread_id, &facade, target).await
        };
        let observe = async {
            let result = async {
                let mut terminal = None;
                let mut retired = false;
                let mut handed_off: Option<LiveBodyTarget> = None;
                let mut appended: Vec<(String, Option<String>)> = Vec::new();
                while terminal.is_none() || !retired {
                    let frame = next_frame(&owner, &mut port, &mut sent).await?;
                    match frame.event {
                        BridgeConversationEvent::State { update } => {
                            inspect_state(&update, &mut terminal)?;
                            owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                        }
                        BridgeConversationEvent::Chat { batch } => {
                            let batch = *batch;
                            ensure!(
                                batch.placement == BridgeChatPlacement::Append
                                    && batch.before.is_none()
                            );
                            ensure!(
                                batch.entries.len() <= 1,
                                "append exceeded the original Main demand"
                            );
                            for entry in batch.entries {
                                let BridgeChatEntry::Item(item) = entry else {
                                    anyhow::bail!("Main appended a raw member instead of an item");
                                };
                                ensure!(
                                    item_ids.insert(item.id.clone()),
                                    "Main repeated item {}",
                                    item.id
                                );
                                let position = item
                                    .position
                                    .context("appended item lacked its position")?;
                                let last = last_position
                                    .context("no baseline position after the initial Set")?;
                                ensure!(
                                    position > last,
                                    "Main Append changed item order: {position} after {last}"
                                );
                                last_position = Some(position);
                                appended.push((item.id, item.content_item_id));
                            }
                            if let Some(current) = &batch.current {
                                if let Some(target) = live_body_target(current)? {
                                    if let Some(previous) = &handed_off {
                                        ensure!(
                                            previous.same_identity(&target),
                                            "live body identity changed mid-stream: {previous:?} -> {target:?}"
                                        );
                                    } else {
                                        let delivered = offer
                                            .take()
                                            .context("body handoff offered twice")?;
                                        delivered
                                            .send(target.clone())
                                            .map_err(|_| anyhow::anyhow!("body consumer closed before its target"))?;
                                        handed_off = Some(target);
                                    }
                                }
                                // Track the latest genuine retirement: only a post-handoff
                                // current with no activity, no active Turn and no residual
                                // items retires the original stream. A stale pre-submit idle
                                // projection, a stopping Turn or the typed terminal alone
                                // never counts, and a later live sighting resets it.
                                retired = handed_off.is_some()
                                    && current.active.is_none()
                                    && current.active_turn.is_none()
                                    && current.items.is_empty();
                            }
                            owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                        }
                        event => anyhow::bail!("unexpected live event: {event:?}"),
                    }
                }
                Ok((
                    terminal.context("typed terminal vanished")?,
                    handed_off.context("Main retired without a live body target")?,
                    appended,
                ))
            }
            .await;
            drop(offer);
            result
        };
        // The one-time identity transfer is synchronous; both owners stay joined on any failure.
        let (main, body) = tokio::join!(observe, consume);
        let (terminal_turn, target, appended) =
            main.with_context(|| format!("continuous body result: {body:?}"))?;
        let body = body?;
        ensure!(body.bytes == BODY_BYTES);
        ensure!(
            body.target.turn_id == terminal_turn,
            "typed terminal Turn {terminal_turn} differs from the streamed Turn {}",
            body.target.turn_id
        );
        ensure!(
            body.target.same_identity(&target),
            "Main's live identity drifted from the consumed body"
        );
        let matching = appended
            .iter()
            .filter(|(id, _)| id == &body.target.display_id)
            .count();
        ensure!(
            matching == 1,
            "completed Main did not carry the live display item {} exactly once: {appended:?}",
            body.target.display_id
        );
        let mut carrying = 0;
        let mut carrier = None;
        for (id, content_item_id) in &appended {
            let Some(item_id) = content_item_id.as_deref() else {
                continue;
            };
            let manifest = facade
                .list_contents(
                    item_id.to_owned(),
                    None,
                    BridgeReadDemand {
                        max_items: 2,
                        max_bytes: WINDOW_MAX,
                    },
                )
                .await
                .map_err(|error| {
                    anyhow::anyhow!("completion.list_contents item_id={item_id}: {error:?}")
                })?;
            if manifest
                .entries
                .iter()
                .any(|entry| entry.reference == body.target.reference)
            {
                carrying += 1;
                carrier = Some(id.clone());
            }
        }
        ensure!(
            carrying == 1,
            "expected one completed manifest carrying the original reference, saw {carrying}"
        );
        ensure!(
            carrier.as_deref() == Some(body.target.display_id.as_str()),
            "completed manifest owner {carrier:?} differs from the live display id {}",
            body.target.display_id
        );
        // The sealed body is re-readable in bounded windows through the original lease; these
        // post-seal reads stay separate from the original-running byte statistics above.
        let mut sealed_cursor = 0;
        let mut sealed_generation = None;
        while sealed_cursor < BODY_BYTES {
            let request = (BODY_BYTES - sealed_cursor).min(WINDOW_MAX as u64);
            let window = facade
                .read_content(
                    body.target.reference.clone(),
                    BridgeContentRange {
                        offset: sealed_cursor,
                        max_bytes: request as u32,
                    },
                )
                .await
                .map_err(|error| anyhow::anyhow!("sealed.read offset={sealed_cursor}: {error:?}"))?;
            ensure!(
                window.sealed
                    && window.offset == sealed_cursor
                    && !window.bytes.is_empty()
                    && window.available_through == BODY_BYTES
            );
            ensure!(
                window.bytes.len() as u64 <= request && request <= WINDOW_MAX as u64,
                "sealed read returned {} bytes over the bounded request {request}",
                window.bytes.len()
            );
            ensure!(sealed_generation
                .as_ref()
                .is_none_or(|value| value == &window.generation));
            sealed_generation = Some(window.generation.clone());
            let (parts, remainder) = window.bytes.as_chunks::<2>();
            ensure!(remainder.is_empty() && parts.iter().all(|part| part == b" a"));
            sealed_cursor += window.bytes.len() as u64;
        }
        ensure!(sealed_cursor == BODY_BYTES);
        ensure!(sealed_generation.as_ref() == Some(&body.generation));
        Ok((terminal_turn, item_ids, body))
    })
    .await;
    // Every frame received before close was acknowledged synchronously; the close takes ACK
    // precedence, so already-published trailing frames cannot be acknowledged afterwards.
    let acknowledged_prefix = sent;
    let close = facade.close().await;
    let settled = owner.is_settled();
    let native_closed = owner.native.lock().await.is_none();
    let producer_joined = owner.producer.lock().await.task.is_none();
    let tail = async {
        let observation = match observation {
            Ok(result) => result,
            Err(elapsed) => Err(anyhow::anyhow!(
                "paced single-item bridge consumer exceeded its observation budget: {elapsed:?}"
            )),
        };
        let (terminal_turn, mut item_ids, body) = observation.with_context(|| {
            format!(
                "conversation cleanup: close={close:?}; settled={settled}; \
                 native_closed={native_closed}; producer_joined={producer_joined}"
            )
        })?;
        close?;
        ensure!(settled, "conversation owner did not settle after close");
        ensure!(
            native_closed,
            "native conversation feed stayed open after close"
        );
        ensure!(producer_joined, "producer task was not joined by close");
        // Closing takes ACK precedence, so already-published trailing frames are validated
        // but not acknowledged.
        let terminal = loop {
            let frame = receive(&mut port).await?;
            ensure!(frame.thread_id == owner.thread_id);
            ensure!(frame.subscription_id == owner.subscription_id);
            if matches!(
                frame.event,
                BridgeConversationEvent::Failure { .. } | BridgeConversationEvent::Closed
            ) {
                // The producer terminal reuses the last published sequence by design.
                ensure!(frame.delivery_sequence == sent);
                ensure!(
                    matches!(frame.event, BridgeConversationEvent::Closed),
                    "Main failed during close: {:?}",
                    frame.event
                );
                break frame;
            }
            ensure!(
                frame.delivery_sequence == sent + 1,
                "duplicated or skipped trailing prefix: expected {}, got {}",
                sent + 1,
                frame.delivery_sequence
            );
            sent = frame.delivery_sequence;
            match frame.event {
                BridgeConversationEvent::State { update } => {
                    let mut trailing = None;
                    inspect_state(&update, &mut trailing)?;
                    ensure!(
                        trailing.is_none_or(|turn| turn == terminal_turn),
                        "another Turn completed after the streamed terminal"
                    );
                }
                BridgeConversationEvent::Chat { batch } => {
                    ensure!(
                        batch.placement == BridgeChatPlacement::Append && batch.before.is_none()
                    );
                    for entry in batch.entries {
                        let BridgeChatEntry::Item(item) = entry else {
                            continue;
                        };
                        ensure!(
                            item_ids.insert(item.id.clone()),
                            "trailing Main repeated item {}",
                            item.id
                        );
                    }
                }
                event => anyhow::bail!("unexpected trailing event: {event:?}"),
            }
        };
        ensure!(
            port.recv().await.is_none(),
            "terminal must be attempted only once"
        );
        {
            let state = owner.state.lock().unwrap();
            ensure!(
                terminal.delivery_sequence == state.sent && state.sent == sent,
                "terminal sequence {} differs from published {} or drained {sent}",
                terminal.delivery_sequence,
                state.sent
            );
            ensure!(
                state.acknowledged == acknowledged_prefix,
                "real ACK watermark {} diverged from the acknowledged prefix {acknowledged_prefix}",
                state.acknowledged
            );
            eprintln!(
                "delivery credit: acknowledged={}, published={}, drained={}",
                state.acknowledged, state.sent, sent
            );
        }
        eprintln!(
            "continuous bridge body: execution={}, turn={}, display={}, bytes={}, windows={}, \
             original_running_reads={}, original_running_bytes={}, peak_window_bytes={}, \
             peak_suffix_bytes={}",
            body.execution_id,
            terminal_turn,
            body.target.display_id,
            body.bytes,
            body.windows,
            body.live_reads,
            body.live_bytes,
            body.peak_window,
            body.peak_suffix,
        );
        Ok(())
    };
    let tail = tail.await;
    env.finish(tail).await
}
