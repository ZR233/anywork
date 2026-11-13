use super::*;
use pl_protocol::{ThreadContentLifecycle, ThreadTextChannel, ThreadTextItem};
use tokio_util::sync::CancellationToken;

fn text(ordinal: u64, revision: u64, body: &str) -> ThreadItem {
    ThreadItem::new(
        format!("text-{ordinal}"),
        "agent".into(),
        "turn".into(),
        ordinal,
        revision,
        1,
        2,
        ThreadItemState::Text(ThreadTextItem::new(
            ThreadTextChannel::Final,
            body.into(),
            vec![],
            ThreadContentLifecycle::completed(2),
        )),
    )
}

#[tokio::test]
async fn agent_page_uses_one_snapshot_for_watermark_ceiling_and_content() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let history = HistoryStore::open(&dir.path().join("history.sqlite"), "agent").await?;
    let original = text(1, 1, "original");
    history
        .commit(1, std::slice::from_ref(&original), &[])
        .await?;
    let (entered_tx, entered) = tokio::sync::oneshot::channel();
    let (release, release_rx) = tokio::sync::oneshot::channel();
    *history.state.agent_page_gate.lock().await = Some((entered_tx, release_rx));
    let cancellation = CancellationToken::new();
    let read = history.agent_page(false, true, None, None, None, 20, &cancellation);
    let write = async {
        entered.await?;
        history
            .commit(2, &[text(1, 2, "revised"), text(2, 1, "new")], &[])
            .await?;
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("read disappeared"))?;
        Ok::<_, anyhow::Error>(())
    };
    let (page, committed) =
        tokio::time::timeout(Duration::from_secs(10), async { tokio::join!(read, write) }).await?;
    committed?;
    let (watermark, ceiling, items, more) = page?;
    assert_eq!((watermark, ceiling, more), (1, 1, false));
    assert_eq!(items, vec![original]);
    let (watermark, ceiling, items, _) = history
        .agent_page(false, true, None, None, None, 20, &cancellation)
        .await?;
    assert_eq!((watermark, ceiling, items.len()), (2, 2, 2));
    Ok(())
}

#[tokio::test]
async fn agent_page_cancelled_initialization_wait_releases_reader() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("history.sqlite");
    let history = HistoryStore::open(&path, "agent").await?;
    let initializing = history.state.init.write().await;
    let entered = history.arm_reader_before_init().await;
    let cancellation = CancellationToken::new();
    let read = history.agent_page(false, false, None, None, None, 20, &cancellation);
    let cancel = async {
        entered.await.unwrap();
        cancellation.cancel();
    };
    let (result, ()) = tokio::join!(read, cancel);
    assert!(matches!(
        result
            .unwrap_err()
            .downcast_ref::<pl_core::thread::ThreadError>(),
        Some(pl_core::thread::ThreadError::Cancelled)
    ));
    assert!(history.state.reader.get().is_none());
    assert!(!path.exists());
    drop(initializing);
    history.commit(1, &[text(1, 1, "saved")], &[]).await?;
    let page = history
        .agent_page(
            false,
            false,
            None,
            None,
            None,
            20,
            &CancellationToken::new(),
        )
        .await?;
    assert_eq!((page.0, page.2.len()), (1, 1));
    Ok(())
}

#[tokio::test]
async fn agent_page_cancelled_pool_wait_and_transaction_release_capacity() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let history = HistoryStore::open(&dir.path().join("history.sqlite"), "agent").await?;
    history.commit(1, &[text(1, 1, "saved")], &[]).await?;
    let connection = history.reader().await?.context("reader")?;
    // The production read pool has one connection. Hold it to force an actual acquisition wait.
    let occupied = connection.db.begin().await?;
    let (entered_tx, entered) = tokio::sync::oneshot::channel();
    *history.state.agent_page_before_transaction.lock().await = Some(entered_tx);
    let cancellation = CancellationToken::new();
    let read = history.agent_page(false, false, None, None, None, 20, &cancellation);
    let cancel = async {
        entered.await.unwrap();
        cancellation.cancel();
    };
    let (result, ()) = tokio::join!(read, cancel);
    assert!(matches!(
        result
            .unwrap_err()
            .downcast_ref::<pl_core::thread::ThreadError>(),
        Some(pl_core::thread::ThreadError::Cancelled)
    ));
    occupied.rollback().await?;

    // Now cancel a page that already owns its transaction and read snapshot.
    let (entered_tx, entered) = tokio::sync::oneshot::channel();
    let (release, release_rx) = tokio::sync::oneshot::channel();
    *history.state.agent_page_gate.lock().await = Some((entered_tx, release_rx));
    let cancellation = CancellationToken::new();
    let read = history.agent_page(false, false, None, None, None, 20, &cancellation);
    let cancel = async {
        entered.await.unwrap();
        cancellation.cancel();
    };
    let (result, ()) = tokio::join!(read, cancel);
    assert!(matches!(
        result
            .unwrap_err()
            .downcast_ref::<pl_core::thread::ThreadError>(),
        Some(pl_core::thread::ThreadError::Cancelled)
    ));
    assert!(
        release.is_closed(),
        "the original page future must have been dropped"
    );
    let cancellation = CancellationToken::new();
    let page = tokio::time::timeout(
        Duration::from_secs(10),
        history.agent_page(false, false, None, None, None, 20, &cancellation),
    )
    .await??;
    assert_eq!((page.0, page.2.len()), (1, 1));
    Ok(())
}

#[tokio::test]
async fn agent_page_distinguishes_absent_empty_and_read_error() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("history.sqlite");
    let history = HistoryStore::open(&path, "agent").await?;
    let cancellation = CancellationToken::new();
    let page = history
        .agent_page(false, false, None, None, None, 20, &cancellation)
        .await?;
    assert_eq!(page, (0, 0, vec![], false));
    assert!(!path.exists());
    history.commit(7, &[], &[]).await?;
    let page = history
        .agent_page(false, false, None, None, None, 20, &cancellation)
        .await?;
    assert_eq!(page, (7, 0, vec![], false));
    history
        .writer()
        .await?
        .db
        .execute_unprepared("DROP TABLE history_items")
        .await?;
    let error = history
        .agent_page(false, false, None, None, None, 20, &cancellation)
        .await
        .expect_err("SQL damage must not become an empty page");
    assert!(
        error.downcast_ref::<sea_orm::DbErr>().is_some(),
        "{error:#}"
    );
    Ok(())
}

#[tokio::test]
async fn agent_page_keyset_keeps_revised_rows_in_original_range() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let history = HistoryStore::open(&dir.path().join("history.sqlite"), "agent").await?;
    history
        .commit(1, &[text(1, 1, "first"), text(2, 1, "second")], &[])
        .await?;
    let cancellation = CancellationToken::new();
    let (through, ceiling, first, more) = history
        .agent_page(false, true, None, None, None, 1, &cancellation)
        .await?;
    assert_eq!((through, ceiling, first[0].ordinal, more), (1, 2, 1, true));
    let revised = text(2, 2, "second revised after first page");
    history
        .commit(2, &[revised.clone(), text(3, 1, "outside ceiling")], &[])
        .await?;
    let (durable, bound, second, more) = history
        .agent_page(
            false,
            true,
            Some(1),
            Some(ceiling),
            Some(through),
            1,
            &cancellation,
        )
        .await?;
    assert_eq!((durable, bound, more), (2, 2, false));
    assert_eq!(
        second,
        vec![revised],
        "new revision must not remove an original-range identity"
    );
    assert!(
        history
            .agent_page(false, true, None, Some(2), Some(3), 1, &cancellation)
            .await
            .is_err()
    );
    Ok(())
}
