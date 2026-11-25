use super::*;

pub(super) fn memory_index(rows: &[SessionDirectoryRow]) -> ThreadDirectoryIndex {
    ThreadDirectoryIndex::new(
        rows.iter()
            .filter(|row| row.is_root_row())
            .map(session_from_row)
            .collect(),
        rows.iter().map(agent_from_row).collect(),
        &[],
    )
}

#[test]
fn reverse_membership_tracks_replacement_migration_rejection_and_root_deletion() {
    let root = row("root", "p1", 10);
    let other = row("other", "p1", 20);
    let mut child = row("child-thread", "p1", 5);
    child.agent_id = "child-agent".into();
    child.session_id = root.session_id.clone();
    child.parent_agent_id = Some(root.agent_id.clone());
    let mut index = memory_index(&[root.clone(), other.clone(), child.clone()]);
    assert_eq!(
        index.directory_facts("child-thread").unwrap().0.session_id,
        "root"
    );
    assert_eq!(
        index.get_agent("child-agent").unwrap().thread_id,
        "child-thread"
    );

    let mut moved = agent_from_row(&child);
    moved.session_id = other.session_id.clone();
    moved.thread_id = "moved-thread".into();
    moved.parent_agent_id = Some(other.agent_id.clone());
    index.insert_agent(moved.clone()).unwrap();
    assert!(index.agent_by_thread("child-thread").is_none());
    assert!(index.sessions["root"].agents.get("child-agent").is_none());
    assert_eq!(
        index.directory_facts("moved-thread").unwrap().0.session_id,
        "other"
    );
    let mut invalid = moved.clone();
    invalid.session_id = "absent".into();
    invalid.explicitly_closed = true;
    assert!(index.insert_agent(invalid).is_none());
    assert_eq!(index.get_agent("child-agent"), Some(&moved));
    assert!(!index.explicitly_closed.contains("child-agent"));

    let mut replacement = moved;
    replacement.agent_id = "replacement-agent".into();
    index.insert_agent(replacement.clone()).unwrap();
    assert!(index.get_agent("child-agent").is_none());
    assert_eq!(index.agent_by_thread("moved-thread"), Some(&replacement));
    index.delete_thread("other");
    for id in ["other", "moved-thread"] {
        assert!(index.agent_by_thread(id).is_none());
        assert!(!index.thread_to_session.contains_key(id));
    }
    assert!(index.get_agent("replacement-agent").is_none());
    assert!(index.insert_agent(replacement).is_none());
    index.insert_session(session_from_row(&other));
    assert!(index.get_session("other").is_none());
    assert!(index.directory_facts("root").is_some());
    assert_eq!(index.agent_directory_entries().len(), 1);
}

#[test]
fn cold_archived_and_distinct_child_metadata_are_memory_facts() {
    let root = row("root", "p1", 3);
    let mut archived = row("archived", "p1", 2);
    archived.archived = true;
    let mut child = row("child", "p1", 1);
    child.session_id = root.session_id.clone();
    child.parent_agent_id = Some(root.agent_id.clone());
    child.mode = None;
    child.workspace_path = root.workspace_path.clone();
    child.last_user_message_at = None;
    let index = memory_index(&[root.clone(), archived.clone(), child.clone()]);
    for expected in [&root, &archived, &child] {
        let (session, agent) = index.directory_facts(&expected.thread_id).unwrap();
        assert_eq!(&row_projection(session, agent), expected);
    }
    assert!(index.directory_facts("missing").is_none());
    assert_eq!(
        index.query(&ThreadDirectoryQuery::default(), None, 10).0,
        vec![root]
    );
    assert_eq!(
        index
            .query(
                &ThreadDirectoryQuery {
                    archived: true,
                    ..Default::default()
                },
                None,
                10
            )
            .0,
        vec![archived]
    );
    assert_eq!(
        index
            .agent_directory_entries()
            .iter()
            .map(|entry| entry.agent_id.as_str())
            .collect::<Vec<_>>(),
        ["archived", "child", "root"]
    );
}

#[test]
fn fixed_pin_queries_and_seek_materialize_only_the_requested_window_at_scale() {
    let rows = (0..10_000)
        .map(|n| row(&format!("row-{n:05}"), "p1", n))
        .collect::<Vec<_>>();
    let mut index = memory_index(&rows);
    let ids = vec!["row-00001".into(), "row-00000".into()];
    let pinned = ThreadDirectoryQuery {
        thread_ids: Some(ids.clone()),
        ..Default::default()
    };
    let (pins, cursor, metrics) = index.query(&pinned, None, 64);
    assert_eq!(
        pins.iter()
            .map(|row| row.thread_id.as_str())
            .collect::<Vec<_>>(),
        ["row-00001", "row-00000"]
    );
    assert!(cursor.is_none());
    assert_eq!(
        metrics,
        DirectoryReadMetrics {
            scanned: 2,
            materialized: 2
        }
    );
    let ordinary = ThreadDirectoryQuery {
        excluded_thread_ids: ids,
        ..Default::default()
    };
    let (first, cursor, metrics) = index.query(&ordinary, None, 20);
    assert_eq!((metrics.scanned, metrics.materialized), (21, 21));
    assert_eq!(first.first().unwrap().thread_id, "row-09999");
    assert_eq!(first.last().unwrap().thread_id, "row-09980");
    let cursor = ThreadDirectoryCursor::decode(&cursor.unwrap()).unwrap();
    let (second, _, metrics) = index.query(&ordinary, Some(&cursor), 20);
    assert_eq!(second.first().unwrap().thread_id, "row-09979");
    assert_eq!((metrics.scanned, metrics.materialized), (21, 21));
    assert!(
        index
            .query(
                &ThreadDirectoryQuery {
                    thread_ids: Some(vec![]),
                    ..Default::default()
                },
                None,
                20
            )
            .0
            .is_empty()
    );

    let delta = DirectoryDelta {
        agent_upserts: vec![agent_from_row(&rows[0])],
        ..Default::default()
    };
    let before = index.agent_directory_members(index.delta_agent_ids(&delta));
    assert_eq!(
        before.len(),
        1,
        "a one-member delta must capture one projection at any directory size"
    );
    assert_eq!(before.keys().next().unwrap(), "row-00000");
    let changes = index.agent_directory_changes(before);
    assert_eq!(changes.compared, 1);
    assert!(changes.upserted.is_empty() && changes.removed.is_empty());
    let before = index.agent_directory_members(["row-00000".into()]);
    let mut agent = agent_from_row(&rows[0]);
    agent.role = "changed-role".into();
    index.insert_agent(agent).unwrap();
    let changes = index.agent_directory_changes(before);
    assert_eq!(changes.compared, 1);
    assert_eq!(changes.upserted.len(), 1);
    assert_eq!(changes.upserted[0].role, "changed-role");
    assert!(changes.removed.is_empty());
    let before = index.agent_directory_members(["row-00000".into()]);
    index.remove_agent("row-00000");
    let changes = index.agent_directory_changes(before);
    assert_eq!(changes.compared, 1);
    assert!(changes.upserted.is_empty());
    assert_eq!(changes.removed, ["row-00000"]);
}

#[test]
fn seek_uses_the_session_sort_key_when_thread_and_session_ids_differ() {
    let rows = [
        ("session-z", "thread-a"),
        ("session-m", "thread-b"),
        ("session-a", "thread-c"),
    ]
    .map(|(session, thread)| {
        let mut row = row(thread, "p1", 10);
        row.session_id = session.into();
        row
    });
    let index = memory_index(&rows);
    let (first, cursor, _) = index.query(&ThreadDirectoryQuery::default(), None, 1);
    assert_eq!(first[0].thread_id, "thread-a");
    let cursor = ThreadDirectoryCursor::decode(&cursor.unwrap()).unwrap();
    let (next, _, _) = index.query(&ThreadDirectoryQuery::default(), Some(&cursor), 2);
    assert_eq!(
        next.iter()
            .map(|row| row.thread_id.as_str())
            .collect::<Vec<_>>(),
        ["thread-b", "thread-c"]
    );
}

#[test]
fn repeated_cold_session_and_archive_keep_one_order_key_and_reverse_lookup() {
    let root = row("root", "p1", 10);
    let mut newer = session_from_row(&root);
    newer.last_user_message_at = Some(20);
    let mut index = ThreadDirectoryIndex::new(
        vec![session_from_row(&root), newer.clone()],
        vec![agent_from_row(&root)],
        &[],
    );
    assert_eq!(index.order.len(), 1);
    newer.archived = true;
    index.insert_session(newer);
    assert!(index.sorted_active_root_rows().is_empty());
    assert!(index.directory_facts("root").unwrap().0.archived);
    index.remove_agent("root");
    assert!(index.agent_by_thread("root").is_none());
    assert!(index.agent_to_session.is_empty());
    assert!(index.thread_to_session.is_empty());
}

#[test]
fn cold_orphan_members_never_enter_reverse_indexes_or_close_projection() {
    let mut orphan = agent_from_row(&row("orphan", "p1", 1));
    orphan.explicitly_closed = true;
    let index = ThreadDirectoryIndex::new(vec![], vec![orphan], &[]);
    assert!(index.agent_to_session.is_empty());
    assert!(index.thread_to_session.is_empty());
    assert!(index.explicitly_closed.is_empty());
    assert!(index.agent_directory_entries().is_empty());
}

#[test]
fn pin_filters_follow_current_metadata_outside_the_ordinary_window() {
    let rows = (0..30)
        .map(|n| row(&format!("row-{n:03}"), "p1", n))
        .collect::<Vec<_>>();
    let mut index = memory_index(&rows);
    let pinned = ThreadDirectoryQuery {
        thread_ids: Some(vec!["row-000".into(), "row-001".into()]),
        filter: crate::ThreadDirectoryFilter::Running,
        ..Default::default()
    };
    assert!(index.query(&pinned, None, 64).0.is_empty());
    let mut session = index.get_session("row-000").unwrap().clone();
    session.title = "Changed outside the ordinary window".into();
    index.insert_session(session);
    let mut agent = index.get_agent("row-000").unwrap().clone();
    agent.set_native_status(ThreadStatus::Running);
    index.insert_agent(agent).unwrap();
    let (pins, cursor, _) = index.query(&pinned, None, 64);
    assert_eq!(pins.len(), 1);
    assert_eq!(pins[0].thread_id, "row-000");
    assert_eq!(pins[0].title, "Changed outside the ordinary window");
    assert!(cursor.is_none());
    assert!(
        index
            .query(&ThreadDirectoryQuery::default(), None, 20)
            .0
            .iter()
            .all(|row| row.thread_id != "row-000")
    );
}

#[derive(Clone, Default)]
struct ComparisonWork(Arc<Mutex<Vec<u64>>>);

impl<S: tracing::Subscriber> tracing_subscriber::Layer<S> for ComparisonWork {
    fn on_event(
        &self,
        event: &tracing::Event<'_>,
        _context: tracing_subscriber::layer::Context<'_, S>,
    ) {
        struct Compared(Option<u64>);
        impl tracing::field::Visit for Compared {
            fn record_u64(&mut self, field: &tracing::field::Field, value: u64) {
                if field.name() == "compared" {
                    self.0 = Some(value);
                }
            }
            fn record_debug(&mut self, _: &tracing::field::Field, _: &dyn std::fmt::Debug) {}
        }
        let mut compared = Compared(None);
        event.record(&mut compared);
        if let Some(compared) = compared.0 {
            self.0.lock().unwrap().push(compared);
        }
    }
}

#[tokio::test]
async fn hot_runtime_patch_compares_one_member_at_scale_and_deduplicates_publication() -> Result<()>
{
    use tracing_subscriber::prelude::*;
    let (_temp, events) = fixture(vec![], vec![]).await?;
    let rows = (0..10_000)
        .map(|n| row(&format!("row-{n:05}"), "p1", n))
        .collect::<Vec<_>>();
    *events.thread_index.lock().unwrap() = memory_index(&rows);
    let mut changes = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    let work = ComparisonWork::default();
    let subscriber = tracing_subscriber::registry().with(work.clone());
    let snapshot = pl_core::thread::ThreadSnapshot {
        observation_revision: 5,
        execution: Some(pl_core::thread::ActiveExecution {
            id: "preparing-target".into(),
            phase: pl_core::thread::ExecutionPhase::Preparing,
            turn_id: None,
        }),
        ..Default::default()
    };
    tracing::subscriber::with_default(subscriber, || -> Result<()> {
        let observation = events.begin_native_observation("row-00000").unwrap();
        assert!(
            changes.try_recv().is_err(),
            "observer registration alone is not a projection change"
        );
        events.patch_thread_runtime(Some(&observation), ThreadStatus::Idle, 0, &snapshot, None)?;
        let StudioProductEventKind::AgentDirectoryChanged(published) = changes.try_recv()?.kind
        else {
            panic!("agent snapshot")
        };
        let agents = &published.state.value().unwrap().agents;
        assert_eq!(agents.len(), 10_000);
        assert_eq!(agents[0].agent_id, "row-00000");
        assert!(
            matches!(&agents[0].activity, StudioAgentActivity::Native { execution: Some(execution), .. } if execution.id() == "preparing-target")
        );
        assert!(matches!(
            &agents[1].activity,
            StudioAgentActivity::Native {
                execution: None,
                ..
            }
        ));
        let sequence = events.current_sequence();
        events.patch_thread_runtime(Some(&observation), ThreadStatus::Idle, 0, &snapshot, None)?;
        assert!(changes.try_recv().is_err());
        assert_eq!(events.current_sequence(), sequence);
        Ok(())
    })?;
    assert_eq!(
        *work.0.lock().unwrap(),
        [1, 1, 1],
        "registration, changed patch and duplicate patch must each compare only the target member"
    );
    events.writer.shutdown().await?;
    Ok(())
}
