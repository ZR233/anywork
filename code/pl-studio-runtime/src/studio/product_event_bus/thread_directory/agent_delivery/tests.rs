use super::*;
use crate::studio::product_event_bus::thread_directory::tests::{agent_from_row, fixture, row};
use crate::studio::product_event_bus::topics::ProductPublication;

fn change(events: &ProductEventBus, token: &NativeAgentObservation, revision: u64) -> Result<()> {
    events
        .patch_thread_runtime(
            Some(token),
            ThreadStatus::Idle,
            1,
            &pl_core::thread::ThreadSnapshot {
                observation_revision: revision,
                ..Default::default()
            },
            Some(Some(revision.to_string())),
        )?
        .expect("live member");
    Ok(())
}

fn state(event: StudioProductEventEnvelope) -> StudioAgentDirectoryState {
    assert_eq!(event.event_id, format!("studio-product-{}", event.sequence));
    let StudioProductEventKind::AgentDirectoryChanged(state) = event.kind else {
        panic!("agent frame")
    };
    state
}

#[tokio::test]
async fn lagged_frames_release_versions_and_retained_frames_keep_their_exact_cuts() -> Result<()> {
    let (_temp, events) = fixture(vec![row("root", "p1", 1)], vec![]).await?;
    let token = events.begin_native_observation("root").unwrap();
    let initial = events.read_agent_directory().await.state.revision();
    let mut values = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    let capacity = super::super::super::topics::TOPIC_CHANNEL_CAPACITY;
    let total = capacity * 3;
    for revision in 1..=total {
        change(&events, &token, revision as u64)?;
    }
    assert_eq!(
        events.agent_history.versions.lock().unwrap().len(),
        capacity
    );
    assert_eq!(
        values.try_recv(),
        Err(crate::ProductTopicTryRecvError::Lagged(
            (total - capacity) as u64
        ))
    );
    for revision in total - capacity + 1..=total {
        let event = values.try_recv()?;
        assert_eq!(event.sequence, revision as u64);
        let frame = state(event);
        assert_eq!(frame.state.revision(), initial + revision as u64);
        assert_eq!(
            frame.state.value().unwrap().agents[0].summary,
            Some(revision.to_string())
        );
    }
    assert!(events.agent_history.versions.lock().unwrap().is_empty());
    drop(values);
    assert_eq!(events.topic_registration_counts(), (0, 0));
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn dequeued_frame_pins_its_cut_during_concurrent_unobserved_writes() -> Result<()> {
    let (_temp, events) = fixture(vec![row("root", "p1", 1)], vec![]).await?;
    let token = events.begin_native_observation("root").unwrap();
    let mut values = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    change(&events, &token, 1)?;
    let expected = events.read_agent_directory().await;
    let publication = values.try_recv_publication()?;
    drop(values);
    assert_eq!(events.agent_history.versions.lock().unwrap().len(), 1);
    let delivered = std::thread::scope(|scope| -> Result<_> {
        let (reached, ready) = std::sync::mpsc::sync_channel(0);
        let (release, released) = std::sync::mpsc::sync_channel(0);
        let worker_events = &events;
        let worker_token = &token;
        let writer = scope.spawn(move || -> Result<()> {
            for revision in 2..=1024 {
                change(worker_events, worker_token, revision)?;
                if revision == 512 {
                    reached.send(()).unwrap();
                    released.recv().unwrap();
                }
            }
            Ok(())
        });
        ready.recv()?;
        let ProductPublication::AgentDirectory { state: pinned, .. } = &publication else {
            panic!("deferred value")
        };
        assert_eq!(
            pinned.reverse.lock().unwrap().len(),
            1,
            "repeated changes coalesce by member, not revision"
        );
        release.send(())?;
        let delivered = state(publication.materialize());
        writer.join().unwrap()?;
        Ok(delivered)
    })?;
    assert_eq!(delivered, expected);
    assert_eq!(
        events
            .read_agent_directory()
            .await
            .state
            .value()
            .unwrap()
            .agents[0]
            .summary
            .as_deref(),
        Some("1024")
    );
    assert!(events.agent_history.versions.lock().unwrap().is_empty());
    events.writer.shutdown().await?;
    Ok(())
}

fn member_change(events: &ProductEventBus, member: &AgentDirectoryRecord, remove: bool) {
    let mut index = events.thread_index.lock().unwrap();
    let before = index.agent_directory_members([member.agent_id.clone()]);
    if remove {
        index.remove_agent(&member.agent_id);
    } else {
        index.insert_agent(member.clone()).unwrap();
    }
    events.publish_agent_directory_locked(&index, before);
}

#[tokio::test]
async fn member_churn_cancels_reverse_entries_and_deleted_backend_changes_still_reconstruct()
-> Result<()> {
    let (_temp, events) = fixture(vec![row("root", "p1", 1)], vec![]).await?;
    let token = events.begin_native_observation("root").unwrap();
    let mut values = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    change(&events, &token, 1)?;
    let expected = events.read_agent_directory().await;
    let publication = values.try_recv_publication()?;
    drop(values);
    let ProductPublication::AgentDirectory { state: pinned, .. } = &publication else {
        panic!("deferred value")
    };
    for n in 0..1024 {
        let mut member = agent_from_row(&row(&format!("new-{n}"), "p1", 1));
        member.session_id = "root".into();
        member.parent_agent_id = Some("root".into());
        member_change(&events, &member, false);
        assert_eq!(pinned.reverse.lock().unwrap().len(), 1);
        if n == 0 {
            assert_eq!(
                state(publication.clone().materialize()),
                expected,
                "a past frame must exclude a later member that still exists"
            );
        }
        member_change(&events, &member, true);
        assert!(
            pinned.reverse.lock().unwrap().is_empty(),
            "post-version create/delete must cancel"
        );
    }
    {
        let mut index = events.thread_index.lock().unwrap();
        let before = index.agent_directory_members(["root".into()]);
        let mut root = index.get_agent("root").unwrap().clone();
        root.backend = crate::AgentBackend::Acp {
            reference: crate::AcpSessionReference {
                account_id: "account".into(),
                acp_session_id: "external".into(),
                cwd: "/workspace".into(),
            },
        };
        index.insert_agent(root).unwrap();
        events.publish_agent_directory_locked(&index, before);
        drop(index);
        assert_eq!(
            state(publication.clone().materialize()),
            expected,
            "backend replacement must not change an earlier Native frame"
        );
        let mut index = events.thread_index.lock().unwrap();
        let before = index.agent_directory_members(["root".into()]);
        index.delete_thread("root");
        events.publish_agent_directory_locked(&index, before);
    }
    assert!(
        events
            .read_agent_directory()
            .await
            .state
            .value()
            .unwrap()
            .agents
            .is_empty()
    );
    assert_eq!(state(publication.materialize()), expected);
    assert!(events.agent_history.versions.lock().unwrap().is_empty());
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn last_unread_subscriber_drop_reclaims_all_reverse_material() -> Result<()> {
    let (_temp, events) = fixture(vec![row("root", "p1", 1)], vec![]).await?;
    let token = events.begin_native_observation("root").unwrap();
    let first = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    let second = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    for revision in 1..=8 {
        change(&events, &token, revision)?;
    }
    assert_eq!(events.agent_history.versions.lock().unwrap().len(), 8);
    drop(first);
    assert_eq!(events.agent_history.versions.lock().unwrap().len(), 8);
    drop(second);
    assert!(events.agent_history.versions.lock().unwrap().is_empty());
    assert_eq!(events.topic_registration_counts(), (0, 0));
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn pending_value_survives_bus_shutdown_without_retaining_the_bus_or_store() -> Result<()> {
    let (_temp, events) = fixture(vec![row("root", "p1", 1)], vec![]).await?;
    let token = events.begin_native_observation("root").unwrap();
    let mut values = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    change(&events, &token, 1)?;
    let expected = events.read_agent_directory().await;
    let index = Arc::downgrade(&events.thread_index);
    let history = Arc::downgrade(&events.agent_history);
    events.writer.shutdown().await?;
    drop(events);
    assert!(
        index.upgrade().is_some(),
        "the pending frame retains only its RAM facts"
    );
    assert_eq!(state(values.try_recv()?), expected);
    assert_eq!(
        values.try_recv(),
        Err(crate::ProductTopicTryRecvError::Closed)
    );
    assert!(index.upgrade().is_none());
    assert!(history.upgrade().is_none());
    Ok(())
}

#[tokio::test]
async fn dequeued_version_survives_lagged_overwrite_and_releases_separately_from_the_queue()
-> Result<()> {
    let (_temp, events) = fixture(vec![row("root", "p1", 1)], vec![]).await?;
    let token = events.begin_native_observation("root").unwrap();
    let mut values = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    change(&events, &token, 1)?;
    let expected = events.read_agent_directory().await;
    let pinned = values.try_recv_publication()?;
    let capacity = super::super::super::topics::TOPIC_CHANNEL_CAPACITY;
    let total = capacity * 3 + 1;
    for revision in 2..=total {
        change(&events, &token, revision as u64)?;
    }
    assert_eq!(
        events.agent_history.versions.lock().unwrap().len(),
        capacity + 1
    );
    assert_eq!(
        values.try_recv(),
        Err(crate::ProductTopicTryRecvError::Lagged(
            (total - 1 - capacity) as u64
        ))
    );
    assert_eq!(
        state(pinned.materialize()),
        expected,
        "ring overwrite must not revoke an already dequeued version"
    );
    assert_eq!(
        events.agent_history.versions.lock().unwrap().len(),
        capacity
    );
    drop(values);
    assert!(events.agent_history.versions.lock().unwrap().is_empty());
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn close_recovery_publishes_missing_members_without_replacing_current_common_metadata()
-> Result<()> {
    let (_temp, events) = fixture(vec![row("root", "p1", 1)], vec![]).await?;
    let mut child = agent_from_row(&row("child", "p1", 2));
    child.session_id = "root".into();
    child.parent_agent_id = Some("root".into());
    // Persistence may contain a member not yet in the published RAM slice.
    events
        .store
        .persist_directory_summaries(&DirectoryDelta {
            agent_upserts: vec![child],
            ..Default::default()
        })
        .await?;
    let mut values = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    {
        let mut index = events.thread_index.lock().unwrap();
        let before = index.agent_directory_members(["root".into()]);
        let mut session = index.get_session("root").unwrap().clone();
        session.title = "Published RAM title".into();
        index.insert_session(session);
        events.publish_agent_directory_locked(&index, before);
    }
    let expected = events.read_agent_directory().await;
    assert_ne!(
        events.store.catalog().get_session("root").unwrap().title,
        "Published RAM title"
    );
    events
        .store
        .save_agent_close(&crate::studio::store::agent_close::AgentCloseRecord {
            agent_id: "child".into(),
            parent_id: "root".into(),
            root_id: "root".into(),
            workspace_id: "p1".into(),
            revision: 1,
            force: false,
            worktree: None,
            git: None,
            execution_closed: false,
            worktree_cleanup: pl_tool::collaboration::control::AgentWorktreeCleanup::Pending,
            error: None,
        })
        .await?;
    events.commit_explicit_close("child").await?;
    events.commit_explicit_close("child").await?;
    assert_eq!(
        state(values.try_recv()?),
        expected,
        "restoring a child must not silently change an earlier root frame"
    );
    let restored = state(values.try_recv()?);
    assert_eq!(restored, events.read_agent_directory().await);
    assert_eq!(restored.state.revision(), expected.state.revision() + 1);
    let agents = &restored.state.value().unwrap().agents;
    assert_eq!(agents.len(), 2);
    assert!(
        agents
            .iter()
            .all(|entry| entry.task == "Published RAM title")
    );
    assert!(agents.iter().any(|entry| entry.agent_id == "child"));
    assert!(
        values.try_recv().is_err(),
        "membership restoration publishes once even when close status was already persisted"
    );
    events.writer.shutdown().await?;
    Ok(())
}
