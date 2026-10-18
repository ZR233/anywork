//! 无状态页：内存与 durable 行合并、keyset 边界、真实 `has_older` 与有界读取。

#[path = "support/timeline.rs"]
mod timeline_support;

use std::sync::Arc;

use pl_core::chat::{
    CHAT_ITEM_PREVIEW_BYTES, ChatCursor, ChatDetailRequest, ChatError, ChatField, ChatPageRequest,
    PAGE_PREVIEW_BYTES, Session,
};
use timeline_support::*;

/// 读取窗口内有一次真实撤回时，此前捕获的引用就作废——即使同一身份随后以新 order/revision 重新发布。
///
/// 捕获的引用是撤回**之前**的正文，与新事实无关；新事实靠 post-SQL 的当前候选独立进入页，
/// 所以这里既不能返回旧正文，也不能把新事实一起屏蔽。
#[tokio::test]
async fn a_withdrawal_invalidates_captured_references_even_when_the_identity_is_published_again() {
    let mut history = GatedHistory::new(Stored::default());
    let gate = Arc::new(HistoryGate::new());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history);

    // 旧事实（推测内容，可被真实撤回）与页边界。
    session
        .publish_preview(identified("item-1", 1, 1, "old-body", false))
        .unwrap();
    session.publish(item(2, 1, "boundary", true)).unwrap();
    // 该边界来自真实页：更旧内容严格小于 (order 2, item-2)。
    let boundary = ChatCursor::new(2, "item-2");

    let read = tokio::spawn({
        let session = session.clone();
        let boundary = boundary.clone();
        async move {
            session
                .page(ChatPageRequest::before(boundary).with_limit(32))
                .await
        }
    });
    gate.entered().await;
    // 读取停在存储期间：真实撤回旧身份，随后同一 id 以新 order/revision 重新发布。
    session.drop_preview("item-1");
    assert_eq!(session.reserve_order("item-1").await.unwrap(), 3);
    session
        .publish(identified("item-1", 3, 2, "new-body", true))
        .unwrap();
    gate.release();

    let page = read.await.unwrap().unwrap();
    assert!(
        page.items.iter().all(|item| item.item_id != "item-1"),
        "the captured pre-withdrawal body must not be served: {page:?}"
    );
    assert!(
        page.items.is_empty(),
        "the boundary excludes the new order and the old speculation was withdrawn: {page:?}"
    );

    // 新事实照常进入最新页：撤回不是墓碑，也不屏蔽新发布。
    gate.release();
    let latest = session
        .page(ChatPageRequest::latest().with_limit(32))
        .await
        .unwrap();
    let current = latest
        .items
        .iter()
        .find(|item| item.item_id == "item-1")
        .expect("the republished identity is a normal fact");
    assert_eq!(current.order, 3);
    assert_eq!(current.revision, 2);
    assert_eq!(body_text(current), "new-body");

    // 旧边界再读一次：缓存里没有旧正文 ghost。
    gate.release();
    let again = session
        .page(ChatPageRequest::before(boundary).with_limit(32))
        .await
        .unwrap();
    assert!(
        again.items.iter().all(|item| item.item_id != "item-1"),
        "the cache must not resurrect the withdrawn body: {again:?}"
    );
}

/// 一次读取在 SQL 期间捕获的候选引用，不能把权威已经释放的 preview 带回页里或缓存里。
///
/// `drop_previews_*` 是真实撤回（不是缓存淘汰）：它把身份从热缓存与分配表里移除并发布删除事实。
/// 读取起点捕获的引用若是唯一还持有它的地方，合并时就必须按同一份撤回证据剔除；`hydrate` 也不能把
/// 它重新种回缓存，否则第二次查询会从缓存里再看到这个 ghost。
#[tokio::test]
async fn a_withdrawn_preview_is_never_resurrected_by_the_page_that_captured_it() {
    let mut history = GatedHistory::new(Stored::default());
    let gate = Arc::new(HistoryGate::new());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history);
    let prefix = attempt_prefix("attempt");
    let in_flight = presentation("attempt", "message-1");
    session
        .publish_preview(identified(&in_flight, 1, 1, "in-flight", false))
        .unwrap();

    let read = tokio::spawn({
        let session = session.clone();
        async move { session.page(ChatPageRequest::latest()).await }
    });
    gate.entered().await;
    // 权威在读取停在存储期间撤回这条推测内容（真实释放，不是淘汰）。
    session.drop_previews_with_prefix(&prefix);
    gate.release();

    let page = read.await.unwrap().unwrap();
    assert!(
        page.items.iter().all(|item| item.item_id != in_flight),
        "a withdrawn preview must not survive through the captured reference: {page:?}"
    );
    assert!(page.items.is_empty());

    // 第二次查询：缓存没有被重新种回 ghost。
    let second = tokio::spawn({
        let session = session.clone();
        async move { session.page(ChatPageRequest::latest()).await }
    });
    gate.entered().await;
    gate.release();
    let second = second.await.unwrap().unwrap();
    assert!(
        second.items.iter().all(|item| item.item_id != in_flight),
        "the preview cache must not be reseeded with a withdrawn identity: {second:?}"
    );
}

/// 撤回窗口越过有界日志后无法证明连续性：读取显式失败（`ReadInvalidated`，对外是 Busy 可重试），
/// 而不是猜一个删除、复活或空页。
#[tokio::test]
async fn a_page_read_whose_withdrawal_window_left_the_bounded_log_is_retried() {
    let mut history = GatedHistory::new(Stored::default());
    let gate = Arc::new(HistoryGate::new());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history);
    // 读取起点捕获到候选，才有需要核对的引用。
    session.publish(item(1, 1, "captured", false)).unwrap();

    let read = tokio::spawn({
        let session = session.clone();
        async move { session.page(ChatPageRequest::latest()).await }
    });
    gate.entered().await;
    // 远超连续性元数据窗口的发布量：该读取起点已无法再有证据。
    for order in 2..=600 {
        session.publish(item(order, 1, "x", true)).unwrap();
    }
    gate.release();

    assert!(
        matches!(read.await.unwrap(), Err(ChatError::ReadInvalidated)),
        "an unprovable withdrawal window must be a typed retryable failure, not a guessed page"
    );
    // 失败没有把任何东西种回缓存：下一次读取照常给出权威页。
    gate.release();
    let retried = session
        .page(ChatPageRequest::latest().with_limit(4))
        .await
        .expect("the retry reads the authoritative page");
    assert_eq!(
        retried
            .items
            .iter()
            .map(|item| item.order)
            .collect::<Vec<_>>(),
        vec![597, 598, 599, 600]
    );
}

/// 预览预算计的是**不可缩结构 + 实际正文**：身份文本和宿主字段 key 按真实 UTF-8 计，空字段也不是免费。
#[tokio::test]
async fn preview_structure_accounting_charges_identities_and_host_keys() {
    let baseline = with_fields("item-1", 1, 1, [(ChatField::Body, "x".to_owned())], true);
    let extra_fields = |suffix: &str| {
        (0..20)
            .map(|index| (ChatField::host(format!("k{index}{suffix}")), String::new()))
            .collect::<Vec<_>>()
    };
    let fields_with = |suffix: &str| {
        std::iter::once((ChatField::Body, "x".to_owned()))
            .chain(extra_fields(suffix))
            .collect::<Vec<_>>()
    };
    let short = with_fields("item-1", 1, 1, fields_with(""), true);
    let long_keys = with_fields("item-1", 1, 1, fields_with(&"k".repeat(100)), true);

    let key_bytes: usize = extra_fields("")
        .iter()
        .map(|(field, _)| field.to_string().len())
        .sum();
    let added = short.preview_structure_bytes() - baseline.preview_structure_bytes();
    assert!(
        added > key_bytes,
        "empty fields cost more than their key text: added={added} keys={key_bytes}"
    );
    assert_eq!(
        long_keys.preview_structure_bytes() - short.preview_structure_bytes(),
        20 * 100,
        "host keys are charged by their real UTF-8 bytes"
    );

    let longer_identity = with_fields("item-1", 1, 1, fields_with(""), true);
    let mut renamed = longer_identity.clone();
    renamed.item_id = format!("item-1{}", "z".repeat(64));
    assert_eq!(
        renamed.preview_structure_bytes() - longer_identity.preview_structure_bytes(),
        64,
        "stable identities are charged by their real UTF-8 bytes"
    );
}

/// 结构自身超限是不可缩的资源限制：发布、冷页与首帧基线都不能绕过，宿主 codec 也不能覆盖。
#[tokio::test]
async fn an_unshrinkable_structure_over_budget_is_a_typed_resource_limit() {
    // 每条正文都是空的：唯一的成本就是身份与字段声明，因此这里测的是结构而不是载荷。
    let crowded = with_fields(
        "item-1",
        1,
        1,
        (0..4000)
            .map(|index| {
                (
                    ChatField::host(format!("budget.field.{index}")),
                    String::new(),
                )
            })
            .collect::<Vec<_>>(),
        true,
    );
    assert!(crowded.preview_structure_bytes() > CHAT_ITEM_PREVIEW_BYTES);
    assert_eq!(
        crowded.omitted_bytes(),
        0,
        "nothing is omitted: the structure itself is over budget"
    );

    let session = Session::new(Stored::default());
    assert!(matches!(
        session.publish(crowded.clone()),
        Err(ChatError::Overloaded(_))
    ));

    // 冷页与首帧基线走同一条准入计量。
    let cold = Session::new(Stored::with([crowded.clone()]));
    assert!(matches!(
        cold.page(ChatPageRequest::latest()).await,
        Err(ChatError::Overloaded(_))
    ));
    assert!(matches!(
        cold.subscribe_tail().await,
        Err(ChatError::Overloaded(_))
    ));

    // 覆盖 `bounded` 的宿主 codec 也必须被同一上限拦住，而不是把超限预览交给会话。
    let lazy = Session::new(IgnoresBudget::new(Stored::default()));
    let oversized = item(1, 1, &"a".repeat(300 * 1024), true);
    assert!(matches!(
        lazy.publish(oversized.clone()),
        Err(ChatError::Overloaded(_))
    ));
    let lazy_cold = Session::new(IgnoresBudget::new(Stored::with([oversized])));
    assert!(matches!(
        lazy_cold.page(ChatPageRequest::latest()).await,
        Err(ChatError::Overloaded(_))
    ));
}

/// 结构先占用自己那份额度：正文只剩 `256 KiB - 结构`，但身份、完整长度、详情入口与 UTF-8 边界都不变。
#[tokio::test]
async fn the_structure_share_reduces_the_body_cap_without_rewriting_identity_or_total() {
    let body = "é".repeat(100 * 1024);
    let mut large = with_fields("item-1", 1, 1, [(ChatField::Body, body.clone())], true);
    // 静态结构本身很大（产品把它编码进 `meta`），因此可缩正文的剩余额度明显变小。
    large.meta = Arc::from(vec![b'{'; 200 * 1024]);
    let structure = large.preview_structure_bytes();
    assert!(structure < CHAT_ITEM_PREVIEW_BYTES);
    let body_budget = CHAT_ITEM_PREVIEW_BYTES - structure;
    assert!(
        body_budget < body.len(),
        "the body really has to be trimmed for this to be a signal"
    );

    let session = Session::new(Stored::default());
    session.publish(large).unwrap();
    let page = session.page(ChatPageRequest::latest()).await.unwrap();
    let shown = &page.items[0];
    assert_eq!(shown.item_id, "item-1");
    assert_eq!(shown.order, 1);
    assert_eq!(shown.revision, 1);
    assert_eq!(
        shown.field_total_bytes(&ChatField::Body),
        Some(body.len() as u64),
        "the complete length is never rewritten by the preview"
    );
    let kept = shown.body().unwrap().len();
    assert_eq!(kept, body_budget, "structure is charged before the body");
    assert_eq!(
        shown.omitted_bytes() as usize,
        body.len() - kept,
        "the omitted amount follows the real UTF-8 bytes"
    );
    assert_eq!(kept % 2, 0, "the preview stops on a UTF-8 boundary");
    assert_eq!(body_text(shown), body[..kept]);

    // 详情仍能按身份读到完整正文，不受预览剩余额度影响。
    let chunk = session
        .read_detail(ChatDetailRequest::new("item-1", ChatField::Body, 1))
        .await
        .unwrap();
    assert_eq!(chunk.total_bytes, body.len() as u64);
    assert_eq!(chunk.text, body[..chunk.text.len()]);
    assert!(chunk.continuation.is_some());
}

#[tokio::test]
async fn a_page_merges_uncommitted_rows_without_a_hole_or_a_second_identity() {
    let stored = Stored::with([
        item(1, 1, "one", true),
        item(2, 1, "two", true),
        item(3, 1, "three", true),
    ]);
    let session = Session::new(stored);
    // An in-flight row is visible before the writer ever persists it.
    session.publish(item(4, 1, "four", false)).unwrap();

    let page = session.page(ChatPageRequest::latest()).await.unwrap();

    assert_eq!(
        page.items.iter().map(|item| item.order).collect::<Vec<_>>(),
        vec![1, 2, 3, 4]
    );
    assert_eq!(
        page.items
            .iter()
            .map(|item| item.item_id.as_str())
            .collect::<Vec<_>>(),
        vec!["item-1", "item-2", "item-3", "item-4"]
    );
    assert!(!page.has_older);
    assert_eq!(page.before, None);
}

#[tokio::test]
async fn has_older_only_comes_from_a_real_older_row() {
    let session = Session::new(Stored::with(
        (1..=32).map(|order| item(order, 1, "x", true)),
    ));
    let page = session.page(ChatPageRequest::latest()).await.unwrap();
    assert_eq!(page.items.len(), 32);
    assert!(
        !page.has_older,
        "a full page is not evidence of more history"
    );
    assert_eq!(page.before, None);

    let session = Session::new(Stored::with(
        (1..=33).map(|order| item(order, 1, "x", true)),
    ));
    let page = session.page(ChatPageRequest::latest()).await.unwrap();
    assert_eq!(page.items.len(), 32);
    assert_eq!(page.items.first().unwrap().order, 2);
    assert!(page.has_older);
    // The boundary is taken from the first row actually returned, so the next page resumes exactly
    // there instead of repeating or skipping a row.
    let before = page.before.expect("an older row was proven");
    assert_eq!(before, ChatCursor::new(2, "item-2"));

    let older = session.page(ChatPageRequest::before(before)).await.unwrap();
    assert_eq!(
        older
            .items
            .iter()
            .map(|item| item.order)
            .collect::<Vec<_>>(),
        vec![1]
    );
    assert!(!older.has_older);
    assert_eq!(older.before, None);
}

#[tokio::test]
async fn an_explicit_limit_outside_the_supported_range_is_rejected_instead_of_clamped() {
    let session = Session::new(Stored::with((1..=3).map(|order| item(order, 1, "x", true))));
    for rejected in [0usize, 101, 4096] {
        assert!(matches!(
            session
                .page(ChatPageRequest::latest().with_limit(rejected))
                .await,
            Err(ChatError::InvalidArgument(_))
        ));
    }
    for accepted in [1usize, 32, 100] {
        let page = session
            .page(ChatPageRequest::latest().with_limit(accepted))
            .await
            .unwrap();
        assert_eq!(page.items.len(), 3.min(accepted));
    }
}

#[tokio::test]
async fn every_page_read_is_bounded_by_the_requested_limit() {
    let history = BoundedReads::new(Stored::with(
        (1..=200).map(|order| item(order, 1, "x", true)),
    ));
    let largest = history.largest_page.clone();
    let session = Session::new(history);

    let page = session.page(ChatPageRequest::latest()).await.unwrap();
    assert_eq!(page.items.len(), 32);
    assert_eq!(*largest.lock().unwrap(), 32);

    let page = session
        .page(ChatPageRequest::latest().with_limit(7))
        .await
        .unwrap();
    assert_eq!(page.items.len(), 7);
    assert_eq!(*largest.lock().unwrap(), 32);
}

#[tokio::test]
async fn the_page_preview_budget_truncates_the_oldest_end_and_keeps_a_real_boundary() {
    // Ten rows whose bounded preview is the per-item budget: the page byte budget holds only the
    // newest few, so the page stops early without claiming the history ended. The count follows the
    // shared accounting (structure + retained body), not a hand-written constant.
    let text = "a".repeat(300 * 1024);
    let session = Session::new(Stored::with(
        (1..=10).map(|order| item(order, 1, &text, true)),
    ));

    let page = session
        .page(ChatPageRequest::latest().with_limit(10))
        .await
        .unwrap();

    let resident =
        |item: &pl_core::chat::ChatItem| item.preview_structure_bytes() + body_text(item).len();
    let used: usize = page.items.iter().map(resident).sum();
    assert!(
        used <= PAGE_PREVIEW_BYTES,
        "the page respects the shared byte budget: {used}"
    );
    let one = resident(&page.items[0]);
    assert!(
        used + one > PAGE_PREVIEW_BYTES,
        "the byte budget is what stopped the page, not the row count: used={used} one={one}"
    );
    assert!(page.items.len() < 10, "the page really was truncated");
    for item in &page.items {
        assert!(
            resident(item) <= CHAT_ITEM_PREVIEW_BYTES,
            "every retained preview stays inside the single-item budget"
        );
        assert_eq!(
            item.field_total_bytes(&ChatField::Body),
            Some(text.len() as u64)
        );
    }
    assert_eq!(page.items.last().unwrap().order, 10);
    assert!(page.has_older);
    let oldest = page.items.first().unwrap().order;
    assert_eq!(
        page.before,
        Some(ChatCursor::new(oldest, format!("item-{oldest}"))),
        "a byte-truncated page still reports its real next boundary"
    );

    let older = session
        .page(ChatPageRequest::before(page.before.unwrap()).with_limit(10))
        .await
        .unwrap();
    assert!(
        older.items.iter().all(|item| item.order < oldest),
        "a truncated page never repeats the rows it already returned"
    );
    assert!(!older.items.is_empty());
}

#[tokio::test]
async fn a_revision_published_while_the_page_read_awaited_is_not_replaced_by_the_stale_row() {
    let mut history = GatedHistory::new(Stored::with([item(1, 1, "durable", true)]));
    let gate = Arc::new(HistoryGate::new());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history);

    let read = tokio::spawn({
        let session = session.clone();
        async move { session.page(ChatPageRequest::latest()).await }
    });
    gate.entered().await;
    // A newer revision of the same identity lands while the page read is parked in storage.
    session
        .publish(identified("item-1", 1, 5, "newer", true))
        .unwrap();
    gate.release();

    let page = read.await.unwrap().unwrap();
    assert_eq!(page.items.len(), 1, "one identity is never shown twice");
    assert_eq!(page.items[0].revision, 5);
    assert_eq!(body_text(&page.items[0]), "newer");
}

#[tokio::test]
async fn a_stale_storage_row_never_rolls_back_a_newer_save_or_terminal_fact() {
    let mut history = GatedHistory::new(Stored::with([{
        let mut stored = item(1, 4, "kept", false);
        stored.saved = false;
        stored
    }]));
    let gate = Arc::new(HistoryGate::new());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history);
    session.publish(item(1, 4, "kept", true)).unwrap();
    session.confirm_saved("item-1", 4);

    let read = tokio::spawn({
        let session = session.clone();
        async move { session.page(ChatPageRequest::latest()).await }
    });
    gate.entered().await;
    gate.release();

    let page = read.await.unwrap().unwrap();
    assert_eq!(page.items.len(), 1);
    let current = &page.items[0];
    assert!(current.is_terminal(), "the terminal fact survives the read");
    assert!(current.is_saved(), "the save watermark survives the read");
    assert_eq!(body_text(current), "kept");
}

#[tokio::test]
async fn a_cursor_boundary_is_strict_and_rejects_the_row_it_names() {
    let session = Session::new(Stored::with((1..=4).map(|order| item(order, 1, "x", true))));
    let page = session
        .page(ChatPageRequest::before(ChatCursor::new(3, "item-3")))
        .await
        .unwrap();
    assert_eq!(
        page.items.iter().map(|item| item.order).collect::<Vec<_>>(),
        vec![1, 2]
    );
    assert!(!page.has_older);
}

#[tokio::test]
async fn an_empty_store_returns_an_empty_page_and_never_a_fake_boundary() {
    let session = Session::new(Stored::default());
    let page = session.page(ChatPageRequest::latest()).await.unwrap();
    assert!(page.items.is_empty());
    assert!(!page.has_older);
    assert_eq!(page.before, None);
}

#[tokio::test]
async fn a_storage_failure_is_reported_instead_of_looking_like_the_beginning_of_history() {
    let session = Session::new(Failing);
    assert!(matches!(
        session.page(ChatPageRequest::latest()).await,
        Err(ChatError::History(_))
    ));
}

/// A history whose every read fails.
#[derive(Debug)]
struct Failing;

impl pl_core::chat::ChatHistory for Failing {
    async fn latest_allocated_order(&self) -> Result<u64, ChatError> {
        Err(ChatError::History(
            std::io::Error::other("unreadable").into(),
        ))
    }

    async fn page(
        &self,
        _before: Option<&ChatCursor>,
        _limit: usize,
    ) -> Result<pl_core::chat::ChatHistoryPage, ChatError> {
        Err(ChatError::History(
            std::io::Error::other("unreadable").into(),
        ))
    }

    async fn item(&self, _item_id: &str) -> Result<Option<pl_core::chat::ChatItem>, ChatError> {
        Err(ChatError::History(
            std::io::Error::other("unreadable").into(),
        ))
    }
}

/// 同一 revision 的预览被权威完整正文补齐：内容变完整，但 revision 不伪增长。
///
/// 两条真实路径都覆盖：先 speculative 预览、再同 revision 的可靠完整发布；以及内存预览与同 revision
/// 的 durable 行合并。断言只落在可观察结果上：正文完整、省略量归零、字段总长与预览长度一致、
/// revision 与身份不变、保存水位不被回滚。
#[tokio::test]
async fn a_same_revision_preview_is_completed_without_a_revision_bump() {
    let complete = item(1, 3, "abcdefgh", true);

    // 1) 同 revision：speculative 预览 → 可靠完整发布。
    let session = Session::new(Stored::default());
    session.publish_preview(preview_of(&complete, 4)).unwrap();
    session.publish(complete.clone()).unwrap();
    let items = visible(&session, 1).await;
    assert_eq!(items.len(), 1, "one identity keeps one row");
    assert_eq!(
        items[0].revision, 3,
        "a preview completed at the same revision is not a new content revision"
    );
    assert_eq!(items[0].item_id, "item-1");
    assert_eq!(items[0].order, 1);
    assert!(items[0].field_is_complete(&pl_core::chat::ChatField::Body));
    assert_eq!(body_text(&items[0]), "abcdefgh");
    assert_eq!(items[0].omitted_bytes(), 0);

    // 2) 同 revision：内存预览 + durable 完整行合并。
    let durable = saved_item(1, 3, "abcdefgh", true);
    let session = Session::new(Stored::with([durable.clone()]));
    session.publish_preview(preview_of(&durable, 4)).unwrap();
    let page = session.page(ChatPageRequest::latest()).await.unwrap();
    let item = &page.items[0];
    assert_eq!(item.revision, 3);
    assert_eq!(item.item_id, "item-1");
    assert_eq!(item.order, 1);
    assert!(item.field_is_complete(&pl_core::chat::ChatField::Body));
    assert_eq!(body_text(item), "abcdefgh");
    assert_eq!(
        item.field_total_bytes(&pl_core::chat::ChatField::Body),
        Some(8)
    );
    assert_eq!(item.omitted_bytes(), 0);
    assert!(item.is_saved(), "the durable row's save watermark is kept");
}
