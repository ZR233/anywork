use crate::thread_assembler::test_support::*;
#[tokio::test]
async fn sealed_cleanup_cannot_consume_the_preserve_disposition() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let fixture = Fixture::new(store.clone())?;
    fixture.add("parent", None).await?;
    let child = fixture.add("child", Some("parent")).await?;
    crate::studio::agent_close::commit(&child).await?;
    fixture
        .owner
        .freeze_agent_close_disposition("child", WorkspaceRelease::Preserve)?;
    let targets = vec![(1, "child".to_owned())];
    let seal = fixture
        .owner
        .seal_agent_close(&targets, WorkspaceRelease::Preserve)
        .await?;
    assert!(
        fixture
            .owner
            .seal_agent_close(&targets, WorkspaceRelease::Cleanup)
            .await
            .is_err()
    );
    drop(seal);
    fixture.owner.close("child").await?;
    assert_eq!(
        *fixture.closes.lock().unwrap(),
        vec![("child".into(), WorkspaceRelease::Preserve)]
    );
    assert!(fixture.owner.close_session().await.is_empty());
    fixture.stop_writers().await?;
    Ok(())
}
