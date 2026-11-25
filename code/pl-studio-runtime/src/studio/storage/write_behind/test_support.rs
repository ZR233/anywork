//! Real SQLite writer fixtures with a controlled pause between commit and ticket ACK.

use std::{
    sync::{Arc, Mutex},
    time::Duration,
};

use anyhow::{Context, Result};
use tokio::sync::oneshot;

use super::super::{
    queue::{PendingBatch, StudioMutation},
    worker::{BatchCommit, BatchError},
};
use super::{SqliteBatchCommit, StudioStore, ThreadWriteBehindWriter, supervise_writer};
use crate::studio::worktree::worktree_lease::WorktreeLeaseState;

struct LeaseAckGate {
    owner_thread_id: String,
    state: WorktreeLeaseState,
    entered: oneshot::Sender<()>,
    release: oneshot::Receiver<()>,
}

#[derive(Clone, Default)]
pub(in crate::studio) struct LeaseAcks(Arc<Mutex<Option<LeaseAckGate>>>);

impl LeaseAcks {
    pub(in crate::studio) fn arm(
        &self,
        owner_thread_id: &str,
        state: WorktreeLeaseState,
    ) -> (oneshot::Receiver<()>, oneshot::Sender<()>) {
        let (entered, waiting) = oneshot::channel();
        let (release, released) = oneshot::channel();
        assert!(
            self.0
                .lock()
                .unwrap()
                .replace(LeaseAckGate {
                    owner_thread_id: owner_thread_id.to_owned(),
                    state,
                    entered,
                    release: released,
                })
                .is_none()
        );
        (waiting, release)
    }
}

impl BatchCommit for LeaseAcks {
    async fn commit(&self, store: &StudioStore, batch: &PendingBatch) -> Result<(), BatchError> {
        SqliteBatchCommit.commit(store, batch).await?;
        let gate = {
            let mut armed = self.0.lock().unwrap();
            if armed.as_ref().is_some_and(|gate| {
                batch.entries.iter().any(|entry| {
                    matches!(entry.mutation.as_ref(), StudioMutation::WorktreeLease(lease)
                    if lease.owner_thread_id == gate.owner_thread_id && lease.state == gate.state)
                })
            }) {
                armed.take()
            } else {
                None
            }
        };
        if let Some(gate) = gate {
            gate.entered
                .send(())
                .expect("test waits for the SQL commit");
            gate.release
                .await
                .expect("test releases ticket acknowledgement");
        }
        Ok(())
    }
}

pub(in crate::studio) fn writer_with_lease_ack_gate(
    store: StudioStore,
) -> (ThreadWriteBehindWriter, LeaseAcks) {
    let writer = ThreadWriteBehindWriter::new(store);
    let lease_acks = LeaseAcks::default();
    *writer.task.lock().unwrap() = Some(tokio::spawn(supervise_writer(
        writer.shared.clone(),
        writer.pending_commits.clone(),
        lease_acks.clone(),
    )));
    (writer, lease_acks)
}

/// Wait for the actual receipt across retry, even while the prior Blocked state is visible.
pub(in crate::studio) async fn wait_for_durable_ticket(
    writer: &ThreadWriteBehindWriter,
    target: u64,
) -> Result<()> {
    let mut durable = writer.shared.durable_ticket.subscribe();
    let _request = writer.request_flush();
    tokio::time::timeout(
        Duration::from_secs(5),
        durable.wait_for(|ticket| *ticket >= target),
    )
    .await?
    .context("writer durability channel closed")?;
    Ok(())
}
