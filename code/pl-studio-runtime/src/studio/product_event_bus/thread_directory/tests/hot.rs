use super::*;

#[derive(Clone, Copy, Debug)]
enum HotMutation {
    Runtime,
    UserMessage,
    Delta,
    Observed,
}

async fn assert_serial_publication(mutation: HotMutation) -> Result<()> {
    let first = row("first", "p1", 1);
    let second = row("second", "p1", 2);
    let (_temp, events) = fixture(
        vec![first.clone(), second],
        vec![project("p1", "Project", "/workspace/project")],
    )
    .await?;
    let baseline_revision = query(&events, &ThreadDirectoryQuery::default(), None, 10)?
        .stamp
        .revision;
    let mut topic = events.subscribe_topic(&crate::StudioProductTopic::ThreadDirectory);
    let mut internal = events.subscribe_internal();
    let worker_events = events.clone();
    let runtime = tokio::runtime::Handle::current();
    let (first_event, second_event, held_index) = tokio::task::spawn_blocking(move || {
        // Stop the real final dispatch after internal.send. A second identity must not pass the
        // first mutation until its row, revision and topic dispatch all leave the index scope.
        let topics = worker_events.topics.lock().unwrap();
        std::thread::scope(|scope| {
            let first_writer = scope.spawn(|| -> Result<()> {
                let _runtime = runtime.enter();
                match mutation {
                    HotMutation::Runtime => {
                        worker_events.patch_thread_runtime(
                            worker_events.begin_native_observation("first").as_ref(),
                            crate::ThreadStatus::Running,
                            10,
                            &pl_core::thread::ThreadSnapshot::default(),
                            None,
                        )?;
                    }
                    HotMutation::UserMessage => {
                        worker_events.record_user_message("first", 10);
                    }
                    HotMutation::Delta => {
                        let mut first = first;
                        first.title = "New first title".into();
                        worker_events.publish_thread_delta(vec![first], Vec::new(), Vec::new());
                    }
                    HotMutation::Observed => {
                        runtime.block_on(worker_events.commit_observed_thread_mode(
                            &first.thread_id,
                            crate::mode::ThreadModeId::new("mode.custom").unwrap(),
                            10,
                        ))?;
                    }
                }
                Ok(())
            });
            let first_event = runtime.block_on(internal.recv()).unwrap();
            let held_index = worker_events.thread_index.try_lock().is_err();
            let (attempted, started) = std::sync::mpsc::sync_channel(0);
            let runtime = &runtime;
            let worker_events = &worker_events;
            let second_writer = scope.spawn(move || {
                let _runtime = runtime.enter();
                attempted.send(()).unwrap();
                worker_events.record_user_message("second", 20);
            });
            started.recv().unwrap();
            drop(topics);
            first_writer.join().unwrap().unwrap();
            second_writer.join().unwrap();
            let mut published = vec![first_event];
            published.extend(std::iter::from_fn(|| internal.try_recv().ok()));
            let expected_agent_events = usize::from(!matches!(mutation, HotMutation::UserMessage));
            assert_eq!(
                published
                    .iter()
                    .filter(|event| matches!(
                        event.kind,
                        StudioProductEventKind::AgentDirectoryChanged(_)
                    ))
                    .count(),
                expected_agent_events
            );
            let mut thread_events = published.into_iter().filter(|event| {
                matches!(
                    event.kind,
                    StudioProductEventKind::ThreadDirectoryChanged(_)
                )
            });
            let first_event = thread_events.next().expect("first thread publication");
            let second_event = thread_events.next().expect("second thread publication");
            assert!(thread_events.next().is_none());
            (first_event, second_event, held_index)
        })
    })
    .await?;
    assert!(held_index, "{mutation:?} released index before dispatch");
    assert_eq!(topic.try_recv()?, first_event);
    assert_eq!(topic.try_recv()?, second_event);
    assert!(first_event.sequence < second_event.sequence);
    let first_delta = event_delta(first_event);
    let second_delta = event_delta(second_event);
    assert_eq!(first_delta.revision, baseline_revision + 1);
    assert_eq!(second_delta.revision, first_delta.revision + 1);
    assert_eq!(first_delta.upserted[0].thread_id, "first");
    assert_eq!(second_delta.upserted[0].thread_id, "second");
    assert_eq!(second_delta.upserted[0].last_user_message_at, Some(20));
    let frame = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
    assert_eq!(frame.stamp.revision, second_delta.revision);
    for row in frame.rows {
        let expected = if row.thread_id == "first" {
            &first_delta.upserted[0]
        } else {
            &second_delta.upserted[0]
        };
        assert_eq!(&row, expected);
    }
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn runtime_patch_is_one_hot_watermark_and_dispatch_scope() -> Result<()> {
    assert_serial_publication(HotMutation::Runtime).await
}

#[tokio::test]
async fn user_message_is_one_hot_watermark_and_dispatch_scope() -> Result<()> {
    assert_serial_publication(HotMutation::UserMessage).await
}

#[tokio::test]
async fn directory_delta_is_one_hot_watermark_and_dispatch_scope() -> Result<()> {
    assert_serial_publication(HotMutation::Delta).await
}

#[tokio::test]
async fn observed_commit_is_one_hot_watermark_and_dispatch_scope() -> Result<()> {
    assert_serial_publication(HotMutation::Observed).await
}

#[tokio::test]
async fn repeated_or_older_user_message_watermarks_do_not_publish_or_regress() -> Result<()> {
    let (_temp, events) = fixture(vec![row("root", "p1", 1)], vec![]).await?;
    let mut changes = events.subscribe_topic(&crate::StudioProductTopic::ThreadDirectory);
    events.record_user_message("root", 10);
    let first = event_delta(changes.try_recv()?);
    let sequence = events.current_sequence();
    for accepted_at in [10, 9, 1] {
        events.record_user_message("root", accepted_at);
        assert_eq!(events.current_sequence(), sequence);
        assert!(changes.try_recv().is_err());
        let frame = events.read_thread_metadata("root", "test")?;
        assert_eq!(frame.stamp.revision, first.revision);
        assert_eq!(frame.row.unwrap().last_user_message_at, Some(10));
    }
    events.writer.shutdown().await?;
    assert_eq!(
        events
            .store
            .catalog()
            .get_session("root")
            .unwrap()
            .last_user_message_at,
        Some(10)
    );
    Ok(())
}
