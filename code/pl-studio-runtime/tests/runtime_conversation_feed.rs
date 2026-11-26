#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_provider_fixture::{Protocol, ReplyStage, Step, WebSocketAction};
use pl_studio_runtime::{
    ChatScope, ThreadStatus, ThreadWorkspaceMode,
    history::{
        HistoryDemand, HistoryEventRecord, HistoryEventsQuery, HistoryReader,
        decode_event_envelope, read_event_body_bytes,
    },
    timeline::{ConversationEvent, LiveStatusPhase, TimelineItem, TimelinePatch},
};
use std::collections::HashSet;
use support::{Environment, prompt_step, reached};
use tokio_util::sync::CancellationToken;

#[tokio::test]
async fn closing_a_thread_waiting_for_input_drains_history_and_saves_current() -> Result<()> {
    let env = Environment::new(
        vec![prompt_step(
            "waiting-close",
            0,
            support::tool_reply(
                "request_user_input",
                "ask",
                serde_json::json!({"questions":[{"id":"choice","header":"Choice","question":"Choose?"}]}),
            ),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let started = env
            .start(ThreadWorkspaceMode::Local, "waiting-close")
            .await?;
        let feed = env
            .runtime
            .open_conversation_feed(&started.thread.id, 64)
            .await?;
        tokio::time::timeout(support::integration_test_deadline()?, async {
            loop {
                let meta = feed.session_meta_snapshot();
                if meta.status == ThreadStatus::WaitingInteraction
                    && meta.last_turn.is_some_and(|turn| turn.state.is_terminal())
                {
                    return Ok::<_, anyhow::Error>(());
                }
                if feed.next_event().await.is_none() {
                    anyhow::bail!("ConversationFeed closed before reporting the pending question");
                }
            }
        })
        .await??;
        feed.close().await;
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
    recoveries: Vec<(pl_studio_runtime::ModelRecoveryNotice, OutputOriginal)>,
}

async fn connection_boundaries(reader: &HistoryReader) -> Result<Vec<(String, serde_json::Value)>> {
    let mut events = Vec::new();
    let mut cursor = None;
    let demand = HistoryDemand {
        max_rows: 128,
        max_bytes: 1024 * 1024,
    };
    loop {
        let page = reader.timeline_page(None, cursor.take(), demand).await?;
        for entry in page.entries {
            let record = entry.event;
            if matches!(
                record.kind,
                pl_studio_runtime::history::HistoryEventKind::ConnectionDisconnected
                    | pl_studio_runtime::history::HistoryEventKind::ConnectionReconnected
            ) {
                ensure!(
                    record.original.is_none(),
                    "connection boundary must not be indexed as Original"
                );
                let envelope = decode_event_envelope(&record)?;
                events.push((record.event_id, envelope.data));
            }
        }
        if page.next.is_none() {
            break;
        }
        cursor = page.next;
    }
    Ok(events)
}

async fn public_history(reader: &HistoryReader) -> Result<PublicHistory> {
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
                None,
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
            if let Some(notice) = envelope.data.get("modelRecovery") {
                result.recoveries.push((
                    serde_json::from_value(notice.clone())?,
                    OutputOriginal {
                        event_id: event.event_id,
                        payload,
                        bodies,
                    },
                ));
                continue;
            }
            for (key, bytes) in &bodies {
                let (parts, remainder) = bytes.as_chunks::<2>();
                ensure!(
                    remainder.is_empty() && parts.iter().all(|part| part == b" a"),
                    "public body differs from provider output: key={key}"
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
        let feed = env.runtime.open_conversation_feed(id, 64).await?;
        ensure!(matches!(
            feed.next_event().await,
            Some(ConversationEvent::Timeline(TimelinePatch::Reset { .. }))
        ));
        reached(&stage).await?;
        let mut streamed_text = String::new();
        while streamed_text.is_empty() {
            match feed.next_event().await {
                Some(ConversationEvent::LiveStatus(ls)) => {
                    if let LiveStatusPhase::StreamingText { text, .. } = ls.phase
                        && !text.is_empty()
                    {
                        streamed_text = text;
                    }
                }
                Some(_) => {}
                None => anyhow::bail!("ConversationFeed ended before the response stream appeared"),
            }
        }
        let owner = feed.session_meta_snapshot().owner_epoch;
        ensure!(!owner.is_empty());

        feed.close().await;
        ensure!(
            feed.next_event().await.is_none(),
            "event stream survived ConversationFeed close"
        );
        ensure!(
            feed.load_older("0".into(), 16).await.is_err(),
            "closed ConversationFeed remained readable"
        );

        let reopened = env.runtime.open_conversation_feed(id, 64).await?;
        let meta = reopened.session_meta_snapshot();
        ensure!(
            meta.owner_epoch == owner && meta.execution_present,
            "reopening replaced the live owner or execution"
        );
        ensure!(
            matches!(
                reopened.live_status_snapshot().phase,
                LiveStatusPhase::StreamingText { ref text, .. } if !text.is_empty()
            ),
            "reopened ConversationFeed lost live StreamingText status"
        );

        stage.release();
        let terminal = support::completed_prompt(&env.runtime, id, "close-retry").await?;
        ensure!(terminal.thread_id.as_str() == id);
        reopened.close().await;
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
    let release = CancellationToken::new();
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
                pl_provider_fixture::Reply::WebSocket(frames),
            ),
        ],
        vec![],
        pl_model::model::ModelTransportProfile::responses_websocket(),
    )
    .await?;
    let result = async {
        // This script uses OpenAI's connection-lifetime code. Select that policy and
        // a synthetic loopback credential through the isolated runtime's public API.
        env.runtime
            .patch_account(pl_studio_runtime::PatchAccountRequest {
                operation_id: "reconnect-openai-policy".into(),
                expected_revision: env.runtime.read_settings()?.config.revision,
                account_id: "root-fixture".into(),
                authentication: pl_studio_runtime::AccountAuthenticationIntent::ApiKey,
                name: Default::default(),
                base_url: Default::default(),
                template_id: Default::default(),
                protocol: pl_studio_runtime::AccountTextPatch::Set {
                    value: pl_model::protocol::providers::openai::ID.to_string(),
                },
                secret: pl_studio_runtime::AccountSecretUpdate::Replace {
                    value: "isolated-reconnect-fixture-token".into(),
                },
                custom_models: Default::default(),
            })
            .await?;
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

        let feed = env.runtime.open_conversation_feed(id, 64).await?;
        let live = feed.session_meta_snapshot();
        ensure!(live.execution_present);
        ensure!(
            live.runtime
                .as_ref()
                .is_some_and(|runtime| runtime.deferred.is_empty()),
            "ordinary websocket state unexpectedly deferred runtime fields"
        );
        let owner = live.owner_epoch.clone();
        let history = env
            .runtime
            .open_history_reader(id, pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION)
            .await?;
        history
            .capture()
            .await
            .context("live History could not capture a read cut")?;
        feed.close().await;

        release.cancel();
        let terminal = support::completed_prompt(&env.runtime, id, "reconnect").await?;
        ensure!(
            matches!(terminal.state, pl_studio_runtime::TurnState::Completed(_)),
            "websocket reconnect did not complete: {terminal:?}"
        );
        ensure!(terminal.id == live.active_turn.context("live Turn")?.id);
        let published = public_history(&history).await?;
        let conn_events = connection_boundaries(&history).await?;
        ensure!(
            published.recoveries.len() == 2
                && published.recoveries.iter().all(|(notice, _)| {
                    notice.retry_count == 1
                        && notice.max_retries == 5
                        && notice.failure.as_ref().is_some_and(|failure| {
                            failure.code.as_deref() == Some("websocket_connection_limit_reached")
                                && failure.provider_kind
                                    == Some(pl_protocol::ProviderFailureKind::Transport)
                        })
                })
                && published.recoveries.iter().any(|(notice, _)| {
                    notice.phase == pl_core::model::ModelRecoveryPhase::Recovered
                }),
            "websocket recovery notices lost their failure or successful recovery: {:?}",
            published.recoveries
        );
        ensure!(
            published.outputs.len() == 3 && output_shape(&published) == (3, 196),
            "websocket reconnect changed public output: outputs={}, shape={:?}",
            published.outputs.len(),
            output_shape(&published)
        );
        ensure!(
            conn_events.len() == 2
                && conn_events[0].1["state"] == "reconnected"
                && conn_events[0].1["scope"] == "model"
                && conn_events[0].1["transport"] == "ws"
                && conn_events[1].1["state"] == "disconnected"
                && conn_events[1].1["scope"] == "model"
                && conn_events[1].1["transport"] == "ws"
                && conn_events[1].1["recoverable"] == true,
            "websocket reconnect changed connection boundary events: {conn_events:?}"
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

        let paused = env.runtime.open_conversation_feed(id, 64).await?;
        let paused_meta = paused.session_meta_snapshot();
        ensure!(
            paused_meta.owner_epoch == owner && !paused_meta.execution_present,
            "passive cold reading changed saved provenance or replayed execution"
        );
        ensure!(
            paused_meta.active_turn.is_none()
                && matches!(paused.live_status_snapshot().phase, LiveStatusPhase::Idle),
            "paused ConversationFeed replayed execution"
        );
        if let Some(ConversationEvent::Timeline(TimelinePatch::Reset { items, .. })) =
            paused.next_event().await
        {
            ensure!(
                items
                    .iter()
                    .any(|item| matches!(item, TimelineItem::AssistantText { .. }))
            );
        }
        let restored_history = env
            .runtime
            .open_history_reader(id, pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION)
            .await?;
        ensure!(
            public_history(&restored_history).await? == published
                && connection_boundaries(&restored_history).await? == conn_events,
            "restart changed websocket output identities, order, connection boundaries or bytes"
        );
        restored_history.close().await;
        paused.close().await;
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
        let conn_events = connection_boundaries(&history).await?;
        ensure!(
            output_shape(&published) == (ITEMS, OUTPUT_BYTES)
                && published.recoveries.is_empty()
                && conn_events.is_empty(),
            "scale output changed: shape={:?}, conn_events={}",
            output_shape(&published),
            conn_events.len()
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
