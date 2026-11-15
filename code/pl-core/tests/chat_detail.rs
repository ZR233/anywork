//! Explicit manifests and bounded byte windows replace the retired field/preview contract.
//! UTF-8 may be split: callers join bytes, not independently decoded strings.
#[path = "support/timeline.rs"]
mod support;

use std::sync::{Arc, atomic::Ordering};

use pl_core::{chat::*, model::ContentBlock};
use support::*;

async fn read_all(session: &Session, reference: ContentRef, size: usize) -> Vec<u8> {
    let mut bytes = Vec::new();
    loop {
        let window = session
            .read_content(content_request(reference.clone(), bytes.len() as u64, size))
            .await
            .unwrap();
        assert!(window.sealed);
        assert_eq!(window.offset, bytes.len() as u64);
        bytes.extend_from_slice(window.bytes.as_bytes());
        if bytes.len() as u64 == window.available_through {
            return bytes;
        }
        assert!(
            !window.bytes.as_bytes().is_empty(),
            "a non-EOF window must progress"
        );
    }
}

#[tokio::test]
async fn multibyte_payload_ranges_join_into_the_original_even_inside_code_points() {
    let body = "汉语 mixed with English 📖 and more text";
    let stored = Stored::with([record_identified("x", 1, body)]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    assert_eq!(
        read_all(&session, ContentRef::ItemPayload("x".into()), 1).await,
        body.as_bytes()
    );
    assert_eq!(
        stored.reads.item.load(Ordering::SeqCst),
        0,
        "ranges never load item()"
    );
    assert_eq!(stored.reads.ranges.lock().unwrap().len(), body.len());
}

#[tokio::test]
async fn a_deferred_payload_is_read_only_through_requested_windows() {
    let body = "x".repeat(300 * 1024);
    let stored = Stored::with([record_identified("x", 1, &body)]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    let page = session
        .page(
            ChatPageRequest::latest(query(), ReadDemand::new(1, 256)),
            &Budget::default(),
        )
        .await
        .unwrap();
    assert!(matches!(
        page.items[0].payload,
        PayloadData::Deferred { .. }
    ));
    assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 0);
    assert_eq!(
        read_all(&session, ContentRef::ItemPayload("x".into()), 64 * 1024).await,
        body.as_bytes()
    );
    let ranges = stored.reads.ranges.lock().unwrap();
    assert_eq!(ranges.len(), 5);
    assert!(ranges.iter().all(|request| request.max_bytes == 64 * 1024));
    assert_eq!(stored.reads.item.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn missing_payload_and_body_are_not_empty_content_or_an_empty_manifest() {
    let item = with_body(draft("x", ""), "empty", ContentData::Bytes(Arc::from([])));
    let key = item.contents.keys().next().unwrap().clone();
    let stored = Stored::with([ChatItem::complete(item, 1)]);
    let session = Session::new(stored, epoch("run-1"));
    for reference in [
        ContentRef::ItemPayload("x".into()),
        ContentRef::Body(key.clone()),
    ] {
        let window = session
            .read_content(content_request(reference, 0, 1))
            .await
            .unwrap();
        assert!(window.bytes.as_bytes().is_empty());
        assert_eq!(window.available_through, 0);
    }
    let missing = ChatContentKey {
        key: "missing".into(),
        ..key
    };
    for reference in [
        ContentRef::ItemPayload("missing".into()),
        ContentRef::Body(missing),
    ] {
        assert!(matches!(
            session.read_content(content_request(reference, 0, 1)).await,
            Err(ChatError::NotFound(_))
        ));
    }
    let empty = Session::new(Stored::default(), epoch("run-1"));
    empty
        .publish_batch(vec![draft("empty", "unknown payload, no inferred refs")])
        .await
        .unwrap();
    let request = ContentManifestRequest {
        epoch: epoch("run-1"),
        item_id: "empty".into(),
        after: None,
        demand: demand(1),
    };
    assert!(
        empty
            .list_contents(request.clone(), &Budget::default())
            .await
            .unwrap()
            .entries
            .is_empty()
    );
    assert!(matches!(
        empty
            .list_contents(
                ContentManifestRequest {
                    item_id: "missing".into(),
                    ..request
                },
                &Budget::default()
            )
            .await,
        Err(ChatError::NotFound(_))
    ));
}

#[tokio::test]
async fn invalid_sizes_offsets_epochs_and_generations_remain_distinct() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    session.publish_batch(vec![draft("x", "汉")]).await.unwrap();
    let reference = ContentRef::ItemPayload("x".into());
    for size in [0, MAX_READ_BYTES + 1] {
        assert!(matches!(
            session
                .read_content(content_request(reference.clone(), 0, size))
                .await,
            Err(ChatError::InvalidDemand(_))
        ));
    }
    for offset in [4, u64::MAX] {
        assert!(matches!(
            session
                .read_content(content_request(reference.clone(), offset, 1))
                .await,
            Err(ChatError::InvalidArgument(_))
        ));
    }
    let mut request = content_request(reference, 1, 1);
    assert_eq!(
        session
            .read_content(request.clone())
            .await
            .unwrap()
            .bytes
            .as_bytes(),
        &"汉".as_bytes()[1..2]
    );
    request.generation = Some(1);
    assert!(matches!(
        session.read_content(request.clone()).await,
        Err(ChatError::StaleContent)
    ));
    request.epoch = epoch("old");
    assert!(matches!(
        session.read_content(request).await,
        Err(ChatError::EpochMismatch { .. })
    ));
}

#[tokio::test]
async fn pending_ranges_reuse_the_original_arc_across_commit_clear() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let records = session
        .publish_batch(vec![draft("x", &"y".repeat(100 * 1024))])
        .await
        .unwrap();
    let window = session
        .read_content(content_request(ContentRef::ItemPayload("x".into()), 13, 17))
        .await
        .unwrap();
    assert!(Arc::ptr_eq(&window.bytes.storage, &records[0].payload));
    stored.insert((*records[0]).clone());
    session.confirm_durable(1).unwrap();
    drop(records);
    assert_eq!(window.bytes.as_bytes(), &[b'y'; 17]);
    assert_eq!(stored.reads.ranges.lock().unwrap().len(), 0);
    let next = session
        .read_content(content_request(ContentRef::ItemPayload("x".into()), 30, 17))
        .await
        .unwrap();
    assert_eq!(next.bytes.as_bytes(), &[b'y'; 17]);
    assert_eq!(stored.reads.ranges.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn explicit_manifest_is_paged_by_stable_key_and_encoded_demand_without_payload_reads() {
    let mut item = draft("x", r#"{"unknown":"payload","ref":"not-a-body"}"#);
    for key in ["c", "a", "b"] {
        item = with_body(item, key, ContentData::Bytes(Arc::from([1, 2, 3])));
    }
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let records = session.publish_batch(vec![item]).await.unwrap();
    let budget = Budget::default();
    let first_descriptor = &records[0].contents.first_key_value().unwrap().1.descriptor;
    let bytes = budget.fixed_bytes() + budget.manifest_bytes(first_descriptor);
    let mut request = ContentManifestRequest {
        epoch: epoch("run-1"),
        item_id: "x".into(),
        after: None,
        demand: ReadDemand::new(5, bytes),
    };
    let first = session
        .list_contents(request.clone(), &budget)
        .await
        .unwrap();
    assert_eq!(first.entries.len(), 1);
    assert_eq!(first.entries[0].key.key, "a");
    request.after = first.next;
    // Transfer to durable storage between pages, retaining the same manifest identity/order.
    stored.insert((*records[0]).clone());
    session.confirm_durable(1).unwrap();
    let second = session
        .list_contents(request.clone(), &budget)
        .await
        .unwrap();
    assert_eq!(second.entries[0].key.key, "b");
    request.after = second.next;
    let third = session.list_contents(request, &budget).await.unwrap();
    assert_eq!(third.entries[0].key.key, "c");
    assert!(third.next.is_none());
    assert_eq!(stored.reads.manifests.load(Ordering::SeqCst), 2);
    assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 0);
    assert!(stored.reads.ranges.lock().unwrap().is_empty());
    let reference = ContentRef::Body(third.entries[0].key.clone());
    let mut range = content_request(reference, 1, 1);
    range.generation = Some(8);
    assert!(matches!(
        session.read_content(range.clone()).await,
        Err(ChatError::StaleContent)
    ));
    range.generation = Some(7);
    assert_eq!(
        session.read_content(range).await.unwrap().bytes.as_bytes(),
        &[2]
    );
}

#[tokio::test]
async fn a_too_small_manifest_envelope_is_an_error_not_eof_or_a_skipped_entry() {
    let item = with_body(
        draft("x", "payload"),
        "body",
        ContentData::Bytes(Arc::from([1])),
    );
    let session = Session::new(Stored::default(), epoch("run-1"));
    session.publish_batch(vec![item]).await.unwrap();
    let request = ContentManifestRequest {
        epoch: epoch("run-1"),
        item_id: "x".into(),
        after: None,
        demand: ReadDemand::new(1, 65),
    };
    assert!(matches!(
        session.list_contents(request, &Budget::default()).await,
        Err(ChatError::InvalidDemand(_))
    ));
}

#[tokio::test]
async fn shared_model_blocks_support_byte_windows_without_flattening_the_body() {
    let body = "汉📖abc".repeat(2048);
    let mut block = ContentBlock::empty();
    for chunk in body.as_bytes().chunks("汉📖abc".len()) {
        block = ContentBlock::append(&block, std::str::from_utf8(chunk).unwrap());
    }
    let item = with_body(
        draft("x", "opaque"),
        "body",
        ContentData::text(block.clone()),
    );
    let key = item.contents.keys().next().unwrap().clone();
    let session = Session::new(Stored::default(), epoch("run-1"));
    let records = session.publish_batch(vec![item]).await.unwrap();
    let ContentData::Text(frozen) = &records[0].contents[&key].data else {
        panic!("shared blocks")
    };
    assert!(Arc::ptr_eq(frozen.block(), &block));
    for (offset, size) in [
        (0, 1),
        (1, 1),
        (3, 1),
        (6, 13),
        (10001, 19),
        (body.len(), 1),
    ] {
        let window = session
            .read_content(content_request(
                ContentRef::Body(key.clone()),
                offset as u64,
                size,
            ))
            .await
            .unwrap();
        assert_eq!(
            window.bytes.as_bytes(),
            &body.as_bytes()[offset..(offset + size).min(body.len())]
        );
        assert_eq!(window.generation, 7);
    }
}

#[tokio::test]
async fn cancelled_range_read_publishes_nothing_and_leaves_the_session_usable() {
    let stored = Stored::with([record_identified("x", 1, "body")]);
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored.clone());
    history.content_gate = Some(gate.clone());
    let session = Session::new(history, epoch("run-1"));
    let read = {
        let session = session.clone();
        tokio::spawn(async move {
            session
                .read_content(content_request(ContentRef::ItemPayload("x".into()), 1, 2))
                .await
        })
    };
    gate.entered().await;
    read.abort();
    assert!(read.await.unwrap_err().is_cancelled());
    assert!(stored.reads.ranges.lock().unwrap().is_empty());
    assert_eq!(
        session
            .page(latest(1), &Budget::default())
            .await
            .unwrap()
            .items
            .len(),
        1
    );
    gate.release();
    let window = session
        .read_content(content_request(ContentRef::ItemPayload("x".into()), 1, 2))
        .await
        .unwrap();
    assert_eq!(window.bytes.as_bytes(), b"od");
}
