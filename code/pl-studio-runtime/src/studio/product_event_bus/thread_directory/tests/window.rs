use super::*;

use crate::{StudioError, StudioErrorCode, ThreadDirectoryFilter};

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
    set_status(&mut changed, crate::ThreadStatus::Running);
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
    assert!(
        events
            .apply_project_delta(&[workspace(&renamed_project)], &[])
            .await?
            .is_none()
    );
    assert_eq!(
        query(&events, &project_query, None, 10)?.stamp,
        project_result.stamp
    );
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

/// Old Drop sits between receiver release and registry cleanup. A later generation of the
/// same thread must survive that Drop even when its own receiver count is already zero.
#[tokio::test]
async fn delayed_metadata_drop_cannot_reclaim_a_new_generation_in_aba_order() -> Result<()> {
    let (_temp, events) = fixture(vec![], vec![]).await?;
    let mut old = events.subscribe_thread_metadata("thread-a");
    let old_generation = old.registration.generation();
    drop(old.receiver.take());
    events.notify_thread_metadata_for_test("thread-a");
    assert_eq!(events.metadata_signal_count(), 0);
    let unrelated = events.subscribe_thread_metadata("thread-b");
    let mut replacement = events.subscribe_thread_metadata("thread-a");
    assert!(unrelated.registration.generation() > old_generation);
    assert!(replacement.registration.generation() > unrelated.registration.generation());
    events.notify_thread_metadata_for_test("thread-a");
    assert!(
        replacement
            .receiver
            .as_mut()
            .expect("replacement receiver")
            .has_changed()
            .expect("replacement sender")
    );
    // The new receiver can itself be dropping. Count == 0 alone must not let the old Drop
    // remove its entry: only the matching generation owns that cleanup.
    drop(replacement.receiver.take());
    drop(old);
    assert_eq!(events.metadata_signal_count(), 2);
    drop(replacement);
    drop(unrelated);
    assert_eq!(events.metadata_signal_count(), 0);
    events.writer.shutdown().await?;
    Ok(())
}
