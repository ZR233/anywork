//! Deterministic work/IO bounds, not elapsed-time thresholds. These exercise real Session reads;
//! storage is an instrumented port, so real SQLite range/index evidence remains the host's task.
#[path = "support/timeline.rs"]
mod support;

use std::sync::{Arc, atomic::Ordering};

use pl_core::chat::*;
use support::*;

#[tokio::test]
async fn producer_manifest_size_and_body_size_do_not_enter_normal_page_work() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let mut item = draft("large-manifest", "small opaque payload");
    let body: Arc<[u8]> = Arc::from(vec![42; 2 * 1024 * 1024]);
    for index in 0..1024 {
        item = with_body(
            item,
            &format!("part-{index:04}"),
            ContentData::Bytes(body.clone()),
        );
    }
    let records = session.publish_batch(vec![item]).await.unwrap();
    let manifest_refs = Arc::strong_count(&records[0].contents);
    let body_refs = Arc::strong_count(&body);
    let budget = Budget::default();
    let page = session.page(latest(1), &budget).await.unwrap();
    assert_eq!(page.items.len(), 1);
    let PayloadData::Inline(payload) = &page.items[0].payload else {
        panic!("small payload")
    };
    assert!(Arc::ptr_eq(payload, &records[0].payload));
    assert_eq!(Arc::strong_count(&records[0].contents), manifest_refs);
    assert_eq!(Arc::strong_count(&body), body_refs);
    assert_eq!(stored.reads.manifests.load(Ordering::SeqCst), 0);
    assert!(stored.reads.ranges.lock().unwrap().is_empty());
    assert!(stored.reads.pages.lock().unwrap().is_empty());
}

#[tokio::test]
async fn explicit_viewport_demand_is_not_replaced_by_a_fixed_ui_page_size() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    session
        .publish_batch(
            (0..2100)
                .map(|i| draft(&format!("item-{i}"), "x"))
                .collect(),
        )
        .await
        .unwrap();
    let page = session
        .page(latest(2048), &Budget::default())
        .await
        .unwrap();
    assert_eq!(page.items.len(), 2048);
    assert_eq!(page.items[0].header.append_seq, 53);
    assert!(page.before.is_some());
    assert!(stored.reads.pages.lock().unwrap().is_empty());
}
