use super::*;
use crate::studio::store::agent_close::AgentCloseRecord;
use crate::{StudioAgentActivity, StudioProductTopic};
use pl_tool::collaboration::control::AgentWorktreeCleanup;

#[tokio::test]
async fn cold_scheduling_checks_identity_and_cannot_overwrite_a_live_observer() -> Result<()> {
    let root = row("root", "p1", 1);
    let (_temp, events) = fixture(vec![root.clone()], vec![]).await?;
    let before = events.read_agent_directory().await;
    let snapshot = pl_core::thread::ThreadSnapshot {
        continuation: Some(pl_core::thread::ContinuationPoint {
            id: "point-1".into(),
            source_turn_id: None,
            reason: None,
            created_at: 1,
        }),
        ..Default::default()
    };
    events.publish_cold_agent_scheduling(
        "other-session",
        &root.agent_id,
        &root.thread_id,
        &snapshot,
    )?;
    events.publish_cold_agent_scheduling(
        &root.session_id,
        "other-agent",
        &root.thread_id,
        &snapshot,
    )?;
    assert_eq!(events.read_agent_directory().await, before);
    events.publish_cold_agent_scheduling(
        &root.session_id,
        &root.agent_id,
        &root.thread_id,
        &snapshot,
    )?;
    let awaiting = events.read_agent_directory().await;
    assert!(matches!(
        entries(&awaiting)[0].activity,
        StudioAgentActivity::Native {
            awaiting_scheduling: true,
            execution: None,
            can_stop: false,
            ..
        }
    ));
    assert_eq!(awaiting.state.revision(), before.state.revision() + 1);
    events.publish_cold_agent_scheduling(
        &root.session_id,
        &root.agent_id,
        &root.thread_id,
        &snapshot,
    )?;
    assert_eq!(events.read_agent_directory().await, awaiting);
    events.begin_native_observation(&root.thread_id).unwrap();
    let live = events.read_agent_directory().await;
    events.publish_cold_agent_scheduling(
        &root.session_id,
        &root.agent_id,
        &root.thread_id,
        &snapshot,
    )?;
    assert_eq!(events.read_agent_directory().await, live);
    events.writer.shutdown().await?;
    Ok(())
}

fn acp(mut row: SessionDirectoryRow) -> SessionDirectoryRow {
    row.mode = None;
    row.backend = crate::AgentBackend::Acp {
        reference: crate::AcpSessionReference {
            account_id: "account".into(),
            acp_session_id: format!("external-{}", row.agent_id),
            cwd: "/workspace/project".into(),
        },
    };
    row
}

fn entries(state: &StudioAgentDirectoryState) -> &[StudioAgentDirectoryEntry] {
    &state
        .state
        .value()
        .expect("published agent directory")
        .agents
}

fn changed(
    rx: &mut crate::studio::product_event_bus::ProductTopicReceiver,
    state: &StudioAgentDirectoryState,
) {
    let StudioProductEventKind::AgentDirectoryChanged(event) =
        rx.try_recv().expect("agent event").kind
    else {
        panic!("agent topic must contain agent snapshots");
    };
    assert_eq!(
        &event, state,
        "the event and baseline must freeze the same set and revision"
    );
    assert!(
        rx.try_recv().is_err(),
        "one projection change publishes once"
    );
}

#[tokio::test]
async fn native_observation_replacement_preserves_only_same_member_summary() -> Result<()> {
    let root = row("root", "p1", 1);
    let (_temp, events) = fixture(vec![root.clone()], vec![]).await?;
    let mut changes = events.subscribe_topic(&StudioProductTopic::AgentDirectory);
    let old = events.begin_native_observation(&root.thread_id).unwrap();
    let mut old_snapshot = pl_core::thread::ThreadSnapshot {
        observation_revision: 10,
        execution: Some(pl_core::thread::ActiveExecution {
            id: "old-execution".into(),
            phase: pl_core::thread::ExecutionPhase::Preparing,
            turn_id: None,
        }),
        ..Default::default()
    };
    events.patch_thread_runtime(
        Some(&old),
        ThreadStatus::Idle,
        1,
        &old_snapshot,
        Some(Some("confirmed summary".into())),
    )?;
    let confirmed = events.read_agent_directory().await;
    assert_eq!(
        entries(&confirmed)[0].summary.as_deref(),
        Some("confirmed summary")
    );
    changed(&mut changes, &confirmed);

    let current = events.begin_native_observation(&root.thread_id).unwrap();
    let replaced = events.read_agent_directory().await;
    assert_ne!(old, current);
    assert_eq!(
        entries(&replaced)[0].summary.as_deref(),
        Some("confirmed summary"),
        "replacing an observer must retain the same member's confirmed summary"
    );
    assert!(
        matches!(
            entries(&replaced)[0].activity,
            StudioAgentActivity::Native {
                execution: None,
                can_stop: false,
                ..
            }
        ),
        "the prior execution must not become a new-generation fact"
    );
    assert_eq!(replaced.state.revision(), confirmed.state.revision() + 1);
    changed(&mut changes, &replaced);

    old_snapshot.observation_revision = u64::MAX;
    assert!(
        events
            .patch_thread_runtime(
                Some(&old),
                ThreadStatus::Running,
                99,
                &old_snapshot,
                Some(Some("late old summary".into())),
            )?
            .is_none(),
        "a larger revision cannot restore the revoked token"
    );
    assert_eq!(events.read_agent_directory().await, replaced);
    assert!(changes.try_recv().is_err());

    let early = pl_core::thread::ThreadSnapshot {
        observation_revision: 1,
        ..Default::default()
    };
    assert!(
        events
            .patch_thread_runtime(Some(&current), ThreadStatus::Idle, 1, &early, None)?
            .is_some()
    );
    assert_eq!(
        events.read_agent_directory().await,
        replaced,
        "an early publication has no new summary and must preserve the confirmed value"
    );
    assert!(changes.try_recv().is_err());
    events.patch_thread_runtime(Some(&current), ThreadStatus::Idle, 1, &early, Some(None))?;
    let cleared = events.read_agent_directory().await;
    assert_eq!(entries(&cleared)[0].summary, None);
    assert_eq!(cleared.state.revision(), replaced.state.revision() + 1);
    assert_eq!(
        entries(&cleared)[0].activity,
        entries(&replaced)[0].activity
    );
    changed(&mut changes, &cleared);
    events.patch_thread_runtime(
        Some(&current),
        ThreadStatus::Idle,
        1,
        &early,
        Some(Some("retained idle summary".into())),
    )?;
    let idle = events.read_agent_directory().await;
    changed(&mut changes, &idle);
    let next = events.begin_native_observation(&root.thread_id).unwrap();
    assert_ne!(current, next);
    assert_eq!(
        events.read_agent_directory().await,
        idle,
        "an observer-only change must not clear the idle summary or advance the directory revision"
    );
    assert!(changes.try_recv().is_err());
    events.writer.shutdown().await?;

    Ok(())
}

#[tokio::test]
async fn summary_is_invalidated_by_identity_backend_and_removal() -> Result<()> {
    let root = row("root", "p1", 1);
    let early = pl_core::thread::ThreadSnapshot {
        observation_revision: 1,
        ..Default::default()
    };
    for transition in ["identity", "backend", "removal"] {
        let (_temp, events) = fixture(vec![root.clone()], vec![]).await?;
        let old = events.begin_native_observation(&root.thread_id).unwrap();
        events.patch_thread_runtime(
            Some(&old),
            ThreadStatus::Idle,
            1,
            &early,
            Some(Some("previous member summary".into())),
        )?;
        assert_eq!(
            entries(&events.read_agent_directory().await)[0]
                .summary
                .as_deref(),
            Some("previous member summary"),
            "{transition} starts with a real summary"
        );
        let mut next = root.clone();
        match transition {
            "identity" => next.thread_id = "replacement-thread".into(),
            "backend" => {
                events
                    .apply_thread_delta(vec![acp(root.clone())], vec![])
                    .await?;
                let external = events.read_agent_directory().await;
                assert_eq!(entries(&external)[0].summary, None);
                assert!(events.begin_native_observation(&root.thread_id).is_none());
            }
            "removal" => {
                events
                    .apply_thread_delta(vec![], vec![root.thread_id.clone()])
                    .await?;
                assert!(entries(&events.read_agent_directory().await).is_empty());
            }
            _ => unreachable!(),
        }
        events
            .apply_thread_delta(vec![next.clone()], vec![])
            .await?;
        let current = events.begin_native_observation(&next.thread_id).unwrap();
        assert_ne!(old, current);
        let fresh = events.read_agent_directory().await;
        assert_eq!(
            entries(&fresh)[0].summary,
            None,
            "{transition} must not inherit a summary"
        );
        assert!(
            events
                .patch_thread_runtime(
                    Some(&old),
                    ThreadStatus::Running,
                    99,
                    &early,
                    Some(Some("late old summary".into()))
                )?
                .is_none()
        );
        assert_eq!(events.read_agent_directory().await, fresh);
        events.writer.shutdown().await?;
    }
    Ok(())
}

#[tokio::test]
async fn cold_roots_and_children_preserve_backend_and_distinct_identities() -> Result<()> {
    let mut native = row("native-thread", "p1", 1);
    native.session_id = "native-session".into();
    native.agent_id = "native-agent".into();
    let mut external = acp(row("acp-thread", "p1", 2));
    external.session_id = "acp-session".into();
    external.agent_id = "acp-agent".into();
    let mut acp_child = acp(row("acp-child-thread", "p1", 3));
    acp_child.session_id = native.session_id.clone();
    acp_child.agent_id = "acp-child-agent".into();
    acp_child.parent_agent_id = Some(native.agent_id.clone());
    let mut native_child = row("native-child-thread", "p1", 4);
    native_child.session_id = external.session_id.clone();
    native_child.agent_id = "native-child-agent".into();
    native_child.parent_agent_id = Some(external.agent_id.clone());
    let rows = vec![native, external, acp_child, native_child];
    let (_temp, events) = fixture(rows.clone(), vec![]).await?;
    let baseline = events.read_agent_directory().await;
    assert_eq!(entries(&baseline).len(), rows.len());
    for expected in rows {
        let actual = entries(&baseline)
            .iter()
            .find(|agent| agent.agent_id == expected.agent_id)
            .unwrap();
        assert_eq!(actual.session_id, expected.session_id);
        assert_eq!(actual.thread_id, expected.thread_id);
        assert_eq!(actual.parent_agent_id, expected.parent_agent_id);
        assert_ne!(actual.agent_id, actual.session_id);
        assert_ne!(actual.agent_id, actual.thread_id);
        assert_ne!(actual.session_id, actual.thread_id);
        let json = serde_json::to_value(actual)?;
        match expected.backend {
            crate::AgentBackend::Native { .. } => {
                assert!(matches!(
                    actual.activity,
                    StudioAgentActivity::Native {
                        state: crate::AgentState::Idle(_),
                        execution: None,
                        can_stop: false,
                        awaiting_scheduling: false,
                    }
                ));
                assert_eq!(json["activity"]["kind"], "native");
            }
            crate::AgentBackend::Acp { .. } => {
                assert_eq!(
                    actual.activity,
                    StudioAgentActivity::Acp {
                        explicitly_closed: false
                    }
                );
                assert_eq!(
                    json["activity"],
                    serde_json::json!({"kind":"acp", "explicitlyClosed":false})
                );
                assert!(events.begin_native_observation(&actual.thread_id).is_none());
            }
        }
        assert!(json.get("state").is_none());
        assert!(json.get("execution").is_none());
        assert_eq!(
            serde_json::from_value::<StudioAgentDirectoryEntry>(json)?,
            *actual
        );
    }
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn acp_only_directory_add_close_ack_and_delete_publish_actual_changes() -> Result<()> {
    let root = acp(row("root", "p1", 1));
    let (_temp, events) = fixture(vec![root.clone()], vec![]).await?;
    let mut changes = events.subscribe_topic(&StudioProductTopic::AgentDirectory);
    let before = events.read_agent_directory().await;
    let mut child = acp(row("child-thread", "p1", 2));
    child.session_id = root.session_id.clone();
    child.agent_id = "child-agent".into();
    child.parent_agent_id = Some(root.agent_id.clone());
    events
        .commit_directory(DirectoryDelta {
            agent_upserts: vec![agent_from_row(&child)],
            ..Default::default()
        })
        .await?;
    let added = events.read_agent_directory().await;
    assert_eq!(added.state.revision(), before.state.revision() + 1);
    assert_eq!(entries(&added).len(), 2);
    changed(&mut changes, &added);
    events
        .commit_directory(DirectoryDelta {
            agent_upserts: vec![agent_from_row(&child)],
            ..Default::default()
        })
        .await?;
    assert_eq!(events.read_agent_directory().await, added);
    assert!(changes.try_recv().is_err());
    let mut close = AgentCloseRecord {
        agent_id: child.thread_id.clone(),
        parent_id: root.thread_id.clone(),
        root_id: root.session_id.clone(),
        workspace_id: "p1".into(),
        revision: 1,
        force: false,
        worktree: None,
        git: None,
        execution_closed: false,
        worktree_cleanup: AgentWorktreeCleanup::Pending,
        error: None,
    };
    events.store.save_agent_close(&close).await?;
    events.commit_explicit_close(&child.thread_id).await?;
    let intent = events.read_agent_directory().await;
    assert_eq!(intent.state.revision(), added.state.revision() + 1);
    assert_eq!(
        entries(&intent)
            .iter()
            .find(|entry| entry.agent_id == child.agent_id)
            .unwrap()
            .activity,
        StudioAgentActivity::Acp {
            explicitly_closed: true
        }
    );
    changed(&mut changes, &intent);
    // Completion ACK is a different close-owner fact; it does not change ACP directory intent.
    close.execution_closed = true;
    close.changed()?;
    events.store.save_agent_close(&close).await?;
    events.commit_explicit_close(&child.thread_id).await?;
    assert_eq!(events.read_agent_directory().await, intent);
    assert!(changes.try_recv().is_err());
    events.writer.flush().await?;
    events
        .commit_directory(DirectoryDelta::delete_threads(vec![
            child.thread_id.clone(),
        ]))
        .await?;
    let removed = events.read_agent_directory().await;
    assert_eq!(removed.state.revision(), intent.state.revision() + 1);
    assert_eq!(entries(&removed).len(), 1);
    changed(&mut changes, &removed);
    events.writer.flush().await?;
    events
        .commit_directory(DirectoryDelta::delete_threads(vec![root.thread_id]))
        .await?;
    let empty = events.read_agent_directory().await;
    assert_eq!(empty.state.revision(), removed.state.revision() + 1);
    assert!(entries(&empty).is_empty());
    changed(&mut changes, &empty);
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn native_hot_facts_keep_current_metadata_and_deduplicate_identical_projection() -> Result<()>
{
    let root = row("root", "p1", 1);
    let (_temp, events) = fixture(vec![root.clone()], vec![]).await?;
    let mut changes = events.subscribe_topic(&StudioProductTopic::AgentDirectory);
    let initial = events.read_agent_directory().await;
    let observation = events.begin_native_observation(&root.thread_id).unwrap();
    let snapshot = running_snapshot();
    events.patch_thread_runtime(
        Some(&observation),
        ThreadStatus::Idle,
        10,
        &snapshot,
        Some(Some("summary".into())),
    )?;
    let active = events.read_agent_directory().await;
    assert_eq!(active.state.revision(), initial.state.revision() + 1);
    assert!(
        matches!(&entries(&active)[0].activity, StudioAgentActivity::Native { state: crate::AgentState::Running(_), execution: Some(execution), can_stop: true, .. }
        if execution.id() == "execution:1" && execution.phase() == crate::AgentExecutionPhase::Running)
    );
    changed(&mut changes, &active);
    let (session, mut agent) = events.directory_facts(&root.thread_id).unwrap();
    let mut renamed = session.clone();
    renamed.title = "Renamed by current directory".into();
    renamed.delegation_preference = crate::DelegationPreference::Fast;
    agent.role = "renamed-profile".into();
    let route = crate::NewThreadModelRoute {
        account_id: "new-account".into(),
        model_id: "new-model".into(),
        effort: None,
    };
    let crate::AgentBackend::Native { config, .. } = &mut agent.backend else {
        unreachable!()
    };
    config.route = Some(route.clone());
    events
        .commit_directory(DirectoryDelta {
            session_upserts: vec![renamed],
            agent_upserts: vec![agent],
            ..Default::default()
        })
        .await?;
    let renamed = events.read_agent_directory().await;
    assert_eq!(entries(&renamed)[0].task, "Renamed by current directory");
    assert_eq!(entries(&renamed)[0].role, "renamed-profile");
    assert_eq!(entries(&renamed)[0].frozen_model, Some(route));
    assert_eq!(
        entries(&renamed)[0].delegation_preference,
        crate::DelegationPreference::Fast
    );
    assert_eq!(entries(&renamed)[0].activity, entries(&active)[0].activity);
    changed(&mut changes, &renamed);
    events.patch_thread_runtime(
        Some(&observation),
        ThreadStatus::Idle,
        10,
        &snapshot,
        Some(Some("summary".into())),
    )?;
    events.patch_thread_runtime(Some(&observation), ThreadStatus::Idle, 10, &snapshot, None)?;
    assert_eq!(events.read_agent_directory().await, renamed);
    assert!(changes.try_recv().is_err());
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn newer_runtime_cut_and_observer_generation_reject_stale_facts() -> Result<()> {
    let root = row("root", "p1", 1);
    let (_temp, events) = fixture(vec![root.clone()], vec![]).await?;
    let mut changes = events.subscribe_topic(&StudioProductTopic::AgentDirectory);
    let observation = events.begin_native_observation(&root.thread_id).unwrap();
    let mut snapshot = running_snapshot();
    events.patch_thread_runtime(
        Some(&observation),
        ThreadStatus::Idle,
        10,
        &snapshot,
        Some(Some("summary".into())),
    )?;
    let renamed = events.read_agent_directory().await;
    changed(&mut changes, &renamed);
    let old = snapshot.clone();
    snapshot.observation_revision += 1;
    snapshot.execution = None;
    events.patch_thread_runtime(
        Some(&observation),
        ThreadStatus::Idle,
        10,
        &snapshot,
        Some(None),
    )?;
    let retired = events.read_agent_directory().await;
    assert_eq!(entries(&retired)[0].summary, None);
    assert_eq!(retired.state.revision(), renamed.state.revision() + 1);
    assert!(matches!(
        entries(&retired)[0].activity,
        StudioAgentActivity::Native {
            execution: None,
            can_stop: false,
            ..
        }
    ));
    changed(&mut changes, &retired);
    assert!(
        events
            .patch_thread_runtime(Some(&observation), ThreadStatus::Idle, 10, &old, None)?
            .is_none()
    );
    assert_eq!(events.read_agent_directory().await, retired);
    assert!(events.native_observation_covers(Some(&observation), &old));
    let current = events.begin_native_observation(&root.thread_id).unwrap();
    let new_generation = events.read_agent_directory().await;
    changed(&mut changes, &new_generation);
    assert!(!events.native_observation_covers(Some(&observation), &old));
    assert!(
        events
            .patch_thread_runtime(Some(&observation), ThreadStatus::Running, 99, &old, None)?
            .is_none()
    );
    let mut wrong_identity = current.clone();
    wrong_identity.session_id = "another-session".into();
    assert!(
        events
            .patch_thread_runtime(Some(&wrong_identity), ThreadStatus::Running, 99, &old, None)?
            .is_none()
    );
    assert_eq!(events.read_agent_directory().await, new_generation);
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn backend_replacement_and_deletion_revoke_native_coverage() -> Result<()> {
    let root = row("root", "p1", 1);
    let (_temp, events) = fixture(vec![root.clone()], vec![]).await?;
    let mut changes = events.subscribe_topic(&StudioProductTopic::AgentDirectory);
    let current = events.begin_native_observation(&root.thread_id).unwrap();
    let old = running_snapshot();
    events.patch_thread_runtime(Some(&current), ThreadStatus::Running, 10, &old, None)?;
    let active = events.read_agent_directory().await;
    changed(&mut changes, &active);
    events
        .apply_thread_delta(vec![acp(root.clone())], vec![])
        .await?;
    let external = events.read_agent_directory().await;
    assert_eq!(
        entries(&external)[0].activity,
        StudioAgentActivity::Acp {
            explicitly_closed: false
        }
    );
    changed(&mut changes, &external);
    assert!(
        events
            .patch_thread_runtime(Some(&current), ThreadStatus::Running, 99, &old, None)?
            .is_none()
    );
    assert_eq!(events.read_agent_directory().await, external);
    assert!(!events.native_observation_covers(Some(&current), &old));
    events
        .apply_thread_delta(vec![root.clone()], vec![])
        .await?;
    let native_again = events.read_agent_directory().await;
    changed(&mut changes, &native_again);
    assert!(
        events
            .patch_thread_runtime(Some(&current), ThreadStatus::Running, 99, &old, None)?
            .is_none()
    );
    let current = events.begin_native_observation(&root.thread_id).unwrap();
    events.writer.flush().await?;
    events
        .commit_directory(DirectoryDelta::delete_threads(vec![root.thread_id.clone()]))
        .await?;
    let deleted = events.read_agent_directory().await;
    assert!(entries(&deleted).is_empty());
    assert!(!events.native_observation_covers(Some(&current), &old));
    changed(&mut changes, &deleted);
    assert!(
        events
            .patch_thread_runtime(Some(&current), ThreadStatus::Running, 99, &old, None)?
            .is_none()
    );
    events.publish_thread_delta(vec![root], vec![], vec![]);
    assert_eq!(events.read_agent_directory().await, deleted);
    assert!(changes.try_recv().is_err());
    events.writer.shutdown().await?;
    Ok(())
}

#[test]
fn agent_collection_revision_and_dispatch_share_one_publication_lock() -> Result<()> {
    let runtime = tokio::runtime::Runtime::new()?;
    let (_temp, events) = runtime.block_on(fixture(vec![row("root", "p1", 1)], vec![]))?;
    let observation = events.begin_native_observation("root").unwrap();
    let before = runtime.block_on(events.read_agent_directory());
    let mut internal = events.subscribe_internal();
    let topics = events.topics.lock().unwrap();
    let published = std::thread::scope(|scope| -> Result<_> {
        let events = &events;
        let writer = scope.spawn(move || {
            events.patch_thread_runtime(
                Some(&observation),
                ThreadStatus::Idle,
                1,
                &pl_core::thread::ThreadSnapshot {
                    observation_revision: 1,
                    execution: Some(pl_core::thread::ActiveExecution {
                        id: "execution:1".into(),
                        phase: pl_core::thread::ExecutionPhase::Preparing,
                        turn_id: None,
                    }),
                    ..Default::default()
                },
                None,
            )
        });
        let publication = runtime.block_on(internal.recv_publication())?;
        assert!(
            events.thread_index.try_lock().is_err(),
            "baseline cannot read a new revision with an older collection while dispatch is paused"
        );
        drop(topics);
        writer.join().unwrap()?;
        let StudioProductEventKind::AgentDirectoryChanged(state) = publication.materialize().kind
        else {
            panic!("execution-only agent event");
        };
        assert_eq!(state.state.revision(), before.state.revision() + 1);
        Ok(state)
    })?;
    assert_eq!(runtime.block_on(events.read_agent_directory()), published);
    runtime.block_on(events.writer.shutdown())?;
    Ok(())
}

fn running_snapshot() -> pl_core::thread::ThreadSnapshot {
    pl_core::thread::ThreadSnapshot {
        observation_revision: 5,
        execution: Some(pl_core::thread::ActiveExecution {
            id: "execution:1".into(),
            phase: pl_core::thread::ExecutionPhase::Running,
            turn_id: Some("turn-1".into()),
        }),
        turns: vec![pl_core::thread::TurnRecord {
            input_id: None,
            turn_id: "turn-1".into(),
            state: pl_core::thread::TurnState::Running,
            model_steps: 0,
            elapsed_ms: None,
        }]
        .into(),
        ..Default::default()
    }
}
