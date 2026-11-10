use super::*;
use crate::studio::{StudioStore, agent_host::ThreadWriteBehindWriter};

async fn fixture() -> Result<(tempfile::TempDir, ProductEventBus)> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let events = ProductEventBus::new(store, writer);
    events.initialize_directories().await?;
    Ok((temp, events))
}

fn row(id: &str, time: i64) -> pl_protocol::SessionDirectoryRow {
    pl_protocol::SessionDirectoryRow {
        session_id: id.into(),
        agent_id: id.into(),
        parent_agent_id: None,
        thread_id: id.into(),
        workspace_id: "directory-pull-fixture".into(),
        title: id.into(),
        mode: pl_protocol::ThreadModeId::simple(),
        workspace_mode: pl_protocol::ThreadWorkspaceMode::Local,
        delegation_mode: Default::default(),
        delegation_preference: Default::default(),
        workspace_path: format!("/tmp/{id}"),
        role: crate::config::ROOT_AGENT_ROUTE_KEY.into(),
        binding: pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
            route: None,
            system_instructions: None,
        }),
        status: pl_protocol::ThreadStatus::Idle,
        created_at: time,
        updated_at: time,
        last_user_message_at: None,
        archived: false,
    }
}

fn observe(events: &ProductEventBus, limit: u32) -> Result<ThreadsObservation> {
    ThreadsObservation::open(
        events.clone(),
        "pull-fixture".into(),
        ThreadDirectoryQuery::default(),
        ThreadDirectoryWindow {
            before: None,
            limit,
        },
    )
}

#[tokio::test]
async fn registration_and_consumer_in_flight_changes_are_retained() -> Result<()> {
    let (_temp, events) = fixture().await?;
    let observation = observe(&events, 2)?;
    // This mutation falls after registration but before the initial next.
    events
        .apply_thread_delta(vec![row("old", 1), row("head", 3)], vec![])
        .await?;
    let first = observation.next().await?.expect("initial result");
    assert_eq!(first.thread_ids[0], "head");
    assert_eq!(first.stamp.resource_key, "thread-directory");
    let wire = serde_json::to_value(&first)?;
    assert_eq!(wire["threadIds"], serde_json::json!(["head", "old"]));
    assert!(wire.get("rows").is_none());

    // A completed native read has not yet been accepted by its consumer.
    let mut outside = row("outside", 2);
    outside.title = "renamed while accepting".into();
    events
        .apply_thread_delta(vec![outside.clone()], vec![])
        .await?;
    let next = observation.next().await?.expect("retained notification");
    assert!(next.stamp.revision > first.stamp.revision);
    assert_eq!(next.thread_ids, ["head", "outside"]);
    assert!(next.next_cursor.is_some());
    observation.close().await?;
    Ok(())
}

#[tokio::test]
async fn selected_metadata_and_reopened_large_window_are_independent() -> Result<()> {
    let (_temp, events) = fixture().await?;
    events
        .apply_thread_delta(
            (0..90).map(|n| row(&format!("row-{n:03}"), n)).collect(),
            vec![],
        )
        .await?;
    let selected =
        ThreadMetadataObservation::open(events.clone(), "pull-fixture".into(), "row-000".into())?;
    let wide = observe(&events, 80)?;
    let before = wide.next().await?.expect("wide result");
    assert_eq!(before.thread_ids.len(), 80);
    assert_eq!(before.thread_ids.last().unwrap(), "row-010");
    assert_eq!(
        selected.next().await?.unwrap().row.unwrap().thread_id,
        "row-000"
    );
    wide.close().await?;

    let mut outside = row("row-000", 0);
    outside.title = "changed outside list".into();
    outside.archived = true;
    events.apply_thread_delta(vec![outside], vec![]).await?;
    let entity = selected.next().await?.expect("independent entity update");
    assert!(entity.row.as_ref().unwrap().archived);
    assert_eq!(entity.row.as_ref().unwrap().title, "changed outside list");
    let reopened = observe(&events, 80)?;
    let after = reopened.next().await?.expect("same complete demand");
    assert_eq!(after.window, before.window);
    assert_eq!(after.thread_ids.len(), 80);
    assert_eq!(after.thread_ids.last().unwrap(), "row-010");
    assert!(after.stamp.revision > before.stamp.revision);
    reopened.close().await?;
    selected.close().await?;
    Ok(())
}

#[tokio::test]
async fn close_wakes_the_actual_next_and_releases_its_receiver() -> Result<()> {
    let (_temp, events) = fixture().await?;
    let observation = observe(&events, 20)?;
    assert!(observation.next().await?.unwrap().thread_ids.is_empty());
    let mut waiting = std::pin::pin!(observation.next());
    assert!(futures::poll!(waiting.as_mut()).is_pending());
    let error = observation
        .next()
        .await
        .expect_err("concurrent next is rejected");
    assert_eq!(
        error.downcast_ref::<StudioError>().unwrap().code,
        StudioErrorCode::Busy
    );
    observation.request_close();
    assert!(waiting.await?.is_none());
    observation.close().await?;
    assert!(observation.inner.next.lock().await.signal.is_none());
    assert!(observation.next().await?.is_none());

    let missing =
        ThreadMetadataObservation::open(events.clone(), "pull-fixture".into(), "missing".into())?;
    assert!(missing.next().await?.unwrap().row.is_none());
    events
        .apply_thread_delta(vec![row("missing", 1)], vec![])
        .await?;
    assert_eq!(
        missing.next().await?.unwrap().row.unwrap().thread_id,
        "missing"
    );
    missing.close().await?;
    assert!(missing.inner.next.lock().await.signal.is_none());
    Ok(())
}

async fn metadata_has_pending(observation: &ThreadMetadataObservation) -> bool {
    observation
        .inner
        .next
        .lock()
        .await
        .signal
        .as_mut()
        .unwrap()
        .receiver()
        .has_changed()
        .unwrap()
}

#[tokio::test]
async fn content_only_changes_do_not_deliver_structure_or_wake_unrelated_metadata() -> Result<()> {
    let (_temp, events) = fixture().await?;
    events
        .apply_thread_delta(vec![row("a", 2), row("b", 1)], vec![])
        .await?;
    let list = observe(&events, 1)?;
    let a = ThreadMetadataObservation::open(events.clone(), "epoch".into(), "a".into())?;
    let b = ThreadMetadataObservation::open(events.clone(), "epoch".into(), "b".into())?;
    let first = list.next().await?.unwrap();
    assert_eq!(first.thread_ids, ["a"]);
    a.next().await?.unwrap();
    let baseline_b = b.next().await?.unwrap();

    let mut changed = row("a", 2);
    changed.title = "new title".into();
    events.apply_thread_delta(vec![changed], vec![]).await?;
    assert!(metadata_has_pending(&a).await);
    assert!(
        !metadata_has_pending(&b).await,
        "B must not even be signalled by A"
    );
    assert_eq!(a.next().await?.unwrap().row.unwrap().title, "new title");
    assert_eq!(
        events.read_thread_metadata("b", "epoch")?.row,
        baseline_b.row
    );
    let mut next_structure = std::pin::pin!(list.next());
    assert!(futures::poll!(next_structure.as_mut()).is_pending());
    events.patch_thread_runtime(
        "a",
        pl_protocol::ThreadStatus::Running,
        2,
        &pl_core::thread::ThreadSnapshot::default(),
    )?;
    assert_eq!(
        a.next().await?.unwrap().row.unwrap().status,
        pl_protocol::ThreadStatus::Running
    );
    assert!(!metadata_has_pending(&b).await);
    assert!(futures::poll!(next_structure.as_mut()).is_pending());

    // The existing next must still notice a member moving in from outside its fixed window.
    let mut moved = row("b", 1);
    moved.last_user_message_at = Some(3);
    events.apply_thread_delta(vec![moved], vec![]).await?;
    let next = next_structure.await?.unwrap();
    assert_eq!(next.thread_ids, ["b"]);
    assert!(next.stamp.revision > first.stamp.revision);
    list.close().await?;
    a.close().await?;
    b.close().await?;
    assert_eq!(events.metadata_signal_count(), 0);
    Ok(())
}

#[tokio::test]
async fn metadata_registration_is_shared_reclaimed_and_survives_cancelled_next() -> Result<()> {
    let (_temp, events) = fixture().await?;
    let a = ThreadMetadataObservation::open(events.clone(), "epoch".into(), "a".into())?;
    let other = ThreadMetadataObservation::open(events.clone(), "epoch".into(), "a".into())?;
    assert_eq!(events.metadata_signal_count(), 1);
    assert!(a.next().await?.unwrap().row.is_none());
    let mut waiting = Box::pin(a.next());
    assert!(futures::poll!(waiting.as_mut()).is_pending());
    let error = a.next().await.expect_err("one in-flight metadata read");
    assert_eq!(
        error.downcast_ref::<StudioError>().unwrap().code,
        StudioErrorCode::Busy
    );
    drop(waiting); // Cancel just next, not its owning observation.
    events.apply_thread_delta(vec![row("a", 1)], vec![]).await?;
    assert_eq!(a.next().await?.unwrap().row.unwrap().thread_id, "a");
    a.close().await?;
    assert_eq!(events.metadata_signal_count(), 1);
    assert!(other.next().await?.unwrap().row.is_some());
    let mut waiting = std::pin::pin!(other.next());
    assert!(futures::poll!(waiting.as_mut()).is_pending());
    other.request_close();
    assert!(waiting.await?.is_none());
    other.close().await?;
    assert_eq!(events.metadata_signal_count(), 0);
    let dropped =
        ThreadMetadataObservation::open(events.clone(), "epoch".into(), "missing".into())?;
    assert_eq!(events.metadata_signal_count(), 1);
    drop(dropped);
    assert_eq!(
        events.metadata_signal_count(),
        0,
        "abandoned handles release registration"
    );
    Ok(())
}

#[tokio::test]
async fn metadata_read_retains_a_notification_after_its_source_cut() -> Result<()> {
    let (_temp, events) = fixture().await?;
    let observation = ThreadMetadataObservation::open(events.clone(), "epoch".into(), "a".into())?;
    // Split the synchronous read/delivery boundary to place an update at the exact interleaving:
    // ready consumes the signal, the owner captures a slice, then a writer commits before delivery.
    {
        let mut state = observation.inner.next.lock().await;
        assert!(state.ready(&observation.inner.cancellation).await);
        let frame = events.read_thread_metadata("a", "epoch")?;
        events.apply_thread_delta(vec![row("a", 1)], vec![]).await?;
        state.last = Some(frame.row);
    }
    assert!(metadata_has_pending(&observation).await);
    assert!(observation.next().await?.unwrap().row.is_some());
    observation.close().await?;
    Ok(())
}

#[tokio::test]
async fn session_facts_notify_actual_members_with_distinct_identities() -> Result<()> {
    use crate::studio::store::directory::DirectoryDelta;

    let (_temp, events) = fixture().await?;
    let mut root = row("root-thread", 1);
    // Native persistence retains the physical root Thread as its Session ID.
    // Agent IDs and member Thread IDs are independent.
    root.session_id = root.thread_id.clone();
    root.agent_id = "root-agent".into();
    let mut child = row("child-thread", 1);
    child.session_id = root.session_id.clone();
    child.agent_id = "child-agent".into();
    child.parent_agent_id = Some(root.agent_id.clone());
    events
        .apply_thread_delta(vec![root.clone(), child], vec![])
        .await?;
    let root_observation =
        ThreadMetadataObservation::open(events.clone(), "epoch".into(), root.thread_id.clone())?;
    let child_observation =
        ThreadMetadataObservation::open(events.clone(), "epoch".into(), "child-thread".into())?;
    let unrelated =
        ThreadMetadataObservation::open(events.clone(), "epoch".into(), "unrelated".into())?;
    root_observation.next().await?;
    child_observation.next().await?;
    unrelated.next().await?;

    // A session-level Mode change affects both members, not an ID guessed from session/agent.
    events
        .commit_observed_thread_mode(&root.thread_id, pl_protocol::ThreadModeId::task(), 2)
        .await?;
    for observation in [&root_observation, &child_observation] {
        assert!(metadata_has_pending(observation).await);
        assert_eq!(
            observation.next().await?.unwrap().row.unwrap().mode,
            pl_protocol::ThreadModeId::task()
        );
    }
    assert!(!metadata_has_pending(&unrelated).await);
    // A recent-user-message watermark is projected on the root only.
    events.record_user_message("child-thread", 3);
    assert!(metadata_has_pending(&root_observation).await);
    assert!(!metadata_has_pending(&child_observation).await);
    assert_eq!(
        root_observation
            .next()
            .await?
            .unwrap()
            .row
            .unwrap()
            .last_user_message_at,
        Some(3)
    );

    events
        .commit_directory(DirectoryDelta::archive_sessions(vec![
            root.session_id.clone(),
        ]))
        .await?;
    for observation in [&root_observation, &child_observation] {
        assert!(observation.next().await?.unwrap().row.unwrap().archived);
    }
    let (baseline, _) = events.directory_facts(&root.thread_id).unwrap();
    let mut restored = baseline.clone();
    restored.archived = false;
    events.commit_session_update(baseline, restored).await?;
    for observation in [&root_observation, &child_observation] {
        assert!(!observation.next().await?.unwrap().row.unwrap().archived);
    }
    // Root deletion removes its complete member set.
    events
        .commit_directory(DirectoryDelta::delete_threads(vec![root.thread_id]))
        .await?;
    for observation in [&root_observation, &child_observation] {
        assert!(observation.next().await?.unwrap().row.is_none());
        observation.close().await?;
    }
    assert!(!metadata_has_pending(&unrelated).await);
    unrelated.close().await?;
    assert_eq!(events.metadata_signal_count(), 0);
    Ok(())
}

#[tokio::test]
async fn cursor_and_project_search_changes_are_structure_dependencies() -> Result<()> {
    use crate::studio::store::directory::{DirectoryDelta, ProjectRemoval};

    let (_temp, events) = fixture().await?;
    events.apply_thread_delta(vec![row("a", 2)], vec![]).await?;
    let list = observe(&events, 1)?;
    let first = list.next().await?.unwrap();
    assert_eq!(first.thread_ids, ["a"]);
    assert!(first.next_cursor.is_none());
    events.apply_thread_delta(vec![row("b", 1)], vec![]).await?;
    let boundary = list.next().await?.unwrap();
    assert_eq!(boundary.thread_ids, first.thread_ids);
    assert!(
        boundary.next_cursor.is_some(),
        "boundary-only changes must be delivered"
    );

    let search = ThreadsObservation::open(
        events.clone(),
        "epoch".into(),
        ThreadDirectoryQuery {
            search: Some("needle".into()),
            ..Default::default()
        },
        ThreadDirectoryWindow {
            before: None,
            limit: 2,
        },
    )?;
    let metadata = ThreadMetadataObservation::open(events.clone(), "epoch".into(), "a".into())?;
    metadata.next().await?;
    assert!(search.next().await?.unwrap().thread_ids.is_empty());
    events
        .apply_project_entry(crate::WorkspaceRecord {
            id: "directory-pull-fixture".into(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: "Needle".into(),
            path: "/workspace".into(),
            ssh_alias: None,
            updated_at: 3,
        })
        .await?;
    assert!(
        !metadata_has_pending(&metadata).await,
        "project search text is not row metadata"
    );
    assert_eq!(search.next().await?.unwrap().thread_ids, ["a", "b"]);
    let mut unchanged = Box::pin(list.next());
    assert!(
        futures::poll!(unchanged.as_mut()).is_pending(),
        "project rename must not resend an unchanged list"
    );
    drop(unchanged);

    events
        .commit_directory(DirectoryDelta {
            project_removals: vec![ProjectRemoval {
                workspace_id: "directory-pull-fixture".into(),
                session_ids: vec!["a".into(), "b".into()],
                closed_at: 4,
            }],
            ..Default::default()
        })
        .await?;
    assert!(metadata.next().await?.unwrap().row.unwrap().archived);
    assert!(search.next().await?.unwrap().thread_ids.is_empty());
    assert!(list.next().await?.unwrap().thread_ids.is_empty());
    metadata.close().await?;
    list.close().await?;
    search.close().await?;
    Ok(())
}

#[tokio::test]
async fn metadata_notifications_do_not_infer_thread_from_session_or_agent() -> Result<()> {
    let (_temp, events) = fixture().await?;
    let mut root = row("thread", 1);
    root.session_id = "session".into();
    root.agent_id = "agent".into();
    let mut child = row("child-thread", 1);
    child.session_id = root.session_id.clone();
    child.agent_id = "child-agent".into();
    child.parent_agent_id = Some(root.agent_id.clone());
    events
        .apply_thread_delta(vec![root.clone(), child], vec![])
        .await?;
    let observed =
        ThreadMetadataObservation::open(events.clone(), "epoch".into(), "child-thread".into())?;
    observed.next().await?;
    root.mode = pl_protocol::ThreadModeId::task();
    events.apply_thread_delta(vec![root], vec![]).await?;
    assert!(metadata_has_pending(&observed).await);
    assert_eq!(
        observed.next().await?.unwrap().row.unwrap().mode,
        pl_protocol::ThreadModeId::task()
    );
    // Removal references Thread IDs, not Agent IDs.
    events
        .apply_thread_delta(vec![], vec!["child-thread".into()])
        .await?;
    assert!(observed.next().await?.unwrap().row.is_none());
    observed.close().await?;
    Ok(())
}
