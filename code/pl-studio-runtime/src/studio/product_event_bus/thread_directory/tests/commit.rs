use super::*;
use futures::poll;

#[tokio::test]
async fn typed_session_archive_and_delete_use_thread_references_without_resurrection() -> Result<()>
{
    let mut root = row("root-thread", "p1", 10);
    // Native physical history retains its original root Thread bytes in S1.
    root.session_id = root.thread_id.clone();
    root.agent_id = "root-agent".into();
    let mut child = row("child-thread", "p1", 11);
    child.session_id = root.session_id.clone();
    child.agent_id = "child-agent".into();
    child.parent_agent_id = Some(root.agent_id.clone());
    let (_temp, events) = fixture(
        vec![root.clone(), child.clone()],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    let archived = event_delta(
        events
            .commit_directory(DirectoryDelta::archive_sessions(vec![
                root.session_id.clone(),
            ]))
            .await?,
    );
    assert_eq!(
        archived.removed.into_iter().collect::<BTreeSet<_>>(),
        BTreeSet::from([root.thread_id.clone(), child.thread_id.clone()])
    );
    assert!(
        query(&events, &ThreadDirectoryQuery::default(), None, 10)?
            .rows
            .is_empty()
    );
    // This unit isolates directory publication, not the lifecycle deletion journal. Settle the
    // preceding archive first; real delete_thread installs its durable replay fence before removal.
    events.writer.flush().await?;
    events
        .commit_directory(DirectoryDelta::delete_threads(vec![
            child.thread_id.clone(),
            root.thread_id.clone(),
        ]))
        .await?;
    // A late observation cannot recreate either member or its now-absent session.
    events.publish_thread_delta(vec![root.clone(), child], vec![], vec![root]);
    assert!(events.store.catalog().sessions().is_empty());
    assert!(events.store.catalog().agents().is_empty());
    assert!(events.thread_index.lock().unwrap().sessions.is_empty());
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn durable_commit_exposes_old_slice_until_publication_and_never_locks_readers() -> Result<()>
{
    let original = row("existing", "p1", 10);
    let (_temp, events) = fixture(
        vec![original],
        vec![project("p1", "Before", "/workspace/project")],
    )
    .await?;
    let before = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    let before_agents = events.read_agent_directory().await;
    let mut changes = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    let new_row = row("new", "p1", 20);
    let (saving, release_save, save_checkpoint) = checkpoint();
    let (saved, release_publish, publish_checkpoint) = checkpoint();
    let commit = commit_at_boundaries(
        &events,
        DirectoryDelta {
            project_upserts: vec![project("p1", "After", "/workspace/project")],
            session_upserts: vec![session_from_row(&new_row)],
            agent_upserts: vec![agent_from_row(&new_row)],
            ..Default::default()
        },
        DirectoryBaselines::default(),
        Some(save_checkpoint),
        Some(publish_checkpoint),
    );
    tokio::pin!(commit);
    assert!(poll!(commit.as_mut()).is_pending());
    saving.await?;
    assert!(events.thread_index.try_lock().is_ok());
    assert_eq!(
        query(&events, &ThreadDirectoryQuery::default(), None, 10)?.stamp,
        before.stamp
    );
    assert_eq!(events.read_agent_directory().await, before_agents);
    release_save.send(()).unwrap();
    tokio::select! {
        result = &mut commit => panic!("published before saved checkpoint: {result:?}"),
        result = saved => result?,
    }
    assert!(events.store.catalog().get_agent("new").is_some());
    assert_eq!(
        query(&events, &ThreadDirectoryQuery::default(), None, 10)?.rows,
        before.rows
    );
    assert_eq!(
        events
            .query_threads(&ThreadDirectoryQuery::default(), None, 10)
            .await?
            .state
            .revision(),
        before.stamp.revision
    );
    assert_eq!(events.read_agent_directory().await, before_agents);
    assert!(changes.try_recv().is_err());
    let filter = ThreadDirectoryQuery {
        search: Some("after".into()),
        ..Default::default()
    };
    assert!(query(&events, &filter, None, 10)?.rows.is_empty());
    release_publish.send(()).unwrap();
    commit.await?;
    let after = query(&events, &filter, None, 10)?;
    assert_eq!(
        after
            .rows
            .iter()
            .map(|row| row.thread_id.as_str())
            .collect::<Vec<_>>(),
        ["new", "existing"]
    );
    assert!(after.stamp.revision > before.stamp.revision);
    let current = events.read_agent_directory().await;
    let StudioProductEventKind::AgentDirectoryChanged(published) = changes.try_recv()?.kind else {
        panic!("agent event")
    };
    assert_eq!(published, current);
    assert_eq!(current.state.revision(), before_agents.state.revision() + 1);
    assert!(changes.try_recv().is_err());
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn saved_command_rebases_over_hot_facts_and_persists_the_published_cut() -> Result<()> {
    let original = row("existing", "p1", 10);
    let (_temp, events) = fixture(vec![original], vec![]).await?;
    let (baseline_session, baseline_agent) = events.directory_facts("existing").unwrap();
    let mut requested = baseline_session.clone();
    requested.title = "Durable command title".into();
    let mut bases = DirectoryBaselines::default();
    bases.sessions.insert("existing".into(), baseline_session);
    bases
        .agents
        .insert("existing".into(), baseline_agent.clone());
    let (saved, release, checkpoint) = checkpoint();
    let commit = commit_at_boundaries(
        &events,
        DirectoryDelta {
            session_upserts: vec![requested],
            agent_upserts: vec![baseline_agent],
            ..Default::default()
        },
        bases,
        None,
        Some(checkpoint),
    );
    tokio::pin!(commit);
    tokio::select! {
        result = &mut commit => panic!("published before checkpoint: {result:?}"),
        result = saved => result?,
    }
    events.patch_thread_runtime(
        events.begin_native_observation("existing").as_ref(),
        ThreadStatus::Running,
        30,
        &pl_core::thread::ThreadSnapshot::default(),
        None,
    )?;
    events.record_user_message("existing", 40);
    let hot = events.read_thread_metadata("existing", "test")?;
    release.send(()).unwrap();
    let event = commit.await?;
    let delta = event_delta(event);
    let committed = events.read_thread_metadata("existing", "test")?;
    let row = committed.row.unwrap();
    assert_eq!(row.title, "Durable command title");
    assert_eq!(row.native_status(), Some(ThreadStatus::Running));
    assert_eq!(row.last_user_message_at, Some(40));
    assert_eq!(delta.upserted, vec![row.clone()]);
    assert_eq!(delta.revision, committed.stamp.revision);
    assert!(committed.stamp.revision > hot.stamp.revision);
    events.writer.flush().await?;
    let session = events.store.catalog().get_session("existing").unwrap();
    let agent = events.store.catalog().get_agent("existing").unwrap();
    assert_eq!(session.title, row.title);
    assert_eq!(session.last_user_message_at, Some(40));
    assert_eq!(agent.native_status(), row.native_status());
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn failed_durable_commit_never_changes_the_ram_owner() -> Result<()> {
    let original = row("existing", "p1", 10);
    let (_temp, events) = fixture(
        vec![original.clone()],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    let before = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    let before_agents = events.read_agent_directory().await;
    let before_sequence = events.current_sequence();
    let (baseline_session, _) = events.directory_facts(&original.thread_id).expect("facts");
    let mut conflicting = baseline_session;
    conflicting.workspace_path = "/conflicting/session/identity".into();
    let result = events
        .commit_directory(DirectoryDelta {
            session_upserts: vec![conflicting],
            ..Default::default()
        })
        .await;
    assert!(result.is_err());
    let after = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    assert_eq!(after.rows, before.rows);
    assert_eq!(after.stamp, before.stamp);
    assert_eq!(events.read_agent_directory().await, before_agents);
    assert_eq!(events.current_sequence(), before_sequence);
    assert_eq!(
        events
            .thread_index
            .lock()
            .unwrap()
            .get_agent("existing")
            .unwrap()
            .thread_id,
        "existing"
    );
    events.writer.shutdown().await?;
    Ok(())
}
