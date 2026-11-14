//! Product-independent completion owner, scoped demand reads and immutable content ranges.
//! Business payloads and public protocol mapping belong to the producer/host, not Core.

mod cursor;
mod detail;
mod error;
mod history;
mod item;
mod read;

mod session;
mod tail;

pub use cursor::{
    CHAT_CURSOR_VERSION, CHAT_INDEX_VERSION, ChatBudget, ChatCompletionCursor, ChatCursor,
    ChatHistoryItemRequest, ChatHistoryPage, ChatHistoryRequest, ChatItemRequest, ChatPage,
    ChatPageItem, ChatPageRequest, MAX_READ_BYTES, MAX_READ_ITEMS, PayloadData, PayloadMode,
    ReadDemand, TimelineEpoch, select_payload,
};
pub use detail::{
    ChatContent, ChatContentKey, ContentBytes, ContentData, ContentDescriptor, ContentManifestPage,
    ContentManifestRequest, ContentReadRequest, ContentRef, ContentWindow, IndexedText,
};
pub use error::ChatError;
pub use history::ChatHistory;
pub use item::{
    ChatContents, ChatDraft, ChatItem, ChatItemHeader, ChatKey, ChatPublicationSeed, ChatQuery,
    PresentationPart, presentation_item_id, presentation_prefix,
};
pub use session::{ChatAdmission, Session, WeakSession};
pub use tail::{ChatCompletedBatch, ChatTail, ChatTailBaseline, ChatTailUpdate};

#[cfg(test)]
mod record_tests {
    use super::*;
    use crate::test_fixture_timeline as support;
    use std::sync::{Arc, atomic::Ordering};
    use support::*;

    fn pending_cut(session: &Session) -> (u64, u64, usize, usize) {
        session.with_timeline(|state| {
            let (records, contents) = state.pending_counts();
            (state.head, state.durable, records, contents)
        })
    }

    struct HeaderOnly<'a>(&'a Budget);
    impl ChatBudget for HeaderOnly<'_> {
        fn fixed_bytes(&self) -> usize {
            self.0.fixed_bytes()
        }
        fn item_bytes(&self, h: &ChatItemHeader, mode: PayloadMode) -> usize {
            self.0.item_bytes(h, mode)
        }
        fn manifest_bytes(&self, d: &ContentDescriptor) -> usize {
            self.0.manifest_bytes(d)
        }
        fn allow_inline(&self, _: &ChatItemHeader) -> bool {
            false
        }
    }

    #[test]
    fn sequence_exhaustion_preserves_the_previous_seed() {
        let mut seed = ChatPublicationSeed {
            head_seq: i64::MAX as u64 - 1,
        };
        assert_eq!(seed.advance().unwrap(), i64::MAX as u64);
        let old = seed.clone();
        assert!(matches!(seed.advance(), Err(ChatError::SeqExhausted)));
        assert_eq!(seed, old);
    }

    #[tokio::test]
    async fn all_classes_and_real_parent_use_the_same_cut_and_release_their_indexes() {
        let session = Session::new(Stored::default(), epoch("records"));
        let parent = ChatKey::new("turn", "target").unwrap();
        let mut one = draft("one", "原文");
        one.parent_id = Some(parent.clone());
        let mut diagnostic =
            ChatDraft::new("diagnostic", "diagnostic", Arc::from(b"raw".as_slice()));
        diagnostic.parent_id = Some(parent.clone());
        session
            .publish_batch(vec![one, diagnostic, draft("other", "其他")])
            .await
            .unwrap();
        let all = ChatQuery {
            query_class: None,
            parent_id: Some(parent),
        };
        let first = session
            .page(
                ChatPageRequest::latest(all.clone(), demand(1)),
                &Budget::default(),
            )
            .await
            .unwrap();
        assert_eq!(sequences(&first.items), [2]);
        assert_eq!(first.ceiling, 3);
        session
            .publish_batch(vec![draft("future", "后来")])
            .await
            .unwrap();
        let second = session
            .page(
                ChatPageRequest::before(first.before.unwrap(), demand(4)),
                &Budget::default(),
            )
            .await
            .unwrap();
        assert_eq!(sequences(&second.items), [1]);
        assert_eq!(second.ceiling, 3);
        session.confirm_durable(4).unwrap();
        session.with_timeline(|state| {
            assert!(state.pending_index(Some(&all)).is_none());
            assert!(state.pending_index(Some(&query())).is_none());
        });
    }

    #[tokio::test]
    async fn durable_confirmation_releases_all_secondary_record_and_content_references_exactly() {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("release"));
        let records = session
            .publish_batch(vec![
                with_body(
                    draft("a", "原始正文"),
                    "body",
                    ContentData::Bytes(Arc::from(b"owned body".as_slice())),
                ),
                draft("b", "原始正文"),
            ])
            .await
            .unwrap();
        let body = records[0].contents.values().next().unwrap().clone();
        let body_key = body.descriptor.key.clone();
        let weak = Arc::downgrade(&records[0]);
        let remaining = Arc::downgrade(&records[1]);
        stored.insert((*records[0]).clone());
        let before = pending_cut(&session);
        let record_references_before = Arc::strong_count(&records[0]);
        let content_references_before = Arc::strong_count(&body);
        session.confirm_durable(1).unwrap();
        let after = pending_cut(&session);
        assert_eq!(before, (2, 0, 2, 1));
        assert_eq!(after, (2, 1, 1, 0));
        eprintln!(
            "core_pending_release history=controlled \
         head_before={} durable_before={} pending_completion_records_before={} pending_content_keys_before={} \
         head_after={} durable_after={} pending_completion_records_after={} pending_content_keys_after={} \
         first_record_strong_before={} first_record_strong_after={} \
         content_strong_before={} content_strong_after={}",
            before.0,
            before.1,
            before.2,
            before.3,
            after.0,
            after.1,
            after.2,
            after.3,
            record_references_before,
            Arc::strong_count(&records[0]),
            content_references_before,
            Arc::strong_count(&body),
        );
        assert_eq!(
            Arc::strong_count(&records[0]),
            1,
            "every index released the first Arc"
        );
        assert_eq!(
            Arc::strong_count(&body),
            2,
            "only the frozen manifest and this reader retain the body"
        );
        assert!(
            session
                .with_timeline(|state| state.pending_content(&body_key))
                .is_none()
        );
        assert!(Arc::strong_count(&records[1]) > 1);
        drop(records);
        assert!(weak.upgrade().is_none());
        assert!(
            remaining.upgrade().is_some(),
            "uncommitted member stays pending"
        );
        assert!(matches!(
            session.confirm_durable(3),
            Err(ChatError::InvalidArgument(_))
        ));
        assert_eq!((session.durable_seq(), session.head_seq()), (1, 2));
        session.confirm_durable(1).unwrap();
        assert_eq!(pending_cut(&session), after);
    }

    fn item_request(session: &Session, item_id: &str, ceiling: Option<u64>) -> ChatItemRequest {
        ChatItemRequest {
            epoch: session.epoch(),
            item_id: item_id.into(),
            ceiling,
            demand: demand(1),
        }
    }

    #[tokio::test]
    async fn read_item_pending_hit_and_pending_only_miss_do_no_history_io_or_manifest_clone() {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("point-pending"));
        let records = session
            .publish_batch(vec![
                with_body(
                    draft("first", "原始正文"),
                    "body",
                    ContentData::Bytes(Arc::from(b"separate body".as_slice())),
                ),
                draft("future", "原始正文"),
            ])
            .await
            .unwrap();
        let identity_reads = stored.reads.item.load(Ordering::SeqCst);
        let manifests = Arc::strong_count(&records[0].contents);
        let item = session
            .read_item(item_request(&session, "first", None), &Budget::default())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(item.header, records[0].header);
        let PayloadData::Inline(payload) = &item.payload else {
            panic!("small envelope")
        };
        assert!(Arc::ptr_eq(payload, &records[0].payload));
        assert_eq!(Arc::strong_count(&records[0].contents), manifests);
        assert!(
            session
                .read_item(
                    item_request(&session, "future", Some(1)),
                    &Budget::default()
                )
                .await
                .unwrap()
                .is_none(),
            "known future pending identity must not fall through to history"
        );
        assert!(
            session
                .read_item(item_request(&session, "missing", None), &Budget::default())
                .await
                .unwrap()
                .is_none()
        );
        assert_eq!(stored.reads.item.load(Ordering::SeqCst), identity_reads);
        assert!(stored.reads.item_envelopes.lock().unwrap().is_empty());
        assert!(stored.reads.pages.lock().unwrap().is_empty());
        assert_eq!(stored.reads.manifests.load(Ordering::SeqCst), 0);
        assert!(stored.reads.ranges.lock().unwrap().is_empty());
        let weak = Arc::downgrade(&records[0]);
        for record in records.iter() {
            stored.insert((**record).clone());
        }
        session.confirm_durable(2).unwrap();
        drop(records);
        assert!(
            weak.upgrade().is_none(),
            "envelope does not retain the record/contents owner"
        );
        assert_eq!(
            payload.as_ref(),
            "原始正文".as_bytes(),
            "returned payload survives commit cleanup"
        );
    }

    #[tokio::test]
    async fn read_item_cold_history_reads_only_the_requested_envelope_with_reserved_budget() {
        let stored = Stored::with([ChatItem::complete(
            with_body(
                draft("durable", "原始正文"),
                "body",
                ContentData::Bytes(Arc::from(b"not requested".as_slice())),
            ),
            1,
        )]);
        let session = Session::new(stored.clone(), epoch("point-cold"));
        let budget = Budget::default();
        let request = item_request(&session, "durable", None);
        let max_bytes = request.demand.max_bytes - budget.fixed_bytes();
        let item = session.read_item(request, &budget).await.unwrap().unwrap();
        assert_eq!((session.head_seq(), session.durable_seq()), (1, 1));
        assert_eq!(
            (item.header.item_id.as_str(), item.header.append_seq),
            ("durable", 1)
        );
        assert!(matches!(item.payload, PayloadData::Inline(_)));
        assert_eq!(
            stored.reads.item_envelopes.lock().unwrap().as_slice(),
            [ChatHistoryItemRequest {
                item_id: "durable".into(),
                ceiling: 1,
                demand: ReadDemand::new(1, max_bytes)
            },]
        );
        assert_eq!(
            stored.reads.item.load(Ordering::SeqCst),
            0,
            "never use publication item()"
        );
        assert_eq!(
            stored.reads.payload_bytes.load(Ordering::SeqCst),
            "原始正文".len()
        );
        assert_eq!(stored.reads.manifests.load(Ordering::SeqCst), 0);
        assert!(stored.reads.ranges.lock().unwrap().is_empty());
        assert!(
            session
                .read_item(item_request(&session, "durable", Some(0)), &budget)
                .await
                .unwrap()
                .is_none()
        );
        assert_eq!(stored.reads.item_envelopes.lock().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn read_item_defers_large_payloads_without_loading_contents_in_pending_or_history() {
        for durable in [false, true] {
            let stored = Stored::default();
            let session = Session::new(stored.clone(), epoch("point-large"));
            let mut large = draft("large", "原始正文");
            large.payload = Arc::from(vec![b'x'; 2 * 1024 * 1024]);
            let records = session
                .publish_batch(vec![with_body(
                    large,
                    "body",
                    ContentData::Bytes(Arc::from(vec![b'y'; 4 * 1024 * 1024])),
                )])
                .await
                .unwrap();
            if durable {
                stored.insert((*records[0]).clone());
                session.confirm_durable(1).unwrap();
            }
            let manifests = Arc::strong_count(&records[0].contents);
            let identity_reads = stored.reads.item.load(Ordering::SeqCst);
            let mut request = item_request(&session, "large", None);
            request.demand = ReadDemand::new(20, 512);
            let item = session
                .read_item(request, &Budget::default())
                .await
                .unwrap()
                .unwrap();
            assert_eq!(
                item.payload,
                PayloadData::Deferred {
                    item_id: "large".into(),
                    byte_length: 2 * 1024 * 1024,
                }
            );
            assert_eq!(Arc::strong_count(&records[0].contents), manifests);
            assert_eq!(stored.reads.item.load(Ordering::SeqCst), identity_reads);
            assert_eq!(
                stored.reads.item_envelopes.lock().unwrap().len(),
                usize::from(durable)
            );
            assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 0);
            assert_eq!(stored.reads.manifests.load(Ordering::SeqCst), 0);
            assert!(stored.reads.ranges.lock().unwrap().is_empty());
        }
    }

    #[tokio::test]
    async fn read_item_miss_captures_d_before_new_snapshot_even_when_writer_commits_and_cleans() {
        for explicit_cut in [None, Some(1)] {
            let stored = Stored::with([record_identified("old", 1, "durable prefix")]);
            let gate = Arc::new(HistoryGate::new());
            let mut history = GatedHistory::new(stored.clone());
            history.read_item_gate = Some(gate.clone());
            let session = Session::new(history, epoch("point-cut"));
            let reading = {
                let session = session.clone();
                tokio::spawn(async move {
                    session
                        .read_item(
                            item_request(&session, "future", explicit_cut),
                            &Budget::default(),
                        )
                        .await
                })
            };
            gate.entered().await;
            let records = session
                .publish_batch(vec![draft("future", "原始正文")])
                .await
                .unwrap();
            stored.insert((*records[0]).clone());
            session.confirm_durable(2).unwrap();
            gate.release();
            assert!(reading.await.unwrap().unwrap().is_none());
            assert_eq!(
                stored.reads.item_envelopes.lock().unwrap()[0].ceiling,
                1,
                "fresh history snapshot must still honor captured D/H, not latest D"
            );
            gate.release();
            let after_cleanup = session
                .read_item(item_request(&session, "future", None), &Budget::default())
                .await
                .unwrap()
                .unwrap();
            assert_eq!(after_cleanup.header.append_seq, 2);
            assert_eq!(stored.reads.item_envelopes.lock().unwrap()[1].ceiling, 2);
        }
    }

    #[tokio::test]
    async fn read_item_keeps_absence_budget_epoch_and_history_errors_distinct() {
        for durable in [false, true] {
            let stored = Stored::default();
            let session = Session::new(stored.clone(), epoch("point-errors"));
            let records = session
                .publish_batch(vec![draft("one", "原始正文")])
                .await
                .unwrap();
            if durable {
                stored.insert((*records[0]).clone());
                session.confirm_durable(1).unwrap();
            }
            let budget = Budget::default();
            let missing = session
                .read_item(item_request(&session, "missing", None), &budget)
                .await
                .unwrap();
            assert!(missing.is_none());
            let mut tiny = item_request(&session, "one", None);
            tiny.demand = ReadDemand::new(1, budget.fixed_bytes() + 1);
            assert!(matches!(
                session.read_item(tiny, &budget).await,
                Err(ChatError::InvalidDemand(_))
            ));
            let mut stale = item_request(&session, "one", None);
            stale.epoch = epoch("retired");
            assert!(matches!(
                session.read_item(stale, &budget).await,
                Err(ChatError::EpochMismatch { .. })
            ));
            assert!(matches!(
                session
                    .read_item(item_request(&session, "one", Some(2)), &budget)
                    .await,
                Err(ChatError::InvalidArgument(_))
            ));
            assert!(matches!(
                session
                    .read_item(item_request(&session, "", None), &budget)
                    .await,
                Err(ChatError::InvalidArgument(_))
            ));
            if durable {
                stored.fail_read_item.store(true, Ordering::SeqCst);
                assert!(matches!(
                    session
                        .read_item(item_request(&session, "one", None), &budget)
                        .await,
                    Err(ChatError::History(_))
                ));
                assert!(
                    session
                        .read_item(item_request(&session, "one", None), &budget)
                        .await
                        .unwrap()
                        .is_some(),
                    "a failed read does not consume the fixed identity"
                );
            }
        }
    }

    #[tokio::test]
    async fn read_item_explicit_detail_can_inline_work_while_header_only_demand_never_fetches_it() {
        for durable in [false, true] {
            let stored = Stored::default();
            let session = Session::new(stored.clone(), epoch("point-payload-policy"));
            let records = session
                .publish_batch(vec![draft("work", "原始正文")])
                .await
                .unwrap();
            if durable {
                stored.insert((*records[0]).clone());
                session.confirm_durable(1).unwrap();
            }
            let budget = Budget::default();
            let detail = session
                .read_item(item_request(&session, "work", None), &budget)
                .await
                .unwrap()
                .unwrap();
            assert!(matches!(detail.payload, PayloadData::Inline(_)));
            stored.reads.payload_bytes.store(0, Ordering::SeqCst);
            let header_only = HeaderOnly(&budget);
            let deferred = session
                .read_item(item_request(&session, "work", None), &header_only)
                .await
                .unwrap()
                .unwrap();
            assert!(matches!(deferred.payload, PayloadData::Deferred { .. }));
            assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 0);
        }
    }
}
