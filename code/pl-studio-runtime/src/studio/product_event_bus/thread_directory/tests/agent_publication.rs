use super::*;
use futures::FutureExt;
use tracing_subscriber::prelude::*;

#[derive(Clone, Default)]
struct PublicationWork {
    compared: Arc<Mutex<Vec<u64>>>,
    materialized: Arc<Mutex<Vec<u64>>>,
}

impl<S: tracing::Subscriber> tracing_subscriber::Layer<S> for PublicationWork {
    fn on_event(&self, event: &tracing::Event<'_>, _: tracing_subscriber::layer::Context<'_, S>) {
        struct WorkFields<'a>(&'a PublicationWork);
        impl tracing::field::Visit for WorkFields<'_> {
            fn record_u64(&mut self, field: &tracing::field::Field, value: u64) {
                match field.name() {
                    "compared" => self.0.compared.lock().unwrap().push(value),
                    "materialized_agents" => self.0.materialized.lock().unwrap().push(value),
                    _ => {}
                }
            }
            fn record_debug(&mut self, _: &tracing::field::Field, _: &dyn std::fmt::Debug) {}
        }
        event.record(&mut WorkFields(self));
    }
}

fn patch_summary(
    events: &ProductEventBus,
    token: &NativeAgentObservation,
    revision: u64,
    title: &str,
    time: i64,
) -> Result<()> {
    events
        .patch_thread_runtime(
            Some(token),
            ThreadStatus::Idle,
            time,
            &pl_core::thread::ThreadSnapshot {
                observation_revision: revision,
                ..Default::default()
            },
            Some(Some(title.into())),
        )?
        .expect("current observation");
    Ok(())
}

fn capture(work: &PublicationWork, operation: impl FnOnce() -> Result<()>) -> Result<()> {
    tracing::subscriber::with_default(tracing_subscriber::registry().with(work.clone()), operation)
}

#[tokio::test]
async fn signal_and_catalog_observers_publish_no_full_collection_at_scale() -> Result<()> {
    let (_temp, events) = fixture(vec![], vec![]).await?;
    let rows = (0..10_000)
        .map(|n| row(&format!("row-{n:05}"), "p1", n))
        .collect::<Vec<_>>();
    *events.thread_index.lock().unwrap() = super::index::memory_index(&rows);
    let mut catalog = events.subscribe_catalog_events();
    let mut signal = events.subscribe_topic_signal(&crate::StudioProductTopic::AgentDirectory);
    let before = events.read_agent_directory().await;
    let token = events.begin_native_observation("row-00000").unwrap();
    let sequence = events.current_sequence();
    let work = PublicationWork::default();
    capture(&work, || {
        patch_summary(&events, &token, 1, "first", 0)?;
        patch_summary(&events, &token, 2, "second", 0)?;
        patch_summary(&events, &token, 2, "second", 0)
    })?;
    assert_eq!(*work.compared.lock().unwrap(), [1, 1, 1]);
    assert!(
        work.materialized.lock().unwrap().is_empty(),
        "wake-only consumers must not materialize the directory"
    );
    assert_eq!(events.current_sequence(), sequence + 2);
    assert!(signal.changed().now_or_never().unwrap().is_ok());
    assert!(
        signal.changed().now_or_never().is_none(),
        "the duplicate patch must not produce another wake"
    );
    assert!(
        catalog.try_recv().is_err(),
        "catalog refresh gets AgentDirectory through its signal"
    );
    let after = events.read_agent_directory().await;
    assert_eq!(after.state.revision(), before.state.revision() + 2);
    assert_eq!(after.state.value().unwrap().agents.len(), 10_000);
    assert_eq!(
        after.state.value().unwrap().agents[0].summary.as_deref(),
        Some("second")
    );
    assert_eq!(before.state.value().unwrap().agents[0].summary, None);
    let recovery = events.emit_recovery_state(crate::ObservedResource::ready(1, 0, vec![]));
    assert_eq!(
        catalog.try_recv()?,
        recovery,
        "other catalog values keep their original envelope"
    );
    events.writer.shutdown().await?;
    Ok(())
}

enum ValueSubscription {
    Typed(crate::ProductTopicReceiver),
    Internal(tokio::sync::broadcast::Receiver<StudioProductEventEnvelope>),
}

impl ValueSubscription {
    fn receive(&mut self) -> Result<StudioProductEventEnvelope> {
        Ok(match self {
            Self::Typed(receiver) => receiver.try_recv()?,
            Self::Internal(receiver) => receiver.try_recv()?,
        })
    }
}

async fn preserves_value_cuts(internal: bool) -> Result<()> {
    let (_temp, events) = fixture(vec![row("a", "p1", 1), row("b", "p1", 2)], vec![]).await?;
    let before = events.read_agent_directory().await;
    let token = events.begin_native_observation("a").unwrap();
    let mut values = if internal {
        ValueSubscription::Internal(events.subscribe_internal())
    } else {
        ValueSubscription::Typed(events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory))
    };
    let work = PublicationWork::default();
    capture(&work, || {
        patch_summary(&events, &token, 1, "first", 1)?;
        patch_summary(&events, &token, 2, "second", 1)?;
        patch_summary(&events, &token, 2, "second", 1)
    })?;
    assert_eq!(*work.compared.lock().unwrap(), [1, 1, 1]);
    assert_eq!(*work.materialized.lock().unwrap(), [2, 2]);
    let first = values.receive()?;
    let second = values.receive()?;
    assert!(values.receive().is_err());
    assert_eq!(second.sequence, first.sequence + 1);
    let states = [&first, &second].map(|event| {
        let StudioProductEventKind::AgentDirectoryChanged(state) = &event.kind else {
            panic!("complete agent snapshot")
        };
        state
    });
    for (offset, expected) in ["first", "second"].into_iter().enumerate() {
        let state = states[offset];
        assert_eq!(
            state.state.revision(),
            before.state.revision() + offset as u64 + 1
        );
        let agents = &state.state.value().unwrap().agents;
        assert_eq!(
            agents
                .iter()
                .map(|entry| entry.agent_id.as_str())
                .collect::<Vec<_>>(),
            ["a", "b"]
        );
        assert_eq!(agents[0].summary.as_deref(), Some(expected));
        assert_eq!(agents[1], before.state.value().unwrap().agents[1]);
    }
    assert_eq!(events.read_agent_directory().await, *states[1]);
    drop(values);
    let unobserved = PublicationWork::default();
    capture(&unobserved, || {
        patch_summary(&events, &token, 3, "third", 1)
    })?;
    assert!(unobserved.materialized.lock().unwrap().is_empty());
    let mut reopened = events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory);
    assert!(
        reopened.try_recv().is_err(),
        "registration must not replay the unobserved commit"
    );
    let baseline = events.read_agent_directory().await;
    assert_eq!(baseline.state.revision(), before.state.revision() + 3);
    assert_eq!(
        baseline.state.value().unwrap().agents[0].summary.as_deref(),
        Some("third")
    );
    patch_summary(&events, &token, 4, "fourth", 1)?;
    let next = reopened.try_recv()?;
    assert_eq!(
        next.sequence,
        second.sequence + 2,
        "notification-only commits keep their own global sequence"
    );
    let StudioProductEventKind::AgentDirectoryChanged(next) = next.kind else {
        panic!("agent value")
    };
    assert_eq!(next, events.read_agent_directory().await);
    assert_eq!(next.state.revision(), baseline.state.revision() + 1);
    assert_eq!(
        next.state.value().unwrap().agents[0].summary.as_deref(),
        Some("fourth")
    );
    events.writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn typed_value_subscribers_keep_complete_ordered_snapshots_and_registration_baselines()
-> Result<()> {
    preserves_value_cuts(false).await
}

#[tokio::test]
async fn full_internal_subscribers_keep_complete_ordered_snapshots_and_registration_baselines()
-> Result<()> {
    preserves_value_cuts(true).await
}
