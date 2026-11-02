//! Both observed-position queries use the public reader, not reconstructed/decoded cursor tokens.
use super::*;
use crate::studio::thread_projection::LiveProjection;
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload},
    model::{ModelCompletedMember, ModelToolCall},
    thread::{
        ThreadEffectBatch, ThreadSnapshot as CoreSnapshot, TurnRecord, TurnState as CoreTurnState,
        journal::ContextChange,
        task::{TaskAcknowledgement, TaskRecord, TaskStatus},
    },
};
use pl_model::{
    completion::{
        CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
        CompletionPresentationPartKind,
    },
    runtime::{ModelMemberReceipt, ModelMemberState},
};

#[derive(Clone, Copy, Debug)]
enum Window {
    Inclusive,
    Exclusive,
}

impl Window {
    async fn read(
        self,
        reader: &ConversationReader,
        anchor: u64,
        before: Option<&str>,
        demand: ReadDemand,
    ) -> Result<ChatBatch> {
        match self {
            Self::Inclusive => reader.read_at(anchor, before, demand).await,
            Self::Exclusive => reader.read_before(anchor, before, demand).await,
        }
    }
}

fn invalid_argument(result: Result<ChatBatch>) {
    let error = result.expect_err("invalid window qualification was accepted");
    assert!(
        matches!(
            error.downcast_ref::<core::ChatError>(),
            Some(core::ChatError::InvalidArgument(_))
        ),
        "{error:#}"
    );
}

fn finish(id: &str) -> Result<ModelCompletedMember> {
    let receipt = ModelMemberReceipt {
        item: CompletionPresentationItem {
            provider_item_id: id.into(),
            output_index: None,
            kind: CompletionPresentationItemKind::Text(pl_protocol::trace::TraceTextChannel::Final),
            parts: vec![CompletionPresentationPart {
                content_index: 0,
                provider_part_id: None,
                text: format!("completed {id}"),
                kind: CompletionPresentationPartKind::OutputText,
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

// Find the public reader's actual K=1 admission threshold without copying its private cursor
// encoding or budget algorithm. Every failed probe must be InvalidDemand, never a swallowed error.
async fn tightest(
    window: Window,
    reader: &ConversationReader,
    anchor: u64,
    maximum: ReadDemand,
) -> Result<(ReadDemand, ChatBatch)> {
    let (mut rejected, mut accepted) = (0, maximum.max_bytes);
    while accepted - rejected > 1 {
        let bytes = rejected + (accepted - rejected) / 2;
        match window
            .read(
                reader,
                anchor,
                None,
                ReadDemand {
                    max_bytes: bytes,
                    ..maximum
                },
            )
            .await
        {
            Ok(batch) => {
                assert_eq!(batch.entries.len(), 1);
                assert!(batch.encoded_len()? <= bytes as usize);
                accepted = bytes;
            }
            Err(error) => {
                assert!(
                    matches!(
                        error.downcast_ref::<core::ChatError>(),
                        Some(core::ChatError::InvalidDemand(_))
                    ),
                    "{error:#}"
                );
                rejected = bytes;
            }
        }
    }
    let demand = ReadDemand {
        max_bytes: accepted,
        ..maximum
    };
    let batch = window.read(reader, anchor, None, demand).await?;
    assert_eq!(rejected + 1, accepted);
    let error = window
        .read(
            reader,
            anchor,
            None,
            ReadDemand {
                max_bytes: rejected,
                ..maximum
            },
        )
        .await
        .unwrap_err();
    assert!(
        matches!(
            error.downcast_ref::<core::ChatError>(),
            Some(core::ChatError::InvalidDemand(_))
        ),
        "{error:#}"
    );
    eprintln!(
        "{window:?} K=1 minimum={accepted}, encoded={}, one-byte-less=InvalidDemand",
        batch.encoded_len()?
    );
    Ok((demand, batch))
}

#[tokio::test]
async fn observed_position_windows_include_anchor_preserve_payload_and_freeze_source_cut()
-> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = Thread::from(
            env.runtime
                .create_thread(&env.project.id, "observed windows")
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
        projection.bind_execution_history(channel.order_index(), history)?;
        projection.bind_conversation_identity(database.clone())?;
        projection.observe_test_current(&thread, Vec::new())?;

        // Legitimate frozen legacy receipts have no recorded source lifecycle. Keep two in H0 so
        // the original history token is nonempty, and test Unknown rather than fabricating an end.
        let mut old = Vec::new();
        for (id, ordinal) in [("old-receipt-a", 17), ("old-receipt-b", 91)] {
            let item = ThreadItem::new(
                id.into(),
                thread.id.clone(),
                String::new(),
                ordinal,
                1,
                1,
                1,
                ThreadItemState::Raw(ThreadRawItem::runtime_control("old", 1)),
            );
            old.push(crate::studio::runtime::chat_item::completion_draft(
                &item, 0, &database,
            )?);
        }
        let mut records = session.publish_batch(old).await?.to_vec();
        let (_owner, progress) = watch::channel(Default::default());
        let source =
            Arc::new(super::super::super::thread_observation::ThreadLiveFeed::new(None, progress));
        let slot = env.runtime.thread_observations.observation_slot(&thread.id);
        slot.install(source.clone());
        source.publish_test_conversation(
            &session,
            projection.current_state().context("initial")?,
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
        let initial = chat(&mut feed).await?;
        let h0_before = initial.before.clone().context("H0 continuation")?;
        assert_eq!(
            completed_atoms(&initial)
                .next()
                .context("H0 atom")?
                .completion_seq,
            Some(2)
        );
        let reader = feed.reader().clone();
        assert_eq!(reader.inner.ceiling, 2);

        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "atomic-turn".into(),
            state: CoreTurnState::Running,
            model_steps: 1,
        };
        let mut state = CoreSnapshot {
            turns: vec![turn.clone()].into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            turn: Some(turn.clone()),
            model_member_starts: vec![
                atoms::start("window-first", false),
                atoms::start("uncompleted-gap", false),
                atoms::start("window-second", false),
            ]
            .into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        source.publish_test_conversation(
            &session,
            prepared.current_state.clone().context("starts")?,
            prepared.current_handoff.clone(),
        )?;
        assert_eq!(
            session.head_seq(),
            2,
            "source-only/start facts manufactured a completion seq"
        );
        for window in [Window::Inclusive, Window::Exclusive] {
            invalid_argument(window.read(&reader, 3, None, one).await);
            invalid_argument(window.read(&reader, 0, None, one).await);
        }
        // Consume only the four reliable starts; all following completion publication remains queued.
        for _ in 0..4 {
            assert_eq!(chat(&mut feed).await?.entries.len(), 1);
        }

        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 2,
            committed_at: 11,
            model_members: vec![finish("window-first")?, finish("window-second")?].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        records.extend(prepared.completions.iter().cloned());
        source.publish_test_conversation(
            &session,
            prepared.current_state.clone().context("members")?,
            prepared.current_handoff.clone(),
        )?;

        let task = TaskRecord {
            id: "window-task".into(),
            call_id: "window-call".into(),
            tool_id: "arbitrary".into(),
            turn_id: "atomic-turn".into(),
            revision: 1,
            status: TaskStatus::Running,
            cancel_requested: false,
            started_sequence: Some(1),
            acknowledgement: Some(TaskAcknowledgement {
                record_id: "window-ack".into(),
                context_revision: 1,
            }),
        };
        let context = vec![
            ContextRecord {
                id: "window-request".into(),
                turn_id: Some("atomic-turn".into()),
                source: ContextSource::Assistant,
                content: vec![],
                tool_calls: vec![ModelToolCall {
                    call_id: task.call_id.clone(),
                    tool_id: task.tool_id.clone(),
                    arguments: OpaquePayload::new("application/json", 1, "{}")?,
                    presentation_contract: None,
                    rejection: None,
                }],
            },
            ContextRecord {
                id: "window-ack".into(),
                turn_id: Some("atomic-turn".into()),
                source: ContextSource::ToolResult {
                    call_id: task.call_id.clone(),
                    tool_id: task.tool_id.clone(),
                },
                content: vec![ContextContent::Text {
                    text: "accepted ".repeat(128).into(),
                }],
                tool_calls: vec![],
            },
        ];
        state.context = ContextSnapshot {
            revision: 1,
            records: context.clone().into(),
        };
        state.tasks.insert(task.id.clone(), task.clone());
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 3,
            committed_at: 12,
            tasks: vec![task].into(),
            context: Some(ContextChange::Append {
                revision: 1,
                records: context.into(),
            }),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        assert_eq!(prepared.completions.len(), 1);
        let anchor_record = prepared.completions[0].clone();
        let anchor = anchor_record.header.append_seq;
        assert_eq!(anchor, 5);
        let frozen: ChatAtom = serde_json::from_slice(&anchor_record.header.metadata)?;
        assert_ne!(frozen.id, anchor_record.header.item_id);
        assert!(
            frozen.source_state.is_none()
                && frozen.payload.is_none()
                && frozen.completion_seq.is_none()
        );
        records.push(anchor_record.clone());
        source.publish_test_conversation(
            &session,
            prepared.current_state.clone().context("ack")?,
            prepared.current_handoff.clone(),
        )?;
        let delivered = feed.delivered;
        let current = feed.current.clone();
        let serial = feed.seen_serial;
        let cut_entry = feed.cut_entry;

        let inclusive = reader.read_at(anchor, None, one).await?;
        let exclusive = reader.read_before(anchor, None, one).await?;
        let at_cursor = inclusive.before.clone().context("inclusive continuation")?;
        let before_cursor = exclusive.before.clone().context("exclusive continuation")?;
        let at = completed_atoms(&inclusive).next().context("anchor")?;
        assert_eq!(inclusive.entries.len(), 1);
        assert_eq!(at.completion_seq, Some(anchor));
        assert_eq!(at.id, frozen.id);
        assert_eq!(at.completion_item_id, frozen.completion_item_id);
        assert_eq!(at.contents, frozen.contents);
        assert_eq!(
            at.payload,
            Some(PayloadData::Inline {
                bytes: anchor_record.payload.to_vec()
            })
        );
        assert_eq!(
            completed_atoms(&exclusive)
                .next()
                .context("exclusive first")?
                .completion_seq,
            Some(4)
        );
        let earlier: Vec<ChatAtom> = records[2..4]
            .iter()
            .map(|record| serde_json::from_slice(&record.header.metadata))
            .collect::<Result<_, _>>()?;
        assert!(
            earlier[1].source_order.context("second order")?
                > earlier[0].source_order.context("first order")? + 1,
            "fixture did not retain a sparse source order"
        );

        for window in [Window::Inclusive, Window::Exclusive] {
            let wrong_kind = match window {
                Window::Inclusive => &before_cursor,
                Window::Exclusive => &at_cursor,
            };
            invalid_argument(window.read(&reader, anchor, Some(wrong_kind), one).await);
            let own_cursor = match window {
                Window::Inclusive => &at_cursor,
                Window::Exclusive => &before_cursor,
            };
            invalid_argument(
                window
                    .read(&reader, anchor - 1, Some(own_cursor), one)
                    .await,
            );
            invalid_argument(window.read(&reader, anchor, Some(&h0_before), one).await);
            invalid_argument(window.read(&reader, anchor + 1, None, one).await);
        }
        invalid_argument(reader.load_older(&at_cursor, one).await);
        invalid_argument(reader.load_older(&before_cursor, one).await);
        let mut other = env
            .runtime
            .open_conversation_feed(&thread.id, ChatScope::Main, one)
            .await?;
        invalid_argument(other.reader().read_at(anchor, Some(&at_cursor), one).await);
        invalid_argument(
            other
                .reader()
                .read_before(anchor, Some(&before_cursor), one)
                .await,
        );
        other.close().await?;
        other.reader().close().await?;

        // Capture both continuations before a real later source end is published.
        let cancelled = TurnRecord {
            state: CoreTurnState::Cancelled,
            ..turn
        };
        state.turns = vec![cancelled.clone()].into();
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 4,
            committed_at: 13,
            turn: Some(cancelled),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        source.publish_test_conversation(
            &session,
            prepared.current_state.clone().context("end")?,
            prepared.current_handoff.clone(),
        )?;
        for (window, first) in [
            (Window::Inclusive, inclusive),
            (Window::Exclusive, exclusive),
        ] {
            let mut page = first;
            let mut sequences = Vec::new();
            loop {
                assert_eq!(page.placement, ChatPlacement::Prepend);
                assert!(page.current.is_none() && page.entries.len() <= 1);
                assert!(page.encoded_len()? <= one.max_bytes as usize);
                for atom in completed_atoms(&page) {
                    let seq = atom.completion_seq.context("window seq")?;
                    sequences.push(seq);
                    let source = atom.source_state.as_ref().context("source annotation")?;
                    assert_eq!(source.source, atom.source);
                    if seq > 2 {
                        assert_eq!(
                            source.lifecycle,
                            ChatSourceLifecycle::Active,
                            "window chased late source end"
                        );
                        assert!(source.ended.is_none());
                    } else {
                        assert_eq!(source.lifecycle, ChatSourceLifecycle::Unknown);
                        assert!(source.started.is_none() && source.ended.is_none());
                    }
                }
                assert!(
                    page.entries
                        .iter()
                        .all(|entry| matches!(entry, ChatEntry::Atom(_)))
                );
                let Some(cursor) = page.before else { break };
                page = window.read(&reader, anchor, Some(&cursor), one).await?;
                assert_ne!(
                    page.before.as_ref(),
                    Some(&cursor),
                    "window did not advance"
                );
            }
            assert_eq!(
                sequences,
                match window {
                    Window::Inclusive => vec![5, 4, 3, 2, 1],
                    Window::Exclusive => vec![4, 3, 2, 1],
                }
            );
        }

        for (window, selected_seq) in [(Window::Inclusive, anchor), (Window::Exclusive, anchor - 1)]
        {
            let (tight, batch) = tightest(window, &reader, anchor, one).await?;
            assert_eq!(batch.entries.len(), 1);
            let atom = completed_atoms(&batch).next().context("tight atom")?;
            assert_eq!(atom.completion_seq, Some(selected_seq));
            let original = &records[selected_seq as usize - 1];
            assert!(
                matches!(&atom.payload, Some(PayloadData::Deferred { reference, byte_length })
                if *byte_length == original.header.byte_length && reference == &ContentRef {
                    database_id: database.clone(), target: ContentTarget::ItemPayload {
                        item_id: original.header.item_id.clone()
                    }
                })
            );
            let Some(PayloadData::Deferred { reference, .. }) = &atom.payload else {
                bail!("tight payload was not deferred");
            };
            let payload = reader
                .read_content(
                    reference,
                    ContentRange {
                        offset: 0,
                        max_bytes: 64 * 1024,
                    },
                )
                .await?;
            assert!(payload.sealed);
            assert_eq!(payload.available_through, original.header.byte_length);
            assert_eq!(payload.bytes, original.payload.as_ref());
            assert!(matches!(atom.source_state.as_ref(), Some(source)
                if source.source == atom.source && matches!(source.lifecycle,
                    ChatSourceLifecycle::Ended { outcome: ChatTerminalOutcome::Cancelled })));
            assert!(batch.current.is_none() && batch.encoded_len()? <= tight.max_bytes as usize);
            if matches!(window, Window::Inclusive) {
                assert_eq!(atom.id, frozen.id);
                assert_ne!(atom.id, original.header.item_id);
                assert_eq!(atom.contents, frozen.contents);
            }
            let exact = ReadDemand {
                max_bytes: u32::try_from(batch.encoded_len()?)?,
                ..one
            };
            reader.finish_batch(batch.clone(), exact)?;
            let error = reader
                .finish_batch(
                    batch,
                    ReadDemand {
                        max_bytes: exact.max_bytes - 1,
                        ..exact
                    },
                )
                .unwrap_err();
            assert!(matches!(
                error.downcast_ref::<core::ChatError>(),
                Some(core::ChatError::InvalidDemand(_))
            ));
        }
        let old = reader.load_older(&h0_before, one).await?;
        assert_eq!(
            completed_atoms(&old)
                .next()
                .context("original H0 older")?
                .completion_seq,
            Some(1)
        );
        assert_eq!(reader.inner.ceiling, 2);
        assert_eq!(feed.delivered, delivered);
        assert_eq!(feed.current, current);
        assert_eq!(feed.seen_serial, serial);
        assert_eq!(feed.cut_entry, cut_entry);
        assert_eq!(initial.before.as_deref(), Some(h0_before.as_str()));
        feed.close().await?;
        reader.close().await?;
        assert!(reader.read_at(anchor, None, one).await.is_err());
        assert!(reader.read_before(anchor, None, one).await.is_err());
        Ok(())
    }
    .await;
    env.finish(result).await
}
