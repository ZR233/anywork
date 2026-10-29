//! Minimal benchmark assembly around the real reliable writer and live projection.
//! No test module, substitute saver, or accounting reducer is compiled into this fixture.

use super::*;
use crate::studio::store::directory::{DirectoryDelta, ProjectDirectoryRecord};
use crate::studio::thread_projection::LiveProjection;
use std::path::Path;

struct ActiveThread {
    sink: ThreadStorageSink,
    projection: LiveProjection,
    sequence: u64,
}

pub(crate) struct WriterFixture {
    store: StudioStore,
    threads: Vec<ActiveThread>,
    expected_watermarks: std::collections::BTreeMap<String, u64>,
}

impl WriterFixture {
    pub(crate) async fn open(root: &Path, active_threads: usize) -> Result<Self> {
        ensure!(
            active_threads > 0,
            "a benchmark writer needs an active Thread"
        );
        let store = StudioStore::open(root.join("studio/v2/studio.sqlite")).await?;
        let mut fixture = Self {
            store,
            threads: Vec::new(),
            expected_watermarks: std::collections::BTreeMap::new(),
        };
        let setup = async {
            let project_root = root.join("project");
            tokio::fs::create_dir_all(&project_root).await?;
            let mut delta = DirectoryDelta::upsert_project(ProjectDirectoryRecord {
                id: "bench-project".into(),
                name: "Statistics benchmark".into(),
                path: project_root.to_string_lossy().into_owned(),
                ssh_alias: None,
                created_at: 1,
                updated_at: 1,
                last_opened_at: None,
                closed: false,
            });
            let threads: Vec<_> = (0..active_threads)
                .map(|index| {
                    let id = format!("bench-thread-{index:04}");
                    let mut thread = pl_protocol::Thread::placeholder(&id);
                    thread.project_id = "bench-project".into();
                    thread.agent_path = id.clone();
                    thread.root_thread_id = id;
                    thread
                })
                .collect();
            delta.thread_upserts = threads.clone();
            fixture.store.persist_directory_summaries(&delta).await?;
            for thread in threads {
                fixture.expected_watermarks.insert(thread.id.clone(), 0);
                let sink = ThreadStorageSink::new(fixture.store.clone(), thread, None).await?;
                fixture.threads.push(ActiveThread {
                    sink,
                    projection: LiveProjection::new(),
                    sequence: 0,
                });
            }
            fixture
                .store
                .calls()
                .observation()
                .wait_observers(
                    &fixture.expected_watermarks,
                    fixture.store.calls().admitted_ticket(),
                )
                .await?;
            Ok::<_, anyhow::Error>(())
        }
        .await;
        if let Err(error) = setup {
            let cleanup = fixture.close().await;
            return Err(error.context(format!("benchmark writer setup cleanup: {cleanup:?}")));
        }
        Ok(fixture)
    }

    pub(crate) fn calls(&self) -> &super::super::calls::CallsStore {
        self.store.calls()
    }

    /// Admission -> real live projection -> history/checkpoint commit -> calls durability ->
    /// the affected Thread's actual directed progress observation. Idle Threads remain initialized
    /// and their absolute progress is checked, but they owe no work for another Thread's mutation.
    pub(crate) async fn empty_effect(&mut self) -> Result<Duration> {
        let (working, idle_threads) = self.threads.split_at_mut(1);
        let active = &mut working[0];
        let sequence = active.sequence + 1;
        let id = active.sink.0.thread.id.clone();
        let write = ThreadWrite {
            effect: Arc::new(pl_core::thread::ThreadEffectBatch {
                thread_id: id.clone(),
                sequence,
                committed_at: crate::studio::benchmark::FIXTURE_TIME,
                ..Default::default()
            }),
            checkpoint: ThreadCheckpoint::capture_transfer(
                id.clone(),
                sequence,
                ThreadSnapshot {
                    commit_sequence: sequence,
                    ..Default::default()
                },
            ),
            output_claim: None,
        };
        let started = std::time::Instant::now();
        active.sink.admit(&id, write)?;
        let write = active
            .sink
            .0
            .channel
            .next_unprojected()
            .context("admitted benchmark effect is owed a live projection")?;
        let (_, prepared) = active.projection.advance(
            &active.sink.0.chat,
            &active.sink.0.thread,
            &write.effect,
            &write.checkpoint.state,
            true,
        )?;
        ensure!(
            active.sink.0.channel.prepare(prepared),
            "benchmark projection handoff rejected"
        );
        tokio::time::timeout(Duration::from_secs(30), active.sink.flush(&id, sequence)).await??;
        active.sequence = sequence;
        self.expected_watermarks.insert(id.clone(), sequence);
        let calls = self.store.calls();
        let target = calls.admitted_ticket();
        crate::studio::benchmark::wait_calls(calls, target).await?;
        calls
            .observation()
            .wait_observers(
                &std::collections::BTreeMap::from([(id.clone(), sequence)]),
                target,
            )
            .await?;
        for idle in idle_threads {
            ensure!(
                lock_progress(&idle.sink.0).calls_durable == 0,
                "an idle benchmark Thread acquired another Thread's progress"
            );
        }
        let elapsed = started.elapsed();
        ensure!(
            lock_progress(&active.sink.0).calls_durable == sequence,
            "benchmark effect did not advance its durable calls watermark"
        );
        Ok(elapsed)
    }

    pub(crate) async fn close(self) -> Result<()> {
        let mut failures = Vec::new();
        for active in &self.threads {
            if let Err(error) = active.sink.0.channel.stop_and_join().await {
                failures.push(error.to_string());
            }
        }
        if let Err(error) = crate::studio::benchmark::wait_calls(
            self.store.calls(),
            self.store.calls().admitted_ticket(),
        )
        .await
        {
            failures.push(error.to_string());
        }
        if let Err(error) = self.store.close().await {
            failures.push(error.to_string());
        }
        ensure!(
            failures.is_empty(),
            "benchmark writer close: {}",
            failures.join("; ")
        );
        Ok(())
    }
}
