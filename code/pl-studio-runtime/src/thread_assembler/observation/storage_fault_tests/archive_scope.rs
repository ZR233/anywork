//! The new archive scope still consumes the real core/writer/projection close barriers.
use super::*;

#[tokio::test]
async fn archive_scope_keeps_the_published_owner_until_writer_and_observation_ack() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let fixture = Fixture::new(store.clone())?;
    fixture.add("parent", None).await?;
    fixture.add("child", Some("parent")).await?;
    let scope = fixture.owner.seal_archive_scope(&["parent".into()])?;
    fixture.owner.drain_archive_preparations(&scope).await?;
    assert!(
        fixture.owner.observed_thread("child").is_some(),
        "draining preparation is not a published-resource close ACK"
    );
    fixture
        .fail_drain_after_writer
        .store(true, Ordering::SeqCst);
    assert!(fixture.owner.close_tree("parent").await.is_err());
    assert!(fixture.owner.observed_thread("parent").is_some());
    assert!(
        fixture
            .closes
            .lock()
            .unwrap()
            .iter()
            .all(|release| *release == WorkspaceRelease::Preserve)
    );
    let checkpoint = store
        .history("parent")
        .await?
        .checkpoint()
        .await?
        .context("durable closed checkpoint")?;
    assert_eq!(checkpoint.state.lifecycle, ThreadLifecycle::Closed);
    fixture
        .fail_drain_after_writer
        .store(false, Ordering::SeqCst);
    fixture.owner.close_tree("parent").await?;
    assert!(fixture.owner.observed_thread("parent").is_none());
    assert!(fixture.owner.observed_thread("child").is_none());
    fixture.stop_writers().await?;
    Ok(())
}
