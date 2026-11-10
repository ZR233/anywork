use super::*;

#[tokio::test]
async fn fixed_pin_group_keeps_old_members_outside_the_ordinary_window() -> Result<()> {
    let rows = (0..30)
        .map(|n| row(&format!("row-{n:03}"), "p1", n))
        .collect();
    let (_temp, events) =
        fixture(rows, vec![project("p1", "Project", "/workspace/project")]).await?;
    let ids = vec!["row-001".into(), "row-000".into()];
    let pinned = ThreadDirectoryQuery {
        workspace_id: Some("p1".into()),
        thread_ids: Some(ids.clone()),
        ..Default::default()
    };
    let ordinary = ThreadDirectoryQuery {
        workspace_id: Some("p1".into()),
        excluded_thread_ids: ids,
        ..Default::default()
    };
    let pins = query(&events, &pinned, None, 64)?;
    assert_eq!(
        pins.rows
            .iter()
            .map(|row| row.thread_id.as_str())
            .collect::<Vec<_>>(),
        ["row-001", "row-000"]
    );
    assert!(pins.next_cursor.is_none());
    let first = query(&events, &ordinary, None, 20)?;
    assert_eq!(first.rows.len(), 20);
    assert_eq!(first.rows.last().unwrap().thread_id, "row-010");
    let next = query(&events, &ordinary, first.next_cursor.clone(), 20)?;
    assert_eq!(next.rows.len(), 8);
    assert_eq!(next.rows.last().unwrap().thread_id, "row-002");
    assert!(next.next_cursor.is_none());
    assert!(
        query(
            &events,
            &ThreadDirectoryQuery {
                thread_ids: Some(vec![]),
                ..Default::default()
            },
            None,
            20
        )?
        .rows
        .is_empty()
    );

    let running_pins = ThreadDirectoryQuery {
        filter: pl_protocol::studio::ThreadDirectoryFilter::Running,
        ..pinned
    };
    assert!(query(&events, &running_pins, None, 64)?.rows.is_empty());
    let mut updated = {
        let (session, agent) = events.directory_facts("row-000").unwrap();
        row_projection(&session, &agent)
    };
    updated.title = "Changed outside the ordinary window".into();
    updated.status = pl_protocol::ThreadStatus::Running;
    events.apply_thread_delta(vec![updated], vec![]).await?;
    let changed = query(&events, &running_pins, None, 64)?;
    assert_eq!(changed.rows.len(), 1);
    assert_eq!(changed.rows[0].thread_id, "row-000");
    assert_eq!(changed.rows[0].title, "Changed outside the ordinary window");
    assert!(changed.stamp.revision > pins.stamp.revision);
    events.writer.shutdown().await?;
    Ok(())
}
use pl_protocol::studio::{StudioError, StudioErrorCode, ThreadDirectoryFilter};

#[tokio::test]
async fn startup_index_owns_cold_archived_and_child_metadata() -> Result<()> {
    let root = row("root", "p1", 3);
    let mut archived = row("archived", "p1", 2);
    archived.archived = true;
    let mut child = row("child", "p1", 1);
    child.session_id = root.session_id.clone();
    child.parent_agent_id = Some(root.agent_id.clone());
    // 会话级事实（工作区路径、最近用户消息时间）只随主成员行携带。
    child.workspace_path = root.workspace_path.clone();
    child.last_user_message_at = None;
    let (_temp, events) = fixture(
        vec![root.clone(), archived.clone(), child.clone()],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;

    for expected in [&root, &archived, &child] {
        let frame = events.read_thread_metadata(&expected.thread_id, "owner-a")?;
        assert_eq!(frame.stamp.resource_key, THREAD_DIRECTORY_RESOURCE_KEY);
        assert_eq!(frame.stamp.owner_epoch, "owner-a");
        assert_eq!(frame.row.as_ref(), Some(expected));
    }
    assert!(
        events
            .read_thread_metadata("missing", "owner-a")?
            .row
            .is_none()
    );
    assert_eq!(
        query(&events, &ThreadDirectoryQuery::default(), None, 10)?.rows,
        vec![root]
    );
    let archived_query = ThreadDirectoryQuery {
        archived: true,
        ..Default::default()
    };
    assert_eq!(
        query(&events, &archived_query, None, 10)?.rows,
        vec![archived]
    );
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn limit_and_seek_return_complete_windows_with_bounded_materialization() -> Result<()> {
    let rows = (1..=6)
        .map(|value| row(&format!("t{value}"), "p1", value))
        .collect::<Vec<_>>();
    let (_temp, events) =
        fixture(rows, vec![project("p1", "Project", "/workspace/project")]).await?;
    let window = ThreadDirectoryWindow {
        before: None,
        limit: 2,
    };
    let first =
        events.read_threads_window_inner(&ThreadDirectoryQuery::default(), &window, "owner-a")?;
    assert_eq!(
        first
            .rows
            .iter()
            .map(|row| row.thread_id.as_str())
            .collect::<Vec<_>>(),
        vec!["t6", "t5"]
    );
    assert_eq!(first.metrics.scanned, 3);
    assert_eq!(first.metrics.materialized, 3);
    let second = query(
        &events,
        &ThreadDirectoryQuery::default(),
        first.next_cursor,
        2,
    )?;
    assert_eq!(
        second
            .rows
            .iter()
            .map(|row| row.thread_id.as_str())
            .collect::<Vec<_>>(),
        vec!["t4", "t3"]
    );
    assert!(second.next_cursor.is_some());
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn off_window_metadata_and_project_changes_recompute_membership_order_and_stamp() -> Result<()>
{
    let p1 = project("p1", "Alpha", "/workspace/alpha");
    let p2 = project("p2", "Beta", "/workspace/beta");
    let a = row("a", "p1", 30);
    let b = row("b", "p1", 20);
    let c = row("c", "p1", 10);
    let (_temp, events) =
        fixture(vec![a.clone(), b.clone(), c.clone()], vec![p1, p2.clone()]).await?;
    let initial = query(&events, &ThreadDirectoryQuery::default(), None, 1)?;
    assert_eq!(initial.rows, vec![a]);

    let mut changed = c;
    changed.title = "Needle renamed".into();
    changed.status = pl_protocol::ThreadStatus::Running;
    changed.workspace_id = "p2".into();
    changed.last_user_message_at = Some(40);
    changed.updated_at = 40;
    events
        .apply_thread_delta(vec![changed.clone()], Vec::new())
        .await?;
    let filtered = ThreadDirectoryQuery {
        workspace_id: Some("p2".into()),
        search: Some("needle".into()),
        filter: ThreadDirectoryFilter::Running,
        ..Default::default()
    };
    let after = query(&events, &filtered, None, 1)?;
    assert_eq!(after.rows, vec![changed.clone()]);
    assert!(after.stamp.revision > initial.stamp.revision);

    events
        .commit_directory(DirectoryDelta::archive_sessions(vec![
            changed.session_id.clone(),
        ]))
        .await?;
    assert!(query(&events, &filtered, None, 1)?.rows.is_empty());
    let archived = ThreadDirectoryQuery {
        archived: true,
        workspace_id: Some("p2".into()),
        search: Some("needle".into()),
        filter: ThreadDirectoryFilter::Running,
        ..Default::default()
    };
    assert_eq!(query(&events, &archived, None, 1)?.rows[0].thread_id, "c");

    let mut renamed_project = p2;
    renamed_project.name = "Find Me Project".into();
    renamed_project.path = "/workspace/find-me".into();
    renamed_project.updated_at = 2;
    let before_project = query(&events, &ThreadDirectoryQuery::default(), None, 1)?.stamp;
    events
        .apply_project_delta(&[workspace(&renamed_project)], &[])
        .await?;
    let project_query = ThreadDirectoryQuery {
        search: Some("find me".into()),
        archived: true,
        ..Default::default()
    };
    let project_result = query(&events, &project_query, None, 10)?;
    assert_eq!(project_result.rows[0].thread_id, "c");
    assert!(project_result.stamp.revision > before_project.revision);
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn invalid_window_cursor_and_oversized_frame_are_typed_failures() -> Result<()> {
    let mut oversized = row("large", "p1", 1);
    oversized.title = "x".repeat(ThreadDirectoryWindow::MAX_FRAME_BYTES);
    let (_temp, events) = fixture(
        vec![oversized],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    // Titles are not part of the structural delivery budget.
    let structure = events.read_threads_window(
        &ThreadDirectoryQuery::default(),
        &ThreadDirectoryWindow {
            before: None,
            limit: 1,
        },
        "owner-test",
    )?;
    assert_eq!(structure.thread_ids, ["large"]);
    let error = events
        .query_threads(&ThreadDirectoryQuery::default(), None, 1)
        .await
        .expect_err("oversized one-shot row page must fail");
    assert_eq!(
        error.downcast_ref::<StudioError>().unwrap().code,
        StudioErrorCode::Overloaded
    );
    let error = events
        .read_thread_metadata("large", "owner-test")
        .expect_err("oversized metadata frame must fail");
    assert_eq!(
        error.downcast_ref::<StudioError>().unwrap().code,
        StudioErrorCode::Overloaded
    );
    let error = query(
        &events,
        &ThreadDirectoryQuery::default(),
        Some("not-a-cursor".into()),
        1,
    )
    .expect_err("invalid cursor must fail");
    assert_eq!(
        error.downcast_ref::<StudioError>().unwrap().code,
        StudioErrorCode::InvalidArgument
    );
    events.writer.shutdown().await?;
    Ok(())
}
