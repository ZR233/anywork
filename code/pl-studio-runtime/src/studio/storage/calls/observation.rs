//! Explicit benchmark observations. Each CallsStore owns one instance; no process-wide counters.
//!
//! Relaxed atomics only count completed/attempted operations, never synchronize business state.
//! Snapshots are taken after the case's durable barriers; concurrent snapshots are diagnostic only.

use std::collections::BTreeMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

macro_rules! metrics {
    ($($name:ident => $label:literal),+ $(,)?) => {
        #[derive(Clone, Copy)]
        pub(crate) enum Metric { $($name,)+ Count }
        const NAMES: &[&str] = &[$($label,)+];
        const METRICS: &[Metric] = &[$(Metric::$name,)+];
    };
}

metrics! {
    JsonlReadOpen => "jsonl_read_open",
    JsonlSegmentOpen => "jsonl_segment_open",
    JsonlFlush => "jsonl_flush",
    JsonlSync => "jsonl_sync_data",
    RecentIndexSql => "sql_recent_index_read",
    RecentRead => "recent_performance_read",
    WatermarkReadSql => "sql_thread_watermark_read",
    ObserverWatermarkReadSql => "sql_observer_watermark_read",
    WatermarkWriteSql => "sql_thread_watermark_write",
    BillingIdentitySql => "sql_billing_identity_read",
    LogIndexWriteSql => "sql_log_index_write",
    SummaryReadSql => "sql_summary_read",
    SummaryRevisionSql => "sql_summary_revision_read",
    SummaryWriteSql => "sql_summary_write",
    SummaryReplaced => "summary_projection_written",
    SummarySkipped => "summary_projection_skipped",
    PerformanceWriteSql => "sql_performance_write",
    PerformanceTrimSql => "sql_performance_trim",
    PerformanceSummarySql => "sql_performance_summary_read",
    BatchCommit => "calls_batch_commit",
    AccountingRead => "checkpoint_accounting_read",
    EffectEncode => "effect_encode",
    BillingEncode => "billing_encode",
    LogRecordEncode => "log_record_encode",
    ReceiptExtraction => "receipt_extraction",
    MaterializedRefresh => "materialized_refresh",
    ObserverRefresh => "observer_refresh",
    ReadLockAcquire => "log_read_lock_acquire",
    ReadLockWaitNanos => "log_read_lock_wait_ns",
    WriteLockAcquire => "log_write_lock_acquire",
    WriteLockWaitNanos => "log_write_lock_wait_ns",
    QueueDequeued => "queue_dequeued_mutations",
    QueueAgeNanos => "queue_age_at_dequeue_ns",
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ObservationSnapshot {
    pub counters: BTreeMap<String, u64>,
    pub queue_high_water_mutations: u64,
    pub queue_high_water_bytes: u64,
    pub queue_age_max_nanos: u64,
}

impl ObservationSnapshot {
    /// Counters are deltas; high-water gauges are absolute within this store/case.
    pub fn since(&self, earlier: &Self) -> Self {
        Self {
            counters: self
                .counters
                .iter()
                .map(|(key, value)| (key.clone(), value.saturating_sub(earlier.counters[key])))
                .collect(),
            queue_high_water_mutations: self.queue_high_water_mutations,
            queue_high_water_bytes: self.queue_high_water_bytes,
            queue_age_max_nanos: self.queue_age_max_nanos,
        }
    }
}

struct ObserverResult {
    ticket: u64,
    sequence: Result<u64, String>,
}

pub(crate) struct Observation {
    counters: [AtomicU64; Metric::Count as usize],
    queue_mutations: AtomicU64,
    queue_bytes: AtomicU64,
    queue_age_max_nanos: AtomicU64,
    /// Observation only: a real recent read entered. It does not require a particular read backend.
    read_epochs: tokio::sync::watch::Sender<u64>,
    observer_tickets: tokio::sync::watch::Sender<BTreeMap<String, ObserverResult>>,
}

impl Default for Observation {
    fn default() -> Self {
        Self {
            counters: std::array::from_fn(|_| AtomicU64::new(0)),
            queue_mutations: AtomicU64::new(0),
            queue_bytes: AtomicU64::new(0),
            queue_age_max_nanos: AtomicU64::new(0),
            read_epochs: tokio::sync::watch::channel(0).0,
            observer_tickets: tokio::sync::watch::channel(BTreeMap::new()).0,
        }
    }
}

impl Observation {
    pub(crate) fn increment(&self, metric: Metric) {
        self.counters[metric as usize].fetch_add(1, Ordering::Relaxed);
    }

    pub(crate) fn lock_acquired(&self, read: bool, elapsed: Duration) {
        let (count, nanos) = if read {
            (Metric::ReadLockAcquire, Metric::ReadLockWaitNanos)
        } else {
            (Metric::WriteLockAcquire, Metric::WriteLockWaitNanos)
        };
        self.increment(count);
        self.counters[nanos as usize].fetch_add(
            u64::try_from(elapsed.as_nanos()).unwrap_or(u64::MAX),
            Ordering::Relaxed,
        );
    }

    pub(crate) fn recent_read_started(&self) {
        self.increment(Metric::RecentRead);
        self.read_epochs.send_modify(|epoch| *epoch += 1);
    }

    pub(crate) fn subscribe_reads(&self) -> tokio::sync::watch::Receiver<u64> {
        self.read_epochs.subscribe()
    }

    pub(crate) fn observer_refreshed(
        &self,
        thread_id: &str,
        ticket: u64,
        sequence: Result<u64, String>,
    ) {
        self.increment(Metric::ObserverRefresh);
        self.observer_tickets.send_modify(|tickets| {
            tickets.insert(thread_id.to_owned(), ObserverResult { ticket, sequence });
        });
    }

    pub(crate) async fn wait_observers(
        &self,
        expected_sequences: &BTreeMap<String, u64>,
        target: u64,
    ) -> anyhow::Result<()> {
        let mut tickets = self.observer_tickets.subscribe();
        tokio::time::timeout(Duration::from_secs(30), async {
            loop {
                let complete = {
                    let observed = tickets.borrow_and_update();
                    let mut complete = true;
                    for (id, expected) in expected_sequences {
                        match observed.get(id) {
                            Some(result) => {
                                let sequence = result.sequence.as_ref().map_err(|error| {
                                    anyhow::anyhow!(
                                        "benchmark observer {id} watermark query failed: {error}"
                                    )
                                })?;
                                complete &= result.ticket >= target && sequence >= expected;
                            }
                            None => complete = false,
                        }
                    }
                    complete
                };
                if complete {
                    return Ok(());
                }
                tickets.changed().await?;
            }
        })
        .await
        .map_err(|_| {
            anyhow::anyhow!("benchmark observers did not settle at calls ticket {target}")
        })?
    }

    pub(crate) fn queue(&self, mutations: usize, bytes: usize) {
        self.queue_mutations
            .fetch_max(mutations as u64, Ordering::Relaxed);
        self.queue_bytes.fetch_max(bytes as u64, Ordering::Relaxed);
    }

    pub(crate) fn dequeued(&self, age: Duration) {
        let nanos =
            u64::try_from(age.as_nanos()).expect("benchmark queue age fits u64 nanoseconds");
        self.increment(Metric::QueueDequeued);
        self.counters[Metric::QueueAgeNanos as usize].fetch_add(nanos, Ordering::Relaxed);
        self.queue_age_max_nanos.fetch_max(nanos, Ordering::Relaxed);
    }

    /// The measured operation starts only after fixture preparation has settled.
    pub(crate) fn reset_queue_age(&self) {
        self.queue_age_max_nanos.store(0, Ordering::Relaxed);
    }

    /// Only called after fixture setup has settled, before starting measured work.
    pub(crate) fn reset_queue_high_water(&self) {
        self.queue_mutations.store(0, Ordering::Relaxed);
        self.queue_bytes.store(0, Ordering::Relaxed);
    }

    pub(crate) fn snapshot(&self) -> ObservationSnapshot {
        ObservationSnapshot {
            counters: NAMES
                .iter()
                .zip(METRICS)
                .map(|(name, metric)| {
                    (
                        name.to_string(),
                        self.counters[*metric as usize].load(Ordering::Relaxed),
                    )
                })
                .collect(),
            queue_high_water_mutations: self.queue_mutations.load(Ordering::Relaxed),
            queue_high_water_bytes: self.queue_bytes.load(Ordering::Relaxed),
            queue_age_max_nanos: self.queue_age_max_nanos.load(Ordering::Relaxed),
        }
    }
}
