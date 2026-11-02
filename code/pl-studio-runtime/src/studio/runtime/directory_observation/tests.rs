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

fn thread(id: &str, time: i64) -> pl_protocol::Thread {
    let mut thread = pl_protocol::Thread::placeholder(id);
    thread.workspace_id = "directory-pull-fixture".into();
    thread.root_thread_id = id.into();
    thread.agent_path = id.into();
    thread.title = id.into();
    thread.created_at = time;
    thread.updated_at = time;
    thread
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
        .apply_thread_delta(vec![thread("old", 1), thread("head", 3)], vec![])
        .await?;
    let first = observation.next().await?.expect("initial result");
    assert_eq!(first.threads[0].id, "head");
    assert_eq!(first.stamp.resource_key, "thread-directory");

    // A completed native read has not yet been accepted by its consumer.
    let mut outside = thread("outside", 2);
    outside.title = "renamed while accepting".into();
    events
        .apply_thread_delta(vec![outside.clone()], vec![])
        .await?;
    let next = observation.next().await?.expect("retained notification");
    assert!(next.stamp.revision > first.stamp.revision);
    assert_eq!(
        next.threads
            .iter()
            .map(|row| row.id.as_str())
            .collect::<Vec<_>>(),
        ["head", "outside"]
    );
    assert_eq!(next.threads[1].title, outside.title);
    assert!(next.next_cursor.is_some());
    observation.close().await?;
    Ok(())
}

#[tokio::test]
async fn selected_metadata_and_reopened_large_window_are_independent() -> Result<()> {
    let (_temp, events) = fixture().await?;
    events
        .apply_thread_delta(
            (0..90).map(|n| thread(&format!("row-{n:03}"), n)).collect(),
            vec![],
        )
        .await?;
    let selected =
        ThreadMetadataObservation::open(events.clone(), "pull-fixture".into(), "row-000".into())?;
    let wide = observe(&events, 80)?;
    let before = wide.next().await?.expect("wide result");
    assert_eq!(before.threads.len(), 80);
    assert_eq!(before.threads.last().unwrap().id, "row-010");
    assert_eq!(
        selected.next().await?.unwrap().thread.unwrap().id,
        "row-000"
    );
    wide.close().await?;

    let mut outside = thread("row-000", 0);
    outside.title = "changed outside list".into();
    outside.archived = true;
    events.apply_thread_delta(vec![outside], vec![]).await?;
    let entity = selected.next().await?.expect("independent entity update");
    assert!(entity.thread.as_ref().unwrap().archived);
    assert_eq!(
        entity.thread.as_ref().unwrap().title,
        "changed outside list"
    );
    let reopened = observe(&events, 80)?;
    let after = reopened.next().await?.expect("same complete demand");
    assert_eq!(after.window, before.window);
    assert_eq!(after.threads.len(), 80);
    assert_eq!(after.threads.last().unwrap().id, "row-010");
    assert!(after.stamp.revision > before.stamp.revision);
    reopened.close().await?;
    selected.close().await?;
    Ok(())
}

#[tokio::test]
async fn close_wakes_the_actual_next_and_releases_its_receiver() -> Result<()> {
    let (_temp, events) = fixture().await?;
    let observation = observe(&events, 20)?;
    assert!(observation.next().await?.unwrap().threads.is_empty());
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
    assert!(missing.next().await?.unwrap().thread.is_none());
    events
        .apply_thread_delta(vec![thread("missing", 1)], vec![])
        .await?;
    assert_eq!(missing.next().await?.unwrap().thread.unwrap().id, "missing");
    missing.close().await?;
    assert!(missing.inner.next.lock().await.signal.is_none());
    Ok(())
}
