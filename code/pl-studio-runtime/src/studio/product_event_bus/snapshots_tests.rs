use super::*;
use crate::studio::product_event_bus::thread_directory::tests::{fixture, project};
use anyhow::Result;

#[derive(Clone, Copy, Debug)]
enum Publication {
    Project,
    Persistence,
    Queue,
}

impl Publication {
    fn publish(self, events: &ProductEventBus, count: u64) -> Result<()> {
        match self {
            Self::Project => {
                let mut entry =
                    crate::WorkspaceRecord::from(&project("project", "Workspace", "/workspace"));
                entry.updated_at = count as i64;
                events.apply_project_snapshot_delta(&[entry], &[])?;
            }
            Self::Persistence => events.update_persistence(
                PersistenceStateSnapshot::default(),
                crate::studio::storage::coordinator::ThreadPersistenceSnapshot {
                    pending_commits: count,
                    ..Default::default()
                },
            ),
            Self::Queue => events.publish_persistence_queue(crate::PersistenceQueueSnapshot {
                pending_operations: count,
                ..Default::default()
            }),
        }
        Ok(())
    }

    fn publication_locked(self, events: &ProductEventBus) -> bool {
        match self {
            Self::Project => events.project_snapshot.try_lock().is_err(),
            Self::Persistence => events.persistence_snapshot.try_lock().is_err(),
            Self::Queue => events.persistence_queue.try_lock().is_err(),
        }
    }

    async fn assert_current(
        self,
        events: &ProductEventBus,
        event: StudioProductEventEnvelope,
    ) -> u64 {
        match (self, event.kind) {
            (Self::Project, StudioProductEventKind::ProjectDirectoryChanged(state)) => {
                assert_eq!(events.read_project_directory().await.unwrap(), state);
                assert_eq!(state.state.value().unwrap().projects[0].updated_at, 1);
                state.state.revision()
            }
            (Self::Persistence, StudioProductEventKind::PersistenceStateChanged(state)) => {
                assert_eq!(events.persistence_state(), state);
                assert_eq!(state.state.pending_commits(), 1);
                state.revision
            }
            (Self::Queue, StudioProductEventKind::PersistenceQueueStateChanged(state)) => {
                assert_eq!(events.persistence_queue_state(), state);
                assert_eq!(state.queue.pending_operations, 1);
                state.revision
            }
            (_, kind) => panic!("unexpected {self:?} event: {kind:?}"),
        }
    }
}

#[test]
fn snapshot_revision_and_dispatch_share_the_owner_lock_and_identical_values_do_not_emit()
-> Result<()> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    for publication in [
        Publication::Project,
        Publication::Persistence,
        Publication::Queue,
    ] {
        let (_temp, events) = runtime.block_on(fixture(vec![], vec![]))?;
        let mut internal = events.subscribe_internal();
        // Internal delivery precedes typed dispatch. Holding topics freezes this exact boundary
        // without adding a pause, probe or fault field to the production owner.
        let topics = events.topics.lock().unwrap();
        let (received, locked) = std::thread::scope(|scope| -> Result<_> {
            let writer = scope.spawn(|| publication.publish(&events, 1));
            let received = runtime.block_on(async {
                tokio::time::timeout(std::time::Duration::from_secs(5), internal.recv()).await
            });
            let locked = publication.publication_locked(&events);
            drop(topics);
            writer.join().unwrap()?;
            Ok((received, locked))
        })?;
        assert!(
            locked,
            "{publication:?}: a reader or second writer must wait for dispatch"
        );
        let first = received??;
        let revision = runtime.block_on(publication.assert_current(&events, first));
        assert!(revision > 0);
        publication.publish(&events, 1)?;
        assert!(
            internal.try_recv().is_err(),
            "{publication:?}: repeated material must not advance the event stream"
        );
        publication.publish(&events, 2)?;
        let next = internal.try_recv()?;
        let next_revision = match next.kind {
            StudioProductEventKind::ProjectDirectoryChanged(state) => state.state.revision(),
            StudioProductEventKind::PersistenceStateChanged(state) => state.revision,
            StudioProductEventKind::PersistenceQueueStateChanged(state) => state.revision,
            kind => panic!("unexpected event: {kind:?}"),
        };
        assert_eq!(next_revision, revision + 1);
        runtime.block_on(events.writer.shutdown())?;
    }
    Ok(())
}
