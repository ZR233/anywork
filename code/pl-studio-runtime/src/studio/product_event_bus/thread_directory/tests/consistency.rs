use super::*;
use futures::poll;

#[tokio::test]
async fn one_shot_page_returns_its_consistent_slice_without_waiting_for_quiet() -> Result<()> {
    let row = thread("existing", "p1", 10);
    let (_temp, events) = fixture(
        vec![row],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    let (captured, release) = install_pause(&events.directory_test_pauses.page_captured);
    let page = events.read_thread_directory_page(None, 10);
    tokio::pin!(page);
    assert!(poll!(page.as_mut()).is_pending());
    captured.await?;

    events.record_user_message("existing", 20);
    release.send(()).unwrap();
    let captured = page.await?;
    let current = events.read_thread_directory_page(None, 10).await?;
    assert!(current.state.revision() > captured.state.revision());
    assert_eq!(
        captured.state.value().unwrap().threads[0].last_user_message_at,
        Some(10)
    );
    assert_eq!(
        current.state.value().unwrap().threads[0].last_user_message_at,
        Some(20)
    );

    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn legacy_page_matches_the_owner_snapshot_without_concurrency() -> Result<()> {
    let rows = vec![thread("newer", "p1", 20), thread("older", "p1", 10)];
    let (_temp, events) =
        fixture(rows, vec![project("p1", "Project", "/workspace/project")]).await?;

    let owner = events.read_thread_directory().await?;
    let page = events.read_thread_directory_page(None, 10).await?;
    assert_eq!(page.state.revision(), owner.state.revision());
    assert_eq!(page.state.updated_at(), owner.state.updated_at());
    assert_eq!(
        page.state.value().unwrap().threads,
        owner.state.value().unwrap().threads
    );

    events.writer.shutdown().await?;
    Ok(())
}
