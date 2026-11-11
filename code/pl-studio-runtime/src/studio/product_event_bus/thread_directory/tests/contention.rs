use super::*;
use crate::studio::store::agent_close::AgentCloseRecord;
use futures::poll;
use pl_tool::collaboration::control::AgentWorktreeCleanup;

#[tokio::test]
async fn hot_patch_and_query_do_not_wait_for_the_catalog_write_lock() -> Result<()> {
    let (_temp, events) = fixture(
        vec![row("root", "p1", 1)],
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
        frame.row.unwrap().status,
        pl_protocol::ThreadStatus::Running
    );
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn update_uses_the_request_baseline_not_a_later_runtime_row() -> Result<()> {
    let baseline_row = row("root", "p1", 1);
    let (_temp, events) = fixture(
        vec![baseline_row.clone()],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    // The frozen baseline is read before the commit call, as can happen while canceling an
    // auto-title task.
    let (baseline_session, _) = events
        .directory_facts(&baseline_row.thread_id)
        .expect("facts");
    let mut requested = baseline_session.clone();
    requested.title = "Manual title".into();
    events.patch_thread_runtime(
        "root",
        pl_protocol::ThreadStatus::Running,
        2,
        &pl_core::thread::ThreadSnapshot::default(),
    )?;
    events
        .commit_session_update(baseline_session, requested)
        .await?;
    events
        .commit_observed_thread_mode("root", pl_protocol::ThreadModeId::task(), 3)
        .await?;
    let row = events
        .read_thread_metadata("root", "request-base")?
        .row
        .unwrap();
    assert_eq!(row.title, "Manual title");
    assert_eq!(row.status, pl_protocol::ThreadStatus::Running);
    assert_eq!(row.mode, pl_protocol::ThreadModeId::task());
    events.writer.flush().await?;
    let session = events.store.catalog().get_session("root").unwrap();
    let agent = events.store.catalog().get_agent("root").unwrap();
    assert_eq!(session.title, row.title);
    assert_eq!(agent.status, row.status);
    assert_eq!(session.mode, row.mode);
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn explicit_close_is_a_current_owner_fact_not_a_catalog_read_dependency() -> Result<()> {
    let root = row("root", "p1", 1);
    let mut child = row("child", "p1", 2);
    child.session_id = root.session_id.clone();
    child.parent_agent_id = Some(root.agent_id.clone());
    child.last_user_message_at = None;
    let (_temp, events) = fixture(
        vec![root, child],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    let missing = events.commit_explicit_close("child").await.unwrap_err();
    assert!(format!("{missing:#}").contains("close progress requires its durable intent"));
    let mut close = AgentCloseRecord {
        agent_id: "child".into(),
        parent_id: "root".into(),
        root_id: "root".into(),
        workspace_id: "p1".into(),
        revision: 1,
        force: false,
        worktree: None,
        git: None,
        execution_closed: false,
        worktree_cleanup: AgentWorktreeCleanup::Pending,
        error: None,
    };
    // save_agent_close validates the real persisted domain fact and its owner.
    events.store.save_agent_close(&close).await?;
    events.commit_explicit_close("child").await?;
    events.patch_thread_runtime(
        "child",
        pl_protocol::ThreadStatus::Running,
        3,
        &pl_core::thread::ThreadSnapshot::default(),
    )?;
    let (_, baseline_agent) = events.directory_facts("child").expect("facts");
    assert_eq!(baseline_agent.status, pl_protocol::ThreadStatus::Closing);
    let mut closed_agent = baseline_agent.clone();
    closed_agent.status = pl_protocol::ThreadStatus::Closed;
    let (saving, release_save) = install_pause(&events.directory_test_pauses.commit_before_persist);
    let mut bases = DirectoryBaselines::default();
    bases
        .agents
        .insert(baseline_agent.agent_id.clone(), baseline_agent);
    let commit = events.commit_directory_with_bases(
        DirectoryDelta {
            agent_upserts: vec![closed_agent],
            ..Default::default()
        },
        bases,
    );
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
        .row
        .unwrap();
    assert_eq!(
        projected.status,
        pl_protocol::ThreadStatus::Closing,
        "a generic raw Closed candidate cannot acknowledge permanent execution closure"
    );
    assert_eq!(projected.updated_at, 5);
    assert_eq!(projected.mode, pl_protocol::ThreadModeId::task());
    // 已受理用户消息的水位是会话级事实：成员行不携带，主成员行保留并发提交期间的值。
    let root_row = events
        .read_thread_metadata("root", "close-projection")?
        .row
        .unwrap();
    assert_eq!(root_row.last_user_message_at, Some(4));
    // Keep the ACK outside the original paused generic save above, preserving
    // its concurrent mode/message interleaving. A restore read before this lock
    // would still carry false, as the old bool-across-lock implementation did.
    let stale = events.store.agent_close("child").await?.unwrap();
    assert!(!stale.execution_closed);
    let directory_command = events.directory_commands.lock().await;
    let queued = events.commit_explicit_close("child");
    tokio::pin!(queued);
    assert!(
        poll!(queued.as_mut()).is_pending(),
        "the progress publication must wait for the original directory command lock"
    );
    close.execution_closed = true;
    close.changed()?;
    events.store.save_agent_close(&close).await?;
    assert_eq!(
        events.store.agent_close("child").await?,
        Some(close.clone())
    );
    drop(directory_command);
    queued.await?;
    let acknowledged = events
        .read_thread_metadata("child", "close-ack")?
        .row
        .unwrap();
    assert_eq!(acknowledged.status, pl_protocol::ThreadStatus::Closed);
    assert_eq!(acknowledged.updated_at, 5);
    assert_eq!(acknowledged.mode, pl_protocol::ThreadModeId::task());
    assert_eq!(
        events.store.catalog().get_agent("child").unwrap().status,
        pl_protocol::ThreadStatus::Closed,
        "the queued publication must read the new true ACK, not its old false observation"
    );
    events.commit_explicit_close("child").await?;
    assert_eq!(
        events
            .read_thread_metadata("child", "repeat-close-restore")?
            .row
            .unwrap()
            .status,
        pl_protocol::ThreadStatus::Closed,
        "repeated close restoration must not regress the acknowledged stage"
    );
    events.patch_thread_runtime(
        "child",
        pl_protocol::ThreadStatus::Idle,
        6,
        &pl_core::thread::ThreadSnapshot::default(),
    )?;
    assert_eq!(
        events
            .read_thread_metadata("child", "close-test")?
            .row
            .unwrap()
            .status,
        pl_protocol::ThreadStatus::Closed
    );
    events.writer.shutdown().await?;
    let saved_agent = events.store.catalog().get_agent("child").unwrap();
    assert!(saved_agent.explicitly_closed);
    assert_eq!(saved_agent.status, pl_protocol::ThreadStatus::Closed);
    assert_eq!(saved_agent.updated_at, 6);
    let saved_session = events.store.catalog().get_session("root").unwrap();
    assert_eq!(saved_session.last_user_message_at, Some(4));
    assert_eq!(saved_session.mode, pl_protocol::ThreadModeId::task());
    Ok(())
}
