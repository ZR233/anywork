use super::*;
use crate::studio::thread_projection::{LiveProjection, PreparedEffect};
use pl_core::{
    context::OpaquePayload,
    model::{
        ModelCompletedMember, ModelStartedMember, ModelTextChannel, ObservedItemKind,
        ObservedPartIdentity, ObservedPartKind, ProviderPartIdentity,
    },
    thread::{
        ThreadEffectBatch, ThreadSnapshot as CoreSnapshot, TurnRecord, TurnState as CoreTurnState,
    },
};
use pl_model::{
    completion::{
        CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
        CompletionPresentationPartKind,
    },
    runtime::{ModelMemberReceipt, ModelMemberState},
};

pub(super) fn start(id: &str, reasoning: bool) -> ModelStartedMember {
    ModelStartedMember {
        turn_id: "atomic-turn".into(),
        attempt_id: "atomic-attempt".into(),
        generation: 0,
        identity: ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: id.into(),
            output_index: None,
            content_index: 0,
            item_kind: if reasoning {
                ObservedItemKind::Reasoning
            } else {
                ObservedItemKind::Text(ModelTextChannel::Final)
            },
            part: if reasoning {
                ObservedPartKind::ReasoningText
            } else {
                ObservedPartKind::OutputText
            },
        }),
    }
}

fn finish(id: &str, reasoning: bool, text: &str) -> Result<ModelCompletedMember> {
    let receipt = ModelMemberReceipt {
        item: CompletionPresentationItem {
            provider_item_id: id.into(),
            output_index: None,
            kind: if reasoning {
                CompletionPresentationItemKind::Reasoning
            } else {
                CompletionPresentationItemKind::Text(pl_protocol::trace::TraceTextChannel::Final)
            },
            parts: vec![CompletionPresentationPart {
                content_index: 0,
                provider_part_id: None,
                text: text.into(),
                kind: if reasoning {
                    CompletionPresentationPartKind::ReasoningText
                } else {
                    CompletionPresentationPartKind::OutputText
                },
            }],
        },
        state: ModelMemberState::Completed,
    };
    Ok(ModelCompletedMember {
        turn_id: "atomic-turn".into(),
        attempt_id: "atomic-attempt".into(),
        generation: 0,
        member_id: id.into(),
        payload: OpaquePayload::new(
            "pl.model.completed-member",
            1,
            serde_json::to_string(&receipt)?,
        )?,
    })
}

fn publish(
    source: &super::super::super::thread_observation::ThreadLiveFeed,
    session: &core::Session,
    prepared: &Arc<PreparedEffect>,
) -> Result<()> {
    source.publish_test_conversation(
        session,
        prepared.current_state.clone().context("prepared current")?,
        prepared.current_handoff.clone(),
    )
}

#[tokio::test]
async fn reliable_starts_empty_text_and_reverse_completion_share_the_real_feed() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = Thread::from(
            env.runtime
                .create_thread(&env.project.id, "atomic starts")
                .await?,
        );
        let history = env.runtime.store.history(&thread.id).await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let session = env.runtime.store.chat_session(&thread.id).await?;
        let channel = env
            .runtime
            .store
            .thread_persistence()
            .history_channel(&thread.id);
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        projection.observe_test_current(&thread, Vec::new())?;
        let (_owner, owner_progress) = watch::channel(Default::default());
        let source = Arc::new(
            super::super::super::thread_observation::ThreadLiveFeed::new(None, owner_progress),
        );
        env.runtime
            .thread_observations
            .observation_slot(&thread.id)
            .install(source.clone());
        source.publish_test_conversation(
            &session,
            projection.current_state().context("initial")?,
            None,
        )?;
        let mut feed = env
            .runtime
            .open_conversation_feed(
                &thread.id,
                ChatScope::Main,
                ReadDemand {
                    max_items: 1,
                    ..demand()
                },
            )
            .await?;
        assert!(chat(&mut feed).await?.entries.is_empty());
        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "atomic-turn".into(),
            state: CoreTurnState::Running,
            model_steps: 1,
        };
        let state = CoreSnapshot {
            turns: vec![turn.clone()].into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            turn: Some(turn),
            model_member_starts: vec![start("reasoning", true), start("empty-text", false)].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        assert_eq!(
            session.head_seq(),
            0,
            "a start must not manufacture a completion"
        );
        assert_eq!(prepared.current.source_changes.len(), 1);
        publish(&source, &session, &prepared)?;
        let mut starts = Vec::new();
        let mut source_events = 0;
        for _ in 0..3 {
            let batch = chat(&mut feed).await?;
            assert_eq!(batch.entries.len(), 1, "K=1 reliable facts were not split");
            assert!(batch.before.is_none());
            assert_eq!(batch.current.context("current")?.atoms.len(), 2);
            starts.extend(batch.entries.into_iter().filter_map(|entry| match entry {
                ChatEntry::Atom(atom) => Some(atom),
                ChatEntry::Source(_) => { source_events += 1; None },
            }));
        }
        assert_eq!(source_events, 1, "read annotations swallowed the reliable source start");
        assert_eq!(starts.len(), 2);
        assert_eq!(starts[0].kind, ChatAtomKind::Reasoning);
        assert_eq!(starts[1].kind, ChatAtomKind::Text);
        let mixed = ChatBatch {
            placement: ChatPlacement::Append,
            entries: vec![ChatEntry::Source(prepared.current.source_changes[0].clone()),
                ChatEntry::Atom(starts[0].clone())],
            before: None,
            current: Some(prepared.current.projection.clone()),
        };
        feed.reader().finish_batch(mixed.clone(), ReadDemand { max_items: 2, ..demand() })?;
        assert!(feed.reader().finish_batch(mixed.clone(), ReadDemand { max_items: 1, ..demand() }).is_err(),
            "final gate excluded a reliable Source event from max_items");
        let exact = ReadDemand { max_items: 2, max_bytes: u32::try_from(mixed.encoded_len()?)? };
        feed.reader().finish_batch(mixed.clone(), exact)?;
        let error = feed.reader().finish_batch(
            mixed, ReadDemand { max_bytes: exact.max_bytes - 1, ..exact },
        ).unwrap_err();
        assert!(matches!(error.downcast_ref::<core::ChatError>(),
            Some(core::ChatError::InvalidDemand(_))),
            "one byte less accepted a mixed reliable envelope");
        assert!(starts.iter().all(|atom| atom.payload.is_none()
            && matches!(
                atom.lifecycle,
                ChatAtomLifecycle::Active {
                    started: Some(_),
                    ..
                }
            )));
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 2,
            committed_at: 11,
            model_members: vec![finish("empty-text", false, "")?].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        publish(&source, &session, &prepared)?;
        let batch = chat(&mut feed).await?;
        let text = completed_atoms(&batch)
            .next()
            .context("completed empty text")?
            .clone();
        assert_eq!(text.id, starts[1].id);
        assert_eq!(text.completion_seq, Some(1));
        assert_eq!(batch.entries.len(), 1);
        assert_eq!(text.source_state.as_ref().context("text source annotation")?.source, text.source);
        let frozen: ChatAtom = serde_json::from_slice(&prepared.completions[0].header.metadata)?;
        assert!(frozen.source_state.is_none(), "read annotation was written into completion metadata");
        assert_eq!(
            batch.current.context("post text")?.atoms[0].id,
            starts[0].id,
            "text start/end must not retire reasoning"
        );
        let mut mid = env
            .runtime
            .open_conversation_feed(&thread.id, ChatScope::Main, demand())
            .await?;
        let set = chat(&mut mid).await?;
        assert_eq!(completed_atoms(&set).count(), 1);
        assert!(set.entries.iter().all(|entry| matches!(entry, ChatEntry::Atom(_))));
        assert!(completed_atoms(&set).all(|atom| matches!(
            atom.source_state.as_ref().map(|state| &state.lifecycle),
            Some(ChatSourceLifecycle::Active))));
        mid.close().await?;
        mid.reader().close().await?;
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 3,
            committed_at: 12,
            model_members: vec![finish("reasoning", true, "proof")?].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        publish(&source, &session, &prepared)?;
        let batch = chat(&mut feed).await?;
        let reasoning = completed_atoms(&batch)
            .next()
            .context("reasoning in Main")?;
        assert_eq!(reasoning.id, starts[0].id);
        assert_eq!(reasoning.completion_seq, Some(2));
        assert!(
            reasoning.source_order < text.source_order,
            "completion order must not overwrite actual source order"
        );
        assert!(
            batch
                .current
                .as_ref()
                .context("post members")?
                .atoms
                .is_empty()
        );
        assert!(
            prepared
                .current
                .projection
                .sources
                .iter()
                .any(|source| matches!(source.lifecycle, ChatSourceLifecycle::Active)),
            "members must not end a Turn"
        );
        use pl_core::thread::{ContextCompactionEvent, ContextCompactionOutcome};
        let operation = "actual-operation";
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(), sequence: 4, committed_at: 13,
            context_compactions: vec![ContextCompactionEvent::Started {
                operation_id: operation.into(), turn_id: None, attempt_id: None,
            }].into(), ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        assert_eq!(session.head_seq(), 2);
        publish(&source, &session, &prepared)?;
        let operation_start = chat(&mut feed).await?;
        assert!(operation_start.entries.iter().any(|entry| matches!(entry,
            ChatEntry::Source(source) if matches!(&source.source, ChatSourceId::Operation { operation_id }
                if operation_id == operation) && source.lifecycle == ChatSourceLifecycle::Active)));
        let current = operation_start.current.as_ref().context("operation current")?;
        let active_operation = current.atoms.iter().find(|atom| atom.kind == ChatAtomKind::Compaction)
            .context("Started must publish an active compaction atom")?.clone();
        assert_eq!(current.active.as_ref().context("compacting head")?.kind, ThreadActivityKind::Compacting);
        assert_eq!(active_operation.source, ChatSourceId::Operation { operation_id: operation.into() });
        assert_eq!(active_operation.delivery, ChatDeliveryKind::Independent);
        assert!(active_operation.turn_id.is_none() && active_operation.attempt_id.is_none());
        assert!(active_operation.completion_seq.is_none() && active_operation.completion_item_id.is_none());
        assert!(active_operation.payload.is_none() && active_operation.contents.is_empty());
        let operation_position = ChatFactPosition { effect_seq: 4, suborder: 1 };
        assert_eq!(active_operation.lifecycle, ChatAtomLifecycle::Active {
            started: Some(operation_position), status: ChatActiveStatus::Running,
        });
        let operation_member = chat(&mut feed).await?;
        assert!(operation_member.entries.iter().any(|entry| matches!(entry,
            ChatEntry::Atom(atom) if atom.as_ref() == &active_operation)));
        assert!(operation_member.encoded_len()? <= demand().max_bytes as usize);
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(), sequence: 5, committed_at: 14,
            context_compactions: vec![ContextCompactionEvent::Finished {
                operation_id: operation.into(), outcome: ContextCompactionOutcome::Cancelled,
            }].into(), ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        publish(&source, &session, &prepared)?;
        let _operation_end = chat(&mut feed).await?;
        let batch = chat(&mut feed).await?;
        let operation_atom = completed_atoms(&batch).next().context("operation terminal")?;
        assert_eq!(operation_atom.id, active_operation.id);
        assert_eq!(operation_atom.completion_item_id.as_deref(), Some(active_operation.id.as_str()));
        assert_eq!(operation_atom.delivery, ChatDeliveryKind::Independent);
        assert_eq!(operation_atom.source, active_operation.source);
        assert!(operation_atom.payload.is_some());
        assert_eq!(operation_atom.started_at, active_operation.started_at);
        let current = batch.current.as_ref().context("operation retired current")?;
        assert!(!current.atoms.iter().any(|atom| atom.id == active_operation.id));
        assert_ne!(current.active.as_ref().map(|head| head.kind), Some(ThreadActivityKind::Compacting));
        assert_eq!(operation_atom.kind, ChatAtomKind::Compaction);
        assert!(operation_atom.turn_id.is_none(), "idle operation borrowed an old Turn");
        assert!(matches!(operation_atom.lifecycle, ChatAtomLifecycle::Terminal {
            started: Some(_), ended: Some(_), outcome: ChatTerminalOutcome::Cancelled,
        }));

        // H0 remains zero, while a normal observed-position window can read its later completions.
        let reader = feed.reader().clone();
        let delivered = feed.delivered;
        let main_current = feed.current.clone();
        let one = ReadDemand { max_items: 1, ..demand() };
        let window = reader.read_before(3, None, one).await?;
        assert_eq!(window.entries.len(), 1);
        assert_eq!(window.placement, ChatPlacement::Prepend);
        assert!(window.current.is_none());
        assert!(window.encoded_len()? <= one.max_bytes as usize);
        assert_eq!(completed_atoms(&window).next().context("window first")?.completion_seq, Some(2));
        let cursor = window.before.context("window continuation")?;
        assert!(reader.load_older(&cursor, one).await.is_err(), "window escaped into H0");
        assert!(reader.read_before(2, Some(&cursor), one).await.is_err(), "anchor mismatch accepted");
        assert!(reader.read_before(0, None, one).await.is_err());
        assert!(reader.read_before(4, None, one).await.is_err(), "unpublished position accepted");
        assert!(reader.read_before(3, None, ReadDemand { max_items: 1, max_bytes: 1 }).await.is_err());
        let mut other = env.runtime.open_conversation_feed(&thread.id, ChatScope::Main, demand()).await?;
        let _set = chat(&mut other).await?;
        assert!(other.reader().read_before(3, Some(&cursor), one).await.is_err(), "other lease accepted cursor");
        other.close().await?;
        other.reader().close().await?;
        let cancelled = TurnRecord { elapsed_ms: None, input_id: None, turn_id: "atomic-turn".into(),
            state: CoreTurnState::Cancelled, model_steps: 1 };
        let terminal_state = CoreSnapshot { turns: vec![cancelled.clone()].into(), ..Default::default() };
        let effect = ThreadEffectBatch { thread_id: thread.id.clone(), sequence: 6, committed_at: 15,
            turn: Some(cancelled), ..Default::default() };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &terminal_state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        publish(&source, &session, &prepared)?;
        let older = reader.read_before(3, Some(&cursor), one).await?;
        assert_eq!(older.entries.len(), 1);
        assert_eq!(completed_atoms(&older).next().context("window second")?.completion_seq, Some(1));
        assert!(completed_atoms(&older).all(|atom| matches!(atom.source_state.as_ref(),
            Some(source) if source.source == atom.source && source.lifecycle == ChatSourceLifecycle::Active)),
            "window chased a later source end");
        if let Some(cursor) = older.before {
            let end = reader.read_before(3, Some(&cursor), one).await?;
            assert!(end.entries.is_empty() && end.before.is_none());
        }
        let empty = reader.read_before(1, None, one).await?;
        assert!(empty.entries.is_empty() && empty.before.is_none());
        assert_eq!(reader.inner.ceiling, 0);
        assert_eq!(feed.delivered, delivered, "query advanced feed delivery");
        assert_eq!(feed.current, main_current, "query replaced Main current");
        feed.close().await?;
        feed.reader().close().await?;
        assert!(reader.read_before(1, None, one).await.is_err(), "closed read qualification accepted a window");
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn cold_pages_annotate_one_atom_and_budget_current_only_sources_and_deferred_payload()
-> Result<()> {
    use crate::studio::{
        runtime::conversation_reader::{JsonBudget, annotate_atoms, entries, query},
        storage::history::{EffectCommit, HistoryStore},
    };
    use pl_core::chat::ChatBudget as _;
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = Thread::from(
            env.runtime
                .create_thread(&env.project.id, "cold annotation budget")
                .await?,
        );
        let history =
            HistoryStore::open(&env._temp.path().join("cold-annotation.sqlite"), &thread.id)
                .await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let session = core::Session::new(
            history.clone(),
            core::TimelineEpoch::new("cold-budget-fixture")?,
        );
        let channel = env
            .runtime
            .store
            .thread_persistence()
            .history_channel(&thread.id);
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "atomic-turn".into(),
            state: CoreTurnState::Running,
            model_steps: 1,
        };
        let state = CoreSnapshot {
            turns: vec![turn.clone()].into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            turn: Some(turn),
            model_member_starts: vec![start("cold-live-text", false)].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        history
            .commit_effect(
                1,
                EffectCommit {
                    items: &prepared.items,
                    completions: &[],
                    current: &prepared.current,
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let budget = JsonBudget::new(database.clone(), None, String::new());
        let mut expected_current = prepared.current.projection.clone();
        expected_current.execution_present = false;
        let saved_current = history
            .conversation_current()
            .await?
            .context("saved current")?;
        assert_eq!(saved_current, expected_current);
        // A cold snapshot cannot prove a resident execution source. JSON false is one byte
        // longer than the prepared hot projection's true; use the actual persisted read shape.
        let current_cost = serde_json::to_vec(&saved_current)?.len() - b"null".len();
        let tight = ReadDemand {
            max_items: 1,
            max_bytes: u32::try_from(budget.fixed_bytes() + current_cost + 1)?,
        };
        let cold = history
            .cold_conversation(
                query(&ChatScope::Main)?,
                core::ReadDemand::new(1, tight.max_bytes as usize),
                &budget,
            )
            .await?
            .context("cold cut")?;
        assert_eq!(cold.current.source_effect_seq, 1);
        let mut selected = entries(cold.page.items, &database)?;
        annotate_atoms(&mut selected, &cold.sources)?;
        let empty_set = ChatBatch {
            placement: ChatPlacement::Set,
            entries: selected,
            before: None,
            current: Some(cold.current),
        };
        assert!(
            empty_set.entries.is_empty(),
            "current-only source became an entry"
        );
        assert_eq!(
            empty_set.current.as_ref().context("current")?.sources.len(),
            1
        );
        assert!(empty_set.encoded_len()? <= tight.max_bytes as usize);
        let error = history
            .cold_conversation(
                query(&ChatScope::Main)?,
                core::ReadDemand::new(1, tight.max_bytes as usize - 1),
                &budget,
            )
            .await
            .err()
            .context("one byte less must reject the current-only envelope")?;
        assert!(matches!(
            error.downcast_ref::<core::ChatError>(),
            Some(core::ChatError::InvalidDemand(_))
        ));

        let item = ThreadItem::new(
            "budget-receipt".into(),
            thread.id.clone(),
            String::new(),
            4,
            2,
            11,
            11,
            ThreadItemState::Raw(ThreadRawItem::runtime_control("x".repeat(16384), 11)),
        );
        let draft = crate::studio::runtime::chat_item::completion_draft(&item, 2, &database)?;
        let frozen: ChatAtom = serde_json::from_slice(&draft.metadata)?;
        assert!(frozen.source_state.is_none());
        assert!(
            serde_json::from_slice::<serde_json::Value>(&draft.metadata)?
                .get("sourceState")
                .is_none()
        );
        let receipt_state = ChatSourceState {
            source: frozen.source.clone(),
            lifecycle: ChatSourceLifecycle::Ended {
                outcome: ChatTerminalOutcome::Completed,
            },
            started: Some(ChatFactPosition {
                effect_seq: 2,
                suborder: 0,
            }),
            ended: Some(ChatFactPosition {
                effect_seq: 2,
                suborder: 0,
            }),
        };
        let records = session.publish_batch(vec![draft]).await?;
        let metadata = records[0].header.metadata.clone();
        let mut current = prepared.current.as_ref().clone();
        current.projection.source_effect_seq = 2;
        current.projection.sources.push(receipt_state.clone());
        current.source_changes = vec![receipt_state.clone()].into();
        current.changes = Arc::from([]);
        current.contents = Arc::from([]);
        history
            .commit_effect(
                2,
                EffectCommit {
                    items: &[item],
                    completions: &records,
                    current: &current,
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let saved_current = history
            .conversation_current()
            .await?
            .context("saved current")?;
        let current_cost = serde_json::to_vec(&saved_current)?.len() - b"null".len();
        let deferred_cost = budget.item_bytes(&records[0].header, core::PayloadMode::Deferred);
        let demand = ReadDemand {
            max_items: 1,
            max_bytes: u32::try_from(budget.fixed_bytes() + current_cost + deferred_cost)?,
        };
        let cold = history
            .cold_conversation(
                query(&ChatScope::Main)?,
                core::ReadDemand::new(1, demand.max_bytes as usize),
                &budget,
            )
            .await?
            .context("cold receipt")?;
        assert_eq!(cold.current.source_effect_seq, 2);
        let mut stored = cold.page.items;
        assert_eq!(stored.len(), 1);
        assert_eq!(stored[0].header.metadata, metadata);
        assert!(matches!(
            stored[0].payload,
            core::PayloadData::Deferred { .. }
        ));
        let mut selected = entries(stored.clone(), &database)?;
        annotate_atoms(&mut selected, &cold.sources)?;
        let batch = ChatBatch {
            placement: ChatPlacement::Set,
            entries: selected,
            before: None,
            current: Some(cold.current),
        };
        assert_eq!(batch.entries.len(), 1);
        assert!(batch.encoded_len()? <= demand.max_bytes as usize);
        let read = completed_atoms(&batch)
            .next()
            .context("annotated receipt")?;
        assert_eq!(read.source_state.as_ref(), Some(&receipt_state));
        assert!(matches!(read.payload, Some(PayloadData::Deferred { .. })));
        let error = history
            .cold_conversation(
                query(&ChatScope::Main)?,
                core::ReadDemand::new(1, demand.max_bytes as usize - 1),
                &budget,
            )
            .await
            .err()
            .context("one byte less must reject the budgeted deferred atom")?;
        assert!(matches!(
            error.downcast_ref::<core::ChatError>(),
            Some(core::ChatError::InvalidDemand(_))
        ));
        assert!(
            batch
                .current
                .as_ref()
                .context("current-only source")?
                .sources
                .iter()
                .any(|source| source.source
                    == (ChatSourceId::ForegroundTurn {
                        turn_id: "atomic-turn".into()
                    })
                    && source.lifecycle == ChatSourceLifecycle::Active)
        );
        let mut conflicting = batch.entries.clone();
        let ChatEntry::Atom(atom) = &mut conflicting[0] else {
            bail!("atom missing");
        };
        atom.source_state = Some(ChatSourceState {
            source: ChatSourceId::Receipt {
                receipt_id: "wrong".into(),
            },
            lifecycle: ChatSourceLifecycle::Unknown,
            started: None,
            ended: None,
        });
        assert!(matches!(
            annotate_atoms(&mut conflicting, &cold.sources)
                .unwrap_err()
                .downcast_ref::<core::ChatError>(),
            Some(core::ChatError::Conflict(_))
        ));
        let mut polluted = frozen;
        polluted.source_state = Some(receipt_state);
        stored[0].header.metadata = serde_json::to_vec(&polluted)?.into();
        assert!(
            entries(stored, &database).is_err(),
            "frozen metadata accepted a mutable read annotation"
        );
        assert!(
            serde_json::from_slice::<ChatAtom>(&records[0].header.metadata)?
                .source_state
                .is_none()
        );
        assert_eq!(
            records[0].header.metadata, metadata,
            "ordinary read rewrote immutable metadata"
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn activation_restores_saved_atomic_evidence_once_without_a_new_start() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = Thread::from(
            env.runtime
                .create_thread(&env.project.id, "atomic restore")
                .await?,
        );
        // This storage fixture is deliberately separate from the Runtime writer coordinator:
        // committing synthetic effects into its live database would forge the coordinator's clock.
        let history = crate::studio::storage::history::HistoryStore::open(
            &env._temp.path().join("atomic-restore.sqlite"),
            &thread.id,
        )
        .await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let session = core::Session::new(
            history.clone(),
            core::TimelineEpoch::new("restore-fixture")?,
        );
        let channel = env
            .runtime
            .store
            .thread_persistence()
            .history_channel(&thread.id);
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "atomic-turn".into(),
            state: CoreTurnState::Running,
            model_steps: 1,
        };
        let state = CoreSnapshot {
            turns: vec![turn.clone()].into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            turn: Some(turn),
            model_member_starts: vec![
                start("restore-reasoning", true),
                start("restore-empty-text", false),
            ]
            .into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        history
            .commit_effect(
                1,
                crate::studio::storage::history::EffectCommit {
                    items: &prepared.items,
                    completions: &prepared.completions,
                    current: &prepared.current,
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let mut restored = LiveProjection::new();
        restored.bind_execution_history(channel.order_index(), history.clone())?;
        restored.bind_conversation_identity(database)?;
        restored.restore_current(&session, &thread, &state).await?;
        assert!(
            restored
                .restore_current(&session, &thread, &state)
                .await
                .is_err(),
            "activation restored twice"
        );
        let (_, restored_current) = restored
            .prepare(
                &thread,
                &ThreadEffectBatch {
                    thread_id: thread.id.clone(),
                    sequence: 2,
                    committed_at: 100,
                    ..Default::default()
                },
                &state,
                false,
            )
            .await?;
        assert_eq!(
            restored_current.current.projection.atoms, prepared.current.projection.atoms,
            "restore fabricated new start positions, times, identities, order or content owners"
        );
        assert!(
            restored_current
                .current_handoff
                .as_ref()
                .context("handoff")?
                .entries
                .is_empty(),
            "restore manufactured a new reliable start"
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn background_result_precedes_unfinished_foreground_and_mid_set_preserves_both_sources()
-> Result<()> {
    use pl_core::{
        context::{
            AgentMessageKind, ContextContent, ContextRecord, ContextSnapshot, ContextSource,
        },
        model::ModelToolCall,
        thread::{
            ToolDelivery, ToolOutcome,
            inbox::{InboxRecord, ThreadMessage},
            journal::ContextChange,
            task::{TaskAcknowledgement, TaskRecord, TaskStatus},
        },
    };
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        // This test owns the projection and its synthetic Core effects. Register only the durable
        // directory fact: create_thread also activates a real observation worker, which would race
        // this owner over the same execution index and overwrite its completion identity knowledge.
        let (delta, thread) = crate::studio::store::directory::DirectoryDelta::register_root_thread(
            "background-order".into(),
            &env.project.id,
            "background order",
            pl_protocol::ThreadModeId::simple(),
            pl_protocol::ThreadWorkspaceMode::Local,
            env.project.path.clone(),
        );
        env.runtime
            .agent_facility
            .product_events
            .commit_directory(delta)
            .await?;
        assert!(env.runtime.threads.observed_thread(&thread.id).is_none());
        let history = env.runtime.store.history(&thread.id).await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let session = env.runtime.store.chat_session(&thread.id).await?;
        let channel = env
            .runtime
            .store
            .thread_persistence()
            .history_channel(&thread.id);
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history)?;
        projection.bind_conversation_identity(database)?;
        projection.observe_test_current(&thread, Vec::new())?;
        let (_owner, progress) = watch::channel(Default::default());
        let source =
            Arc::new(super::super::super::thread_observation::ThreadLiveFeed::new(None, progress));
        env.runtime
            .thread_observations
            .observation_slot(&thread.id)
            .install(source.clone());
        source.publish_test_conversation(
            &session,
            projection.current_state().context("initial")?,
            None,
        )?;
        let background_turn = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "background-turn".into(),
            state: CoreTurnState::Running,
            model_steps: 1,
        };
        let mut task = TaskRecord {
            id: "task-b".into(),
            call_id: "call-b".into(),
            tool_id: "arbitrary".into(),
            turn_id: "background-turn".into(),
            revision: 1,
            status: TaskStatus::Running,
            cancel_requested: false,
            acknowledgement: Some(TaskAcknowledgement {
                record_id: "ack-b".into(),
                context_revision: 1,
            }),
            started_sequence: Some(1),
        };
        let records = vec![
            ContextRecord {
                id: "request-b".into(),
                turn_id: Some("background-turn".into()),
                source: ContextSource::Assistant,
                content: vec![],
                tool_calls: vec![ModelToolCall {
                    call_id: "call-b".into(),
                    tool_id: "arbitrary".into(),
                    arguments: OpaquePayload::new("application/json", 1, "{}")?,
                    presentation_contract: None,
                    rejection: None,
                }],
            },
            ContextRecord {
                id: "ack-b".into(),
                turn_id: Some("background-turn".into()),
                source: ContextSource::ToolResult {
                    call_id: "call-b".into(),
                    tool_id: "arbitrary".into(),
                },
                content: vec![ContextContent::Text {
                    text: "background accepted".into(),
                }],
                tool_calls: vec![],
            },
        ];
        let mut state = CoreSnapshot {
            turns: vec![background_turn.clone()].into(),
            context: ContextSnapshot {
                revision: 1,
                records: records.clone().into(),
            },
            ..Default::default()
        };
        state.tasks.insert(task.id.clone(), task.clone());
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            turn: Some(background_turn.clone()),
            tasks: vec![task.clone()].into(),
            context: Some(ContextChange::Append {
                revision: 1,
                records: records.into(),
            }),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        let ack: ChatAtom = serde_json::from_slice(&prepared.completions[0].header.metadata)?;
        assert_eq!(ack.delivery, ChatDeliveryKind::BackgroundHandoff);
        assert!(matches!(
            ack.lifecycle,
            ChatAtomLifecycle::Terminal {
                outcome: ChatTerminalOutcome::Transferred,
                ..
            }
        ));
        publish(&source, &session, &prepared)?;
        let cancelled = TurnRecord {
            state: CoreTurnState::Cancelled,
            ..background_turn
        };
        state.turns = vec![cancelled.clone()].into();
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 2,
            committed_at: 11,
            turn: Some(cancelled),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        publish(&source, &session, &prepared)?;
        let foreground = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "atomic-turn".into(),
            state: CoreTurnState::Running,
            model_steps: 1,
        };
        let mut turns = state.turns.to_vec();
        turns.push(foreground.clone());
        state.turns = turns.into();
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 3,
            committed_at: 12,
            turn: Some(foreground),
            model_member_starts: vec![start("unfinished-t", false)].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        publish(&source, &session, &prepared)?;
        let payload = OpaquePayload::new("application/json", 1, "{\"answer\":\"B\"}")?;
        let delivery = ToolDelivery {
            target: Default::default(),
            call_id: "call-b".into(),
            tool_id: "arbitrary".into(),
            output: pl_core::tool::ToolOutput::new(payload.clone(), vec![]),
            delivered_context: vec![ContextContent::Text {
                text: "B result".into(),
            }],
            outcome: ToolOutcome::Succeeded,
        };
        let inbox = InboxRecord {
            sequence: 1,
            message: ThreadMessage {
                id: "result-b".into(),
                source_id: task.id.clone(),
                kind: AgentMessageKind::Report,
                payload,
                context: vec![],
            },
        };
        task.status = TaskStatus::Succeeded;
        task.revision = 2;
        state.tasks.insert(task.id.clone(), task.clone());
        state.deliveries = vec![delivery.clone()].into();
        state.inbox = vec![inbox.clone()].into();
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 4,
            committed_at: 13,
            tasks: vec![task].into(),
            deliveries: vec![delivery].into(),
            inbox: vec![inbox].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        let b_seq = session.head_seq();
        publish(&source, &session, &prepared)?;
        let one = ReadDemand {
            max_items: 1,
            ..demand()
        };
        let mut feed = env
            .runtime
            .open_conversation_feed(&thread.id, ChatScope::Main, one)
            .await?;
        let set = chat(&mut feed).await?;
        let b = completed_atoms(&set)
            .find(|atom| matches!(atom.source, ChatSourceId::BackgroundResult { .. }))
            .context("independent B result in Set")?;
        assert_eq!(
            b.source,
            ChatSourceId::BackgroundResult {
                message_id: "result-b".into()
            }
        );
        assert_eq!(b.completion_seq, Some(b_seq));
        assert_eq!(b.delivery, ChatDeliveryKind::Independent);
        assert_ne!(
            b.id, ack.id,
            "independent result resurrected transferred foreground member"
        );
        assert_eq!(
            set.current.as_ref().context("mid Set current")?.atoms.len(),
            1
        );
        assert_eq!(set.entries.len(), 1);
        assert_eq!(
            b.source_state
                .as_ref()
                .context("B source annotation")?
                .source,
            b.source
        );
        assert!(
            set.current
                .as_ref()
                .context("current-only source")?
                .sources
                .iter()
                .any(|source| source.source
                    == (ChatSourceId::ForegroundTurn {
                        turn_id: "atomic-turn".into()
                    })
                    && source.lifecycle == ChatSourceLifecycle::Active)
        );
        let mut before = set.before.clone();
        let mut older_seqs = Vec::new();
        while let Some(cursor) = before {
            let page = feed.reader().load_older(&cursor, one).await?;
            assert!(page.current.is_none());
            assert!(page.entries.len() <= 1);
            assert!(
                page.entries
                    .iter()
                    .all(|entry| matches!(entry, ChatEntry::Atom(_)))
            );
            older_seqs.extend(
                completed_atoms(&page)
                    .map(|atom| atom.completion_seq.context("older seq"))
                    .collect::<Result<Vec<_>>>()?,
            );
            assert!(completed_atoms(&page).all(|atom| {
                atom.source_state
                    .as_ref()
                    .is_some_and(|state| state.source == atom.source)
            }));
            before = page.before;
        }
        assert_eq!(older_seqs, vec![2, 1]);
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 5,
            committed_at: 14,
            model_members: vec![finish("unfinished-t", false, "T")?].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        publish(&source, &session, &prepared)?;
        let append = chat(&mut feed).await?;
        let t = completed_atoms(&append).next().context("T completion")?;
        assert!(t.completion_seq.context("T seq")? > b_seq);
        assert_eq!(
            t.source,
            ChatSourceId::ForegroundTurn {
                turn_id: "atomic-turn".into()
            }
        );
        let anchor = t.completion_seq.context("observed T")?;
        let one = ReadDemand {
            max_items: 1,
            ..demand()
        };
        let mut window = feed.reader().read_before(anchor, None, one).await?;
        let mut sequences = Vec::new();
        let mut sources = Vec::new();
        loop {
            assert!(window.entries.len() <= 1);
            for atom in completed_atoms(&window) {
                sequences.push(atom.completion_seq.context("window completion")?);
                sources.push(atom.source.clone());
            }
            let Some(before) = window.before else {
                break;
            };
            window = feed
                .reader()
                .read_before(anchor, Some(&before), one)
                .await?;
            assert_ne!(
                window.before.as_ref(),
                Some(&before),
                "window made no progress"
            );
        }
        assert_eq!(sequences, vec![b_seq, 2, 1]);
        assert!(
            sources
                .iter()
                .any(|source| matches!(source, ChatSourceId::BackgroundResult { .. }))
        );
        assert!(
            sources
                .iter()
                .any(|source| matches!(source, ChatSourceId::ForegroundTurn { .. })),
            "ordinary window filtered another source"
        );
        feed.close().await?;
        feed.reader().close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}
