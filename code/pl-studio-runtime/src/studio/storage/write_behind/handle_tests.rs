use anyhow::Result;
use sea_orm::ConnectionTrait;

use super::test_support::wait_for_durable_ticket;
use super::{DirectoryDelta, StudioStore, ThreadWriteBehindWriter};
use crate::studio::worktree::worktree_lease::{load_leases, test_support::prepared_child_lease};

#[tokio::test]
async fn lease_ticket_admission_is_fifo_across_the_batch_boundary() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    store.database().execute_unprepared("CREATE TRIGGER reject_boundary_lease BEFORE INSERT ON studio_objects WHEN NEW.owner_id='boundary' BEGIN SELECT RAISE(ABORT,'controlled lease admission rejection'); END").await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    for index in 0..super::super::queue::MAX_BATCH_COMMITS - 1 {
        writer.record_worktree_lease(prepared_child_lease(temp.path(), &format!("entry-{index}")));
    }
    let (entered, waiting) = std::sync::mpsc::sync_channel(1);
    let (release, released) = std::sync::mpsc::channel();
    let runtime = tokio::runtime::Handle::current();
    let admitting = writer.clone();
    let critical = prepared_child_lease(temp.path(), "boundary");
    let task = std::thread::spawn(move || {
        let _runtime = runtime.enter();
        admitting.admit_worktree_lease(critical, || {
            entered.send(()).expect("admission test still waiting");
            released.recv().expect("admission test releases queue");
        })
    });
    waiting.recv_timeout(std::time::Duration::from_secs(5))?;
    let directory = DirectoryDelta {
        project_removals: vec![crate::studio::store::directory::ProjectRemoval {
            workspace_id: "unused-project".into(),
            session_ids: vec![],
            closed_at: 1,
        }],
        ..Default::default()
    };
    // The former allocation-before-lock implementation permits precisely the bad 65-before-64
    // interleaving here. The corrected implementation holds this lock through admission.
    let admission_holds_queue = writer.shared.queue.try_lock().is_err();
    if !admission_holds_queue {
        writer.record_directory(directory.clone());
    }
    release.send(())?;
    let ticket = task
        .join()
        .map_err(|_| anyhow::anyhow!("admission thread failed"))?;
    if admission_holds_queue {
        writer.record_directory(directory);
    }
    assert!(
        admission_holds_queue,
        "ticket assignment and enqueue must share the queue lock"
    );
    assert_eq!(ticket, 64);
    assert_eq!(writer.admitted_ticket(), 65);
    assert_eq!(writer.pending_commit_count(), 65);
    assert_eq!(
        writer
            .shared
            .queue
            .lock()
            .unwrap()
            .iter()
            .map(|entry| entry.ticket())
            .collect::<Vec<_>>(),
        (1..=65).collect::<Vec<_>>()
    );
    let blocked = tokio::time::timeout(
        std::time::Duration::from_secs(5),
        writer.flush_through(ticket),
    )
    .await?;
    assert!(
        blocked.is_err(),
        "a later directory ticket must never confirm the rejected lease"
    );
    assert!(writer.saved_watermark() < ticket);
    assert!(load_leases(&store).await?.is_empty());
    store
        .database()
        .execute_unprepared("DROP TRIGGER reject_boundary_lease")
        .await?;
    writer.retry_now();
    wait_for_durable_ticket(&writer, 65).await?;
    assert_eq!(writer.pending_commit_count(), 0);
    assert!(
        load_leases(&store)
            .await?
            .iter()
            .any(|lease| lease.owner_thread_id == "boundary")
    );
    writer.shutdown().await?;
    Ok(())
}
