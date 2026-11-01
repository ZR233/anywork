//! Deterministic work/IO bounds, not elapsed-time thresholds. These exercise real Session reads;
//! storage is an instrumented port, so real SQLite range/index evidence remains the host's task.
#[path = "support/timeline.rs"]
mod support;

use std::sync::{Arc, atomic::Ordering};

use pl_core::chat::*;
use support::*;

#[tokio::test]
async fn increasing_hidden_pending_does_not_increase_scoped_budget_work_or_history_io() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let parent = ChatKey::new("call", "chosen").unwrap();
    let mut chosen = draft("chosen", "opaque");
    chosen.query_class = "activity".into();
    chosen.parent_id = Some(parent.clone());
    session
        .publish_batch(vec![draft("main", "main"), chosen])
        .await
        .unwrap();
    let mut expected_work = None;
    let mut next_hidden = 0;
    for hidden_count in [0, 64, 1024, 8192] {
        let drafts = (next_hidden..hidden_count)
            .map(|i| {
                let mut hidden = draft(&format!("hidden-{i}"), "unrelated");
                hidden.query_class = "activity".into();
                hidden.parent_id = Some(ChatKey::new("turn", "chosen").unwrap());
                hidden
            })
            .collect();
        session.publish_batch(drafts).await.unwrap();
        next_hidden = hidden_count;
        let reads_before = stored.reads.item.load(Ordering::SeqCst);
        let budget = Budget::default();
        let page = session
            .page(
                ChatPageRequest::latest(
                    ChatQuery::new("activity", Some(parent.clone())),
                    demand(1),
                ),
                &budget,
            )
            .await
            .unwrap();
        assert_eq!(sequences(&page.items), [2]);
        let work = budget.visited.lock().unwrap().clone();
        assert!(work.iter().all(|seq| *seq == 2));
        if let Some(expected) = &expected_work {
            assert_eq!(&work, expected);
        } else {
            expected_work = Some(work);
        }
        let main = session.page(latest(1), &Budget::default()).await.unwrap();
        assert_eq!(sequences(&main.items), [1]);
        assert_eq!(stored.reads.item.load(Ordering::SeqCst), reads_before);
        assert!(stored.reads.pages.lock().unwrap().is_empty());
        assert!(stored.reads.afters.lock().unwrap().is_empty());
    }
}

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
