use super::atoms::{Harness, finish, start};
use super::*;
use crate::studio::thread_projection::PreparedEffect;
use pl_core::thread::{ContextCompactionEvent, ContextCompactionOutcome, ThreadEffectBatch};
use std::sync::Arc;

fn inline_envelope(item: &TimelineItem) -> Result<serde_json::Value> {
    let Some(PayloadData::Inline { bytes }) = &item.payload else {
        bail!("small original envelope remained Deferred: {}", item.id);
    };
    let value: serde_json::Value = serde_json::from_slice(bytes)?;
    assert_eq!(value["contract"], "anywork.chat/1");
    Ok(value)
}

fn assert_text(item: &TimelineItem, expected: &str) -> Result<()> {
    let value = inline_envelope(item)?;
    assert_eq!(value["type"], "text");
    assert!(
        value["bodies"]
            .as_array()
            .context("original bodies")?
            .iter()
            .any(|body| {
                serde_json::from_value::<Vec<u8>>(body["inline"].clone())
                    .is_ok_and(|bytes| bytes == expected.as_bytes())
            }),
        "original inline body bytes differ"
    );
    Ok(())
}

fn member<'a>(batch: &'a ChatBatch, id: &str) -> Result<&'a ChatAtom> {
    batch
        .entries
        .iter()
        .find_map(|entry| match entry {
            ChatEntry::Atom(atom) if atom.id == id => Some(atom.as_ref()),
            _ => None,
        })
        .with_context(|| format!("member {id} missing from its opened window"))
}

fn assert_thinking(atom: &ChatAtom, original: &[u8]) -> Result<()> {
    let Some(PayloadData::Inline { bytes }) = &atom.payload else {
        bail!("small member envelope remained Deferred: {}", atom.id);
    };
    assert_eq!(bytes.as_slice(), original, "original member bytes changed");
    let envelope: serde_json::Value = serde_json::from_slice(bytes)?;
    assert_eq!(envelope["contract"], "anywork.chat/1");
    assert_eq!(envelope["type"], "thinking");
    Ok(())
}

#[tokio::test]
async fn opened_members_keep_original_typed_bytes_live_pending_and_sqlite_with_bounded_delivery()
-> Result<()> {
    let mut env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut harness = Harness::new(&env).await?;
        let id = harness.thread.id.clone();
        let one = ReadDemand {
            max_items: 1,
            max_bytes: 8 * 1024,
        };
        let started = harness
            .effect(
                vec![
                    start("small-thinking", true),
                    start("large-thinking", true),
                    start("final", false),
                ],
                vec![],
            )
            .await?;
        let reference = started
            .current
            .projection()
            .items
            .iter()
            .find(|item| item.is_work_group())
            .and_then(|item| item.members.clone())
            .context("original group reference")?;
        let scope = ChatScope::GroupMembers { reference };
        harness.save(&started).await?;
        let mut live = env
            .runtime
            .open_conversation_feed(
                &id,
                scope.clone(),
                ReadDemand {
                    max_items: 2,
                    ..one
                },
            )
            .await?;
        let initial = chat(&mut live).await?;
        let [ChatEntry::Atom(small_head), ChatEntry::Atom(large_head)] = initial.entries.as_slice()
        else {
            bail!("opened group must contain both active reasoning members")
        };
        for atom in [small_head, large_head] {
            assert!(matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }));
            assert!(atom.payload.is_none() && !atom.contents.is_empty());
        }
        let small_id = small_head.id.clone();
        let large_id = large_head.id.clone();
        let small = harness
            .effect(
                vec![],
                vec![finish("small-thinking", true, "small reasoning")?],
            )
            .await?;
        assert_eq!(small.completions.len(), 1);
        let original_small = small.completions[0].payload.as_ref();
        let append = chat(&mut live).await?;
        assert_eq!(append.placement, ChatPlacement::Append);
        let small_atom = member(&append, &small_id)?;
        assert_thinking(small_atom, original_small)?;
        let small_ref = ContentRef {
            database_id: harness
                .history
                .conversation_database_id()
                .await?
                .context("database")?,
            target: ContentTarget::ItemPayload {
                item_id: small_atom
                    .completion_item_id
                    .clone()
                    .context("original completion")?,
            },
        };

        // The same selected member stays Deferred when only its header fits.
        let mut deferred = append.clone();
        let ChatEntry::Atom(atom) = &mut deferred.entries[0] else {
            unreachable!()
        };
        atom.payload = Some(PayloadData::Deferred {
            reference: small_ref.clone(),
            byte_length: original_small.len() as u64,
        });
        let tiny = ReadDemand {
            max_bytes: u32::try_from(deferred.encoded_len()?)?,
            ..one
        };
        let mut bounded = deferred.clone();
        live.reader()
            .inline_timeline_payloads(&mut bounded, tiny)
            .await?;
        assert_eq!(bounded, deferred);
        live.reader().finish_batch(bounded, tiny)?;
        let window = live
            .reader()
            .read_content(
                &small_ref,
                ContentRange {
                    offset: 0,
                    max_bytes: u32::try_from(original_small.len())?,
                },
            )
            .await?;
        assert_eq!(window.bytes.as_slice(), original_small);

        let large = harness
            .effect(
                vec![],
                vec![
                    finish("large-thinking", true, &"x".repeat(4096))?,
                    finish("final", false, "final text")?,
                ],
            )
            .await?;
        let append = chat(&mut live).await?;
        let large_atom = member(&append, &large_id)?;
        assert!(matches!(
            large_atom.payload,
            Some(PayloadData::Deferred { .. })
        ));
        let large_record = large
            .completions
            .iter()
            .find(|record| {
                Some(record.header.item_id.as_str()) == large_atom.completion_item_id.as_deref()
            })
            .context("large original completion")?;
        assert!(large_record.payload.len() > one.max_bytes as usize);
        assert!(large_record.payload.len() <= CONTENT_WINDOW_MAX_BYTES as usize);

        // A source/body or another real completion is not this Atom's payload owner.
        for target in [
            ContentTarget::ItemPayload {
                item_id: large_record.header.item_id.clone(),
            },
            small_atom
                .contents
                .first()
                .context("original body ref")?
                .reference
                .target
                .clone(),
        ] {
            let mut invalid = deferred.clone();
            let ChatEntry::Atom(atom) = &mut invalid.entries[0] else {
                unreachable!()
            };
            let Some(PayloadData::Deferred { reference, .. }) = &mut atom.payload else {
                unreachable!()
            };
            reference.target = target;
            let error = live
                .reader()
                .inline_timeline_payloads(&mut invalid, demand())
                .await
                .expect_err("member accepted a different payload owner");
            assert!(
                matches!(
                    error.downcast_ref::<core::ChatError>(),
                    Some(core::ChatError::StaleContent)
                ),
                "{error:#}"
            );
        }
        let mut no_completion = deferred.clone();
        let ChatEntry::Atom(atom) = &mut no_completion.entries[0] else {
            unreachable!()
        };
        atom.completion_item_id = None;
        let unchanged = no_completion.clone();
        live.reader()
            .inline_timeline_payloads(&mut no_completion, demand())
            .await?;
        assert_eq!(
            no_completion, unchanged,
            "missing completion triggered a content read"
        );
        let mut wrong_length = deferred.clone();
        let ChatEntry::Atom(atom) = &mut wrong_length.entries[0] else {
            unreachable!()
        };
        let Some(PayloadData::Deferred { byte_length, .. }) = &mut atom.payload else {
            unreachable!()
        };
        *byte_length -= 1;
        let error = live
            .reader()
            .inline_timeline_payloads(&mut wrong_length, demand())
            .await
            .expect_err("member accepted a payload/header length mismatch");
        assert!(
            matches!(
                error.downcast_ref::<core::ChatError>(),
                Some(core::ChatError::Conflict(_))
            ),
            "{error:#}"
        );
        assert_eq!(
            harness.session.durable_seq(),
            0,
            "member reads forced a save"
        );

        let mut pending = env
            .runtime
            .open_conversation_feed(&id, scope.clone(), one)
            .await?;
        let latest = chat(&mut pending).await?;
        assert_eq!(latest.entries.len(), 1);
        let latest_atom = member(&latest, &large_id)?;
        let Some(PayloadData::Deferred {
            reference,
            byte_length,
        }) = &latest_atom.payload
        else {
            bail!("large latest member was skipped or inlined");
        };
        let range = ContentRange {
            offset: 0,
            max_bytes: u32::try_from(*byte_length)?,
        };
        let bytes = pending
            .reader()
            .read_content(reference, range.clone())
            .await?;
        assert_eq!(bytes.bytes.as_slice(), large_record.payload.as_ref());
        let older = pending
            .reader()
            .load_older(
                latest.before.as_deref().context("member continuation")?,
                one,
            )
            .await?;
        assert_eq!(older.placement, ChatPlacement::Prepend);
        assert_thinking(member(&older, &small_id)?, original_small)?;

        let mut main = env
            .runtime
            .open_conversation_feed(&id, ChatScope::Main, demand())
            .await?;
        let main_batch = chat(&mut main).await?;
        let group = main_batch
            .entries
            .iter()
            .find_map(|entry| match entry {
                ChatEntry::Item(item) if item.is_work_group() => Some(item),
                _ => None,
            })
            .context("folded Main group")?;
        assert!(group.payload.is_none() && group.contents.is_empty());
        // Even a tempting small reference on a folded header must never enter
        // read_content. An attempted read of this absent original would fail.
        let mut folded = ChatBatch {
            placement: ChatPlacement::Append,
            entries: vec![ChatEntry::Item(group.clone())],
            before: None,
            current: None,
        };
        let ChatEntry::Item(item) = &mut folded.entries[0] else {
            unreachable!()
        };
        item.payload = Some(PayloadData::Deferred {
            reference: ContentRef {
                database_id: small_ref.database_id.clone(),
                target: ContentTarget::ItemPayload {
                    item_id: "absent-folded-payload".into(),
                },
            },
            byte_length: 1,
        });
        let unchanged = folded.clone();
        main.reader()
            .inline_timeline_payloads(&mut folded, demand())
            .await?;
        assert_eq!(folded, unchanged);
        harness.save(&small).await?;
        harness.save(&large).await?;
        for feed in [&mut live, &mut pending, &mut main] {
            feed.close().await?;
            feed.reader().close().await?;
        }
        env.runtime
            .thread_observations
            .observation_slot(&id)
            .retire(&harness.source);
        env.restart().await?;
        let mut cold = env.runtime.open_conversation_feed(&id, scope, one).await?;
        let latest = chat(&mut cold).await?;
        assert_eq!(latest.entries.len(), 1);
        let atom = member(&latest, &large_id)?;
        assert_eq!(
            atom.payload, latest_atom.payload,
            "SQLite changed the deferred owner"
        );
        let bytes = cold.reader().read_content(reference, range).await?;
        assert_eq!(bytes.bytes.as_slice(), large_record.payload.as_ref());
        let older = cold
            .reader()
            .load_older(
                latest.before.as_deref().context("SQLite continuation")?,
                one,
            )
            .await?;
        assert_thinking(member(&older, &small_id)?, original_small)?;
        cold.close().await?;
        cold.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn short_user_and_assistant_envelopes_are_typed_live_and_after_flush_reopen() -> Result<()> {
    let frames =
        pl_provider_fixture::responses_text("inline assistant", "inline-part", support::MODEL);
    let delta = frames
        .iter()
        .position(|frame| frame["type"] == "response.output_text.delta")
        .context("delta")?;
    let stage = ReplyStage::new();
    let reply = stage.gated(frames[..=delta].to_vec(), frames[delta + 1..].to_vec());
    let mut env =
        support::Environment::new(vec![support::prompt_step("inline user", 0, reply)], vec![])
            .await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Local, "inline user").await?;
        let id = thread.thread.id.clone();
        support::reached(&stage).await?;
        env.runtime.synchronize_thread_observation(&id).await?;
        let mut live = env
            .runtime
            .open_conversation_feed(&id, ChatScope::Main, demand())
            .await?;
        let set = chat(&mut live).await?;
        let input = completed_items(&set)
            .find(|item| item.atom_kind == Some(ChatAtomKind::Input))
            .context("user Item")?;
        assert_text(input, "inline user")?;
        stage.release();
        let _ = support::completed_prompt(&env.runtime, &id, "inline user").await?;
        tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                let batch = chat(&mut live).await?;
                if let Some(item) = completed_items(&batch)
                    .find(|item| item.text_channel == Some(ThreadTextChannel::Final))
                {
                    assert_text(item, "inline assistant")?;
                    break Ok::<_, anyhow::Error>(());
                }
            }
        })
        .await??;
        env.runtime.synchronize_thread_observation(&id).await?;
        let channel = env.runtime.store.thread_persistence().history_channel(&id);
        channel
            .await_handoff_durable(&id, channel.handoff_ticket())
            .await?;
        live.close().await?;
        live.reader().close().await?;
        env.restart().await?;
        assert!(env.runtime.threads.observed_thread(&id).is_none());
        let mut cold = env
            .runtime
            .open_conversation_feed(&id, ChatScope::Main, demand())
            .await?;
        let set = chat(&mut cold).await?;
        assert_text(
            completed_items(&set)
                .find(|item| item.atom_kind == Some(ChatAtomKind::Input))
                .context("cold input")?,
            "inline user",
        )?;
        assert_text(
            completed_items(&set)
                .find(|item| item.text_channel == Some(ThreadTextChannel::Final))
                .context("cold assistant")?,
            "inline assistant",
        )?;
        cold.close().await?;
        cold.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

async fn compaction(
    harness: &mut Harness,
    event: ContextCompactionEvent,
) -> Result<Arc<PreparedEffect>> {
    harness.sequence += 1;
    let effect = ThreadEffectBatch {
        thread_id: harness.thread.id.clone(),
        sequence: harness.sequence,
        committed_at: harness.sequence as i64 + 10,
        context_compactions: vec![event].into(),
        ..Default::default()
    };
    let (_, mut prepared) = harness
        .projection
        .prepare(&harness.thread, &effect, &Default::default(), false)
        .await?;
    harness
        .projection
        .publish_prepared(&harness.session, &mut prepared)
        .await?;
    harness.source.publish_test_conversation(
        &harness.session,
        prepared.current_state.clone().context("current")?,
        prepared.current_handoff.clone(),
        prepared.current.timeline_update.generation(),
    )?;
    Ok(prepared)
}

#[tokio::test]
async fn compaction_original_owner_serves_inline_pending_and_sqlite_but_large_envelope_stays_deferred()
-> Result<()> {
    use sea_orm::{ConnectionTrait, Database, DatabaseBackend, Statement};
    let mut env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut harness = Harness::new(&env).await?;
        let id = harness.thread.id.clone();
        let started = compaction(
            &mut harness,
            ContextCompactionEvent::Started {
                operation_id: "small".into(),
                turn_id: None,
                attempt_id: None,
            },
        )
        .await?;
        harness.save(&started).await?;
        let mut live = env
            .runtime
            .open_conversation_feed(&id, ChatScope::Main, demand())
            .await?;
        let _ = chat(&mut live).await?;
        let finished = compaction(
            &mut harness,
            ContextCompactionEvent::Finished {
                operation_id: "small".into(),
                outcome: ContextCompactionOutcome::Changed {
                    context_revision: 9,
                },
            },
        )
        .await?;
        let append = chat(&mut live).await?;
        let item = completed_items(&append)
            .next()
            .context("compaction append")?;
        assert_eq!(item.kind, TimelineItemKind::Status);
        assert_eq!(item.atom_kind, Some(ChatAtomKind::Compaction));
        let value = inline_envelope(item)?;
        assert_eq!(value["type"], "contextCompaction");
        let Some(PayloadData::Inline { bytes }) = &item.payload else {
            unreachable!()
        };
        assert_eq!(bytes.as_slice(), finished.completions[0].payload.as_ref());
        let mut deferred = append.clone();
        let ChatEntry::Item(deferred_item) = &mut deferred.entries[0] else { unreachable!() };
        deferred_item.payload = finished.current.timeline[0].item.payload.clone();
        let tiny_demand = ReadDemand { max_items: 1, max_bytes: u32::try_from(deferred.encoded_len()?)? };
        live.reader().inline_timeline_payloads(&mut deferred, tiny_demand).await?;
        assert!(matches!(&deferred.entries[0], ChatEntry::Item(item) if matches!(item.payload, Some(PayloadData::Deferred { .. }))));
        live.reader().finish_batch(deferred, tiny_demand)?;
        assert_ne!(
            item.id,
            item.content_item_id
                .as_deref()
                .context("frozen content owner")?
        );
        assert_eq!(
            harness.session.durable_seq(),
            0,
            "delivery flushed the pending completion"
        );
        let mut pending = env
            .runtime
            .open_conversation_feed(&id, ChatScope::Main, demand())
            .await?;
        let set = chat(&mut pending).await?;
        assert_eq!(
            inline_envelope(completed_items(&set).next().context("pending Item")?)?,
            value
        );
        pending.close().await?;
        pending.reader().close().await?;
        harness.save(&finished).await?;
        let path = env
            .runtime
            .store
            .registered_session_paths(&id)?
            .history_database();
        let db = Database::connect(format!("sqlite://{}?mode=ro", path.display())).await?;
        let stored = db
            .query_one_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "SELECT metadata FROM timeline_items WHERE item_id=?",
                vec![item.id.clone().into()],
            ))
            .await?
            .context("derived row")?;
        let stored: TimelineItem =
            serde_json::from_slice(&stored.try_get::<Vec<u8>>("", "metadata")?)?;
        assert!(
            matches!(stored.payload, Some(PayloadData::Deferred { .. })),
            "derived table copied an envelope"
        );
        db.close().await?;
        live.close().await?;
        live.reader().close().await?;
        env.runtime
            .thread_observations
            .observation_slot(&id)
            .retire(&harness.source);
        env.restart().await?;
        let mut cold = env
            .runtime
            .open_conversation_feed(&id, ChatScope::Main, demand())
            .await?;
        let set = chat(&mut cold).await?;
        assert_eq!(
            inline_envelope(completed_items(&set).next().context("SQLite Item")?)?,
            value
        );
        cold.close().await?;
        cold.reader().close().await?;
        // Compaction's receipt is intentionally small; its failure description
        // is not a giant payload field. A real text completion whose <=4096-byte
        // body is frozen inside the envelope instead exercises JSON byte-array
        // expansion against a body-sized frame budget (not a large body ref).
        let mut harness = Harness::new(&env).await?;
        let id = harness.thread.id.clone();
        let body="x".repeat(4096);
        let envelope_demand=ReadDemand {max_items:1,max_bytes:u32::try_from(body.len())?};
        let mut large = env
            .runtime
            .open_conversation_feed(&id, ChatScope::Main, envelope_demand)
            .await?;
        let _ = chat(&mut large).await?;
        let finished=harness.effect(vec![super::atoms::start("large-envelope",false)],
            vec![super::atoms::finish("large-envelope",false,&body)?]).await?;
        assert!(finished.completions[0].payload.len() > envelope_demand.max_bytes as usize);
        let batch = chat(&mut large).await?;
        let item = completed_items(&batch).next().context("large Text envelope")?;
        assert!(matches!(item.payload, Some(PayloadData::Deferred { .. })));
        let Some(PayloadData::Deferred {reference,byte_length})=&item.payload else {unreachable!()};
        let original=large.reader().read_content(reference,ContentRange {offset:0,max_bytes:u32::try_from(*byte_length)?}).await?;
        assert_eq!(original.bytes.as_slice(),finished.completions[0].payload.as_ref());
        let envelope:serde_json::Value=serde_json::from_slice(&original.bytes)?;
        assert_eq!(envelope["contract"],"anywork.chat/1");
        assert_eq!(envelope["type"],"text");
        assert!(envelope["bodies"].as_array().context("frozen body")?.iter().any(|value|
            serde_json::from_value::<Vec<u8>>(value["inline"].clone()).is_ok_and(|bytes|bytes==body.as_bytes())));
        let exact = ReadDemand {
            max_items: 1,
            max_bytes: u32::try_from(batch.encoded_len()?)?,
        };
        large.reader().finish_batch(batch.clone(), exact)?;
        assert!(
            large
                .reader()
                .finish_batch(
                    batch.clone(),
                    ReadDemand {
                        max_bytes: exact.max_bytes - 1,
                        ..exact
                    }
                )
                .is_err()
        );
        let mut tiny = env
            .runtime
            .open_conversation_feed(
                &id,
                ChatScope::Main,
                ReadDemand {
                    max_bytes: exact.max_bytes + 2048,
                    ..exact
                },
            )
            .await?;
        let set = chat(&mut tiny).await?;
        assert_eq!(
            completed_items(&set)
                .next()
                .context("tiny Deferred item")?
                .id,
            item.id
        );
        assert!(matches!(
            completed_items(&set).next().unwrap().payload,
            Some(PayloadData::Deferred { .. })
        ));
        harness.save(&finished).await?;
        tiny.close().await?;
        tiny.reader().close().await?;
        large.close().await?;
        large.reader().close().await?;
        env.runtime
            .thread_observations
            .observation_slot(&id)
            .retire(&harness.source);
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}
