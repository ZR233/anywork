#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_provider_fixture::{Protocol, ReplyStage, Step, WebSocketAction};
use pl_studio_runtime::{
    CURRENT_PROTOCOL_VERSION, ChatAtomKind, ChatContentRole, ChatScope, ContentRange,
    CurrentContentRef, CurrentFrame, CurrentProjection, ThreadWorkspaceMode,
    history::{
        HistoryCut, HistoryDemand, HistoryEventRecord, HistoryEventsQuery, HistoryReader,
        HistoryTimelineItem, HistoryTimelineRole, decode_event_envelope, read_event_body_bytes,
    },
};
use std::collections::HashSet;
use support::{Environment, current_demand, prompt_step, reached};
use tokio_util::sync::CancellationToken;

fn final_text_reference(projection: &CurrentProjection) -> Option<CurrentContentRef> {
    projection
        .atoms
        .iter()
        .filter(|atom| atom.kind == ChatAtomKind::Text)
        .flat_map(|atom| atom.contents.iter())
        .find(|content| content.role == ChatContentRole::Body)
        .map(|content| content.reference.clone())
}

#[tokio::test]
async fn closing_a_thread_waiting_for_input_drains_history_and_saves_current() -> Result<()> {
    let env = Environment::new(
        vec![prompt_step(
            "waiting-close",
            0,
            support::tool_reply(
                "request_user_input",
                "ask",
                serde_json::json!({"questions":[{"id":"choice","header":"Choice","question":"Choose?","isOther":true}]}),
            ),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let started = env
            .start(ThreadWorkspaceMode::Local, "waiting-close")
            .await?;
        let reader = env
            .runtime
            .open_current_reader(
                &started.thread.id,
                CURRENT_PROTOCOL_VERSION,
                current_demand(),
            )
            .await?;
        let watch = reader.watch(None, current_demand()).await?;
        tokio::time::timeout(support::integration_test_deadline()?, async {
            while let Some(frame) = watch.next().await? {
                let projection = match frame {
                    CurrentFrame::Reset { view } => Some(view.projection),
                    CurrentFrame::Projection { projection, .. } => Some(*projection),
                    _ => None,
                };
                if projection.is_some_and(|projection| {
                    projection.logical_status == pl_studio_runtime::ThreadStatus::WaitingInteraction
                }) {
                    return Ok::<_, anyhow::Error>(());
                }
            }
            anyhow::bail!("Current closed before reporting the pending question")
        })
        .await??;
        watch.close().await?;
        reader.close().await?;
        let shutdown = env.runtime.shutdown_runtime().await;
        ensure!(
            shutdown.is_ok(),
            "shutdown={shutdown:?}; persistence={:#?}",
            env.runtime.persistence_queue_snapshot()
        );
        support::saved(&env.home, &started.thread.id).await?;
        ensure!(env.runtime.persistence_queue_snapshot().pending_operations == 0);
        Ok(())
    }
    .await;
    env.finish(result).await
}

async fn original_bodies(
    reader: &HistoryReader,
    event: &HistoryEventRecord,
    envelope: &pl_studio_runtime::history::EventPayloadEnvelope,
) -> Result<Vec<(String, Vec<u8>)>> {
    let mut bodies = Vec::new();
    for entry in &envelope.bodies {
        if entry.role == "canonical_payload" || entry.role == "canonical_metadata" {
            continue;
        }
        let bytes = read_event_body_bytes(reader, event, &entry.key, None)
            .await?
            .with_context(|| format!("missing body {} for {}", entry.key, event.event_id))?;
        bodies.push((entry.key.clone(), bytes));
    }
    Ok(bodies)
}

#[derive(Debug, PartialEq, Eq)]
struct OutputOriginal {
    event_id: String,
    payload: Vec<u8>,
    bodies: Vec<(String, Vec<u8>)>,
}

#[derive(Debug, Default, PartialEq, Eq)]
struct PublicHistory {
    outputs: Vec<OutputOriginal>,
    recovery_notices: Vec<OutputOriginal>,
}

async fn public_history_at(
    reader: &HistoryReader,
    cut: Option<HistoryCut>,
) -> Result<PublicHistory> {
    let demand = HistoryDemand {
        max_rows: 128,
        max_bytes: 1024 * 1024,
    };
    let mut cursor = None;
    let mut result = PublicHistory::default();
    let mut identities = HashSet::new();
    loop {
        let page = reader
            .events_page(
                HistoryEventsQuery::Originals {
                    scope: ChatScope::conversation(None),
                },
                cut.clone(),
                cursor.clone(),
                demand,
            )
            .await?;
        for event in page.entries {
            ensure!(
                identities.insert(event.event_id.clone()),
                "History repeated an original identity"
            );
            if event.payload_schema != "anywork.event/1" {
                continue;
            }
            let envelope = decode_event_envelope(&event)?;
            ensure!(envelope.contract == "anywork.event/1");
            let payload = event.payload_json.as_bytes().to_vec();
            let output = envelope.item_type == "thinking"
                || (envelope.item_type == "text"
                    && matches!(
                        envelope.data["channel"].as_str(),
                        Some("final" | "commentary")
                    ));
            if !output {
                continue;
            }
            let bodies = original_bodies(reader, &event, &envelope).await?;
            ensure!(
                !bodies.is_empty(),
                "public output omitted its original body"
            );
            let text: Vec<_> = bodies
                .iter()
                .flat_map(|(_, bytes)| bytes.iter().copied())
                .collect();
            let notice = match text.as_slice() {
                value if value == "连接中断，正在重试（1/5）。".as_bytes() => {
                    Some("连接中断，正在重试（1/5）。")
                }
                value if value == "连接已恢复，继续执行。".as_bytes() => {
                    Some("连接已恢复，继续执行。")
                }
                _ => None,
            };
            if let Some(notice) = notice {
                ensure!(
                    !result.recovery_notices.iter().any(|published| published
                        .bodies
                        .iter()
                        .flat_map(|(_, bytes)| bytes.iter())
                        .copied()
                        .eq(notice.as_bytes().iter().copied())),
                    "recovery notice was published more than once"
                );
                result.recovery_notices.push(OutputOriginal {
                    event_id: event.event_id,
                    payload,
                    bodies,
                });
                continue;
            }
            for (_, bytes) in &bodies {
                let (parts, remainder) = bytes.as_chunks::<2>();
                ensure!(
                    remainder.is_empty() && parts.iter().all(|part| part == b" a"),
                    "public body differs from provider output"
                );
            }
            result.outputs.push(OutputOriginal {
                event_id: event.event_id,
                payload,
                bodies,
            });
        }
        let Some(next) = page.next else {
            break;
        };
        ensure!(
            cursor.as_ref() != Some(&next),
            "event cursor did not advance"
        );
        cursor = Some(next);
    }
    Ok(result)
}

async fn public_history(reader: &HistoryReader) -> Result<PublicHistory> {
    public_history_at(reader, None).await
}

fn output_shape(history: &PublicHistory) -> (usize, u64) {
    (
        history.outputs.len(),
        history
            .outputs
            .iter()
            .flat_map(|output| output.bodies.iter())
            .map(|(_, bytes)| bytes.len() as u64)
            .sum(),
    )
}

#[tokio::test]
async fn closing_current_joins_metadata_and_body_watches_then_reopens_the_live_owner() -> Result<()>
{
    let stage = ReplyStage::new();
    let mut frames =
        pl_provider_fixture::responses_text("close-retry response", "close-retry", support::MODEL);
    let delta = frames
        .iter()
        .position(|frame| frame["type"] == "response.output_text.delta")
        .context("fixture text delta")?;
    let after = frames.split_off(delta + 1);
    let env = Environment::new(
        vec![prompt_step("close-retry", 0, stage.gated(frames, after))],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Worktree, "close-retry")
            .await?;
        let id = &thread.thread.id;
        let demand = current_demand();
        let reader = env
            .runtime
            .open_current_reader(id, CURRENT_PROTOCOL_VERSION, demand)
            .await?;
        let metadata = reader.watch(None, demand).await?;
        ensure!(matches!(
            metadata.next().await?,
            Some(CurrentFrame::Reset { .. })
        ));
        reached(&stage).await?;
        let mut reference = None;
        while reference.is_none() {
            match metadata.next().await? {
                Some(CurrentFrame::Reset { view }) => {
                    reference = final_text_reference(&view.projection);
                }
                Some(CurrentFrame::Projection { projection, .. }) => {
                    reference = final_text_reference(&projection);
                }
                Some(CurrentFrame::Notification { .. }) => {}
                None => anyhow::bail!("Current watch ended before the response body appeared"),
            }
        }
        let reference = reference.context("live response body reference")?;
        let owner = reader.snapshot(demand).await?.revision.owner_id;
        let body = reader
            .watch_body(
                reference,
                ContentRange {
                    offset: 0,
                    max_bytes: 64,
                },
            )
            .await?;
        let window = body.next().await?.context("live body watch")?;
        ensure!(!window.bytes.is_empty() && !window.sealed);

        reader.close().await?;
        ensure!(
            metadata.next().await?.is_none(),
            "metadata watch survived Current close"
        );
        ensure!(
            body.next().await?.is_none(),
            "body watch survived Current close"
        );
        metadata.close().await?;
        body.close().await?;
        ensure!(
            reader.snapshot(demand).await.is_err(),
            "closed Current remained readable"
        );

        let reopened = env
            .runtime
            .open_current_reader(id, CURRENT_PROTOCOL_VERSION, demand)
            .await?;
        let view = reopened.snapshot(demand).await?;
        ensure!(
            view.revision.owner_id == owner && view.projection.execution_present,
            "reopening replaced the live owner or execution"
        );
        let reference =
            final_text_reference(&view.projection).context("response body after Current reopen")?;
        let window = reopened
            .read_body(
                reference,
                ContentRange {
                    offset: 0,
                    max_bytes: 64,
                },
            )
            .await?;
        ensure!(!window.bytes.is_empty());

        stage.release();
        let terminal = support::completed_prompt(&env.runtime, id, "close-retry").await?;
        ensure!(terminal.thread_id.as_str() == id);
        reopened.close().await?;
        ensure!(
            env.root_provider.recorded().len() == 1,
            "Current close/retry made another provider request"
        );
        Ok(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn websocket_reconnect_is_durable_history_but_not_replayed_by_paused_current() -> Result<()> {
    let barrier_reached = CancellationToken::new();
    let retry_barrier_reached = CancellationToken::new();
    let release = CancellationToken::new();
    let retry_release = CancellationToken::new();
    let frames = pl_provider_fixture::responses_reasoning_text(
        &[" a"],
        &[" a"; 96],
        "reconnect",
        support::MODEL,
    );
    let mut actions = frames[..4]
        .iter()
        .cloned()
        .map(WebSocketAction::Event)
        .collect::<Vec<_>>();
    actions.push(WebSocketAction::Barrier {
        reached: barrier_reached.clone(),
        release: release.clone(),
    });
    actions.push(WebSocketAction::Event(serde_json::json!({
        "type":"error",
        "status":400,
        "error":{
            "code":"websocket_connection_limit_reached",
            "message":"Responses websocket connection limit reached (60 minutes). Create a new websocket connection to continue."
        }
    })));
    let mut env = Environment::with_transport(
        vec![
            Step::prompt(
                Protocol::ResponsesWebSocket,
                "reconnect",
                0,
                pl_provider_fixture::Reply::WebSocketScript(actions),
            ),
            Step::prompt(
                Protocol::ResponsesWebSocket,
                "reconnect",
                1,
                pl_provider_fixture::Reply::WebSocketScript(
                    vec![WebSocketAction::Barrier {
                        reached: retry_barrier_reached.clone(),
                        release: retry_release.clone(),
                    }]
                    .into_iter()
                    .chain(frames.iter().cloned().map(WebSocketAction::Event))
                    .collect(),
                ),
            ),
        ],
        vec![],
        pl_model::model::ModelTransportProfile::responses_websocket(),
    )
    .await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Worktree, "reconnect")
            .await?;
        let id = &thread.thread.id;
        tokio::time::timeout(
            support::integration_test_deadline()?,
            barrier_reached.cancelled(),
        )
        .await
        .context("provider websocket barrier was not reached")?;

        let current = env
            .runtime
            .open_current_reader(id, CURRENT_PROTOCOL_VERSION, current_demand())
            .await?;
        let live = current.snapshot(current_demand()).await?;
        ensure!(live.projection.execution_present);
        ensure!(
            live.state
                .runtime
                .as_ref()
                .is_some_and(|runtime| runtime.deferred.is_empty()),
            "ordinary websocket state unexpectedly deferred runtime fields"
        );
        let owner = live.revision.owner_id;
        let history = env
            .runtime
            .open_history_reader(id, pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION)
            .await?;
        history
            .capture()
            .await
            .context("live History could not capture a read cut")?;
        current.close().await?;

        release.cancel();
        tokio::time::timeout(
            support::integration_test_deadline()?,
            retry_barrier_reached.cancelled(),
        )
        .await
        .context("retry provider websocket barrier was not reached")?;
        let (early_cut, early) =
            tokio::time::timeout(support::integration_test_deadline()?, async {
                let mut early_cut = history.capture().await?;
                loop {
                    let published = public_history_at(&history, Some(early_cut.clone())).await?;
                    if published.recovery_notices.len() == 1 && !published.outputs.is_empty() {
                        return Ok::<_, anyhow::Error>((early_cut, published));
                    }
                    early_cut = history.wait_changed(early_cut).await?;
                }
            })
            .await??;
        let early_notice = &early.recovery_notices[0];
        let early_timeline = history
            .timeline_page(Some(early_cut.clone()), None, HistoryDemand::default())
            .await?;
        let divider = early_timeline
            .items
            .iter()
            .find_map(|item| match item {
                HistoryTimelineItem::Divider(event)
                    if event.kind.as_str() == "model_interrupted"
                        && event.timeline_role == HistoryTimelineRole::Divider =>
                {
                    Some(event)
                }
                _ => None,
            })
            .context("interruption was not published as a model_interrupted Divider")?;
        let previous_range = early_timeline
            .items
            .iter()
            .find_map(|item| match item {
                HistoryTimelineItem::WorkRange(range) if range.before_seq == Some(divider.seq) => {
                    Some(range)
                }
                _ => None,
            })
            .context("previous WorkRange did not end at the retry Divider")?;
        let previous_work = history
            .work_range_page(
                previous_range.after_seq,
                previous_range.before_seq,
                Some(early_cut.clone()),
                None,
                HistoryDemand::default(),
            )
            .await?;
        ensure!(
            previous_work.events.iter().any(|event| {
                early
                    .outputs
                    .iter()
                    .any(|output| output.event_id == event.event_id)
                    && decode_event_envelope(event)
                        .is_ok_and(|envelope| envelope.item_type == "thinking")
            }),
            "failed attempt thinking output was not in the WorkRange before the retry Divider"
        );

        retry_release.cancel();
        let terminal = support::completed_prompt(&env.runtime, id, "reconnect").await?;
        ensure!(terminal.id == live.projection.active_turn.context("live Turn")?.id);
        let published = public_history(&history).await?;
        ensure!(
            (published.outputs.len(), published.recovery_notices.len()) == (3, 2)
                && output_shape(&published) == (3, 196),
            "websocket reconnect changed public output: outputs={}, notices={:?}, shape={:?}",
            published.outputs.len(),
            published.recovery_notices,
            output_shape(&published)
        );
        ensure!(
            published
                .recovery_notices
                .iter()
                .filter(|notice| *notice == early_notice)
                .count()
                == 1,
            "retry notice identity or content changed after the retry completed"
        );
        ensure!(
            published.recovery_notices.iter().any(|notice| {
                notice.event_id != early_notice.event_id
                    && notice
                        .bodies
                        .iter()
                        .any(|(_, bytes)| bytes.as_slice() == "连接已恢复，继续执行。".as_bytes())
            }),
            "recovery completion output was not retained as a distinct original"
        );
        history.close().await;

        env.runtime.synchronize_thread_observation(id).await?;
        // Current saves independently; closing the original owner provides its final save.
        env.restart().await?;
        let saved = support::saved(&env.home, id).await?;
        ensure!(saved.current.saved_runtime_epoch.to_string() == owner);
        let current_bytes = std::fs::read(saved.root.join("current.json"))?;
        let provider_requests = env.root_provider.recorded().len();
        ensure!(
            provider_requests == 2,
            "websocket reconnect did not use exactly two provider requests"
        );
        let recorded = env.root_provider.recorded();
        ensure!(
            recorded
                .iter()
                .all(|request| request.accepted && request.method == "WS")
                && recorded[1].body.get("previous_response_id").is_none()
                && recorded[0].body["input"] == recorded[1].body["input"],
            "websocket reconnect changed request identity or admission"
        );

        let paused = env
            .runtime
            .open_current_reader(id, CURRENT_PROTOCOL_VERSION, current_demand())
            .await?;
        let view = paused.snapshot(current_demand()).await?;
        ensure!(
            view.revision.owner_id == owner && !view.projection.execution_present,
            "passive cold reading changed saved provenance or replayed execution"
        );
        ensure!(
            !view.projection.atoms.iter().any(|atom| {
                matches!(
                    atom.kind,
                    ChatAtomKind::Text
                        | ChatAtomKind::Reasoning
                        | ChatAtomKind::ToolCall
                        | ChatAtomKind::Inference
                )
            }),
            "paused Current replayed completed websocket history"
        );
        let restored_history = env
            .runtime
            .open_history_reader(id, pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION)
            .await?;
        ensure!(
            public_history(&restored_history).await? == published,
            "restart changed websocket output identities, order or bytes"
        );
        let restored_timeline = restored_history
            .timeline_page(None, None, HistoryDemand::default())
            .await?;
        ensure!(
            restored_timeline.items.iter().any(|item| matches!(
                item,
                HistoryTimelineItem::Divider(event)
                    if event.event_id == divider.event_id
                        && event.kind.as_str() == "model_interrupted"
                        && event.timeline_role == HistoryTimelineRole::Divider
            )),
            "restart did not retain the retry interruption Divider"
        );
        ensure!(
            restored_timeline.items.iter().any(|item| matches!(
                item,
                HistoryTimelineItem::WorkRange(range)
                    if range.before_seq == Some(divider.seq)
            )),
            "restart did not retain the previous WorkRange boundary"
        );
        ensure!(
            !restored_timeline.items.iter().any(|item| matches!(
                item,
                HistoryTimelineItem::Divider(event)
                    if event.kind.as_str() == "model_recovery_finished"
            )),
            "recovery completion incorrectly created a second Divider"
        );
        restored_history.close().await;
        paused.close().await?;
        ensure!(
            std::fs::read(saved.root.join("current.json"))? == current_bytes,
            "cold Current/History reads rewrote current.json"
        );
        ensure!(
            env.root_provider.recorded().len() == provider_requests,
            "cold Current/History reads activated the provider"
        );
        Ok(())
    }
    .await;
    release.cancel();
    env.finish(result).await
}

#[tokio::test]
#[ignore = "两千条输出规模检查，由 Rust Scale Checks 定时或手动运行"]
async fn current_and_history_2000_item_scale() -> Result<()> {
    const ITEMS: usize = 2_000;
    const OUTPUT_BYTES: u64 =
        (pl_provider_fixture::GUI_STREAMING_OUTPUT_REFERENCE_TOKENS * 2) as u64;
    let prompt = "current-history-scale";
    let mut env = Environment::new(
        vec![prompt_step(
            prompt,
            0,
            pl_provider_fixture::gui_streaming_output_reply(ITEMS, 1),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, prompt).await?;
        let id = &thread.thread.id;
        let history = env
            .runtime
            .open_history_reader(id, pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION)
            .await?;
        history
            .capture()
            .await
            .context("scale History could not capture its initial cut")?;
        let terminal = support::completed_prompt(&env.runtime, id, prompt).await?;
        ensure!(matches!(
            terminal.state,
            pl_studio_runtime::TurnState::Completed(_)
        ));
        let published = public_history(&history).await?;
        ensure!(
            output_shape(&published) == (ITEMS, OUTPUT_BYTES)
                && published.recovery_notices.is_empty(),
            "scale output changed: shape={:?}, notices={}",
            output_shape(&published),
            published.recovery_notices.len()
        );
        history.close().await;

        env.runtime.synchronize_thread_observation(id).await?;
        env.restart().await?;
        let restored = env
            .runtime
            .open_history_reader(id, pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION)
            .await?;
        ensure!(
            public_history(&restored).await? == published,
            "cold History changed scale identities, order or bytes"
        );
        restored.close().await;
        ensure!(
            env.root_provider.recorded().len() == 1,
            "scale fixture made more than one provider request"
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}
