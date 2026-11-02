use super::*;
use futures::poll;

#[tokio::test]
async fn hot_patch_and_query_do_not_wait_for_the_catalog_write_lock() -> Result<()> {
    let (_temp, events) = fixture(
        vec![thread("root", "p1", 1)],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    let catalog = events.store.catalog().clone();
    let (entered, acquired) = std::sync::mpsc::channel();
    let (release, released) = std::sync::mpsc::channel();
    let holder = std::thread::spawn(move || {
        let _document = catalog.test_hold_document();
        entered.send(()).unwrap();
        released.recv().unwrap();
    });
    acquired.recv()?;
    let worker_events = events.clone();
    let runtime = tokio::runtime::Handle::current();
    let (completed, result) = std::sync::mpsc::channel();
    let worker = std::thread::spawn(move || {
        let _runtime = runtime.enter();
        let value = (|| -> Result<ThreadMetadataFrame> {
            worker_events.patch_thread_runtime(
                "root",
                pl_protocol::ThreadStatus::Running,
                2,
                &pl_core::thread::ThreadSnapshot::default(),
            )?;
            worker_events.read_thread_metadata("root", "contention-test")
        })();
        completed.send(value).unwrap();
    });
    // Release and join even on a regression, rather than leaking blocked workers.
    let result = result.recv_timeout(std::time::Duration::from_secs(2));
    release.send(())?;
    holder.join().unwrap();
    worker.join().unwrap();
    let frame = result.expect("metadata must not wait for the Catalog I/O lock")?;
    assert_eq!(
        frame.thread.unwrap().status,
        pl_protocol::ThreadStatus::Running
    );
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn update_uses_the_request_baseline_not_a_later_runtime_row() -> Result<()> {
    let baseline = thread("root", "p1", 1);
    let (_temp, events) = fixture(
        vec![baseline.clone()],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    let mut requested = baseline.clone();
    requested.title = "Manual title".into();
    // This is before the commit call, as can happen while canceling an auto-title task.
    events.patch_thread_runtime(
        "root",
        pl_protocol::ThreadStatus::Running,
        2,
        &pl_core::thread::ThreadSnapshot::default(),
    )?;
    events.commit_thread_update(baseline, requested).await?;
    events
        .commit_observed_thread_mode("root", pl_protocol::ThreadModeId::task(), 3)
        .await?;
    let row = events
        .read_thread_metadata("root", "request-base")?
        .thread
        .unwrap();
    assert_eq!(row.title, "Manual title");
    assert_eq!(row.status, pl_protocol::ThreadStatus::Running);
    assert_eq!(row.mode, pl_protocol::ThreadModeId::task());
    events.writer.flush().await?;
    let saved = events.store.catalog().get("root").unwrap().to_thread();
    assert_eq!(saved.title, row.title);
    assert_eq!(saved.status, row.status);
    assert_eq!(saved.mode, row.mode);
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn explicit_close_is_a_current_owner_fact_not_a_catalog_read_dependency() -> Result<()> {
    let root = thread("root", "p1", 1);
    let mut child = thread("child", "p1", 2);
    child.parent_thread_id = Some(root.id.clone());
    child.root_thread_id = root.id.clone();
    child.agent_path = "root/child".into();
    let (_temp, events) = fixture(
        vec![root, child],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    events.commit_explicit_close("child").await?;
    events.patch_thread_runtime(
        "child",
        pl_protocol::ThreadStatus::Running,
        3,
        &pl_core::thread::ThreadSnapshot::default(),
    )?;
    let baseline = events.thread_snapshot("child").unwrap();
    assert_eq!(baseline.status, pl_protocol::ThreadStatus::Closing);
    let mut closed = baseline.clone();
    closed.status = pl_protocol::ThreadStatus::Closed;
    let (saving, release_save) = install_pause(&events.directory_test_pauses.commit_before_persist);
    let commit = events.commit_thread_update(baseline, closed);
    tokio::pin!(commit);
    assert!(poll!(commit.as_mut()).is_pending());
    saving.await?;
    events.record_user_message("child", 4);
    events
        .commit_observed_thread_mode("child", pl_protocol::ThreadModeId::task(), 5)
        .await?;
    release_save.send(()).unwrap();
    commit.await?;
    let projected = events
        .read_thread_metadata("child", "close-projection")?
        .thread
        .unwrap();
    assert_eq!(projected.status, pl_protocol::ThreadStatus::Closed);
    assert_eq!(projected.updated_at, 5);
    assert_eq!(projected.last_user_message_at, Some(4));
    assert_eq!(projected.mode, pl_protocol::ThreadModeId::task());
    events.patch_thread_runtime(
        "child",
        pl_protocol::ThreadStatus::Idle,
        6,
        &pl_core::thread::ThreadSnapshot::default(),
    )?;
    assert_eq!(
        events
            .read_thread_metadata("child", "close-test")?
            .thread
            .unwrap()
            .status,
        pl_protocol::ThreadStatus::Closed
    );
    events.writer.shutdown().await?;
    let saved = events.store.catalog().get("child").unwrap();
    assert!(saved.explicitly_closed);
    let row = saved.to_thread();
    assert_eq!(row.status, pl_protocol::ThreadStatus::Closed);
    assert_eq!(row.updated_at, 6);
    assert_eq!(row.last_user_message_at, Some(4));
    assert_eq!(row.mode, pl_protocol::ThreadModeId::task());
    Ok(())
}
