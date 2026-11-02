use super::*;
use anyhow::{Context, Result, bail};
use pl_provider_fixture::{Protocol, Reply, ReplyStage, RequestMatch, Step};
use std::{collections::HashMap, time::Duration};

use crate::runtime_test_support as support;

async fn chat(feed: &mut ConversationFeed) -> Result<ChatBatch> {
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            match feed.recv().await?.context("feed ended")? {
                ConversationEvent::Chat { batch } => return Ok(*batch),
                ConversationEvent::State { .. } => {}
            }
        }
    })
    .await?
}
fn demand() -> ReadDemand {
    ReadDemand {
        max_items: 8,
        max_bytes: 128 * 1024,
    }
}

fn question_steps(prompt: &str, first: Reply) -> Vec<Step> {
    vec![
        support::prompt_step(prompt, 0, first),
        Step {
            protocol: Protocol::ResponsesHttp,
            request: RequestMatch::InteractionAnswers {
                text: serde_json::json!({
                    "answers": {
                        "provider": {
                            "answers": ["fixture-answer"]
                        }
                    }
                })
                .to_string(),
                step: 1,
            },
            reply: support::text_reply("question resolved", "question-resolved"),
            optional: false,
        },
    ]
}

fn question_reply(call_id: &str) -> Reply {
    support::tool_reply(
        "request_user_input",
        call_id,
        serde_json::json!({
            "questions": [{
                "id": "provider",
                "header": "Provider",
                "question": "Which provider should the next release verify?",
                "isOther": true
            }]
        }),
    )
}

fn answer() -> InteractionResolution {
    InteractionResolution::UserInput(UserInputResolution {
        answers: HashMap::from([(
            "provider".into(),
            UserInputAnswer {
                answers: vec!["fixture-answer".into()],
            },
        )]),
    })
}

async fn initial_snapshot(feed: &mut ConversationFeed) -> Result<ThreadSnapshot> {
    let ConversationEvent::Chat { batch } = feed.recv().await?.context("missing initial Chat")?
    else {
        bail!("conversation must start with Chat");
    };
    assert_eq!(batch.placement, ChatPlacement::Set);
    let ConversationEvent::State { update } =
        feed.recv().await?.context("missing initial State")?
    else {
        bail!("Chat Set must be followed by State");
    };
    let ThreadSubscriptionUpdate::Snapshot { snapshot } = *update else {
        bail!("first State must be a snapshot");
    };
    Ok(*snapshot)
}

fn assert_notification_revision(notification: &ThreadNotificationEnvelope, revision: &mut u64) {
    assert_eq!(notification.base_revision, *revision);
    assert_eq!(notification.revision, *revision + 1);
    *revision = notification.revision;
}

async fn finish_question(
    feed: &mut ConversationFeed,
    interaction_id: &str,
    pending_revision: u64,
    mut revision: u64,
    pending: &mut usize,
    resolved: &mut usize,
) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            match feed
                .recv()
                .await?
                .context("feed ended before terminal State")?
            {
                ConversationEvent::Chat { .. } => {}
                ConversationEvent::State { update } => {
                    let ThreadSubscriptionUpdate::Notification { notification } = *update else {
                        bail!("live question flow emitted a second State snapshot");
                    };
                    assert_notification_revision(&notification, &mut revision);
                    match notification.notification {
                        ThreadNotification::InteractionChanged { interaction }
                            if interaction.interaction_id == interaction_id =>
                        {
                            match interaction.status() {
                                InteractionStatus::Pending => {
                                    assert_eq!(interaction.revision, pending_revision);
                                    *pending += 1;
                                }
                                InteractionStatus::Resolved => {
                                    assert_eq!(interaction.revision, pending_revision + 1);
                                    *resolved += 1;
                                }
                                status => bail!("question reached unexpected status {status:?}"),
                            }
                        }
                        ThreadNotification::TurnCompleted { .. } if *resolved == 1 => {
                            return Ok(());
                        }
                        _ => {}
                    }
                }
            }
        }
    })
    .await
    .context("finite question scenario did not reach terminal State")?
}

async fn published_pending(
    env: &support::Environment,
    thread_id: &str,
) -> Result<(InteractionRequest, u64)> {
    let slot = env.runtime.thread_observations.observation_slot(thread_id);
    let (position, _) = slot.capture();
    let source = position
        .source
        .context("running Thread has no live owner")?;
    let mut changed = source.content_changes();
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            if let Some(current) = source
                .current_conversation()
                .map(|value| value.current.clone())
                && let Some(interaction) = current
                    .interactions
                    .iter()
                    .find(|interaction| interaction.status() == InteractionStatus::Pending)
            {
                return Ok::<_, anyhow::Error>((
                    interaction.clone(),
                    current.projection.source_effect_seq,
                ));
            }
            changed
                .changed()
                .await
                .context("live publication ended before the pending question")?;
        }
    })
    .await
    .context("pending question was not published by the live owner")?
}

#[tokio::test]
async fn question_cut_late_open_starts_with_published_pending_and_delivers_one_answer() -> Result<()>
{
    let env = support::Environment::new(
        question_steps("late-question", question_reply("late-question-call")),
        vec![],
    )
    .await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Local, "late-question")
            .await?;
        let id = &thread.thread.id;
        let (pending, publication_revision) = published_pending(&env, id).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        let snapshot = initial_snapshot(&mut feed).await?;
        assert_eq!(snapshot.revision, publication_revision);
        assert_eq!(
            snapshot.interactions.as_slice(),
            std::slice::from_ref(&pending),
            "first State did not use the canonical owner cut"
        );
        assert_eq!(pending.status(), InteractionStatus::Pending);

        env.runtime
            .resolve_interaction(
                "late-question-answer".into(),
                id.clone(),
                pending.revision,
                pending.interaction_id.clone(),
                answer(),
            )
            .await?;
        let mut repeated_pending = 0;
        let mut resolved = 0;
        finish_question(
            &mut feed,
            &pending.interaction_id,
            pending.revision,
            snapshot.revision,
            &mut repeated_pending,
            &mut resolved,
        )
        .await?;
        assert_eq!(
            repeated_pending, 0,
            "baseline pending question was notified again"
        );
        assert_eq!(resolved, 1);
        feed.close().await?;
        feed.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn question_cut_open_feed_delivers_new_pending_and_answer_once_in_order() -> Result<()> {
    let stage = ReplyStage::new();
    let Reply::Sse(frames) = question_reply("live-question-call") else {
        unreachable!("question fixture uses SSE")
    };
    let first = stage.gated(vec![frames[0].clone()], frames[1..].to_vec());
    let env = support::Environment::new(question_steps("live-question", first), vec![]).await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Local, "live-question")
            .await?;
        let id = &thread.thread.id;
        support::reached(&stage).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        let snapshot = initial_snapshot(&mut feed).await?;
        assert!(
            snapshot.interactions.is_empty(),
            "held tool interaction entered the initial cut"
        );
        stage.release();

        let mut state_revision = snapshot.revision;
        let pending = tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                match feed
                    .recv()
                    .await?
                    .context("feed ended before pending question")?
                {
                    ConversationEvent::Chat { .. } => {}
                    ConversationEvent::State { update } => {
                        let ThreadSubscriptionUpdate::Notification { notification } = *update
                        else {
                            bail!("live question flow emitted a second State snapshot");
                        };
                        assert_notification_revision(&notification, &mut state_revision);
                        if let ThreadNotification::InteractionChanged { interaction } =
                            notification.notification
                            && interaction.status() == InteractionStatus::Pending
                        {
                            return Ok::<_, anyhow::Error>(interaction);
                        }
                    }
                }
            }
        })
        .await
        .context("live pending question was not delivered")??;
        let mut pending_count = 1;
        let mut resolved = 0;
        env.runtime
            .resolve_interaction(
                "live-question-answer".into(),
                id.clone(),
                pending.revision,
                pending.interaction_id.clone(),
                answer(),
            )
            .await?;
        finish_question(
            &mut feed,
            &pending.interaction_id,
            pending.revision,
            state_revision,
            &mut pending_count,
            &mut resolved,
        )
        .await?;
        assert_eq!(pending_count, 1);
        assert_eq!(resolved, 1);
        feed.close().await?;
        feed.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

async fn state_snapshot(feed: &mut ConversationFeed) -> Result<Box<ThreadSnapshot>> {
    let ConversationEvent::State { update } =
        feed.recv().await?.context("missing State baseline")?
    else {
        bail!("Set must be followed by the State baseline");
    };
    let ThreadSubscriptionUpdate::Snapshot { snapshot } = *update else {
        bail!("first State must be a snapshot");
    };
    Ok(snapshot)
}

#[tokio::test]
async fn pending_plan_is_delivered_live_and_restored_on_hot_and_cold_open() -> Result<()> {
    let plan = format!("# 待确认计划\n\n{}", "步骤\n".repeat(9000));
    let stage = ReplyStage::new();
    let Reply::Sse(frames) = support::tool_reply(
        "plan_submit",
        "feed-plan",
        serde_json::json!({
            "expectedRevision": 0, "plan": plan,
        }),
    ) else {
        bail!("expected SSE tool reply")
    };
    let first = stage.gated(frames[..1].to_vec(), frames[1..].to_vec());
    let mut env = support::Environment::new(
        vec![
            support::prompt_step("pending-plan-feed", 0, first),
            support::prompt_step(
                &plan,
                1,
                support::text_reply("approved and continued", "after-plan"),
            ),
        ],
        vec![],
    )
    .await?;
    let result = async {
        // The long Plan crosses the storage chunk boundary. Keep its continuation within the
        // fixture's declared window so this journey does not require a compaction response.
        let config_store =
            crate::config::ConfigStore::new(crate::config::ConfigPaths::from_config_dir(&env.home));
        let mut config = config_store.load()?;
        let account = config
            .models
            .accounts
            .get_mut(&pl_model::config::AccountId::new("root-fixture")?)
            .context("root fixture account")?;
        let pl_model::config::AccountModelCatalogConfig::Explicit { models, .. } =
            &mut account.catalog
        else {
            bail!("fixture account must have an explicit model catalog");
        };
        let model = models
            .iter_mut()
            .find(|model| model.model_id == support::MODEL)
            .context("root fixture model")?;
        model.context_window = Some(256_000);
        model.max_context_window = Some(256_000);
        model.max_output_tokens = Some(32_000);
        config_store.save(&config)?;
        env.restart().await?;
        let started = env
            .start(ThreadWorkspaceMode::Local, "pending-plan-feed")
            .await?;
        let id = &started.thread.id;
        support::reached(&stage).await?;
        let mut live = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut live).await?.placement, ChatPlacement::Set);
        assert!(state_snapshot(&mut live).await?.interactions.is_empty());
        stage.release();
        let pending = tokio::time::timeout(Duration::from_secs(20), async {
            while let Some(event) = live.recv().await? {
                if let ConversationEvent::State { update } = event
                    && let ThreadSubscriptionUpdate::Notification { notification } = *update
                    && let ThreadNotification::InteractionChanged { interaction } =
                        notification.notification
                    && interaction.status() == InteractionStatus::Pending
                {
                    return Ok::<_, anyhow::Error>(*interaction);
                }
            }
            bail!("Plan submission did not publish its pending interaction");
        })
        .await??;
        assert!(matches!(
            pending.scope.purpose,
            InteractionPurpose::AgentSessionPlanConfirmation(_)
        ));
        assert!(
            serde_json::to_vec(&pending)?.len() > 64 * 1024,
            "cold restore must read multiple content chunks"
        );
        let completed = support::completed_prompt(&env.runtime, id, "pending-plan-feed").await?;
        assert!(matches!(completed.state, TurnState::Completed(_)));
        live.close().await?;
        live.reader().close().await?;

        let mut reopened = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut reopened).await?.placement, ChatPlacement::Set);
        assert_eq!(
            state_snapshot(&mut reopened).await?.interactions,
            vec![pending.clone()]
        );
        reopened.close().await?;
        reopened.reader().close().await?;

        env.restart().await?;
        assert!(env.runtime.threads.observed_thread(id).is_none());
        let mut cold = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut cold).await?.placement, ChatPlacement::Set);
        assert_eq!(
            state_snapshot(&mut cold).await?.interactions,
            vec![pending.clone()]
        );
        assert!(
            env.runtime.threads.observed_thread(id).is_none(),
            "reading a pending Plan activated execution"
        );
        assert_eq!(env.root_provider.recorded().len(), 1);
        cold.close().await?;
        cold.reader().close().await?;

        let mut continuation = env
            .runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: id.clone(),
            })
            .await?;
        let resolved = env
            .runtime
            .resolve_interaction(
                "approve-feed-plan".into(),
                id.clone(),
                pending.revision,
                pending.interaction_id.clone(),
                InteractionResolution::UserInput(UserInputResolution {
                    answers: [(
                        AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
                        UserInputAnswer {
                            answers: vec!["Approve".into()],
                        },
                    )]
                    .into(),
                }),
            )
            .await?;
        assert_eq!(resolved.interaction.status(), InteractionStatus::Resolved);
        tokio::time::timeout(Duration::from_secs(20), async {
            while let Some(update) = continuation.recv().await? {
                if let ThreadSubscriptionUpdate::Notification { notification } = update
                    && let ThreadNotification::TurnCompleted { turn } = notification.notification
                    && turn.id != completed.id
                {
                    anyhow::ensure!(
                        matches!(turn.state, TurnState::Completed(_)),
                        "approved continuation failed: {:?}",
                        turn.state
                    );
                    return Ok::<_, anyhow::Error>(());
                }
            }
            bail!("approved Plan did not complete its continuation");
        })
        .await??;
        drop(continuation);
        assert_eq!(env.root_provider.recorded().len(), 2);
        let mut approved = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut approved).await?.placement, ChatPlacement::Set);
        assert!(
            state_snapshot(&mut approved).await?.interactions.is_empty(),
            "answered Plan returned as pending"
        );
        approved.close().await?;
        approved.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

async fn terminal_state_after_set(
    feed: &mut ConversationFeed,
    expected: &pl_protocol::Turn,
) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        let ConversationEvent::State { update } = feed.recv().await?.context("missing State")?
        else {
            bail!("Set must be followed by the State snapshot");
        };
        let ThreadSubscriptionUpdate::Snapshot { snapshot } = *update else {
            bail!("first State must be a snapshot");
        };
        assert!(snapshot.active_turn.is_none());
        let ConversationEvent::State { update } = feed
            .recv()
            .await?
            .context("missing retained terminal State")?
        else {
            bail!("completed reopen must restore its terminal Turn as State");
        };
        let ThreadSubscriptionUpdate::Notification { notification } = *update else {
            bail!("terminal Turn must follow the snapshot as a notification");
        };
        assert_eq!(notification.base_revision, snapshot.revision);
        assert_eq!(notification.revision, snapshot.revision + 1);
        let ThreadNotification::TurnCompleted { turn } = notification.notification else {
            bail!("completed reopen did not restore its canonical terminal Turn");
        };
        assert_eq!(&turn, expected);
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("completed reopen lost its terminal State")?
}

#[tokio::test]
async fn retained_terminal_state_requires_coverage_and_no_active_turn_and_is_deduplicated()
-> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = env
            .runtime
            .create_thread(&env.project.id, "retained State qualification")
            .await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(&thread.id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut feed).await?.placement, ChatPlacement::Set);
        let _snapshot = feed.recv().await?.context("initial State snapshot")?;
        assert!(feed.pending.is_empty());
        let uncovered = feed
            .state_effect_floor
            .checked_add(1)
            .context("test State cut exhausted")?;
        let terminal = Turn {
            input_id: Some("original-input".into()),
            id: "original-turn".into(),
            thread_id: thread.id.clone(),
            revision: uncovered,
            state: TurnState::Completed(CompletedTurnState::new(
                Some(1),
                2,
                TurnCompletion::Normal,
            )),
            updated_at: 2,
        };
        let revision = feed.state_revision;
        feed.reflect_terminal(terminal.clone())?;
        assert!(feed.pending.is_empty(), "future terminal crossed the cut");
        assert_eq!(feed.state_revision, revision);

        feed.state_effect_floor = terminal.revision;
        feed.active_turn = Some("newer-active-turn".into());
        feed.reflect_terminal(terminal.clone())?;
        assert!(feed.pending.is_empty(), "older terminal hid an active Turn");
        assert_eq!(feed.state_revision, revision);

        feed.active_turn = None;
        feed.reflect_terminal(terminal.clone())?;
        assert_eq!(feed.pending.len(), 1);
        assert_eq!(feed.state_revision, revision + 1);
        feed.reflect_terminal(terminal.clone())?;
        feed.state_event(ThreadLiveEvent::Committed {
            sequence: terminal.revision + 1,
            changes: vec![LiveEvent::Turn {
                turn: terminal.clone(),
                event: TurnEvent::Completed,
            }],
        })?;
        assert_eq!(
            feed.pending.len(),
            1,
            "retained/live duplicate spent a frame"
        );
        assert_eq!(feed.state_revision, revision + 1);

        let newer = Turn {
            revision: terminal.revision + 1,
            ..terminal
        };
        feed.reflect_terminal(newer)?;
        assert_eq!(feed.pending.len(), 2, "newer same-Turn fact was suppressed");
        assert_eq!(feed.state_revision, revision + 2);
        feed.state_event(ThreadLiveEvent::UnframedCommit {
            sequence: feed.state_effect_floor,
        })?;
        assert_eq!(feed.pending.len(), 2, "covered gap spent a State frame");
        assert_eq!(feed.state_revision, revision + 2);
        for _ in 0..2 {
            assert!(matches!(
                feed.recv().await?,
                Some(ConversationEvent::State { .. })
            ));
        }
        let (events, state) = tokio::sync::broadcast::channel(1);
        feed.state = Some(state);
        feed.state_turn = true;
        events.send(ThreadLiveEvent::UnframedCommit {
            sequence: feed.state_effect_floor + 1,
        })?;
        let error = feed.recv().await.unwrap_err();
        assert_eq!(
            error
                .downcast_ref::<pl_protocol::studio::StudioError>()
                .and_then(|error| error.reason()),
            Some("conversationResyncRequired")
        );
        assert!(
            feed.reader().ensure().is_err(),
            "uncovered State gap left the old read qualification active"
        );
        feed.close().await?;
        feed.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn one_effect_main_prefix_retires_only_delivered_previews_and_skips_activity_suffix()
-> Result<()> {
    use crate::studio::{
        runtime::chat_item::BodyKey,
        thread_projection::{LiveProjection, order::presentation_id},
    };
    use pl_core::{
        context::OpaquePayload,
        model::{ContentBlock, ModelCompletedMember},
        thread::{ThreadEffectBatch, ThreadSnapshot},
    };
    use pl_model::{
        completion::{
            CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
            CompletionPresentationPartKind,
        },
        runtime::{ModelMemberReceipt, ModelMemberState},
    };
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = Thread::from(
            env.runtime
                .create_thread(&env.project.id, "prefix delivery")
                .await?,
        );
        let history = env.runtime.store.history(&thread.id).await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database identity")?;
        let session = env.runtime.store.chat_session(&thread.id).await?;
        let channel = env
            .runtime
            .store
            .thread_persistence()
            .history_channel(&thread.id);
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database)?;
        let ids = ["member-a", "member-b"].map(|id| {
            presentation_id(
                "prefix-attempt",
                0,
                id,
                Some(core::PresentationPart::OutputText(0)),
            )
        });
        projection.observe_test_current(
            &thread,
            ids.iter()
                .enumerate()
                .map(|(position, id)| {
                    (
                        id.clone(),
                        BodyKey::Body,
                        ContentBlock::from_text(if position == 0 { "first" } else { "second" }),
                        position as u64 + 1,
                        None,
                    )
                })
                .collect(),
        )?;
        let (_owner, owner_progress) = tokio::sync::watch::channel(Default::default());
        let source = Arc::new(super::super::thread_observation::ThreadLiveFeed::new(
            None,
            owner_progress,
        ));
        let slot = env.runtime.thread_observations.observation_slot(&thread.id);
        slot.install(source.clone());
        source.publish_test_conversation(
            &session,
            projection.current_state().context("before current")?,
            None,
        )?;
        let one = ReadDemand {
            max_items: 1,
            ..demand()
        };
        let mut feed = env
            .runtime
            .open_conversation_feed(&thread.id, ChatScope::Main, one)
            .await?;
        let first = chat(&mut feed).await?;
        assert_eq!(first.placement, ChatPlacement::Set);
        assert_eq!(first.current.context("Set current")?.previews.len(), 2);

        let members = [
            ("member-a", "first", false),
            ("member-b", "second", false),
            ("member-z", "reasoning", true),
        ]
        .into_iter()
        .map(|(id, text, reasoning)| -> Result<ModelCompletedMember> {
            let receipt = ModelMemberReceipt {
                item: CompletionPresentationItem {
                    provider_item_id: id.into(),
                    output_index: None,
                    kind: if reasoning {
                        CompletionPresentationItemKind::Reasoning
                    } else {
                        CompletionPresentationItemKind::Text(
                            pl_protocol::trace::TraceTextChannel::Final,
                        )
                    },
                    parts: vec![CompletionPresentationPart {
                        content_index: 0,
                        provider_part_id: None,
                        kind: if reasoning {
                            CompletionPresentationPartKind::ReasoningText
                        } else {
                            CompletionPresentationPartKind::OutputText
                        },
                        text: text.into(),
                    }],
                },
                state: if reasoning {
                    ModelMemberState::Interrupted
                } else {
                    ModelMemberState::Completed
                },
            };
            Ok(ModelCompletedMember {
                turn_id: "prefix-turn".into(),
                attempt_id: "prefix-attempt".into(),
                generation: 0,
                member_id: id.into(),
                payload: OpaquePayload::new(
                    "pl.model.completed-member",
                    1,
                    serde_json::to_string(&receipt)?,
                )?,
            })
        })
        .collect::<Result<Vec<_>>>()?;
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 17,
            model_members: members.into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection
            .prepare(&thread, &effect, &ThreadSnapshot::default(), false)
            .await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        assert_eq!(session.head_seq(), 3);
        let handoff = prepared
            .current_handoff
            .as_ref()
            .context("frozen handoff")?;
        assert_eq!(handoff.main_through, 2);
        assert_eq!(handoff.retirements.len(), 2);
        source.publish_test_conversation(
            &session,
            prepared
                .current_state
                .as_ref()
                .context("after current")?
                .clone(),
            Some(handoff.clone()),
        )?;

        let first = chat(&mut feed).await?;
        assert_eq!(first.messages.len(), 1);
        assert_eq!(first.messages[0].id, ids[0]);
        let current = first.current.context("first prefix current")?;
        assert_eq!(current.source_effect_seq, 1);
        assert_eq!(current.previews.len(), 1);
        assert_eq!(
            current.previews[0].id, ids[1],
            "undelivered member retired early"
        );
        let second = chat(&mut feed).await?;
        assert_eq!(second.messages.len(), 1);
        assert_eq!(second.messages[0].id, ids[1]);
        assert!(
            second
                .current
                .context("final Main current")?
                .previews
                .is_empty()
        );
        assert_eq!(
            feed.delivered,
            session.head_seq(),
            "scope-external suffix required another batch"
        );
        assert!(feed.cut.is_none());
        let interrupted = prepared
            .items
            .iter()
            .find_map(|item| item.thinking())
            .context("reasoning member")?;
        assert!(matches!(
            interrupted.lifecycle(),
            ThreadContentLifecycle::Cancelled(_)
        ));
        feed.close().await?;
        feed.reader().close().await?;
        slot.retire(&source);
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn live_set_watch_completion_current_and_independent_read_close() -> Result<()> {
    use sea_orm::{Database, SqliteTransactionMode, TransactionOptions, TransactionTrait};

    let body = "真实正文汉📖".repeat(1600);
    let frames = pl_provider_fixture::responses_text(&body, "demand-response", support::MODEL);
    let delta = frames
        .iter()
        .position(|frame| frame["type"] == "response.output_text.delta")
        .context("fixture text delta")?;
    let stage = ReplyStage::new();
    let reply: Reply = stage.gated(frames[..=delta].to_vec(), frames[delta + 1..].to_vec());
    let env =
        support::Environment::new(vec![support::prompt_step("demand-live", 0, reply)], vec![])
            .await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Local, "demand-live").await?;
        let id = &thread.thread.id;
        support::reached(&stage).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        let first = chat(&mut feed).await?;
        assert_eq!(first.placement, ChatPlacement::Set);
        assert!(first.current.is_some());
        let before = first.before.clone();
        let reader = feed.reader().clone();
        let mut current = first.current.context("main Set current")?;
        let reference = loop {
            if let Some(preview) = current
                .previews
                .iter()
                .find(|preview| preview.role == CurrentContentRole::Response)
            {
                break preview.reference.clone();
            }
            let next = chat(&mut feed).await?;
            assert_eq!(next.placement, ChatPlacement::Append);
            current = next.current.context("stream current")?;
        };
        let range = ContentRange {
            offset: (body.len() - 16) as u64,
            max_bytes: 16,
        };
        let mut watch = reader.watch_content(&reference, range.clone()).await?;
        let window = watch.recv().await?.context("active window")?;
        assert!(!window.sealed);
        assert_eq!(window.bytes, &body.as_bytes()[body.len() - 16..]);
        let cancel = watch.cancellation_token();
        let waiting = tokio::spawn(async move {
            let result = watch.recv().await;
            watch.close().await?;
            result
        });
        cancel.cancel();
        assert!(
            tokio::time::timeout(Duration::from_secs(3), waiting)
                .await??
                .is_err()
        );
        // Closing a watch did not revoke the original read qualification.
        assert_eq!(
            reader.read_content(&reference, range.clone()).await?.bytes,
            window.bytes
        );
        let mut lifecycle = env
            .runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: id.clone(),
            })
            .await?;
        // Hold the real writer behind an SQLite transaction: delivery and a later idle open
        // must use the same complete pending tail instead of waiting for a flush or reading D.
        let path = env
            .runtime
            .store
            .registered_session_paths(id)?
            .history_database();
        let options = crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::ReadWrite,
            |options| options.busy_timeout(Duration::from_secs(10)),
        )
        .await?;
        let blocker = Database::connect(options).await?;
        let writer_lock = blocker
            .begin_with_options(TransactionOptions {
                sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
                ..Default::default()
            })
            .await?;
        stage.release();
        let mut saw_body = false;
        let mut retired = false;
        for _ in 0..64 {
            let batch = chat(&mut feed).await?;
            assert_eq!(batch.placement, ChatPlacement::Append);
            assert!(batch.before.is_none());
            for message in &batch.messages {
                let payload = match &message.payload {
                    PayloadData::Inline { bytes } => bytes.clone(),
                    PayloadData::Deferred {
                        reference,
                        byte_length,
                    } => {
                        assert!(*byte_length <= CONTENT_WINDOW_MAX_BYTES as u64);
                        reader
                            .read_content(
                                reference,
                                ContentRange {
                                    offset: 0,
                                    max_bytes: *byte_length as u32,
                                },
                            )
                            .await?
                            .bytes
                    }
                };
                let envelope: serde_json::Value = serde_json::from_slice(&payload)?;
                if envelope["type"] == "text"
                    && envelope["bodies"].as_array().is_some_and(|bodies| {
                        bodies
                            .iter()
                            .any(|entry| entry["byteLength"] == body.len() as u64)
                    })
                {
                    // The real content reference is retained under Item from active through seal.
                    if message.id
                        == match &reference.target {
                            ContentTarget::Body {
                                owner: ContentOwner::Item { item_id },
                                ..
                            } => item_id.as_str(),
                            _ => "",
                        }
                    {
                        saw_body = true;
                    }
                }
            }
            if batch
                .current
                .as_ref()
                .is_some_and(|current| current.active.is_none() && current.active_turn.is_none())
            {
                assert!(
                    saw_body,
                    "current retired before its scope's completed response was delivered"
                );
                retired = true;
                break;
            }
        }
        assert!(retired);
        let session = env.runtime.store.chat_session(id).await?;
        assert!(
            session.head_seq() > session.durable_seq(),
            "writer barrier did not leave pending completions"
        );
        // The existing State owner supplies the real terminal fact before the second open.
        // Neither a retired current nor idle is evidence that this handoff already occurred.
        let completed = tokio::time::timeout(Duration::from_secs(20), async {
            while let Some(update) = lifecycle.recv().await? {
                if let ThreadSubscriptionUpdate::Notification { notification } = update
                    && let ThreadNotification::TurnCompleted { turn } = notification.notification
                {
                    return Ok::<_, anyhow::Error>(turn);
                }
            }
            bail!("canonical State stream ended before the terminal Turn");
        })
        .await??;
        drop(lifecycle);
        let mut idle = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        let idle_set = chat(&mut idle).await?;
        assert_eq!(idle_set.placement, ChatPlacement::Set);
        assert!(
            idle_set
                .current
                .context("idle current")?
                .active_turn
                .is_none()
        );
        let ContentTarget::Body {
            owner: ContentOwner::Item { item_id },
            ..
        } = &reference.target
        else {
            bail!("active response did not retain its Item owner");
        };
        assert!(
            idle_set
                .messages
                .iter()
                .any(|message| &message.id == item_id),
            "idle open lost the pending response"
        );
        terminal_state_after_set(&mut idle, &completed).await?;
        idle.close().await?;
        idle.reader().close().await?;
        writer_lock.rollback().await?;
        blocker.close().await?;
        let sealed = reader.read_content(&reference, range).await?;
        assert!(sealed.sealed);
        assert_eq!(sealed.generation, window.generation);
        feed.close().await?;
        assert!(
            reader
                .read_content(
                    &reference,
                    ContentRange {
                        offset: 0,
                        max_bytes: 7
                    }
                )
                .await
                .is_ok()
        );
        if let Some(before) = before {
            assert_eq!(
                reader.load_older(&before, demand()).await?.placement,
                ChatPlacement::Prepend
            );
        }
        reader.close().await?;
        assert!(
            reader
                .read_content(
                    &reference,
                    ContentRange {
                        offset: 0,
                        max_bytes: 1
                    }
                )
                .await
                .is_err()
        );
        support::completed_prompt(&env.runtime, id, "demand-live").await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn cold_open_is_passive_and_absent_live_absent_revokes_old_read_qualification() -> Result<()>
{
    let mut env = support::Environment::new(
        vec![support::prompt_step(
            "demand-cold",
            0,
            support::text_reply("durable cold response", "cold-response"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Local, "demand-cold").await?;
        let id = &thread.thread.id;
        let completed = support::completed_prompt(&env.runtime, id, "demand-cold").await?;
        env.restart().await?;
        assert!(env.runtime.threads.observed_thread(id).is_none());
        let mut feed = env
            .runtime
            .open_conversation_feed(
                id,
                ChatScope::Main,
                ReadDemand {
                    max_items: 1,
                    max_bytes: 64 * 1024,
                },
            )
            .await?;
        let first = chat(&mut feed).await?;
        assert_eq!(first.placement, ChatPlacement::Set);
        assert!(!first.messages.is_empty());
        assert!(
            !first
                .current
                .context("cold main current")?
                .execution_present
        );
        assert!(
            env.runtime.threads.observed_thread(id).is_none(),
            "passive open activated execution"
        );
        terminal_state_after_set(&mut feed, &completed).await?;
        let reader = feed.reader().clone();
        let before = first.before.context("cold history continuation")?;
        let page = reader.load_older(&before, demand()).await?;
        assert_eq!(page.placement, ChatPlacement::Prepend);
        let mut independent = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        let error = independent
            .reader()
            .load_older(&before, demand())
            .await
            .unwrap_err();
        assert!(matches!(
            error.downcast_ref::<pl_core::chat::ChatError>(),
            Some(pl_core::chat::ChatError::InvalidArgument(_))
        ));
        independent.close().await?;
        independent.reader().close().await?;
        // Exercise the production registry's exact ABA transitions, without an execution/model start.
        let slot = env.runtime.thread_observations.observation_slot(id);
        let (_owner, owner_progress) = tokio::sync::watch::channel(Default::default());
        let source = Arc::new(super::super::thread_observation::ThreadLiveFeed::new(
            None,
            owner_progress,
        ));
        slot.install(source.clone());
        slot.retire(&source);
        let error = feed
            .recv()
            .await
            .err()
            .context("old feed did not require resync")?;
        assert_eq!(
            error
                .downcast_ref::<pl_protocol::studio::StudioError>()
                .and_then(|error| error.reason()),
            Some("conversationResyncRequired")
        );
        let error = reader.load_older(&before, demand()).await.unwrap_err();
        assert_eq!(
            error
                .downcast_ref::<pl_protocol::studio::StudioError>()
                .and_then(|error| error.reason()),
            Some("conversationResyncRequired")
        );
        feed.close().await?;
        reader.close().await?;
        let mut replacement = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut replacement).await?.placement, ChatPlacement::Set);
        replacement.close().await?;
        replacement.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    let close = env.runtime.shutdown_runtime().await;
    result?;
    close?;
    Ok(())
}
