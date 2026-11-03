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
async fn durable_first_commit_keeps_old_slice_readable_then_publishes_one_new_slice() -> Result<()>
{
    let original_project = project("p1", "Before Project", "/workspace/project");
    let original = row("existing", "p1", 10);
    let (_temp, events) = fixture(vec![original.clone()], vec![original_project.clone()]).await?;
    let before = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    let (baseline_session, baseline_agent) =
        events.directory_facts(&original.thread_id).expect("facts");
    let (before_persist, release_persist) =
        install_pause(&events.directory_test_pauses.commit_before_persist);
    let (persisted, release_publish) =
        install_pause(&events.directory_test_pauses.commit_persisted);

    let mut stale_session = baseline_session.clone();
    stale_session.title = "Durable command title".into();
    let new_row = row("new", "p1", 20);
    let new_session = session_from_row(&new_row);
    let new_agent = agent_from_row(&new_row);
    let mut renamed_project = original_project;
    renamed_project.name = "After Project".into();
    renamed_project.updated_at = 2;
    let commit = events.commit_directory_with_bases(
        DirectoryDelta {
            project_upserts: vec![renamed_project],
            session_upserts: vec![stale_session, new_session],
            agent_upserts: vec![baseline_agent.clone(), new_agent],
            ..Default::default()
        },
        {
            let mut bases = DirectoryBaselines::default();
            bases
                .sessions
                .insert(baseline_session.session_id.clone(), baseline_session);
            bases
                .agents
                .insert(baseline_agent.agent_id.clone(), baseline_agent);
            bases
        },
    );
    tokio::pin!(commit);
    assert!(poll!(commit.as_mut()).is_pending());
    before_persist.await?;

    // No metadata lock is held across persistence: synchronous readers return the old slice.
    assert!(events.thread_index.try_lock().is_ok());
    let during_before_persist = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    assert_eq!(during_before_persist.rows, before.rows);
    assert_eq!(during_before_persist.stamp, before.stamp);
    assert!(
        query(
            &events,
            &ThreadDirectoryQuery {
                search: Some("after project".into()),
                ..Default::default()
            },
            None,
            10,
        )?
        .rows
        .is_empty()
    );
    let query_filter = ThreadDirectoryQuery::default();
    let readable = events.query_threads(&query_filter, None, 10).await?;
    assert_eq!(readable.state.value().unwrap().rows, before.rows);

    release_persist.send(()).unwrap();
    tokio::select! {
        result = &mut commit => panic!("commit published before persisted checkpoint: {result:?}"),
        result = persisted => result?,
    }
    let readable = events.query_threads(&query_filter, None, 10).await?;
    assert_eq!(readable.state.value().unwrap().rows, before.rows);
    // The catalog write has completed, but the only query owner still exposes the previous slice.
    assert!(
        events
            .store
            .catalog()
            .get_agent(&new_row.agent_id)
            .is_some()
    );
    assert_eq!(
        query(&events, &ThreadDirectoryQuery::default(), None, 10)?.rows,
        before.rows
    );

    // A later hot mutation may publish while the durable command is paused. Completion must not
    // write the command's stale copy back over this newer visible metadata.
    events
        .patch_thread_runtime(
            &original.thread_id,
            pl_protocol::ThreadStatus::Running,
            30,
            &pl_core::thread::ThreadSnapshot::default(),
        )?
        .unwrap();
    let hot = events.read_thread_metadata(&original.thread_id, "owner-test")?;
    assert_eq!(
        hot.row.as_ref().unwrap().status,
        pl_protocol::ThreadStatus::Running
    );
    assert!(
        events
            .read_thread_metadata(&new_row.thread_id, "owner-test")?
            .row
            .is_none()
    );

    release_publish.send(()).unwrap();
    commit.await?;
    let after = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    let unblocked = events.query_threads(&query_filter, None, 10).await?;
    assert_eq!(unblocked.state.revision(), after.stamp.revision);
    assert_eq!(
        unblocked
            .state
            .value()
            .unwrap()
            .rows
            .iter()
            .map(|row| row.thread_id.as_str())
            .collect::<Vec<_>>(),
        vec!["new", "existing"]
    );
    assert_eq!(
        after
            .rows
            .iter()
            .map(|row| row.thread_id.as_str())
            .collect::<Vec<_>>(),
        vec!["new", "existing"]
    );
    assert_eq!(
        after.stamp,
        events
            .read_thread_metadata(&original.thread_id, "owner-test")?
            .stamp
    );
    let rebased = events
        .read_thread_metadata(&original.thread_id, "owner-test")?
        .row
        .unwrap();
    assert_eq!(rebased.title, "Durable command title");
    assert_eq!(rebased.status, pl_protocol::ThreadStatus::Running);
    assert!(after.stamp.revision > hot.stamp.revision);
    assert_eq!(
        query(
            &events,
            &ThreadDirectoryQuery {
                search: Some("after project".into()),
                ..Default::default()
            },
            None,
            10,
        )?
        .rows
        .len(),
        2
    );
    events.writer.flush().await?;
    let durable_session = events
        .store
        .catalog()
        .get_session(&original.session_id)
        .expect("rebased session is durable");
    assert_eq!(durable_session.title, "Durable command title");
    let durable_agent = events
        .store
        .catalog()
        .get_agent(&original.agent_id)
        .expect("rebased agent is durable");
    assert_eq!(durable_agent.status, pl_protocol::ThreadStatus::Running);
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
    events.writer.shutdown().await?;
    Ok(())
}
