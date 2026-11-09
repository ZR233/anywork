//! A paced single-item output proves the production FRB producer, facade content mapping and
//! credit ACKs keep consuming one 256000-byte body while its original Turn and execution run.
use std::{collections::HashSet, time::Duration};

use anyhow::{Context, Result, ensure};
use pl_protocol::{AgentExecutionPhase, ThreadSnapshot, TurnState};
use pl_provider_fixture::{GUI_STREAMING_OUTPUT_REFERENCE_TOKENS, gui_streaming_output_reply};
use pl_studio_runtime::StudioRuntime;

use super::*;
use crate::api::studio::types::{
    BridgeActivityIdentity, BridgeActivitySnapshot, BridgeChatAtomKind, BridgeChatAtomLifecycle,
    BridgeChatContentRole, BridgeChatPlacement, BridgeContentOwner, BridgeContentRange,
    BridgeContentRef, BridgeContentTarget, BridgeContentWindow,
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

fn live_body_target(activity: &BridgeActivitySnapshot) -> Result<Option<LiveBodyTarget>> {
    let Some(entry) = activity.entries.iter().find(|entry| {
        entry.atom.kind == BridgeChatAtomKind::Text
            && matches!(
                &entry.atom.lifecycle,
                BridgeChatAtomLifecycle::Active { .. }
            )
            && entry
                .atom
                .contents
                .iter()
                .any(|content| content.role == BridgeChatContentRole::Body)
    }) else {
        return Ok(None);
    };
    let Some(content) = entry
        .atom
        .contents
        .iter()
        .find(|content| content.role == BridgeChatContentRole::Body)
    else {
        return Ok(None);
    };
    ensure!(matches!(
        &content.reference.target,
        BridgeContentTarget::Body {
            owner: BridgeContentOwner::Item { .. },
            ..
        }
    ));
    let (atom_id, identity_turn) = match &entry.identity {
        BridgeActivityIdentity::ModelPart { atom_id } => (atom_id, entry.atom.turn_id.as_ref()),
        _ => anyhow::bail!("live Text activity has a non-model identity"),
    };
    let Some(turn_id) = identity_turn else {
        return Ok(None);
    };
    ensure!(atom_id == &entry.atom.id);
    Ok(Some(LiveBodyTarget {
        reference: content.reference.clone(),
        preview_id: atom_id.clone(),
        display_id: atom_id.clone(),
        turn_id: turn_id.clone(),
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
    let state_feed = env
        .runtime
        .open_conversation_state_feed(&env.thread_id)
        .await?;
    let state_owner = managed_state(state_feed);
    let mut state_port = start_port(&state_owner).await;
    let mut sent = 0;
    let observation = tokio::time::timeout(Duration::from_secs(120), async {
        // Reliable Main first: the initial real Set must arrive before the followup is submitted.
        let initial = loop {
            let frame = next_frame(&owner, &mut port, &mut sent).await?;
            match frame.event {
                BridgeConversationEvent::Chat { batch } => {
                    ensure!(batch.placement == BridgeChatPlacement::Set);
                    ensure!(batch.from_seq.is_none());
                    break *batch;
                }
                BridgeConversationEvent::Activity { snapshot } => {
                    ensure!(snapshot.completed_through <= i64::MAX as u64);
                    owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                }
                event => anyhow::bail!("unexpected initial event: {event:?}"),
            }
        };
        let mut accepted_through = initial.through_seq;
        let mut item_ids = HashSet::new();
        let mut last_position = None;
        for entry in &initial.entries {
            ensure!(
                item_ids.insert(entry.record_id.clone()),
                "initial Main repeated record"
            );
            let position = entry.completion_seq;
            ensure!(
                last_position.is_none_or(|last| position > last),
                "initial Main changed completion order"
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
        let observe =
            async {
                let result = async {
                let mut retired = false;
                let mut handed_off: Option<LiveBodyTarget> = None;
                let mut appended: Vec<(String, Option<String>)> = Vec::new();
                let mut activity_revision = 0;
                let mut last_activity = None;
                while !retired {
                    let frame = next_frame(&owner, &mut port, &mut sent).await.with_context(|| {
                        format!("content wait: retired={retired}; activity_revision={activity_revision}; last_activity={last_activity:?}")
                    })?;
                    match frame.event {
                        BridgeConversationEvent::Chat { batch } => {
                            let batch = *batch;
                            ensure!(
                                batch.placement == BridgeChatPlacement::Append
                                    && batch.before.is_none()
                                    && batch.from_seq.is_some_and(|from| from < batch.through_seq)
                            );
                            accepted_through = batch.through_seq;
                            ensure!(
                                batch.entries.len() <= 1,
                                "append exceeded the original Main demand"
                            );
                            for item in batch.entries {
                                ensure!(
                                    item_ids.insert(item.record_id.clone()),
                                    "Main repeated completion record {}",
                                    item.record_id
                                );
                                let position = item.completion_seq;
                                let last = last_position
                                    .context("no baseline completion position after initial Set")?;
                                ensure!(
                                    position > last,
                                    "Main Append changed item order: {position} after {last}"
                                );
                                last_position = Some(position);
                                appended.push((item.record_id, item.atom.completion_item_id));
                            }
                            owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                        }
                        BridgeConversationEvent::Activity { snapshot } => {
                            ensure!(snapshot.revision > activity_revision);
                            ensure!(snapshot.completed_through == accepted_through,
                                "Activity crossed its checked completion prefix");
                            activity_revision = snapshot.revision;
                            last_activity = Some((snapshot.execution_present, snapshot.entries.len()));
                            if let Some(target) = live_body_target(&snapshot)? {
                                if let Some(previous) = &handed_off {
                                    ensure!(
                                        previous.same_identity(&target),
                                        "live Activity identity changed: {previous:?} -> {target:?}"
                                    );
                                } else {
                                    let delivered =
                                        offer.take().context("body handoff offered twice")?;
                                    delivered.send(target.clone()).map_err(|_| {
                                        anyhow::anyhow!("body consumer closed before its target")
                                    })?;
                                    handed_off = Some(target);
                                }
                            }
                            if let Some(target) = &handed_off {
                                retired = !snapshot.entries.iter().any(|entry| {
                                    matches!(&entry.identity,
                                        BridgeActivityIdentity::ModelPart { atom_id }
                                            if atom_id == &target.display_id)
                                });
                                if retired {
                                    ensure!(appended.iter().any(|(id, _)| id == &target.display_id),
                                        "Activity member retired before its completion prefix was accepted");
                                }
                            }
                            owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                        }
                        event => anyhow::bail!("unexpected live event: {event:?}"),
                    }
                }
                Ok((
                    handed_off.context("Main retired without a live body target")?,
                    appended,
                ))
            }
            .await;
                drop(offer);
                result
            };
        // The one-time identity transfer is synchronous; both owners stay joined on any failure.
        let (main, body, state) = tokio::join!(
            observe,
            consume,
            super::live::observe_stopped_execution(&state_owner, &mut state_port),
        );
        let (target, appended) =
            main.with_context(|| format!("continuous body result: {body:?}"))?;
        let body = body?;
        let terminal_turn = state?;
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
                .map_err(|error| {
                    anyhow::anyhow!("sealed.read offset={sealed_cursor}: {error:?}")
                })?;
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
            ensure!(
                sealed_generation
                    .as_ref()
                    .is_none_or(|value| value == &window.generation)
            );
            sealed_generation = Some(window.generation.clone());
            let (parts, remainder) = window.bytes.as_chunks::<2>();
            ensure!(remainder.is_empty() && parts.iter().all(|part| part == b" a"));
            sealed_cursor += window.bytes.len() as u64;
        }
        ensure!(sealed_cursor == BODY_BYTES);
        ensure!(sealed_generation.as_ref() == Some(&body.generation));
        Ok((terminal_turn, item_ids, body, accepted_through))
    })
    .await;
    // Every frame received before close was acknowledged synchronously; the close takes ACK
    // precedence, so already-published trailing frames cannot be acknowledged afterwards.
    let acknowledged_prefix = sent;
    let close = facade.close().await;
    let state_close = state_owner.close().await;
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
        let (terminal_turn, mut item_ids, body, mut accepted_through) =
            observation.with_context(|| {
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
                BridgeConversationEvent::Chat { batch } => {
                    ensure!(
                        batch.placement == BridgeChatPlacement::Append
                            && batch.before.is_none()
                            && batch.from_seq.is_some_and(|from| from < batch.through_seq)
                    );
                    accepted_through = batch.through_seq;
                    for item in batch.entries {
                        ensure!(
                            item_ids.insert(item.record_id.clone()),
                            "trailing Main repeated completion {}",
                            item.record_id
                        );
                    }
                }
                BridgeConversationEvent::Activity { snapshot } => {
                    ensure!(snapshot.revision > 0);
                    ensure!(snapshot.completed_through == accepted_through);
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
    let tail = tail.await.and(state_close.map_err(anyhow::Error::from));
    env.finish(tail).await
}
