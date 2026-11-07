use super::allocation::{self, Sample};
use super::atoms::Harness;
use super::*;
use crate::studio::thread_projection::{CurrentHandoff, FrozenCurrentProjection};

fn item(index: u64) -> TimelineItem {
    TimelineItem {
        id: format!("text:换行\n\"🦀-{index}"),
        kind: TimelineItemKind::Text,
        source: ChatSourceId::ForegroundTurn {
            turn_id: "来源\\\"非ASCII".into(),
        },
        atom_kind: Some(ChatAtomKind::Text),
        delivery: ChatDeliveryKind::Foreground,
        text_channel: Some(ThreadTextChannel::Final),
        turn_id: Some("turn\n\"中文".into()),
        started_at: Some(1),
        finished_at: Some(2),
        outcome: Some(ChatTerminalOutcome::Completed),
        summary: None,
        members: None,
        contents: Vec::new(),
        payload: None,
        content_item_id: None,
        position: Some(index),
        admission_closed: true,
    }
}

fn handoff(count: u64, tail: bool) -> Arc<CurrentHandoff> {
    let mut after = CurrentProjection::empty(1, ThreadStatus::Idle);
    if tail {
        let mut live = item(count);
        live.position = None;
        after.items.push(live);
    }
    let after = FrozenCurrentProjection::new(after);
    Arc::new(CurrentHandoff::new(
        0,
        after.clone(),
        after,
        (0..count)
            .map(|index| ChatEntry::Item(Box::new(item(index))))
            .collect::<Vec<_>>()
            .into(),
    ))
}

fn install(feed: &mut ConversationFeed, harness: &Harness, handoff: Arc<CurrentHandoff>) {
    feed.cut = Some(Arc::new(ConversationCut {
        serial: feed.seen_serial + 1,
        session: harness.session.clone(),
        head: harness.session.head_seq(),
        handoff,
    }));
}

#[test]
fn cut_fragment_lengths_match_serde_for_every_prefix_and_current_tail() -> Result<()> {
    for count in [1_u64, 16, 64] {
        for tail in [false, true] {
            let handoff = handoff(count, tail);
            let mut measure = CutMeasure::new(&handoff, handoff.entries(), true)?;
            let mut entries = Vec::new();
            let mut bytes = 0;
            for (index, entry) in handoff.entries().iter().enumerate() {
                let encoded = entry_json_bytes(entry)?;
                measure = measure.after_entry(entry, encoded)?;
                bytes += encoded;
                entries.push(entry.clone());
                let batch = ChatBatch {
                    placement: ChatPlacement::Append,
                    entries: entries.clone(),
                    before: None,
                    current: Some(handoff.projection_after_items(index + 1)),
                };
                assert_eq!(
                    measure.frame_bytes(bytes, entries.len())?,
                    batch.encoded_len()?,
                    "count={count}, tail={tail}, delivered={}",
                    index + 1
                );
            }
        }
    }
    Ok(())
}

#[tokio::test]
async fn cut_frames_preserve_order_current_retirement_and_delivery_frontier() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        for max_items in [1, 16, 64] {
            let harness = Harness::new(&env).await?;
            let mut feed = env
                .runtime
                .open_conversation_feed(
                    &harness.thread.id,
                    ChatScope::Main,
                    ReadDemand {
                        max_items,
                        ..demand()
                    },
                )
                .await?;
            let _ = chat(&mut feed).await?;
            let cut = handoff(64, true);
            install(&mut feed, &harness, cut.clone());
            let serial = feed.cut.as_ref().unwrap().serial;
            let mut delivered = 0;
            let mut frames = 0;
            while delivered < 64 {
                let batch = chat(&mut feed).await?;
                frames += 1;
                assert_eq!(batch.entries.len(), max_items as usize);
                for entry in &batch.entries {
                    assert_eq!(*entry, cut.entries()[delivered]);
                    delivered += 1;
                }
                let current = batch.current.as_ref().context("split current")?;
                assert_eq!(*current, cut.projection_after_items(delivered));
                assert!(current.items.iter().all(|item| item.position.is_none()));
                if delivered < 64 {
                    assert_eq!(feed.cut_entry, delivered);
                    assert!(feed.seen_serial < serial);
                    assert!(feed.cut_measure.is_some());
                }
            }
            assert_eq!(frames, 64 / max_items as usize);
            assert_eq!(feed.seen_serial, serial);
            assert!(feed.cut.is_none() && feed.cut_entries.is_none() && feed.cut_measure.is_none());
            feed.close().await?;
            feed.reader().close().await?;
        }
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[derive(Debug)]
struct CutCost {
    items: usize,
    requests: Sample,
    delivered_json_bytes: usize,
}

async fn measured_chat(feed: &mut ConversationFeed) -> Result<(ChatBatch, Sample)> {
    let mut total = Sample::default();
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            // Only the real recv future's polls are observed. In particular,
            // chat()'s test-side validation/encoding is not part of this future.
            let (event, sample) = allocation::measure(feed.recv()).await?;
            total.add(sample);
            match event?.context("feed ended during allocation observation")? {
                ConversationEvent::Chat { batch } => return Ok((*batch, total.validate()?)),
                ConversationEvent::State { .. } => {}
            }
        }
    })
    .await?
}

fn assert_linear_allocation_growth(scenario: &str, samples: &[CutCost; 3]) -> Result<()> {
    // Diagnostics, arithmetic checks and all JSON validation happen with the
    // allocator observer disabled. These are actual allocator request bytes,
    // not selected-helper calls or a claim about exact serde invocation count.
    eprintln!("{scenario}: {samples:?}");
    for sample in samples {
        ensure!(
            sample.requests.bytes > 0 && sample.delivered_json_bytes > 0,
            "{scenario}: allocation/output observation must be nonempty: {sample:?}"
        );
    }
    let [one, small, large] = samples;
    assert_eq!([one.items, small.items, large.items], [1, 16, 64]);
    // With four times as many candidates, linear work per delivered JSON byte
    // stays near one; the old quadratic loops approach four. A factor of two
    // separates those costs without adding a latency or production limit.
    // Cross-multiply to avoid floating point and fail explicitly on overflow.
    let observed = (large.requests.bytes as u128)
        .checked_mul(small.delivered_json_bytes as u128)
        .context("allocation growth comparison overflow")?;
    let allowed = (small.requests.bytes as u128)
        .checked_mul(large.delivered_json_bytes as u128)
        .and_then(|bytes| bytes.checked_mul(2))
        .context("allocation growth comparison overflow")?;
    ensure!(
        observed <= allowed,
        "{scenario}: allocation requests per delivered JSON byte grew more than \
         twofold from 16 to 64 candidates: {small:?} -> {large:?}"
    );
    Ok(())
}

#[tokio::test]
async fn single_frame_without_payload_has_linear_allocation_growth() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut samples = Vec::new();
        for count in [1_u32, 16, 64] {
            let harness = Harness::new(&env).await?;
            let requested = ReadDemand {
                max_items: count,
                ..demand()
            };
            let mut feed = env
                .runtime
                .open_conversation_feed(&harness.thread.id, ChatScope::Main, requested)
                .await?;
            let _ = chat(&mut feed).await?; // Fixture setup is outside measurement.
            let cut = handoff(u64::from(count), true);
            install(&mut feed, &harness, cut.clone());
            let serial = feed.cut.as_ref().unwrap().serial;
            let (batch, requests) = measured_chat(&mut feed).await?;

            batch.validate_for(&ChatScope::Main)?;
            assert_eq!(batch.placement, ChatPlacement::Append);
            assert_eq!(batch.entries.as_slice(), cut.entries().as_ref());
            assert_eq!(batch.entries.len(), count as usize);
            assert_eq!(batch.current.as_ref(), Some(cut.after().projection()));
            let delivered_json_bytes = batch.encoded_len()?;
            ensure!(delivered_json_bytes <= requested.max_bytes as usize);
            assert_eq!(feed.seen_serial, serial);
            assert!(feed.cut.is_none() && feed.cut_entries.is_none() && feed.cut_measure.is_none());
            samples.push(CutCost {
                items: batch.entries.len(),
                requests,
                delivered_json_bytes,
            });
            feed.close().await?;
            feed.reader().close().await?;
        }
        let samples: [CutCost; 3] = samples
            .try_into()
            .map_err(|_| anyhow::anyhow!("missing allocation observation fixture"))?;
        assert_linear_allocation_growth("no payload", &samples)
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn single_frame_with_prior_deferred_candidates_has_linear_allocation_growth() -> Result<()> {
    use crate::studio::storage::history::conversation::timeline;
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut samples = Vec::new();
        for count in [1_u32, 16, 64] {
            let harness = Harness::new(&env).await?;
            let requested = ReadDemand {
                max_items: count,
                max_bytes: 64 * 1024,
            };
            let mut feed = env
                .runtime
                .open_conversation_feed(&harness.thread.id, ChatScope::Main, requested)
                .await?;
            let _ = chat(&mut feed).await?;
            let database_id = harness
                .history
                .conversation_database_id()
                .await?
                .context("database")?;
            // Every original is eligible for the normal inline pre-read bound,
            // but its four-byte expansion alone consumes this frame budget.
            // Thus accepted early entries remain Deferred as later ones join.
            let payload_bytes = requested.max_bytes as usize / 4;
            ensure!(payload_bytes <= CONTENT_WINDOW_MAX_BYTES as usize);
            let payload: Arc<[u8]> = vec![b'0'; payload_bytes].into();
            let originals = harness
                .session
                .publish_batch(
                    (0..count)
                        .map(|index| {
                            core::ChatDraft::new(
                                format!("deferred-original-{index}"),
                                "text",
                                payload.clone(),
                            )
                        })
                        .collect(),
                )
                .await?;
            assert_eq!(originals.len(), count as usize);
            let mut candidates = Vec::new();
            for (index, original) in originals.iter().enumerate() {
                let mut candidate = item(index as u64);
                candidate.content_item_id = Some(original.header.item_id.clone());
                candidate.payload = Some(PayloadData::Deferred {
                    reference: ContentRef {
                        database_id: database_id.clone(),
                        target: ContentTarget::ItemPayload {
                            item_id: original.header.item_id.clone(),
                        },
                    },
                    byte_length: payload_bytes as u64,
                });
                let entry = ChatEntry::Item(Box::new(candidate));
                let inline_bound = timeline::inline_entry_bytes(&entry)?
                    .context("Deferred fixture must reach the inline pre-read bound")?;
                ensure!(
                    inline_bound > requested.max_bytes as usize,
                    "Deferred fixture must be rejected by the pre-read budget"
                );
                candidates.push(entry);
            }
            let after =
                FrozenCurrentProjection::new(CurrentProjection::empty(1, ThreadStatus::Idle));
            let cut = Arc::new(CurrentHandoff::new(
                harness.session.head_seq(),
                after.clone(),
                after,
                candidates.into(),
            ));
            install(&mut feed, &harness, cut.clone());
            let serial = feed.cut.as_ref().unwrap().serial;
            let (batch, requests) = measured_chat(&mut feed).await?;

            batch.validate_for(&ChatScope::Main)?;
            assert_eq!(batch.placement, ChatPlacement::Append);
            assert_eq!(batch.entries.as_slice(), cut.entries().as_ref());
            assert_eq!(batch.entries.len(), count as usize);
            assert_eq!(batch.current.as_ref(), Some(cut.after().projection()));
            let delivered_json_bytes = batch.encoded_len()?;
            ensure!(delivered_json_bytes <= requested.max_bytes as usize);
            assert_eq!(feed.seen_serial, serial);
            assert_eq!(feed.delivered, harness.session.head_seq());
            assert!(feed.cut.is_none() && feed.cut_entries.is_none() && feed.cut_measure.is_none());

            // Actual reads after observation prove every unchanged Deferred
            // still targets its legitimate original owner and exact bytes.
            for entry in &batch.entries {
                let ChatEntry::Item(item) = entry else {
                    bail!("Main fixture emitted a non-Item");
                };
                let Some(PayloadData::Deferred {
                    reference,
                    byte_length,
                }) = &item.payload
                else {
                    bail!("pre-read budget fixture did not remain Deferred");
                };
                assert_eq!(*byte_length, payload_bytes as u64);
                let read = feed
                    .reader()
                    .read_content(
                        reference,
                        ContentRange {
                            offset: 0,
                            max_bytes: u32::try_from(*byte_length)?,
                        },
                    )
                    .await?;
                assert!(read.sealed);
                assert_eq!(read.available_through, *byte_length);
                assert_eq!(read.bytes.as_slice(), payload.as_ref());
            }
            samples.push(CutCost {
                items: batch.entries.len(),
                requests,
                delivered_json_bytes,
            });
            feed.close().await?;
            feed.reader().close().await?;
        }
        let samples: [CutCost; 3] = samples
            .try_into()
            .map_err(|_| anyhow::anyhow!("missing Deferred allocation observation fixture"))?;
        assert_linear_allocation_growth("prior Deferred", &samples)
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn rejected_candidate_keeps_the_cut_prefix_and_remains_deliverable() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let harness = Harness::new(&env).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(&harness.thread.id, ChatScope::Main, demand())
            .await?;
        let _ = chat(&mut feed).await?;
        let cut = handoff(2, true);
        let first = ChatBatch {
            placement: ChatPlacement::Append,
            entries: vec![cut.entries()[0].clone()],
            before: None,
            current: Some(cut.projection_after_items(1)),
        };
        install(&mut feed, &harness, cut.clone());
        let serial = feed.seen_serial;
        let delivered = feed.delivered;
        feed.demand.max_bytes = u32::try_from(first.encoded_len()? - 1)?;
        // Inspect the private receive boundary before recv's required error close.
        loop {
            match feed.receive().await {
                Ok(Some(ConversationEvent::State { .. })) => {}
                Err(error) => {
                    assert!(matches!(
                        error.downcast_ref::<core::ChatError>(),
                        Some(core::ChatError::InvalidDemand(_))
                    ));
                    break;
                }
                _ => bail!("undersized candidate unexpectedly delivered"),
            }
        }
        assert_eq!(feed.cut_entry, 0);
        assert_eq!(feed.delivered, delivered);
        assert_eq!(feed.seen_serial, serial);
        feed.demand.max_bytes += 1;
        let first = chat(&mut feed).await?;
        assert_eq!(first.entries, vec![cut.entries()[0].clone()]);
        assert_eq!(feed.cut_entry, 1, "rejected second candidate advanced");
        assert_eq!(feed.seen_serial, serial);
        let second = chat(&mut feed).await?;
        assert_eq!(second.entries, vec![cut.entries()[1].clone()]);
        assert_eq!(
            second.current.as_ref().context("final current")?,
            cut.after().projection()
        );
        assert!(feed.cut_measure.is_none());
        feed.close().await?;
        feed.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn tiny_inline_can_admit_a_candidate_whose_deferred_reference_exceeds_budget() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let harness = Harness::new(&env).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(&harness.thread.id, ChatScope::Main, demand())
            .await?;
        let _ = chat(&mut feed).await?;
        let payload: Arc<[u8]> = Arc::from(b"0".as_slice());
        let published = harness
            .session
            .publish_batch(vec![core::ChatDraft::new(
                "tiny-original",
                "text",
                payload.clone(),
            )])
            .await?;
        let reference = ContentRef {
            database_id: harness
                .history
                .conversation_database_id()
                .await?
                .context("database")?,
            target: ContentTarget::ItemPayload {
                item_id: published[0].header.item_id.clone(),
            },
        };
        let mut candidate = item(0);
        candidate.content_item_id = Some(published[0].header.item_id.clone());
        candidate.payload = Some(PayloadData::Deferred {
            reference: reference.clone(),
            byte_length: 1,
        });
        let after = FrozenCurrentProjection::new(CurrentProjection::empty(1, ThreadStatus::Idle));
        let cut = Arc::new(CurrentHandoff::new(
            1,
            after.clone(),
            after,
            vec![ChatEntry::Item(Box::new(candidate))].into(),
        ));
        let deferred = ChatBatch {
            placement: ChatPlacement::Append,
            entries: cut.entries().to_vec(),
            before: None,
            current: Some(cut.projection_after_items(1)),
        };
        feed.demand.max_bytes = u32::try_from(deferred.encoded_len()? - 1)?;
        install(&mut feed, &harness, cut);
        let batch = chat(&mut feed).await?;
        let [ChatEntry::Item(item)] = batch.entries.as_slice() else {
            bail!("one tiny Item")
        };
        assert_eq!(
            item.payload,
            Some(PayloadData::Inline { bytes: vec![b'0'] })
        );
        assert!(batch.encoded_len()? < deferred.encoded_len()?);
        let read = feed
            .reader()
            .read_content(
                &reference,
                ContentRange {
                    offset: 0,
                    max_bytes: 1,
                },
            )
            .await?;
        assert_eq!(read.bytes.as_slice(), payload.as_ref());
        feed.close().await?;
        feed.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}
