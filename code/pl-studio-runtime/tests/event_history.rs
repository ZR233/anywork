#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};

use pl_studio_runtime::history::*;
use pl_studio_runtime::{
    CURRENT_PROTOCOL_VERSION, ContentRange, CurrentContentRef, CurrentFrame, CurrentProjection,
};
use std::path::Path;
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

async fn saved_streaming_prefix(home: &Path, id: &str, head: &str) -> Result<Option<Vec<u8>>> {
    let Ok(saved) = support::saved(home, id).await else {
        return Ok(None);
    };
    let Some(call) = saved.current.model_call.as_ref() else {
        return Ok(None);
    };
    let pl_core::thread::current::SavedModelPhase::Streaming { stream } = &call.phase else {
        return Ok(None);
    };
    let stream = pl_model::completion::ModelStreamCurrent::decode(stream)?;
    if stream.content_parts.iter().any(|part| part.text == head) {
        Ok(Some(std::fs::read(saved.root.join("current.json"))?))
    } else {
        Ok(None)
    }
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

        // The periodic saver publishes persistence when current.json is written.
        // The test owns this subscription; the runtime still owns the saver.
        let mut persistence = env
            .runtime
            .subscribe_product_topic(pl_studio_runtime::StudioProductTopic::PersistenceQueue)
            .await?;
        let saved_stream_bytes =
            tokio::time::timeout(support::integration_test_deadline()?, async {
                loop {
                    if let Some(bytes) = saved_streaming_prefix(&env.home, &id, &head).await? {
                        return Ok::<_, anyhow::Error>(bytes);
                    }
                    let frame = persistence.recv().await?.context(
                        "persistence queue ended before current.json saved the prefix",
                    )?;
                    if let pl_studio_runtime::StudioProductFrame::Lagged { dropped, .. } = frame {
                        anyhow::bail!(
                            "lost {dropped} persistence events while waiting for current.json"
                        );
                    }
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
        let (old_after_seq, old_before_seq, old_anchor_seq) = if let Some(idx) = old_page
            .entries
            .iter()
            .position(|entry| entry.has_folded_after)
        {
            let anchor_seq = old_page.entries[idx].event.seq;
            (
                Some(anchor_seq),
                idx.checked_sub(1).map(|j| old_page.entries[j].event.seq),
                anchor_seq,
            )
        } else {
            ensure!(
                old_page.has_folded_before_oldest,
                "original R1 folded work range missing"
            );
            (None, old_page.entries.last().map(|e| e.event.seq), 0)
        };
        let old_members = history
            .work_range_page(
                old_after_seq,
                old_before_seq,
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
            if let Some(entry) = page
                .entries
                .iter()
                .find(|entry| entry.has_folded_after && entry.event.seq > old_anchor_seq)
            {
                ensure!(
                    entry.event.run_id.as_deref() == Some(r2.as_str())
                        || entry.event.seq > old_anchor_seq,
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
                .work_range_page(old_after_seq, old_before_seq, Some(old_cut), None, demand(),)
                .await?
                == old_members
        );
        ensure!(
            history
                .work_range_page(old_after_seq, old_before_seq, None, None, demand(),)
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
