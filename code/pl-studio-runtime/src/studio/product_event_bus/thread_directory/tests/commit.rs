use super::*;
use futures::poll;

#[tokio::test]
async fn durable_first_commit_keeps_old_slice_readable_then_publishes_one_new_slice() -> Result<()>
{
    let original_project = project("p1", "Before Project", "/workspace/project");
    let original = thread("existing", "p1", 10);
    let (_temp, events) = fixture(vec![original.clone()], vec![original_project.clone()]).await?;
    let before = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    let (before_persist, release_persist) =
        install_pause(&events.directory_test_pauses.commit_before_persist);
    let (persisted, release_publish) =
        install_pause(&events.directory_test_pauses.commit_persisted);

    let mut stale_existing = original.clone();
    stale_existing.title = "Durable command title".into();
    let new_thread = thread("new", "p1", 20);
    let mut renamed_project = original_project;
    renamed_project.name = "After Project".into();
    renamed_project.updated_at = 2;
    let commit = events.commit_directory_with_bases(
        DirectoryDelta {
            project_upserts: vec![renamed_project],
            thread_upserts: vec![stale_existing, new_thread.clone()],
            ..Default::default()
        },
        HashMap::from([(original.id.clone(), original.clone())]),
    );
    tokio::pin!(commit);
    assert!(poll!(commit.as_mut()).is_pending());
    before_persist.await?;

    // No metadata lock is held across persistence: synchronous readers return the old slice.
    assert!(events.thread_index.try_lock().is_ok());
    let during_before_persist = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    assert_eq!(during_before_persist.threads, before.threads);
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
        .threads
        .is_empty()
    );
    let query_filter = ThreadDirectoryQuery::default();
    let readable = events.query_threads(&query_filter, None, 10).await?;
    assert_eq!(readable.state.value().unwrap().threads, before.threads);

    release_persist.send(()).unwrap();
    tokio::select! {
        result = &mut commit => panic!("commit published before persisted checkpoint: {result:?}"),
        result = persisted => result?,
    }
    let readable = events.query_threads(&query_filter, None, 10).await?;
    assert_eq!(readable.state.value().unwrap().threads, before.threads);
    // The catalog write has completed, but the only query owner still exposes the previous slice.
    assert!(events.store.catalog().get(&new_thread.id).is_some());
    assert_eq!(
        query(&events, &ThreadDirectoryQuery::default(), None, 10)?.threads,
        before.threads
    );

    // A later hot mutation may publish while the durable command is paused. Completion must not
    // write the command's stale copy back over this newer visible metadata.
    events
        .patch_thread_runtime(
            &original.id,
            pl_protocol::ThreadStatus::Running,
            30,
            &pl_core::thread::ThreadSnapshot::default(),
        )?
        .unwrap();
    let hot = events.read_thread_metadata(&original.id, "owner-test")?;
    assert_eq!(
        hot.thread.as_ref().unwrap().status,
        pl_protocol::ThreadStatus::Running
    );
    assert!(
        events
            .read_thread_metadata(&new_thread.id, "owner-test")?
            .thread
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
            .threads
            .iter()
            .map(|thread| thread.id.as_str())
            .collect::<Vec<_>>(),
        vec!["new", "existing"]
    );
    assert_eq!(
        after
            .threads
            .iter()
            .map(|thread| thread.id.as_str())
            .collect::<Vec<_>>(),
        vec!["new", "existing"]
    );
    assert_eq!(
        after.stamp,
        events
            .read_thread_metadata(&original.id, "owner-test")?
            .stamp
    );
    let rebased = events
        .read_thread_metadata(&original.id, "owner-test")?
        .thread
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
        .threads
        .len(),
        2
    );
    events.writer.flush().await?;
    let durable = events
        .store
        .catalog()
        .get(&original.id)
        .expect("rebased row is durable")
        .to_thread();
    assert_eq!(durable.title, "Durable command title");
    assert_eq!(durable.status, pl_protocol::ThreadStatus::Running);
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn failed_durable_commit_never_changes_the_ram_owner() -> Result<()> {
    let original = thread("existing", "p1", 10);
    let (_temp, events) = fixture(
        vec![original.clone()],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    let before = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    let mut conflicting = original;
    conflicting.workspace_path = "/conflicting/session/identity".into();
    let result = events
        .commit_directory(DirectoryDelta {
            thread_upserts: vec![conflicting],
            ..Default::default()
        })
        .await;
    assert!(result.is_err());
    let after = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    assert_eq!(after.threads, before.threads);
    assert_eq!(after.stamp, before.stamp);
    events.writer.shutdown().await?;
    Ok(())
}
