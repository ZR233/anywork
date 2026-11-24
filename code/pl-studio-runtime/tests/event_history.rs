#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};

use pl_core::thread::current::RuntimeEpoch;
use pl_studio_runtime::history::*;
use pl_studio_runtime::{
    CURRENT_PROTOCOL_VERSION, ChatActiveStatus, ChatTerminalOutcome, ContentRange,
    CurrentContentRef, CurrentFrame, CurrentProjection, RuntimeCostAmount,
};
use sea_orm::{ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, Statement};
use std::{path::Path, sync::Arc};
use support::{Environment, current_demand, prompt_step, reached};

fn demand() -> HistoryDemand {
    HistoryDemand::default()
}

#[tokio::test]
async fn approving_a_reopened_plan_commits_its_decision_and_continuation() -> Result<()> {
    use pl_studio_runtime::{
        CreateThreadRequest, InteractionResolution, NewThreadModelRoute, StudioPromptInput,
        ThreadWorkspaceMode, UserInputAnswer, UserInputResolution, mode::ThreadModeId,
    };

    let plan = "# Restart plan\n\nImplement the approved isolated task and report its result.";
    let continuation = pl_provider_fixture::ReplyStage::new();
    let mut env = Environment::new(
        vec![
            prompt_step(
                "reopened-plan",
                0,
                support::tool_reply(
                    "plan_transition",
                    "saved-plan",
                    serde_json::json!({"targetState":"awaitingConfirmation","expectedRevision":0,"content":plan}),
                ),
            ),
            prompt_step(plan, 1, support::held_reply(&continuation, "approved")),
        ],
        vec![],
    )
    .await?;
    let result = tokio::time::timeout(support::integration_test_deadline()?, async {
        let created = env
            .runtime
            .create_thread_command(
                env.project.id.clone(),
                CreateThreadRequest {
                    title: Some("Reopened plan".into()),
                    input: StudioPromptInput {
                        input_id: "input-reopened-plan".into(),
                        text: "reopened-plan".into(),
                        attachment_draft_ids: Vec::new(),
                    },
                    mode: ThreadModeId::auto().to_string(),
                    route: NewThreadModelRoute {
                        account_id: "root-fixture".into(),
                        model_id: support::MODEL.into(),
                        effort: None,
                    },
                    service_tier: None,
                    delegation_mode: Some(pl_studio_runtime::DelegationMode::Profile),
                    delegation_preference: None,
                    workspace_mode: ThreadWorkspaceMode::Local,
                },
                None,
            )
            .await?;
        let id = created.thread.id;
        support::completed_prompt(&env.runtime, &id, "reopened-plan").await?;
        env.runtime.synchronize_thread_observation(&id).await?;
        env.restart().await?;
        let reader = env
            .runtime
            .open_current_reader(&id, CURRENT_PROTOCOL_VERSION, current_demand())
            .await?;
        let view = reader.snapshot(current_demand()).await?;
        let interactions = view
            .projection
            .interactions
            .context("reopened Plan collection")?;
        let page = reader
            .page_collection(interactions, None, current_demand())
            .await?;
        let entry = page
            .entries
            .into_iter()
            .next()
            .context("reopened pending Plan")?;
        let bytes = match entry.payload {
            pl_studio_runtime::CurrentPayloadData::Inline { bytes } => bytes,
            pl_studio_runtime::CurrentPayloadData::Deferred { reference, .. } => {
                read_current_body(&reader, &reference).await?
            }
        };
        let pending: pl_studio_runtime::InteractionRequest = serde_json::from_slice(&bytes)?;
        let metadata = reader.watch(None, current_demand()).await?;
        ensure!(
            env.root_provider.recorded().len() == 1,
            "passive restore invoked a model"
        );
        env.runtime
            .resolve_interaction(
                "approve-reopened-plan".into(),
                id.clone(),
                pending.revision,
                pending.interaction_id.clone(),
                InteractionResolution::UserInput(UserInputResolution {
                    answers: std::collections::HashMap::from([(
                        pl_studio_runtime::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
                        UserInputAnswer {
                            answers: vec!["Approve".into()],
                        },
                    )]),
                }),
            )
            .await?;
        reached(&continuation).await?;
        env.runtime.synchronize_thread_observation(&id).await?;
        let input = loop {
            ensure!(
                metadata.next().await?.is_some(),
                "Current ended before the approved continuation"
            );
            let active = reader.snapshot(current_demand()).await?;
            if let Some(input) = active.state.active_turn.and_then(|turn| turn.input_id)
                && input != "input-reopened-plan"
            {
                break input;
            }
        };
        continuation.release();
        support::terminal(&env.runtime, &id, Some(&input)).await?;
        env.runtime.synchronize_thread_observation(&id).await?;
        metadata.close().await?;
        reader.close().await?;
        ensure!(
            env.root_provider.recorded().len() == 2,
            "approval did not issue exactly one continuation"
        );
        Ok(())
    })
    .await
    .context("reopened Plan approval did not settle")
    .and_then(|result| result);
    continuation.release();
    env.finish(result).await
}
fn event_meta(id: &str, active: bool) -> HistoryEventMeta {
    HistoryEventMeta {
        entity_id: id.into(),
        entity_kind: HistoryEntityKind::Text,
        delivery: HistoryDelivery::Foreground,
        state: if active {
            HistoryEntityState::KnownActive {
                status: ChatActiveStatus::Running,
            }
        } else {
            HistoryEntityState::KnownTerminal {
                outcome: ChatTerminalOutcome::Completed,
            }
        },
        started_at: Some(10),
        finished_at: (!active).then_some(20),
        text_channel: Some(ThreadTextChannel::Final),
        single_visibility: None,
        presentation_contract: None,
        source_order: None,
        content_present: Some(true),
        wait: None,
        tool: None,
    }
}

fn single(id: &str, run: RuntimeEpoch, database_id: &str, body: &[u8]) -> HistoryEvent {
    let mut event = HistoryEvent::new(
        id,
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Divider,
        20,
    );
    let meta = event_meta(id, false);
    let source = HistorySource::ForegroundTurn {
        turn_id: "turn-a".into(),
    };
    event.run_id = Some(run.to_string());
    event.attempt_id = Some(uuid::Uuid::new_v4().to_string());
    event.entity_id = Some(id.into());
    event.turn_id = Some("turn-a".into());
    event.source = Some(source);
    event.original = Some(HistoryOriginalInfo {
        query_class: "conversation".into(),
        parent_id: None,
        original_kind: meta.entity_kind,
        tool_name: None,
    });
    let manifest = pack_bodies(
        &mut event,
        vec![PendingBody::new(
            "body",
            HistoryBodyRole::Body,
            Some("text/plain".into()),
            body.to_vec(),
        )],
        database_id,
    )
    .expect("pack test body");
    let envelope = EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type: "text".into(),
        meta,
        data: serde_json::json!({ "channel": "final" }),
        bodies: manifest,
        source_order: None,
        turn_id: Some("turn-a".into()),
        captured_at: None,
    };
    event.payload_schema = "anywork.event/1".into();
    event.payload_json = serde_json::to_string(&envelope).expect("encode test envelope");
    event
}

#[allow(clippy::too_many_arguments)]
fn work_tool_event(
    event_id: &str,
    kind: HistoryEventKind,
    recorded_at: i64,
    run_id: &str,
    turn_id: Option<&str>,
    call_id: &str,
    tool_name: &str,
    entity_id: &str,
    meta: HistoryEventMeta,
    data: serde_json::Value,
    pending_bodies: Vec<PendingBody>,
    database_id: &str,
) -> Result<HistoryEvent> {
    let mut event = HistoryEvent::new(event_id, kind, HistoryTimelineRole::Work, recorded_at);
    event.occurred_at = Some(recorded_at);
    event.run_id = Some(run_id.to_owned());
    event.turn_id = turn_id.map(str::to_owned);
    event.call_id = Some(call_id.to_owned());
    event.entity_id = Some(entity_id.to_owned());
    event.tool_name = Some(tool_name.to_owned());
    event.source = turn_id.map(|turn| HistorySource::ForegroundTurn {
        turn_id: turn.to_owned(),
    });
    let manifest = pack_bodies(&mut event, pending_bodies, database_id)?;
    let envelope = EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type: "tool".into(),
        meta,
        data,
        bodies: manifest,
        source_order: None,
        turn_id: turn_id.map(str::to_owned),
        captured_at: None,
    };
    event.payload_schema = "anywork.event/1".into();
    event.payload_json = serde_json::to_string(&envelope)?;
    Ok(event)
}
#[tokio::test]
async fn ordinary_question_answer_continues_from_current_without_history_reconstruction()
-> Result<()> {
    use pl_provider_fixture::{GUI_QUESTION_HISTORY_PROMPT, RequestMatch};
    use pl_studio_runtime::{InteractionResolution, ThreadWorkspaceMode, UserInputResolution};
    let continuation = pl_provider_fixture::ReplyStage::new();
    let mut steps = pl_provider_fixture::gui_question_history_script();
    // Reuse the exact native scenario; only hold the new model request so its Current can be observed.
    steps
        .iter_mut()
        .find(|step| matches!(step.request, RequestMatch::InteractionAnswers { .. }))
        .context("question answer fixture step")?
        .reply = support::held_reply(&continuation, "question-continued");
    let env = Environment::new(steps, vec![]).await?;
    let result = tokio::time::timeout(support::integration_test_deadline()?, async {
        let started = env
            .start(ThreadWorkspaceMode::Local, GUI_QUESTION_HISTORY_PROMPT)
            .await?;
        let id = started.thread.id;
        support::completed_prompt(&env.runtime, &id, GUI_QUESTION_HISTORY_PROMPT).await?;
        env.runtime.synchronize_thread_observation(&id).await?;
        let reader = env
            .runtime
            .open_current_reader(&id, CURRENT_PROTOCOL_VERSION, current_demand())
            .await?;
        let reference = reader
            .snapshot(current_demand())
            .await?
            .projection
            .interactions
            .context("pending question collection")?;
        let entry = reader
            .page_collection(reference, None, current_demand())
            .await?
            .entries
            .into_iter()
            .next()
            .context("pending question")?;
        let bytes = match entry.payload {
            pl_studio_runtime::CurrentPayloadData::Inline { bytes } => bytes,
            pl_studio_runtime::CurrentPayloadData::Deferred { reference, .. } => {
                read_current_body(&reader, &reference).await?
            }
        };
        let pending: pl_studio_runtime::InteractionRequest = serde_json::from_slice(&bytes)?;
        let answers: UserInputResolution =
            serde_json::from_str(&pl_provider_fixture::gui_question_history_answers_json())?;
        env.runtime
            .resolve_interaction(
                "answer-current-question".into(),
                id.clone(),
                pending.revision,
                pending.interaction_id,
                InteractionResolution::UserInput(answers),
            )
            .await?;
        env.runtime.synchronize_thread_observation(&id).await?;
        reached(&continuation).await?;
        env.runtime.synchronize_thread_observation(&id).await?;
        let input = reader
            .snapshot(current_demand())
            .await?
            .state
            .active_turn
            .and_then(|turn| turn.input_id)
            .context("running answer continuation")?;
        continuation.release();
        support::terminal(&env.runtime, &id, Some(&input)).await?;
        env.runtime.synchronize_thread_observation(&id).await?;
        reader.close().await?;
        Ok(())
    })
    .await
    .context("ordinary question continuation did not settle")
    .and_then(std::convert::identity);
    continuation.release();
    env.finish(result).await
}

async fn raw(path: &Path) -> Result<DatabaseConnection> {
    let path = path.to_path_buf();
    let mut options = sea_orm::ConnectOptions::new("sqlite:");
    options.map_sqlx_sqlite_opts(move |options| {
        options
            .filename(&path)
            .foreign_keys(true)
            .create_if_missing(true)
    });
    Ok(Database::connect(options).await?)
}

fn final_text_reference(projection: &CurrentProjection) -> Option<CurrentContentRef> {
    projection
        .atoms
        .iter()
        .filter(|atom| {
            atom.kind == pl_studio_runtime::ChatAtomKind::Text
                && atom.text_channel == Some(pl_studio_runtime::ThreadTextChannel::Final)
        })
        .flat_map(|atom| atom.contents.iter())
        .find(|content| content.role == pl_studio_runtime::ChatContentRole::Body)
        .map(|content| content.reference.clone())
}

async fn read_current_body(
    reader: &pl_studio_runtime::CurrentReader,
    reference: &CurrentContentRef,
) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    loop {
        let window = reader
            .read_body(
                reference.clone(),
                ContentRange {
                    offset: bytes.len() as u64,
                    max_bytes: 64 * 1024,
                },
            )
            .await?;
        ensure!(window.offset == bytes.len() as u64);
        let finished = window.offset + window.bytes.len() as u64 == window.available_through;
        ensure!(
            finished || !window.bytes.is_empty(),
            "Current body did not advance"
        );
        bytes.extend(window.bytes);
        if finished {
            break;
        }
    }
    Ok(bytes)
}

async fn read_history_body(
    reader: &HistoryReader,
    reference: &HistoryEventBodyRef,
) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    while bytes.len() as u64 != reference.byte_length {
        let window = reader
            .read_body(
                reference.clone(),
                bytes.len() as u64,
                (reference.byte_length - bytes.len() as u64).min(64 * 1024) as u32,
            )
            .await?;
        ensure!(!window.bytes.is_empty(), "history body did not advance");
        bytes.extend(window.bytes);
    }
    Ok(bytes)
}

#[tokio::test(flavor = "current_thread")]
async fn real_prompt_and_saved_stream_are_independent_from_the_later_immutable_history()
-> Result<()> {
    use pl_provider_fixture::ReplyStage;

    let _tracing = tracing::subscriber::set_default(
        tracing_subscriber::fmt()
            .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
            .with_test_writer()
            .with_ansi(false)
            .without_time()
            .finish(),
    );
    let stage = ReplyStage::new();
    let terminal_stage = ReplyStage::new();
    let head = "流".repeat(33_000);
    let deltas = ["中🙂", "1", "2", "3", "4", "5", "6", "7"];
    let streamed_prefix = format!("{head}{}", deltas.concat());
    let tail = "🎉完整终稿";
    let expected = format!("{streamed_prefix}{tail}").into_bytes();
    let mut chunks = vec![head.as_str()];
    chunks.extend(deltas);
    chunks.push(tail);
    let mut frames =
        pl_provider_fixture::responses_text_chunks(&chunks, "current-history", support::MODEL);
    let terminal = frames.split_off(3 + deltas.len());
    let middle = frames.split_off(3);
    let reply = ReplyStage::staged(vec![frames, middle, terminal], &[&stage, &terminal_stage]);
    let mut env = Environment::new(vec![prompt_step("current-history", 0, reply)], vec![]).await?;
    let result = async {
        let thread = env
            .start(
                pl_studio_runtime::ThreadWorkspaceMode::Worktree,
                "current-history",
            )
            .await?;
        let id = thread.thread.id;
        let demand = current_demand();
        let history_demand = HistoryDemand::default();
        let reader = env
            .runtime
            .open_current_reader(&id, CURRENT_PROTOCOL_VERSION, demand)
            .await?;
        let metadata = reader.watch(None, demand).await?;
        let Some(CurrentFrame::Reset { view }) = metadata.next().await? else {
            anyhow::bail!("Current watch did not begin with Reset");
        };
        ensure!(
            view.state.schema_version == pl_studio_runtime::THREAD_SCHEMA_VERSION,
            "Current did not expose the current Thread schema"
        );
        ensure!(
            view.state
                .runtime
                .as_ref()
                .is_none_or(|runtime| runtime.deferred.is_empty()),
            "small runtime snapshot unexpectedly deferred a State field"
        );
        ensure!(
            view.state
                .activity
                .as_ref()
                .is_none_or(|activity| activity.deferred.is_empty()),
            "small activity snapshot unexpectedly deferred a State field"
        );
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
        let reference = reference.unwrap();
        for stale_reference in [
            {
                let mut stale = reference.clone();
                stale.owner_id.push_str(":wrong-owner");
                stale
            },
            {
                let mut stale = reference.clone();
                stale.generation.push_str(":wrong-generation");
                stale
            },
        ] {
            let stale = reader
                .read_body(
                    stale_reference,
                    ContentRange {
                        offset: 0,
                        max_bytes: 1,
                    },
                )
                .await
                .unwrap_err();
            ensure!(
                stale
                    .downcast_ref::<pl_studio_runtime::StudioError>()
                    .and_then(|error| error.reason())
                    == Some("staleCurrentReference"),
                "wrong owner or body generation was accepted"
            );
        }
        let live_view = reader.snapshot(demand).await?;
        ensure!(
            live_view.state.active_turn.as_ref().is_some_and(|turn| {
                turn.input_id.as_deref() == Some("input-current-history")
                    && matches!(turn.state, pl_studio_runtime::TurnState::Running(_))
            }),
            "held provider lost its actual running Turn: {:?}",
            live_view.state.active_turn
        );
        ensure!(
            live_view
                .state
                .runtime
                .as_ref()
                .is_some_and(|runtime| runtime.deferred.is_empty()),
            "live runtime snapshot unexpectedly deferred a State field"
        );
        ensure!(
            live_view
                .state
                .activity
                .as_ref()
                .is_none_or(|activity| activity.deferred.is_empty()),
            "live activity snapshot unexpectedly deferred a State field"
        );
        ensure!(
            live_view.state.thread.status == live_view.projection.logical_status,
            "Current baseline used an older catalog status"
        );
        let r1 = live_view.revision.owner_id;
        let body = reader
            .watch_body(
                reference.clone(),
                ContentRange {
                    offset: 65_530,
                    max_bytes: 40,
                },
            )
            .await?;
        let live_window = body.next().await?.context("live body watch")?;
        ensure!(live_window.offset == 65_530);
        ensure!(live_window.bytes == expected[65_530..65_570]);
        ensure!(
            !live_window.sealed,
            "the held provider attempt was still active"
        );

        let saved_stream_bytes =
            tokio::time::timeout(support::integration_test_deadline()?, async {
                loop {
                    if let Ok(saved) = support::saved(&env.home, &id).await
                        && let Some(call) = saved.current.model_call.as_ref()
                        && let pl_core::thread::current::SavedModelPhase::Streaming { stream } =
                            &call.phase
                    {
                        let stream = pl_model::completion::ModelStreamCurrent::decode(stream)?;
                        if stream.content_parts.iter().any(|part| part.text == head) {
                            return Ok::<_, anyhow::Error>(std::fs::read(
                                saved.root.join("current.json"),
                            )?);
                        }
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(20)).await;
                }
            })
            .await
            .context("periodic Current did not save the held provider prefix")??;
        env.runtime.synchronize_thread_observation(&id).await?;
        let archive = env
            .runtime
            .open_history_reader(&id, HISTORY_PROTOCOL_VERSION)
            .await?;
        let before_deltas = archive.head().await?;
        tracing::debug!(target: "conversation_work", probe = "pure_deltas_begin", deltas = deltas.len());
        stage.release();
        reached(&terminal_stage).await?;
        loop {
            let window = body
                .next()
                .await?
                .context("Current body ended during pure deltas")?;
            ensure!(!window.sealed, "provider terminal was still held");
            if window.available_through == streamed_prefix.len() as u64 {
                break;
            }
        }
        tokio::time::timeout(
            support::integration_test_deadline()?,
            env.runtime.synchronize_thread_observation(&id),
        )
        .await
        .context("history observation did not settle during the pure deltas")??;
        tracing::debug!(target: "conversation_work", probe = "pure_deltas_end");
        ensure!(
            archive.head().await? == before_deltas,
            "pure stream deltas entered immutable History"
        );
        archive.close().await;
        terminal_stage.release();
        let terminal = loop {
            let Some(frame) = metadata.next().await? else {
                anyhow::bail!("Current watch ended before the provider Turn completed");
            };
            if let CurrentFrame::Notification { notification, .. } = frame
                && let pl_studio_runtime::ThreadNotification::TurnCompleted { turn } =
                    notification.notification
            {
                break turn;
            }
        };
        ensure!(terminal.input_id.as_deref() == Some("input-current-history"));
        loop {
            match body.next().await {
                Ok(Some(window)) => {
                    ensure!(window.bytes == expected[65_530..65_570]);
                    if window.sealed {
                        break;
                    }
                }
                Err(error)
                    if error
                        .downcast_ref::<pl_studio_runtime::StudioError>()
                        .is_some_and(|error| error.reason() == Some("staleCurrentReference")) =>
                {
                    break;
                }
                Err(error) => return Err(error),
                Ok(None) => {
                    anyhow::bail!("body watch ended without sealing or retiring the live reference")
                }
            }
        }
        body.close().await?;
        metadata.close().await?;
        reader.close().await?;

        env.runtime.synchronize_thread_observation(&id).await?;
        let saved = support::saved(&env.home, &id).await?;
        ensure!(saved.current.schema_version == pl_core::thread::current::CURRENT_SCHEMA_VERSION);
        ensure!(saved.current.saved_runtime_epoch.to_string() == r1);

        let history = env
            .runtime
            .open_history_reader(&id, HISTORY_PROTOCOL_VERSION)
            .await?;
        let originals = history
            .events_page(
                HistoryEventsQuery::TextOriginals,
                None,
                None,
                history_demand,
            )
            .await?;
        let mut canonical = None;
        let mut durable = None;
        for event in originals.entries {
            if event.payload_schema != "anywork.event/1" {
                continue;
            }
            let envelope = decode_event_envelope(&event)?;
            ensure!(envelope.contract == "anywork.event/1");
            let Some(bytes) = read_event_body_bytes(&history, &event, "body", None).await? else {
                continue;
            };
            if bytes == expected {
                ensure!(canonical.is_none(), "final body was stored more than once");
                durable = envelope
                    .bodies
                    .iter()
                    .find(|entry| entry.key == "body")
                    .and_then(|entry| entry.reference.clone());
                canonical = Some((event.event_id.clone(), envelope));
            }
        }
        let (event_id, envelope) = canonical.context("final text original")?;
        let durable = durable.context("final text body reference")?;
        ensure!(envelope.turn_id.is_some());
        history.close().await;
        let provider_requests = env.root_provider.recorded().len();
        ensure!(provider_requests == 1, "fixture prompt made extra requests");

        env.restart().await?;
        std::fs::write(saved.root.join("current.json"), b"broken current JSON")?;
        let broken_current_history = env
            .runtime
            .open_history_reader(&id, HISTORY_PROTOCOL_VERSION)
            .await?;
        let detail = broken_current_history
            .read_event(event_id.clone(), history_demand)
            .await?;
        ensure!(read_history_body(&broken_current_history, &durable).await? == expected);
        ensure!(detail.event_id == event_id);
        broken_current_history.close().await;
        ensure!(env.root_provider.recorded().len() == provider_requests);

        std::fs::write(saved.root.join("current.json"), &saved_stream_bytes)?;
        env.restart().await?;
        std::fs::write(saved.path, b"broken history; Current must not open it")?;
        tracing::debug!(target: "conversation_work", probe = "current_restore_begin");
        let current = env
            .runtime
            .open_current_reader(&id, CURRENT_PROTOCOL_VERSION, demand)
            .await?;
        let view = current.snapshot(demand).await?;
        ensure!(
            view.revision.owner_id == r1 && !view.projection.execution_present,
            "passive cold reading must retain saved provenance without activating a new Core owner"
        );
        let restored = final_text_reference(&view.projection).context("saved streaming body")?;
        ensure!(
            read_current_body(&current, &restored).await? == head.as_bytes(),
            "cold Current borrowed the later final body from History"
        );
        let stale = current
            .read_body(
                reference,
                ContentRange {
                    offset: 0,
                    max_bytes: 1,
                },
            )
            .await
            .unwrap_err();
        ensure!(
            stale
                .downcast_ref::<pl_studio_runtime::StudioError>()
                .and_then(|error| error.reason())
                == Some("staleCurrentReference")
        );
        current.close().await?;
        tracing::debug!(target: "conversation_work", probe = "current_restore_end");
        ensure!(env.root_provider.recorded().len() == provider_requests);
        Ok(())
    }
    .await;
    stage.release();
    terminal_stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn accepted_and_committed_pages_share_fixed_cuts_and_immutable_body_ranges() -> Result<()> {
    let temp = tempfile::tempdir()?;
    std::fs::write(temp.path().join("current.json"), b"not current JSON")?;
    let store = HistoryStore::open(
        temp.path().join("history.sqlite"),
        "history",
        HistoryLimits::default(),
    )
    .await?;
    let reader = store.reader();
    let run = RuntimeEpoch::new();
    let bytes: Vec<_> = (0..150_002).map(|index| (index % 251) as u8).collect();
    let first = single("first", run, store.database_id(), &bytes);
    store.accept_batch(std::slice::from_ref(&first)).await?;
    let cut = reader.capture().await?;
    let before = reader
        .timeline_page(Some(cut.clone()), None, demand())
        .await?;
    assert_eq!(before.items.len(), 1);
    let body_page = reader.list_bodies("first".into(), None, demand()).await?;
    let body = body_page
        .entries
        .iter()
        .find(|body| body.body_key == "body")
        .unwrap()
        .reference
        .clone();
    assert_eq!(
        reader.read_body(body.clone(), 65_530, 40).await?.bytes,
        bytes[65_530..65_570]
    );
    assert!(matches!(
        reader.read_body(body.clone(), 0, 65_537).await,
        Err(HistoryError::InvalidDemand(_))
    ));
    reader.verify_body(body.clone()).await?;
    let mut invalid = body.clone();
    invalid.owner_event_id = "someone-else".into();
    assert!(matches!(
        reader.read_body(invalid, 0, 1).await,
        Err(HistoryError::InvalidCursor)
    ));
    let changed = HistoryEvent::new(
        "first-status",
        HistoryEventKind::TurnChanged,
        HistoryTimelineRole::Hidden,
        50,
    );
    store
        .accept_batch(&[changed, single("second", run, store.database_id(), b"next")])
        .await?;
    assert_eq!(
        reader
            .timeline_page(Some(cut.clone()), None, demand())
            .await?,
        before
    );
    store.flush().await?;
    assert_eq!(store.status().pending_events, 0);
    assert_eq!(
        reader.timeline_page(Some(cut), None, demand()).await?,
        before
    );
    assert_eq!(
        reader.read_body(body, 149_990, 64).await?.bytes,
        bytes[149_990..]
    );
    let original = reader
        .events_page(
            HistoryEventsQuery::Originals {
                scope: ChatScope::conversation(None),
            },
            None,
            None,
            demand(),
        )
        .await?;
    assert_eq!(original.entries.len(), 2);
    let detail = reader.read_event("first".into(), demand()).await?;
    assert_eq!(decode_event_envelope(&detail)?.item_type, "text");
    assert_eq!(
        read_event_body_bytes(&reader, &detail, "body", None).await?,
        Some(bytes)
    );
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn fixed_main_member_and_turn_pages_survive_terminal_changes_and_rollback() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let store = HistoryStore::open(
        directory.path().join("history.sqlite"),
        "fixed-pages",
        HistoryLimits::default(),
    )
    .await?;
    let reader = store.reader();
    let run = RuntimeEpoch::new();
    let mut member_meta = event_meta("member", true);
    member_meta.entity_kind = HistoryEntityKind::ToolCall;
    member_meta.text_channel = None;
    member_meta.tool = Some(HistoryToolIdentity {
        call_id: "call".into(),
        name: "lookup".into(),
    });
    let member_start = work_tool_event(
        "member-start",
        HistoryEventKind::ToolCalled,
        10,
        &run.to_string(),
        Some("turn-a"),
        "call",
        "lookup",
        "member",
        member_meta.clone(),
        serde_json::json!({
            "invocation": { "toolCallId": "call", "name": "lookup" },
            "state": { "kind": "running" }
        }),
        Vec::new(),
        store.database_id(),
    )?;
    let mut turn = HistoryTurnHead {
        turn_id: "turn-a".into(),
        input_id: Some("input-a".into()),
        run_id: Some(run.to_string()),
        state: HistoryTurnState::Running,
        phase: None,
        context_disposition: pl_studio_runtime::ThreadContextDisposition::Active,
        queued_at: Some(9),
        started_at: Some(10),
        finished_at: None,
        updated_at: 10,
        detail_event_id: None,
    };
    let turn_event = |id: &str, kind: HistoryEventKind, head: HistoryTurnHead, anchor: bool| {
        let mut event = HistoryEvent::new(id, kind, HistoryTimelineRole::Hidden, head.updated_at);
        event.run_id = Some(run.to_string());
        event.turn_id = Some("turn-a".into());
        event.row_scope = Some(HistoryBusinessRowScope::Turn);
        event.row_key = Some("turn:turn-a".into());
        event.is_anchor = anchor;
        event.payload_schema = "anywork.turn/1".into();
        event.payload_json = serde_json::json!({ "head": head }).to_string();
        event
    };
    store
        .accept_batch(&[
            member_start,
            turn_event(
                "turn-start",
                HistoryEventKind::TurnStarted,
                turn.clone(),
                true,
            ),
        ])
        .await?;
    store
        .record_usage(&usage("priced-usage", run, true))
        .await?;
    let cut = reader.capture().await?;
    let main = reader
        .timeline_page(Some(cut.clone()), None, demand())
        .await?;
    assert_eq!(main.items.len(), 1);
    let HistoryTimelineItem::WorkRange(range) = &main.items[0] else {
        panic!("expected open work range");
    };
    let members = reader
        .work_range_page(
            range.after_seq,
            range.before_seq,
            Some(cut.clone()),
            None,
            demand(),
        )
        .await?;
    assert_eq!(members.events.len(), 1);
    let turns = reader.turns_page(Some(cut.clone()), None, demand()).await?;
    let costs = reader.costs_page(Some(cut.clone()), None, demand()).await?;
    let accounting = reader.accounting(Some(cut.clone())).await?;

    member_meta.state = HistoryEntityState::KnownTerminal {
        outcome: ChatTerminalOutcome::Completed,
    };
    member_meta.finished_at = Some(30);
    let member_end = work_tool_event(
        "member-end",
        HistoryEventKind::ToolCompleted,
        30,
        &run.to_string(),
        Some("turn-a"),
        "call",
        "lookup",
        "member",
        member_meta,
        serde_json::json!({
            "invocation": { "toolCallId": "call", "name": "lookup" },
            "state": { "kind": "succeeded" }
        }),
        Vec::new(),
        store.database_id(),
    )?;
    turn.state = HistoryTurnState::Completed;
    turn.finished_at = Some(30);
    turn.updated_at = 30;
    let ended = turn_event("turn-end", HistoryEventKind::TurnEnded, turn.clone(), false);
    turn.context_disposition = pl_studio_runtime::ThreadContextDisposition::RolledBack;
    turn.updated_at = 40;
    store
        .accept_batch(&[
            member_end,
            ended,
            turn_event("rollback", HistoryEventKind::TurnRolledBack, turn, false),
        ])
        .await?;
    store.flush().await?;

    assert_eq!(
        reader
            .timeline_page(Some(cut.clone()), None, demand())
            .await?,
        main
    );
    assert_eq!(
        reader
            .work_range_page(
                range.after_seq,
                range.before_seq,
                Some(cut.clone()),
                None,
                demand(),
            )
            .await?,
        members
    );
    assert_eq!(reader.turns_page(Some(cut), None, demand()).await?, turns);
    let latest_main = reader.timeline_page(None, None, demand()).await?;
    assert_eq!(
        latest_main.items.len(),
        main.items.len(),
        "rollback must not hide Timeline rows"
    );
    let HistoryTimelineItem::WorkRange(latest_range) = &latest_main.items[0] else {
        panic!("expected updated work range");
    };
    assert_ne!(latest_range, range);
    assert_eq!(latest_range.event_count, 2);
    let latest_members = reader
        .work_range_page(
            latest_range.after_seq,
            latest_range.before_seq,
            None,
            None,
            demand(),
        )
        .await?;
    assert_eq!(latest_members.events.len(), 2);
    assert_eq!(
        latest_members.events[1].kind,
        HistoryEventKind::ToolCompleted
    );
    let latest_turns = reader.turns_page(None, None, demand()).await?;
    assert!(matches!(
        &latest_turns.entries[0].head,
        HistoryBusinessRowHead::Turn(head)
            if head.context_disposition == pl_studio_runtime::ThreadContextDisposition::RolledBack
    ));
    assert_eq!(
        reader.costs_page(None, None, demand()).await?.entries,
        costs.entries,
        "rollback must not retract costs"
    );
    assert_eq!(reader.accounting(None).await?, accounting);
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn event_retries_are_exact_and_sql_enforces_immutable_facts() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "immutability", HistoryLimits::default()).await?;
    let event = single(
        "idempotent",
        RuntimeEpoch::new(),
        store.database_id(),
        b"retained",
    );
    let first = store.accept_batch(std::slice::from_ref(&event)).await?;
    assert_eq!(
        store.accept_batch(std::slice::from_ref(&event)).await?,
        first
    );
    let mut inline_conflict = event.clone();
    inline_conflict.payload_json = "{}".into();
    assert!(matches!(
        store.accept_batch(&[inline_conflict.clone()]).await,
        Err(HistoryError::Conflict(_))
    ));
    let big_event = single(
        "idempotent-big",
        RuntimeEpoch::new(),
        store.database_id(),
        &vec![b'x'; 20_000],
    );
    let big_seq = store.accept_batch(std::slice::from_ref(&big_event)).await?;
    let mut big_conflict = big_event.clone();
    big_conflict.bodies[0].bytes = Arc::from(vec![b'y'; 20_000]);
    assert!(matches!(
        store.accept_batch(&[big_conflict.clone()]).await,
        Err(HistoryError::Conflict(_))
    ));
    store.flush().await?;
    assert_eq!(store.accept_batch(&[event]).await?, first);
    assert_eq!(store.accept_batch(&[big_event]).await?, big_seq);
    assert!(matches!(
        store.accept_batch(&[inline_conflict]).await,
        Err(HistoryError::Conflict(_))
    ));
    assert!(matches!(
        store.accept_batch(&[big_conflict]).await,
        Err(HistoryError::Conflict(_))
    ));
    let db = raw(&path).await?;
    for sql in [
        "UPDATE history_events SET recorded_at=0",
        "DELETE FROM history_events",
        "UPDATE history_bodies SET byte_length=0",
        "DELETE FROM history_bodies",
        "UPDATE history_body_chunks SET data=X'00'",
        "DELETE FROM history_body_chunks",
    ] {
        assert!(db.execute_unprepared(sql).await.is_err(), "{sql}");
    }
    db.close().await?;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn failed_transaction_keeps_accepted_facts_and_corrupt_chunks_are_not_eof() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "failure", HistoryLimits::default()).await?;
    let reader = store.reader();
    let db = raw(&path).await?;
    db.execute_unprepared("CREATE TRIGGER reject_test_write BEFORE INSERT ON history_events BEGIN SELECT RAISE(ABORT,'injected database failure'); END;").await?;
    let event = single(
        "retained",
        RuntimeEpoch::new(),
        store.database_id(),
        &b"original".repeat(3000),
    );
    store.accept_batch(&[event]).await?;
    let cut = reader.capture().await?;
    assert!(store.flush().await.is_err());
    assert_eq!(store.status().pending_events, 1);
    assert!(store.status().write_error.is_some());
    assert_eq!(
        reader
            .timeline_page(Some(cut.clone()), None, demand())
            .await?
            .items
            .len(),
        1
    );
    db.execute_unprepared("DROP TRIGGER reject_test_write")
        .await?;
    store.flush().await?;
    assert_eq!(store.status().pending_events, 0);
    assert!(store.status().write_error.is_none());
    assert_eq!(
        reader
            .timeline_page(Some(cut), None, demand())
            .await?
            .items
            .len(),
        1
    );
    let body = reader
        .list_bodies("retained".into(), None, demand())
        .await?
        .entries
        .into_iter()
        .find(|entry| entry.body_key == "body")
        .unwrap()
        .reference;
    db.execute_unprepared("DROP TRIGGER history_body_chunks_no_update")
        .await?;
    db.execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "UPDATE history_body_chunks SET data=? WHERE body_id=?",
        vec![b"modified".to_vec().into(), body.body_id.clone().into()],
    ))
    .await?;
    assert!(matches!(
        reader.read_body(body.clone(), 0, 64).await,
        Err(HistoryError::Integrity(_))
    ));
    assert!(matches!(
        reader.verify_body(body).await,
        Err(HistoryError::Integrity(_))
    ));
    db.close().await?;
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn large_wait_targets_are_preserved_in_a_deferred_body_and_dividers_split_work_ranges()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = HistoryStore::open(
        temp.path().join("h.sqlite"),
        "wait",
        HistoryLimits::default(),
    )
    .await?;
    let run = RuntimeEpoch::new();
    let reader = store.reader();
    let targets = (0..2000)
        .map(|index| {
            pl_studio_runtime::ThreadWaitTarget::new(
                format!("task-{index}"),
                Some("terminal".into()),
                None,
                None,
            )
        })
        .collect();
    let presentation = pl_studio_runtime::ThreadWaitPresentation::new(
        pl_studio_runtime::ThreadWaitIntent::Events {
            targets,
            timeout_ms: 3000,
        },
        pl_studio_runtime::ThreadWaitState::Waiting,
        None,
    );
    let expected = serde_json::to_vec(&presentation)?;
    assert!(expected.len() > INLINE_BODY_MAX_BYTES);
    let mut head = event_meta("wait", true);
    head.entity_kind = HistoryEntityKind::ToolCall;
    head.text_channel = None;
    head.tool = Some(HistoryToolIdentity {
        call_id: "wait-call".into(),
        name: "wait_events".into(),
    });
    let wait_start = work_tool_event(
        "wait-start",
        HistoryEventKind::ToolCalled,
        1,
        &run.to_string(),
        Some("turn-a"),
        "wait-call",
        "wait_events",
        "wait",
        head,
        serde_json::json!({
            "invocation": { "toolCallId": "wait-call", "name": "wait_events" },
            "state": { "kind": "running" }
        }),
        vec![PendingBody::new(
            "wait_presentation",
            HistoryBodyRole::WaitPresentation,
            Some("application/json".into()),
            expected.clone(),
        )],
        store.database_id(),
    )?;
    let separator = single("separator", run, store.database_id(), b"divider");
    store.accept_batch(&[wait_start, separator]).await?;

    let page = reader.timeline_page(None, None, demand()).await?;
    assert_eq!(page.items.len(), 2);
    assert!(matches!(&page.items[0], HistoryTimelineItem::Divider(d) if d.event_id == "separator"));
    let HistoryTimelineItem::WorkRange(range) = &page.items[1] else {
        panic!("expected work range before divider");
    };
    let work = reader
        .work_range_page(
            range.after_seq,
            range.before_seq,
            Some(page.cut.clone()),
            None,
            demand(),
        )
        .await?;
    assert_eq!(work.events.len(), 1);
    let actual = read_event_body_bytes(&reader, &work.events[0], "wait_presentation", None)
        .await?
        .expect("deferred wait body present");
    assert_eq!(actual, expected);

    let invalid = HistoryEvent::new(
        "",
        HistoryEventKind::ToolCalled,
        HistoryTimelineRole::Work,
        3,
    );
    assert!(matches!(
        store.accept_batch(&[invalid]).await,
        Err(HistoryError::InvalidEvent(_))
    ));
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn budgets_and_authenticated_cursors_preserve_the_unreturned_candidate() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = HistoryStore::open(
        temp.path().join("h.sqlite"),
        "pages",
        HistoryLimits::default(),
    )
    .await?;
    let reader = store.reader();
    let run = RuntimeEpoch::new();
    store
        .accept_batch(
            &(0..5)
                .map(|index| single(&format!("row-{index}"), run, store.database_id(), b"body"))
                .collect::<Vec<_>>(),
        )
        .await?;
    let cut = reader.capture().await?;
    let complete = reader
        .timeline_page(Some(cut.clone()), None, demand())
        .await?;
    let exact = reader
        .timeline_page(
            Some(cut.clone()),
            None,
            HistoryDemand {
                max_rows: 64,
                max_bytes: serde_json::to_vec(&complete)?.len() as u32,
            },
        )
        .await?;
    assert_eq!(
        exact, complete,
        "a proven final page must not reserve a phantom cursor"
    );
    let one = reader
        .timeline_page(
            Some(cut.clone()),
            None,
            HistoryDemand {
                max_rows: 1,
                max_bytes: 65_536,
            },
        )
        .await?;
    let budget = serde_json::to_vec(&one)?.len() as u32 + 8;
    let mut next = None;
    let mut ids = Vec::new();
    loop {
        let page = reader
            .timeline_page(
                Some(cut.clone()),
                next.take(),
                HistoryDemand {
                    max_rows: 5,
                    max_bytes: budget,
                },
            )
            .await?;
        assert!(serde_json::to_vec(&page)?.len() <= budget as usize);
        ids.extend(page.items.into_iter().map(|item| match item {
            HistoryTimelineItem::Divider(rec) => rec.event_id,
            HistoryTimelineItem::WorkRange(range) => range.range_id,
        }));
        next = page.next;
        if next.is_none() {
            break;
        }
    }
    assert_eq!(
        ids,
        (0..5)
            .rev()
            .map(|index| format!("row-{index}"))
            .collect::<Vec<_>>()
    );
    assert!(matches!(
        reader
            .timeline_page(
                Some(cut.clone()),
                None,
                HistoryDemand {
                    max_rows: 1,
                    max_bytes: 1
                }
            )
            .await,
        Err(HistoryError::InvalidDemand(_))
    ));
    let token = one.next.unwrap();
    assert!(matches!(
        reader
            .work_range_page(Some(999), None, None, Some(token.clone()), demand())
            .await,
        Err(HistoryError::InvalidCursor)
    ));
    let mut altered = token.into_bytes();
    altered[10] ^= 1;
    assert!(matches!(
        reader
            .timeline_page(None, Some(String::from_utf8(altered).unwrap()), demand())
            .await,
        Err(HistoryError::InvalidCursor)
    ));
    let other_reader = store.reader();
    assert!(matches!(
        other_reader.timeline_page(Some(cut), None, demand()).await,
        Err(HistoryError::InvalidCursor)
    ));
    other_reader.close().await;
    let long_call_id = "c".repeat(14_000);
    let mut long_events = Vec::new();
    for id in ["long-first", "long-second"] {
        let mut event = HistoryEvent::new(
            id,
            HistoryEventKind::ToolCalled,
            HistoryTimelineRole::Work,
            1,
        );
        event.call_id = Some(long_call_id.clone());
        long_events.push(event);
    }
    store.accept_batch(&long_events).await?;
    let query = HistoryEventsQuery::Call {
        call_id: long_call_id,
    };
    let request = HistoryDemand {
        max_rows: 1,
        max_bytes: 1_048_576,
    };
    let first = reader
        .events_page(query.clone(), None, None, request)
        .await?;
    let next = first
        .next
        .expect("full long-identity page must have a cursor");
    assert!(next.len() > 16 * 1024);
    let second = reader.events_page(query, None, Some(next), request).await?;
    assert_eq!(second.entries[0].event_id, "long-first");
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn atomic_tool_stages_across_divider_keep_call_id_and_work_ranges() -> Result<()> {
    for (outcome, observed_output) in [
        (
            ChatTerminalOutcome::Completed,
            b"completely different final".as_slice(),
        ),
        (
            ChatTerminalOutcome::Cancelled,
            b"interrupted prefix without a final result".as_slice(),
        ),
    ] {
        let temp = tempfile::tempdir()?;
        let store = HistoryStore::open(
            temp.path().join("h.sqlite"),
            "groups",
            HistoryLimits::default(),
        )
        .await?;
        let run = RuntimeEpoch::new();
        let reader = store.reader();
        let mut tool_meta = event_meta("tool", true);
        tool_meta.entity_kind = HistoryEntityKind::ToolCall;
        tool_meta.text_channel = None;
        tool_meta.tool = Some(HistoryToolIdentity {
            call_id: "attempt-scoped-call".into(),
            name: "terminal".into(),
        });
        let start = work_tool_event(
            "tool-start",
            HistoryEventKind::ToolCalled,
            10_000,
            &run.to_string(),
            Some("turn-a"),
            "attempt-scoped-call",
            "terminal",
            "tool",
            tool_meta.clone(),
            serde_json::json!({
                "invocation": { "toolCallId": "attempt-scoped-call", "name": "terminal" },
                "state": { "kind": "running" }
            }),
            Vec::new(),
            store.database_id(),
        )?;
        store.accept_batch(&[start]).await?;
        assert_eq!(
            reader
                .events_page(
                    HistoryEventsQuery::Turn {
                        turn_id: "turn-a".into()
                    },
                    None,
                    None,
                    demand()
                )
                .await?
                .entries[0]
                .event_id,
            "tool-start"
        );

        let divider = single("text", run, store.database_id(), b"visible text");
        store.accept_batch(&[divider]).await?;
        let old_cut = reader.capture().await?;

        tool_meta.state = HistoryEntityState::KnownTerminal { outcome };
        tool_meta.finished_at = Some(15_000);
        let end = work_tool_event(
            "tool-end",
            HistoryEventKind::ToolCompleted,
            15_000,
            &run.to_string(),
            Some("turn-a"),
            "attempt-scoped-call",
            "terminal",
            "tool",
            tool_meta,
            serde_json::json!({
                "invocation": { "toolCallId": "attempt-scoped-call", "name": "terminal" },
                "state": { "kind": if outcome == ChatTerminalOutcome::Completed { "succeeded" } else { "cancelled" } }
            }),
            vec![PendingBody::new(
                "observed-output",
                HistoryBodyRole::ToolOutput,
                Some("text/plain".into()),
                observed_output.to_vec(),
            )],
            store.database_id(),
        )?;
        store.accept_batch(&[end]).await?;
        store.flush().await?;

        let timeline = reader.timeline_page(None, None, demand()).await?;
        assert_eq!(timeline.items.len(), 3);
        let HistoryTimelineItem::WorkRange(new_range) = &timeline.items[0] else {
            panic!("expected new tail work range");
        };
        let HistoryTimelineItem::Divider(div) = &timeline.items[1] else {
            panic!("expected middle divider");
        };
        assert_eq!(div.event_id, "text");
        let HistoryTimelineItem::WorkRange(old_range) = &timeline.items[2] else {
            panic!("expected earlier work range");
        };

        let old_work = reader
            .work_range_page(
                old_range.after_seq,
                old_range.before_seq,
                Some(timeline.cut.clone()),
                None,
                demand(),
            )
            .await?;
        assert_eq!(old_work.events.len(), 1);
        assert_eq!(old_work.events[0].event_id, "tool-start");

        let new_work = reader
            .work_range_page(
                new_range.after_seq,
                new_range.before_seq,
                Some(timeline.cut.clone()),
                None,
                demand(),
            )
            .await?;
        assert_eq!(new_work.events.len(), 1);
        assert_eq!(new_work.events[0].event_id, "tool-end");
        assert_eq!(
            read_event_body_bytes(&reader, &new_work.events[0], "observed-output", None).await?,
            Some(observed_output.to_vec())
        );

        let by_call = reader
            .events_page(
                HistoryEventsQuery::Call {
                    call_id: "attempt-scoped-call".into(),
                },
                None,
                None,
                demand(),
            )
            .await?;
        assert_eq!(
            by_call
                .entries
                .iter()
                .map(|e| e.event_id.as_str())
                .collect::<Vec<_>>(),
            vec!["tool-end", "tool-start"]
        );

        assert_eq!(
            reader
                .timeline_page(Some(old_cut), None, demand())
                .await?
                .items
                .len(),
            2
        );
        reader.close().await;
        store.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn source_composite_identity_and_close_do_not_share_query_consumption() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("h.sqlite");
    let store = HistoryStore::open(&path, "queries", HistoryLimits::default()).await?;
    let reader = store.reader();
    let after = reader.capture().await?;
    let waiting = reader.clone();
    let task = tokio::spawn(async move { waiting.wait_changed(after).await });
    let run = RuntimeEpoch::new();
    let mut events = Vec::new();
    for source in ["a", "b"] {
        let mut event = single(source, run, store.database_id(), b"data");
        let source = HistorySource::InboxMessage {
            source_id: source.into(),
            message_id: "same-message".into(),
        };
        event.source = Some(source);
        events.push(event);
    }
    store.accept_batch(&events).await?;
    let cut = task.await.unwrap()?;
    let page = reader
        .events_page(
            HistoryEventsQuery::Source {
                source: HistorySource::InboxMessage {
                    source_id: "a".into(),
                    message_id: "same-message".into(),
                },
            },
            Some(cut.clone()),
            None,
            demand(),
        )
        .await?;
    assert_eq!(page.entries.len(), 1);
    assert_eq!(page.entries[0].event_id, "a");
    let old_cut = cut.clone();
    let waiter = reader.clone();
    let pending = tokio::spawn(async move { waiter.wait_changed(cut).await });
    reader.close().await;
    assert!(matches!(pending.await.unwrap(), Err(HistoryError::Closed)));
    assert_eq!(
        store
            .reader()
            .timeline_page(None, None, demand())
            .await?
            .items
            .len(),
        2
    );
    store.close().await?;
    // A newly opened owner and reader reject old signed cuts.
    let reopened = HistoryStore::open(&path, "queries", HistoryLimits::default()).await?;
    let new_reader = reopened.reader();
    assert_eq!(
        new_reader
            .timeline_page(None, None, demand())
            .await?
            .items
            .len(),
        2
    );
    assert!(matches!(
        new_reader
            .timeline_page(Some(old_cut), None, demand())
            .await,
        Err(HistoryError::InvalidCursor)
    ));
    new_reader.close().await;
    reopened.close().await?;
    Ok(())
}

fn usage(id: &str, run: RuntimeEpoch, priced: bool) -> HistoryUsageFact {
    let accounting = pl_studio_runtime::InferenceAccounting {
        usage: pl_studio_runtime::UsageReport {
            input_tokens: Some(100),
            output_tokens: Some(20),
            cache_read_tokens: Some(40),
            cache_write_tokens: Some(0),
            reasoning_tokens: Some(3),
            total_tokens: Some(120),
        },
        pricing: if priced {
            pl_studio_runtime::PricingOutcome::Estimated {
                cost: RuntimeCostAmount {
                    currency: "CNY".into(),
                    amount: 0.25,
                },
                cache_savings: Some(RuntimeCostAmount {
                    currency: "CNY".into(),
                    amount: 0.1,
                }),
            }
        } else {
            pl_studio_runtime::PricingOutcome::default()
        },
        ..Default::default()
    };
    HistoryUsageFact { event_id: id.into(), runtime_epoch: run, turn_id: Some("turn-a".into()), outcome: pl_core::usage::UsageOutcome::Succeeded,
        record: serde_json::from_value(serde_json::json!({"inferenceId":id,"purpose":null,"accounting":accounting,"recordedAt":20})).unwrap() }
}
#[tokio::test]
async fn usage_is_folded_once_and_unknown_cost_or_cache_baselines_stay_unknown() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = HistoryStore::open(
        temp.path().join("h.sqlite"),
        "usage",
        HistoryLimits::default(),
    )
    .await?;
    let reader = store.reader();
    let run = RuntimeEpoch::new();
    let first = usage("usage-a", run, false);
    let first_seq = store.record_usage(&first).await?;
    assert_eq!(store.record_usage(&first).await?, first_seq);
    let old = reader.capture().await?;
    store.record_usage(&usage("usage-b", run, true)).await?;
    let totals = reader.accounting(None).await?.unwrap();
    assert_eq!(totals.inference_count, 2);
    assert_eq!(totals.total_tokens, 240);
    assert_eq!(totals.updated_at, 20_000);
    assert!(totals.has_unpriced_usage);
    assert_eq!(
        reader.accounting(Some(old)).await?.unwrap().inference_count,
        1
    );
    let costs = reader.costs_page(None, None, demand()).await?;
    assert_eq!(costs.entries.len(), 1);
    let HistoryBusinessRowHead::Cost(cost) = &costs.entries[0].head else {
        panic!("cost")
    };
    assert_eq!(cost.cost_total, 0.25);
    assert_eq!(cost.updated_at, 20_000);
    let original_usage = reader.read_event("usage-a".into(), demand()).await?;
    assert_eq!(original_usage.recorded_at, 20_000);
    let raw_usage = read_event_body_bytes(&reader, &original_usage, "accounting", Some(65_536))
        .await?
        .expect("usage business fact payload");
    assert_eq!(
        serde_json::from_slice::<pl_studio_runtime::InferenceBillingRecord>(&raw_usage)?
            .recorded_at,
        20
    );
    let before_overflow = reader.capture().await?;
    let mut invalid_usage = usage("overflow", run, false);
    invalid_usage.record.recorded_at = i64::MAX;
    assert!(matches!(
        store.record_usage(&invalid_usage).await,
        Err(HistoryError::InvalidEvent(_))
    ));
    assert_eq!(reader.capture().await?, before_overflow);
    let events = reader
        .events_page(HistoryEventsQuery::AllEvents, None, None, demand())
        .await?;
    assert_eq!(
        events
            .entries
            .iter()
            .filter(|event| {
                event.kind == HistoryEventKind::UsageRecorded
                    && event.row_scope == Some(HistoryBusinessRowScope::Accounting)
            })
            .count(),
        2
    );
    store.flush().await?;
    assert_eq!(
        store.record_usage(&usage("usage-b", run, true)).await?,
        events
            .entries
            .iter()
            .find(|event| event.event_id == "usage-b")
            .unwrap()
            .seq
    );
    assert_eq!(reader.accounting(None).await?.unwrap().inference_count, 2);
    reader.close().await;
    store.close().await?;
    assert!(matches!(
        store.record_usage(&first).await,
        Err(HistoryError::Closed)
    ));
    Ok(())
}

#[tokio::test]
async fn schema25_upgrade_preserves_backup_and_large_body_bytes_without_copying_chunks()
-> Result<()> {
    use sea_orm::TransactionTrait;
    use sha2::Digest;

    let temp = tempfile::tempdir()?;
    let source_path = temp.path().join("v25.sqlite");
    let source_db = raw(&source_path).await?;
    source_db
        .execute_unprepared(include_str!("../src/history/upgrade/schema_v25.sql"))
        .await?;
    source_db
        .execute_unprepared(
            "CREATE TABLE IF NOT EXISTS seaql_migrations (version TEXT PRIMARY KEY NOT NULL, applied_at INTEGER NOT NULL);\
             INSERT INTO seaql_migrations(version, applied_at) VALUES('m20261116_000001_append_only_history', 1);",
        )
        .await?;
    let database_id = uuid::Uuid::new_v4().to_string();
    let body_id = uuid::Uuid::new_v4().to_string();
    let payload = b"preserved binary original".repeat(7000);
    let digest = sha2::Sha256::digest(&payload).to_vec();

    let tx = source_db.begin().await?;
    tx.execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "INSERT INTO history_store_meta(singleton,schema_version,database_id,thread_id) VALUES(1,25,?,'import')",
        vec![database_id.clone().into()],
    ))
    .await?;
    tx.execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "INSERT INTO history_bodies(body_id,owner_event_id,ordinal,body_key,role,byte_length,media_type,digest) VALUES(?,'original',0,'body','body',?,'application/octet-stream',?)",
        vec![
            body_id.clone().into(),
            (payload.len() as i64).into(),
            digest.into(),
        ],
    ))
    .await?;
    for (chunk_no, chunk) in payload.chunks(BODY_CHUNK_BYTES).enumerate() {
        tx.execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "INSERT INTO history_body_chunks(body_id,chunk_no,data) VALUES(?,?,?)",
            vec![
                body_id.clone().into(),
                (chunk_no as i64).into(),
                chunk.to_vec().into(),
            ],
        ))
        .await?;
    }
    tx.execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "INSERT INTO history_events(seq,event_id,kind,entity_id,is_anchor,recorded_at) VALUES(1,'original','legacy_observed','original',0,20)",
        vec![],
    ))
    .await?;
    tx.commit().await?;
    source_db.close().await?;

    let report = upgrade_history(&source_path, "import", temp.path()).await?;
    assert_eq!(report.status, UpgradeStatus::Upgraded);
    let backup = report.backup.as_ref().expect("v25 backup path");
    assert!(backup.starts_with(temp.path()));
    assert_eq!(
        backup.file_name().and_then(|name| name.to_str()),
        Some("history.v25.sqlite")
    );
    let backup_db = raw(backup).await?;
    let meta = backup_db
        .query_one_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "SELECT schema_version, database_id, thread_id FROM history_store_meta WHERE singleton = 1",
            vec![],
        ))
        .await?
        .expect("v25 backup meta row");
    assert_eq!(meta.try_get::<i64>("", "schema_version")?, 25);
    assert_eq!(meta.try_get::<String>("", "database_id")?, database_id);
    assert_eq!(meta.try_get::<String>("", "thread_id")?, "import");
    let event_count = backup_db
        .query_one_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "SELECT COUNT(*) AS c FROM history_events WHERE event_id = 'original'",
            vec![],
        ))
        .await?
        .expect("v25 backup event count");
    assert_eq!(event_count.try_get::<i64>("", "c")?, 1);
    let chunks = backup_db
        .query_all_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "SELECT data FROM history_body_chunks WHERE body_id = ? ORDER BY chunk_no ASC",
            vec![body_id.clone().into()],
        ))
        .await?;
    let mut backup_payload = Vec::new();
    for row in chunks {
        backup_payload.extend(row.try_get::<Vec<u8>>("", "data")?);
    }
    assert_eq!(backup_payload, payload);
    backup_db.close().await?;

    let reopened = HistoryStore::open(&source_path, "import", HistoryLimits::default()).await?;
    let reader = reopened.reader();
    let event = reader.read_event("original".into(), demand()).await?;
    let bodies = reader
        .list_bodies("original".into(), None, demand())
        .await?;
    let reference = bodies
        .entries
        .into_iter()
        .find(|entry| entry.role == HistoryBodyRole::Body)
        .expect("migrated large body")
        .reference;
    assert_eq!(reference.body_id, body_id);
    reader.verify_body(reference.clone()).await?;
    let mut actual = Vec::new();
    while actual.len() < payload.len() {
        actual.extend(
            reader
                .read_body(reference.clone(), actual.len() as u64, 65_536)
                .await?
                .bytes,
        );
    }
    assert_eq!(actual, payload);
    assert_eq!(event.event_id, "original");
    reader.close().await;
    reopened.close().await?;
    Ok(())
}

#[tokio::test]
async fn restarted_current_keeps_owner_work_and_live_admission_independent_of_saved_json()
-> Result<()> {
    use pl_provider_fixture::{Reply, ReplyStage};
    use pl_studio_runtime::{StudioPromptInput, SubmitPromptRequest, ThreadWorkspaceMode};
    let first_stage = ReplyStage::new();
    let second_stage = ReplyStage::new();
    let staged = |name: &str, stage: &ReplyStage| -> Result<Reply> {
        let mut frames = pl_provider_fixture::responses_reasoning_text(
            &["original reasoning"],
            &["original output"],
            name,
            support::MODEL,
        );
        let delta = frames
            .iter()
            .position(|frame| frame["type"] == "response.output_text.delta")
            .context("fixture output delta")?;
        let after = frames.split_off(delta + 1);
        Ok(stage.gated(frames, after))
    };
    let mut env = Environment::new(
        vec![
            prompt_step("restart-r1", 0, staged("r1", &first_stage)?),
            prompt_step("restart-r2", 1, staged("r2", &second_stage)?),
            prompt_step("restart-r3", 2, support::text_reply("third output", "r3")),
        ],
        vec![],
    )
    .await?;
    let result = tokio::time::timeout(support::integration_test_deadline()?, async {
        let started = env.start(ThreadWorkspaceMode::Local, "restart-r1").await?;
        let id = &started.thread.id;
        let old = env
            .runtime
            .open_current_reader(id, CURRENT_PROTOCOL_VERSION, current_demand())
            .await?;
        let old_watch = old.watch(None, current_demand()).await?;
        reached(&first_stage).await?;
        let reference = loop {
            let projection = match old_watch
                .next()
                .await?
                .context("original Current watch ended")?
            {
                CurrentFrame::Reset { view } => view.projection,
                CurrentFrame::Projection { projection, .. } => *projection,
                CurrentFrame::Notification { .. } => continue,
            };
            if let Some(reference) = final_text_reference(&projection) {
                break reference;
            }
        };
        let r1 = old.snapshot(current_demand()).await?.revision.owner_id;
        ensure!(reference.owner_id == r1);
        ensure!(read_current_body(&old, &reference).await? == b"original output");
        first_stage.release();
        support::completed_prompt(&env.runtime, id, "restart-r1").await?;
        env.restart().await?;
        let saved = support::saved(&env.home, id).await?;
        ensure!(
            old_watch.next().await?.is_none(),
            "retired owner still delivered metadata"
        );
        old_watch.close().await?;
        old.close().await?;
        let current = env
            .runtime
            .open_current_reader(id, CURRENT_PROTOCOL_VERSION, current_demand())
            .await?;
        let paused = current.snapshot(current_demand()).await?;
        ensure!(paused.revision.owner_id == r1 && !paused.projection.execution_present);
        ensure!(
            !paused.projection.atoms.iter().any(|atom| matches!(
                atom.kind,
                pl_studio_runtime::ChatAtomKind::Text | pl_studio_runtime::ChatAtomKind::Reasoning
            )),
            "cold Current replayed completed history"
        );
        ensure!(env.root_provider.recorded().len() == 1);
        let history = env
            .runtime
            .open_history_reader(id, HISTORY_PROTOCOL_VERSION)
            .await?;
        let old_cut = history.capture().await?;
        let old_page = history
            .timeline_page(Some(old_cut.clone()), None, demand())
            .await?;
        let old_range = old_page
            .items
            .iter()
            .find_map(|item| match item {
                HistoryTimelineItem::WorkRange(range)
                    if range.run_id.as_deref() == Some(r1.as_str()) =>
                {
                    Some(range.clone())
                }
                _ => None,
            })
            .context("original R1 work range")?;
        let old_members = history
            .work_range_page(
                old_range.after_seq,
                old_range.before_seq,
                Some(old_cut.clone()),
                None,
                demand(),
            )
            .await?;
        let route = paused.state.model_route.context("saved route")?.revision;
        env.runtime
            .submit_prompt_command(
                id.clone(),
                SubmitPromptRequest {
                    input: StudioPromptInput {
                        input_id: "input-restart-r2".into(),
                        text: "restart-r2".into(),
                        attachment_draft_ids: Vec::new(),
                    },
                    expected_model_route_revision: route,
                },
            )
            .await?;
        reached(&second_stage).await?;
        let running = current.snapshot(current_demand()).await?;
        let r2 = running.revision.owner_id;
        ensure!(
            r2 != r1 && running.projection.execution_present,
            "new execution reused the saved owner or remained paused"
        );
        ensure!(running.state.thread.status == running.projection.logical_status);
        let stale = current
            .read_body(
                reference,
                ContentRange {
                    offset: 0,
                    max_bytes: 1,
                },
            )
            .await
            .unwrap_err();
        ensure!(
            stale
                .downcast_ref::<pl_studio_runtime::StudioError>()
                .and_then(|error| error.reason())
                == Some("staleCurrentReference"),
            "old owner reference was accepted by R2"
        );
        let mut cut = history.capture().await?;
        loop {
            let page = history
                .timeline_page(Some(cut.clone()), None, demand())
                .await?;
            if let Some(range) = page.items.iter().find_map(|item| match item {
                HistoryTimelineItem::WorkRange(range)
                    if range.run_id.as_deref() == Some(r2.as_str()) =>
                {
                    Some(range)
                }
                _ => None,
            }) {
                ensure!(
                    range.range_id != old_range.range_id,
                    "R2 extended the saved R1 range"
                );
                break;
            }
            cut = history.wait_changed(cut).await?;
        }
        ensure!(
            history
                .timeline_page(Some(old_cut.clone()), None, demand())
                .await?
                == old_page
        );
        ensure!(
            history
                .work_range_page(
                    old_range.after_seq,
                    old_range.before_seq,
                    Some(old_cut),
                    None,
                    demand(),
                )
                .await?
                == old_members
        );
        ensure!(
            history
                .work_range_page(
                    old_range.after_seq,
                    old_range.before_seq,
                    None,
                    None,
                    demand(),
                )
                .await?
                .events
                == old_members.events,
            "R2 changed the original R1 members"
        );
        second_stage.release();
        support::completed_prompt(&env.runtime, id, "restart-r2").await?;
        // Direct overwrite can make the saved JSON unreadable. A directory holds that
        // condition deterministically even if the periodic writer runs during admission.
        let path = saved.root.join("current.json");
        let bytes = std::fs::read(&path)?;
        std::fs::remove_file(&path)?;
        std::fs::create_dir(&path)?;
        let submitted = env
            .runtime
            .submit_prompt_command(
                id.clone(),
                SubmitPromptRequest {
                    input: StudioPromptInput {
                        input_id: "input-restart-r3".into(),
                        text: "restart-r3".into(),
                        attachment_draft_ids: Vec::new(),
                    },
                    expected_model_route_revision: route,
                },
            )
            .await;
        std::fs::remove_dir(&path)?;
        std::fs::write(&path, bytes)?;
        history.close().await;
        current.close().await?;
        submitted.context("live admission read the saved Current")?;
        support::completed_prompt(&env.runtime, id, "restart-r3").await?;
        ensure!(env.root_provider.recorded().len() == 3);
        Ok(())
    })
    .await
    .context("restart owner integration watchdog")
    .and_then(std::convert::identity);
    first_stage.release();
    second_stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn schema26_index_derived_timeline_and_work_range_ascending_pagination() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let store = HistoryStore::open(
        dir.path().join("timeline.sqlite"),
        "schema26-timeline",
        HistoryLimits::default(),
    )
    .await?;
    let reader = store.reader();
    let run = RuntimeEpoch::new();
    let db_id = store.database_id().to_owned();

    let make_work = |id: &str, ts: i64, call_id: &str| -> Result<HistoryEvent> {
        let mut meta = event_meta(id, false);
        meta.entity_kind = HistoryEntityKind::ToolCall;
        meta.text_channel = None;
        meta.tool = Some(HistoryToolIdentity {
            call_id: call_id.into(),
            name: "exec".into(),
        });
        work_tool_event(
            id,
            HistoryEventKind::ToolCalled,
            ts,
            &run.to_string(),
            Some("turn-1"),
            call_id,
            "exec",
            &format!("tool:{call_id}"),
            meta,
            serde_json::json!({
                "invocation": { "toolCallId": call_id, "name": "exec" },
                "state": { "kind": "running" }
            }),
            Vec::new(),
            &db_id,
        )
    };

    let seqs = store
        .accept_batch(&[
            make_work("w1", 10, "c1")?,
            make_work("w2", 20, "c2")?,
            single("d1", run, &db_id, b"divider 1"),
            make_work("w3", 30, "c3")?,
            make_work("w4", 40, "c4")?,
            single("d2", run, &db_id, b"divider 2"),
            make_work("w5", 50, "c5")?,
        ])
        .await?;
    assert_eq!(seqs, vec![1, 2, 3, 4, 5, 6, 7]);
    store.flush().await?;

    let timeline = reader.timeline_page(None, None, demand()).await?;
    assert_eq!(timeline.items.len(), 5);
    assert!(matches!(
        &timeline.items[0],
        HistoryTimelineItem::WorkRange(r)
            if r.after_seq == Some(6) && r.before_seq.is_none() && r.first_seq == 7 && r.last_seq == 7 && r.event_count == 1
    ));
    assert!(matches!(&timeline.items[1], HistoryTimelineItem::Divider(d) if d.event_id == "d2"));
    let HistoryTimelineItem::WorkRange(mid) = &timeline.items[2] else {
        panic!("expected middle work range");
    };
    assert_eq!(mid.after_seq, Some(3));
    assert_eq!(mid.before_seq, Some(6));
    assert_eq!(mid.first_seq, 4);
    assert_eq!(mid.last_seq, 5);
    assert_eq!(mid.event_count, 2);
    assert!(matches!(&timeline.items[3], HistoryTimelineItem::Divider(d) if d.event_id == "d1"));
    assert!(matches!(
        &timeline.items[4],
        HistoryTimelineItem::WorkRange(r)
            if r.after_seq.is_none() && r.before_seq == Some(3) && r.first_seq == 1 && r.last_seq == 2 && r.event_count == 2
    ));

    // Paginate middle work range with max_rows = 1 -> strictly ascending seq 4 then seq 5
    let one_row = HistoryDemand {
        max_rows: 1,
        max_bytes: 128 * 1024,
    };
    let page1 = reader
        .work_range_page(
            mid.after_seq,
            mid.before_seq,
            Some(timeline.cut.clone()),
            None,
            one_row,
        )
        .await?;
    assert_eq!(page1.events.len(), 1);
    assert_eq!(page1.events[0].event_id, "w3");
    assert_eq!(page1.events[0].seq, 4);
    let page2 = reader
        .work_range_page(
            mid.after_seq,
            mid.before_seq,
            Some(timeline.cut),
            page1.next,
            one_row,
        )
        .await?;
    assert_eq!(page2.events.len(), 1);
    assert_eq!(page2.events[0].event_id, "w4");
    assert_eq!(page2.events[0].seq, 5);
    assert!(page2.next.is_none());

    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn schema26_hybrid_16k_inline_vs_blob_and_attachment_boundaries() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("hybrid16k.sqlite");
    let store = HistoryStore::open(&path, "hybrid16k", HistoryLimits::default()).await?;
    let reader = store.reader();
    let run = RuntimeEpoch::new();
    let db_id = store.database_id().to_owned();

    // 1. Exact 16_384 UTF-8 bytes -> inlined with 0 history_bodies rows
    let exact_16k = vec![b'a'; INLINE_BODY_MAX_BYTES];
    let ev_inline = single("inline-16k", run, &db_id, &exact_16k);
    assert!(ev_inline.bodies.is_empty());

    // 2. 16_385 UTF-8 bytes -> spilled to history_bodies
    let over_16k = vec![b'b'; INLINE_BODY_MAX_BYTES + 1];
    let ev_blob = single("blob-16k-plus-1", run, &db_id, &over_16k);
    assert_eq!(ev_blob.bodies.len(), 1);

    // 3. Per-event inline sum overflow: two 10_000-byte UTF-8 bodies -> 1st inline, 2nd BLOB
    let mut ev_overflow = HistoryEvent::new(
        "overflow-event",
        HistoryEventKind::ToolCompleted,
        HistoryTimelineRole::Work,
        30,
    );
    let part1 = vec![b'1'; 10_000];
    let part2 = vec![b'2'; 10_000];
    let manifest_overflow = pack_bodies(
        &mut ev_overflow,
        vec![
            PendingBody::new("part1", HistoryBodyRole::ToolArguments, None, part1.clone()),
            PendingBody::new("part2", HistoryBodyRole::ToolOutput, None, part2.clone()),
        ],
        &db_id,
    )?;
    assert_eq!(ev_overflow.bodies.len(), 1);
    assert!(manifest_overflow[0].inline_text.is_some());
    assert!(manifest_overflow[0].reference.is_none());
    assert!(manifest_overflow[1].inline_text.is_none());
    assert!(manifest_overflow[1].reference.is_some());
    ev_overflow.payload_schema = "anywork.event/1".into();
    ev_overflow.payload_json = serde_json::to_string(&EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type: "tool".into(),
        meta: event_meta("overflow-tool", false),
        data: serde_json::json!({}),
        bodies: manifest_overflow,
        source_order: None,
        turn_id: None,
        captured_at: None,
    })?;

    // 4. Attachment & non-UTF-8 binary under 16 KiB -> NEVER inlined
    let mut ev_binary = HistoryEvent::new(
        "binary-attach",
        HistoryEventKind::ItemRecorded,
        HistoryTimelineRole::Work,
        40,
    );
    let attach_bytes = b"small attachment".to_vec();
    let non_utf8 = vec![0xff, 0xfe, 0x00, 0x80];
    let manifest_bin = pack_bodies(
        &mut ev_binary,
        vec![
            PendingBody::new(
                "att",
                HistoryBodyRole::Attachment,
                None,
                attach_bytes.clone(),
            ),
            PendingBody::new("bin", HistoryBodyRole::ToolOutput, None, non_utf8.clone()),
        ],
        &db_id,
    )?;
    assert_eq!(ev_binary.bodies.len(), 2);
    assert!(
        manifest_bin
            .iter()
            .all(|b| b.inline_text.is_none() && b.reference.is_some())
    );
    ev_binary.payload_schema = "anywork.event/1".into();
    ev_binary.payload_json = serde_json::to_string(&EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type: "tool".into(),
        meta: event_meta("binary-tool", false),
        data: serde_json::json!({}),
        bodies: manifest_bin,
        source_order: None,
        turn_id: None,
        captured_at: None,
    })?;

    store
        .accept_batch(&[ev_inline, ev_blob, ev_overflow, ev_binary])
        .await?;
    store.flush().await?;

    let rec_inline = reader.read_event("inline-16k".into(), demand()).await?;
    assert_eq!(
        read_event_body_bytes(&reader, &rec_inline, "body", None).await?,
        Some(exact_16k)
    );
    assert!(
        reader
            .list_bodies("inline-16k".into(), None, demand())
            .await?
            .entries
            .is_empty()
    );

    let rec_blob = reader
        .read_event("blob-16k-plus-1".into(), demand())
        .await?;
    assert_eq!(
        read_event_body_bytes(&reader, &rec_blob, "body", None).await?,
        Some(over_16k)
    );

    let rec_overflow = reader.read_event("overflow-event".into(), demand()).await?;
    assert_eq!(
        read_event_body_bytes(&reader, &rec_overflow, "part1", None).await?,
        Some(part1)
    );
    assert_eq!(
        read_event_body_bytes(&reader, &rec_overflow, "part2", None).await?,
        Some(part2)
    );

    let rec_bin = reader.read_event("binary-attach".into(), demand()).await?;
    assert_eq!(
        read_event_body_bytes(&reader, &rec_bin, "att", None).await?,
        Some(attach_bytes)
    );
    assert_eq!(
        read_event_body_bytes(&reader, &rec_bin, "bin", None).await?,
        Some(non_utf8)
    );

    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn schema26_open_kind_and_unknown_payload_schema_round_trip() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let store = HistoryStore::open(
        dir.path().join("open.sqlite"),
        "open-schema",
        HistoryLimits::default(),
    )
    .await?;
    let reader = store.reader();
    let mut future = HistoryEvent::new(
        "future-ev-1",
        HistoryEventKind::Other("future_tool_event".into()),
        HistoryTimelineRole::Work,
        99_000,
    );
    future.call_id = Some("call-future-1".into());
    future.tool_name = Some("brand_new_tool".into());
    future.payload_schema = "anywork.future/9".into();
    future.payload_json = r#"{"futureField":[1,2,3],"nested":{"ok":true}}"#.into();

    store.accept_batch(&[future]).await?;
    store.flush().await?;

    let timeline = reader.timeline_page(None, None, demand()).await?;
    assert_eq!(timeline.items.len(), 1);
    let HistoryTimelineItem::WorkRange(range) = &timeline.items[0] else {
        panic!("expected work range for open kind");
    };
    let work = reader
        .work_range_page(range.after_seq, range.before_seq, None, None, demand())
        .await?;
    assert_eq!(work.events.len(), 1);
    assert_eq!(
        work.events[0].kind,
        HistoryEventKind::Other("future_tool_event".into())
    );
    assert_eq!(work.events[0].payload_schema, "anywork.future/9");
    let raw: serde_json::Value = serde_json::from_str(&work.events[0].payload_json)?;
    assert_eq!(raw["futureField"], serde_json::json!([1, 2, 3]));
    assert_eq!(
        reader
            .read_event("future-ev-1".into(), demand())
            .await?
            .tool_name
            .as_deref(),
        Some("brand_new_tool")
    );

    reader.close().await;
    store.close().await?;
    Ok(())
}
