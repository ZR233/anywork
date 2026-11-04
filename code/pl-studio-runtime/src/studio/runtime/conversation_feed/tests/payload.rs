use super::atoms::Harness;
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
