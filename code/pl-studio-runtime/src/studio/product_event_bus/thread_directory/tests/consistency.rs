use super::*;

#[tokio::test]
async fn one_shot_page_returns_its_consistent_slice_without_waiting_for_quiet() -> Result<()> {
    let existing = row("existing", "p1", 10);
    let (_temp, events) = fixture(
        vec![existing],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    let read = events.read_threads_window_inner(
        &ThreadDirectoryQuery::default(),
        &ThreadDirectoryWindow {
            before: None,
            limit: 10,
        },
        "",
    )?;
    events.record_user_message("existing", 20);
    let captured = read.into_page()?;
    let current = events.read_thread_directory_page(None, 10).await?;
    assert!(current.state.revision() > captured.state.revision());
    assert_eq!(
        captured.state.value().unwrap().rows[0].last_user_message_at,
        Some(10)
    );
    assert_eq!(
        current.state.value().unwrap().rows[0].last_user_message_at,
        Some(20)
    );

    events.writer.shutdown().await?;
    Ok(())
}
