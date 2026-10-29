//! Hidden, opt-in statistics benchmark facade. Not a production storage API.
//!
//! Fixtures own unique directories below the caller's explicit scratch root. Successful close
//! joins real workers before deleting that owned directory; implicit/error drops preserve it.
//! Setup, migrations, seeding, validation and teardown are outside operation timers.

use std::path::Path;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail, ensure};
use pl_protocol::{
    FirstOutputSource, InferenceAccounting, InferenceBillingRecord, InferenceModelObservation,
    InferenceTiming, PricingOutcome, RuntimeCostAmount, UsageReport,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

use super::agent_host::ThreadWriteBehindWriter;
use super::runtime::ModelPerformanceOwner;
use super::storage::calls::{
    CallRetention, CallStatus, CallsStore, PerformanceSampleRow, PurposeUsageProjection,
    SessionCostRollup, SessionUsageProjection,
};
use super::storage::thread_writer::benchmark::WriterFixture;
use super::{ProductEventBus, StudioStore};

mod storage_io;

pub use super::storage::calls::observation::ObservationSnapshot;
pub use storage_io::StorageIo;

pub const SEED: u64 = 209;
pub const TOKIO_WORKER_THREADS: usize = 4;
pub const HISTORY_SAMPLES: usize = 3_000;
/// A fixed UTC day, independent of wall-clock time and comfortably inside retention for this run.
/// The fixture intentionally uses a future date; production retention/sync settings are unchanged.
pub(crate) const FIXTURE_TIME: i64 = 4_102_444_800;
const OLD_RECORDS: usize = 6_000;
const EFFECTS_PER_OPERATION: usize = 32;
const PARALLEL_READS: usize = 4;
const PARALLEL_BATCHES: usize = 8;
const BILLING_BATCH: usize = 64;
const ROTATION_PADDING: usize = 300 * 1024;
const ROTATION_SEED_RECORDS: usize = 52;
const PURPOSES: usize = 4;
const THREADS_PER_ROOT: usize = 4;
const CURRENCIES: [&str; 3] = ["CNY", "EUR", "USD"];

#[derive(Clone, Copy)]
enum Workload {
    History { limit: u32, old_records: usize },
    Billing { count: usize, rotate: bool },
    Effects { active_threads: usize },
    Costs { roots: usize },
    Publication,
    Parallel,
}

pub struct Case {
    pub name: String,
    pub input: Value,
    workload: Workload,
}

/// Stable names and fixed work. Three independent executable runs are coordinated by the caller.
pub fn cases() -> Vec<Case> {
    let mut cases = Vec::new();
    for old_records in [0, OLD_RECORDS] {
        for limit in [0, 100, 3_000] {
            cases.push(Case {
                name: format!("history/recent_{limit}/old_{old_records}"),
                input: json!({"limit": limit, "successfulSamples": HISTORY_SAMPLES,
                    "oldIndexRecords": old_records}),
                workload: Workload::History { limit, old_records },
            });
        }
    }
    for (label, count, rotate) in [
        ("single", 1, false),
        ("batch_64", BILLING_BATCH, false),
        ("segment_rotation_64", BILLING_BATCH, true),
    ] {
        cases.push(Case {
            name: format!("billing/{label}"),
            input: json!({"records": count, "rotation": rotate,
                "paddingBytes": if rotate { ROTATION_PADDING } else { 0 },
                "seedRecords": if rotate { ROTATION_SEED_RECORDS } else { 0 }}),
            workload: Workload::Billing { count, rotate },
        });
    }
    for active_threads in [1, 32] {
        cases.push(Case {
            name: format!("effects/no_billing_change/active_{active_threads}/working_1"),
            input: json!({"activeThreads": active_threads, "workingThreads": 1,
                "effects": EFFECTS_PER_OPERATION}),
            workload: Workload::Effects { active_threads },
        });
    }
    for roots in [1, 32, 256] {
        cases.push(Case {
            name: format!("costs/roots_{roots}/purposes_4/currencies_3"),
            input: json!({"roots": roots, "threadsPerRoot": THREADS_PER_ROOT,
                "purposes": PURPOSES, "currencies": CURRENCIES}),
            workload: Workload::Costs { roots },
        });
    }
    cases.push(Case {
        name: "publication/materialize_3000/roots_32".into(),
        input: json!({"successfulSamples": HISTORY_SAMPLES, "roots": 32,
            "boundary": "explicit materialization through owner adoption and event emission",
            "ownerCachePersistence": "not exercised: no owner revision mutation"}),
        workload: Workload::Publication,
    });
    cases.push(Case {
        name: "parallel/recent_3000/batch_64".into(),
        input: json!({"successfulSamples": HISTORY_SAMPLES, "reads": PARALLEL_READS,
            "writeBatches": PARALLEL_BATCHES, "recordsPerBatch": BILLING_BATCH}),
        workload: Workload::Parallel,
    });
    cases
}

impl Case {
    /// Criterion throughput: completed query operations, billing records, or reliable effects.
    /// Parallel throughput is durable written records per complete concurrent window.
    pub fn throughput_elements(&self) -> u64 {
        match self.workload {
            Workload::History { .. } | Workload::Costs { .. } | Workload::Publication => 1,
            Workload::Billing { count, .. } => count as u64,
            Workload::Effects { .. } => EFFECTS_PER_OPERATION as u64,
            Workload::Parallel => (PARALLEL_BATCHES * BILLING_BATCH) as u64,
        }
    }

    /// Pure reads reuse immutable seeds. Empty effects update only bounded latest checkpoints and
    /// watermarks. Billing/parallel cases always use a fresh fixture so history never drifts.
    pub fn reusable(&self) -> bool {
        matches!(
            self.workload,
            Workload::History { .. }
                | Workload::Effects { .. }
                | Workload::Costs { .. }
                | Workload::Publication
        )
    }

    pub async fn prepare(&self, scratch_root: &Path) -> Result<PreparedCase> {
        ensure!(
            scratch_root.is_dir(),
            "benchmark scratch root must be an explicit existing directory"
        );
        let directory = tempfile::Builder::new()
            .prefix("statistics-case-")
            .tempdir_in(scratch_root)?;
        let fixture = match self.workload {
            Workload::Effects { active_threads } => {
                WriterFixture::open(directory.path(), active_threads)
                    .await
                    .map(|fixture| Fixture::Writer(Box::new(fixture)))
            }
            Workload::Publication => PublicationFixture::open(directory.path())
                .await
                .map(|fixture| Fixture::Publication(Box::new(fixture))),
            _ => {
                async {
                    let calls =
                        CallsStore::prepare(&directory.path().join("calls/calls.sqlite")).await?;
                    calls.start().await;
                    Ok(Fixture::Calls(calls))
                }
                .await
            }
        };
        let fixture = match fixture {
            Ok(fixture) => fixture,
            Err(error) => {
                let preserved = directory.keep();
                return Err(error.context(format!(
                    "benchmark fixture preserved at {}",
                    preserved.display()
                )));
            }
        };
        let mut prepared = PreparedCase {
            directory: Some(directory),
            fixture: Some(fixture),
            workload: self.workload,
            billing_records: Vec::new(),
        };
        if let Err(error) = prepared.seed().await {
            let cleanup = prepared.shutdown().await;
            return Err(error.context(format!("benchmark seed cleanup: {cleanup:?}")));
        }
        Ok(prepared)
    }
}

enum Fixture {
    Calls(CallsStore),
    Writer(Box<WriterFixture>),
    Publication(Box<PublicationFixture>),
}

struct PublicationFixture {
    store: StudioStore,
    owner: ModelPerformanceOwner,
}

impl PublicationFixture {
    async fn open(root: &Path) -> Result<Self> {
        let store = StudioStore::open(root.join("studio/v2/studio.sqlite")).await?;
        let events =
            ProductEventBus::new(store.clone(), ThreadWriteBehindWriter::new(store.clone()));
        let owner =
            ModelPerformanceOwner::new(store.clone(), events, "statistics-benchmark".into());
        Ok(Self { store, owner })
    }

    async fn measure(&self) -> Result<(Duration, Vec<OperationSample>, Value)> {
        let started = Instant::now();
        // Await the real materialization entry, not a mirror projection. This read-only workload
        // does not mutate the owner revision, so it makes no cache-persistence success claim.
        self.owner.initialize_projection().await;
        let elapsed = started.elapsed();
        let snapshot = self.owner.snapshot().await;
        ensure!(
            !snapshot.read_failed && !snapshot.statistics_gap && !snapshot.statistics_pending,
            "benchmark owner did not publish a complete settled projection"
        );
        ensure!(
            snapshot.history.len() == HISTORY_SAMPLES
                && snapshot.history.first().map(|row| row.completed_at)
                    == Some(FIXTURE_TIME + HISTORY_SAMPLES as i64 - 1)
                && snapshot.history.last().map(|row| row.completed_at) == Some(FIXTURE_TIME),
            "benchmark publication changed its retained history"
        );
        let samples: u64 = snapshot.summaries.iter().map(|row| row.sample_count).sum();
        ensure!(
            samples == HISTORY_SAMPLES as u64,
            "benchmark publication lost usable throughput samples"
        );
        let costs = self.owner.published_session_costs().await;
        ensure!(costs.len() == 32, "benchmark publication lost root costs");
        Ok((
            elapsed,
            vec![OperationSample::new(
                "owner_materialize_publish",
                1,
                elapsed,
            )],
            json!({"historyCount": snapshot.history.len(), "usableSamples": samples,
                "rootCostCount": costs.len()}),
        ))
    }
}

pub struct PreparedCase {
    directory: Option<tempfile::TempDir>,
    fixture: Option<Fixture>,
    workload: Workload,
    billing_records: Vec<InferenceBillingRecord>,
}

/// Timings are of individual real operations, never reconstructed from Criterion batch averages.
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationSample {
    pub operation: &'static str,
    pub units: usize,
    pub elapsed_nanos: u64,
}

impl OperationSample {
    fn new(operation: &'static str, units: usize, elapsed: Duration) -> Self {
        Self {
            operation,
            units,
            elapsed_nanos: u64::try_from(elapsed.as_nanos()).unwrap_or(u64::MAX),
        }
    }
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Measurement {
    #[serde(skip)]
    pub elapsed: Duration,
    pub samples: Vec<OperationSample>,
    pub observation: ObservationSnapshot,
    pub storage_io: Option<StorageIo>,
    pub verification: Value,
}

impl PreparedCase {
    fn calls(&self) -> &CallsStore {
        match self.fixture.as_ref().expect("open benchmark fixture") {
            Fixture::Calls(calls) => calls,
            Fixture::Writer(writer) => writer.calls(),
            Fixture::Publication(fixture) => fixture.store.calls(),
        }
    }

    async fn seed(&mut self) -> Result<()> {
        match self.workload {
            Workload::History { old_records, .. } => {
                seed_history(self.calls(), old_records).await?;
            }
            Workload::Billing { count, rotate } => {
                if rotate {
                    let seed: Vec<_> = (0..ROTATION_SEED_RECORDS)
                        .map(|index| billing(index, false, ROTATION_PADDING))
                        .collect();
                    save_billing(self.calls(), &seed).await?;
                }
                self.billing_records = (10_000..10_000 + count)
                    .map(|index| billing(index, false, if rotate { ROTATION_PADDING } else { 0 }))
                    .collect();
            }
            Workload::Costs { roots } => seed_costs(self.calls(), roots).await?,
            Workload::Publication => {
                seed_history(self.calls(), 0).await?;
                seed_costs(self.calls(), 32).await?;
            }
            Workload::Parallel => {
                seed_history(self.calls(), 0).await?;
                self.billing_records = (10_000..10_000 + PARALLEL_BATCHES * BILLING_BATCH)
                    .map(|index| billing(index, true, 0))
                    .collect();
            }
            Workload::Effects { .. } => {}
        }
        self.calls().observation().reset_queue_high_water();
        Ok(())
    }

    pub async fn measure(&mut self) -> Result<Measurement> {
        let observation = self.calls().observation().clone();
        observation.reset_queue_age();
        let before = observation.snapshot();
        let io_before = storage_io::IoSnapshot::read()?;
        let io_started = Instant::now();
        let (elapsed, samples, verification) = match self.workload {
            Workload::History { limit, .. } => {
                let started = Instant::now();
                let rows = self.calls().recent_performance_samples(limit).await?;
                let elapsed = started.elapsed();
                let actual = sample_digest(&rows)?;
                let expected = expected_history_digest(limit)?;
                ensure!(
                    actual == expected,
                    "recent performance sample identity/count changed: {actual} != {expected}"
                );
                (
                    elapsed,
                    vec![OperationSample::new(
                        "history_read",
                        limit as usize,
                        elapsed,
                    )],
                    actual,
                )
            }
            Workload::Billing { count, rotate } => {
                let (elapsed, samples) = save_billing(self.calls(), &self.billing_records).await?;
                let after = observation.snapshot().since(&before);
                if rotate {
                    ensure!(
                        after.counters["jsonl_segment_open"] >= 1,
                        "segment rotation workload did not rotate"
                    );
                }
                (
                    elapsed,
                    samples,
                    json!({"records": count,
                    "durableTicket": self.calls().durable_ticket(), "rotation": rotate}),
                )
            }
            Workload::Effects { active_threads } => {
                let Fixture::Writer(writer) = self.fixture.as_mut().context("open writer")? else {
                    bail!("wrong benchmark fixture");
                };
                let mut samples = Vec::with_capacity(EFFECTS_PER_OPERATION);
                let mut total = Duration::ZERO;
                for _ in 0..EFFECTS_PER_OPERATION {
                    let elapsed = writer.empty_effect().await?;
                    total += elapsed;
                    samples.push(OperationSample::new("reliable_empty_effect", 1, elapsed));
                }
                (
                    total,
                    samples,
                    json!({"effects": EFFECTS_PER_OPERATION,
                    "activeThreads": active_threads, "workingThreads": 1}),
                )
            }
            Workload::Costs { roots } => {
                let started = Instant::now();
                let rows = self.calls().session_cost_rollups().await?;
                let elapsed = started.elapsed();
                let actual = cost_identity(&rows);
                let expected = expected_costs(roots);
                ensure!(
                    actual == expected,
                    "cost rollup values or identities changed"
                );
                (
                    elapsed,
                    vec![OperationSample::new("cost_rollup_read", roots, elapsed)],
                    json!({"roots": roots, "sha256": digest(&actual)?}),
                )
            }
            Workload::Publication => {
                let Some(Fixture::Publication(fixture)) = self.fixture.as_ref() else {
                    bail!("wrong publication benchmark fixture");
                };
                fixture.measure().await?
            }
            Workload::Parallel => parallel(self.calls(), &self.billing_records).await?,
        };
        let io_elapsed = io_started.elapsed();
        let io_after = storage_io::IoSnapshot::read()?;
        Ok(Measurement {
            elapsed,
            samples,
            observation: observation.snapshot().since(&before),
            storage_io: storage_io::measure(io_before, io_after, io_elapsed)?,
            verification,
        })
    }

    async fn shutdown(&mut self) -> Result<()> {
        match self.fixture.take() {
            Some(Fixture::Calls(calls)) => calls.close().await,
            Some(Fixture::Writer(writer)) => writer.close().await,
            Some(Fixture::Publication(fixture)) => {
                fixture.owner.close().await?;
                fixture.store.close().await
            }
            None => Ok(()),
        }
    }

    pub async fn close(mut self) -> Result<()> {
        self.shutdown().await?;
        if let Some(directory) = self.directory.take() {
            directory
                .close()
                .context("remove owned benchmark fixture")?;
        }
        Ok(())
    }
}

impl Drop for PreparedCase {
    fn drop(&mut self) {
        if let Some(directory) = self.directory.take() {
            let preserved = directory.keep();
            eprintln!(
                "unfinished benchmark fixture preserved at {}",
                preserved.display()
            );
        }
    }
}

pub(crate) async fn wait_calls(calls: &CallsStore, target: u64) -> Result<()> {
    let mut durable = calls.subscribe_durable_ticket();
    tokio::time::timeout(Duration::from_secs(30), async {
        while *durable.borrow_and_update() < target {
            durable.changed().await?;
        }
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("benchmark calls durability deadline exceeded")??;
    ensure!(
        !calls.statistics_gap() && calls.last_error().is_none(),
        "benchmark calls writer rejected/lost work: {:?}",
        calls.last_error()
    );
    Ok(())
}

fn billing(index: usize, old: bool, padding: usize) -> InferenceBillingRecord {
    let output = 64 + ((index as u64 + SEED) % 128);
    InferenceBillingRecord {
        inference_id: format!("bench-{SEED}-{index:08}"),
        purpose: Some(format!("purpose-{}", index % PURPOSES)),
        account_id: format!("account-{}", index % 4),
        account_display_name: Some(if padding == 0 {
            "Benchmark".into()
        } else {
            "x".repeat(padding)
        }),
        model_id: Some("bench-model".into()),
        model_observation: Some(InferenceModelObservation {
            configured_model: "bench-model".into(),
            sent_model: "bench-wire-model".into(),
            reported_model: Some("bench-wire-model".into()),
        }),
        effort: Some("medium".into()),
        context_window: Some(32_768),
        accounting: InferenceAccounting {
            usage: UsageReport {
                input_tokens: Some(256),
                output_tokens: Some(output),
                total_tokens: Some(256 + output),
                ..Default::default()
            },
            pricing: PricingOutcome::Estimated {
                cost: RuntimeCostAmount {
                    currency: "USD".into(),
                    amount: 1.0 / 1024.0,
                },
                cache_savings: None,
            },
            price_snapshot: None,
            request_started_at: Some(FIXTURE_TIME),
        },
        prompt_generation: None,
        prompt_cache_policy: None,
        prefix_changed_reason: None,
        orchestration: Default::default(),
        timing: Some(InferenceTiming {
            ttft_millis: Some(20),
            decode_millis: Some(80),
            response_millis: 100,
            first_output_source: FirstOutputSource::Incremental,
        }),
        recorded_at: if old {
            FIXTURE_TIME - 100_000 + index as i64
        } else {
            FIXTURE_TIME + index as i64
        },
    }
}

async fn seed_history(calls: &CallsStore, old_records: usize) -> Result<()> {
    for chunk in (0..old_records).collect::<Vec<_>>().chunks(BILLING_BATCH) {
        let records: Vec<_> = chunk
            .iter()
            .map(|index| billing(*index + HISTORY_SAMPLES, true, 0))
            .collect();
        save_billing(calls, &records).await?;
    }
    for chunk in (0..HISTORY_SAMPLES)
        .collect::<Vec<_>>()
        .chunks(BILLING_BATCH)
    {
        let records: Vec<_> = chunk
            .iter()
            .map(|index| billing(*index, false, 0))
            .collect();
        save_billing(calls, &records).await?;
    }
    Ok(())
}

/// Timed from immediately before admission to the production post-commit durable ticket.
/// Per-record elapsed values are actual admission/barrier observations, not batch/64 estimates.
async fn save_billing(
    calls: &CallsStore,
    records: &[InferenceBillingRecord],
) -> Result<(Duration, Vec<OperationSample>)> {
    let mut tickets = Vec::with_capacity(records.len());
    let mut samples = Vec::with_capacity(records.len() + 1);
    let started = Instant::now();
    for record in records {
        let admitted = Instant::now();
        let ticket = calls.admit_billing(
            "bench-root",
            "bench-billing",
            record,
            CallStatus::Committed,
            CallRetention::Turn,
        )?;
        tickets.push((ticket, admitted));
    }
    for (ticket, admitted) in tickets {
        wait_calls(calls, ticket).await?;
        samples.push(OperationSample::new(
            "billing_record_durable",
            1,
            admitted.elapsed(),
        ));
    }
    let elapsed = started.elapsed();
    samples.push(OperationSample::new(
        "billing_batch_durable",
        records.len(),
        elapsed,
    ));
    Ok((elapsed, samples))
}

fn sample_identity(rows: &[PerformanceSampleRow]) -> Value {
    Value::Array(
        rows.iter()
            .map(|row| {
                json!([
                    row.completed_at,
                    row.account_id,
                    row.account_display_name,
                    row.model_id,
                    row.sent_model,
                    row.reported_model,
                    row.effort,
                    row.completion_tokens,
                    row.ttft_millis,
                    row.decode_millis,
                    row.response_millis,
                    row.has_throughput_sample
                ])
            })
            .collect(),
    )
}

fn sample_digest(rows: &[PerformanceSampleRow]) -> Result<Value> {
    Ok(json!({"count": rows.len(), "sha256": digest(&sample_identity(rows))?}))
}

fn expected_history_digest(limit: u32) -> Result<Value> {
    let rows = Value::Array(
        (0..HISTORY_SAMPLES)
            .rev()
            .take(limit as usize)
            .map(|index| {
                json!([
                    FIXTURE_TIME + index as i64,
                    format!("account-{}", index % 4),
                    "Benchmark",
                    "bench-model",
                    "bench-wire-model",
                    "bench-wire-model",
                    "medium",
                    64 + ((index as u64 + SEED) % 128),
                    20,
                    80,
                    100,
                    true
                ])
            })
            .collect(),
    );
    Ok(json!({"count": (limit as usize).min(HISTORY_SAMPLES), "sha256": digest(&rows)?}))
}

fn digest(value: &Value) -> Result<String> {
    Ok(hex::encode(Sha256::digest(serde_json::to_vec(value)?)))
}

fn fixture_cost(root: usize, thread: usize, purpose: usize, currency: usize) -> f64 {
    ((root + 1) * (thread + 1) * (purpose + 1) * (currency + 1)) as f64 / 1024.0
}

async fn seed_costs(calls: &CallsStore, roots: usize) -> Result<()> {
    for root in 0..roots {
        for thread in 0..THREADS_PER_ROOT {
            calls.replace_session_usage(SessionUsageProjection {
                root_thread_id: format!("root-{root:06}"),
                thread_id: format!("root-{root:06}-thread-{thread}"),
                revision: 1,
                has_unpriced_usage: false,
                purpose_costs: (0..PURPOSES)
                    .map(|purpose| PurposeUsageProjection {
                        purpose: Some(format!("purpose-{purpose}")),
                        estimated_costs: CURRENCIES
                            .iter()
                            .enumerate()
                            .map(|(currency, name)| RuntimeCostAmount {
                                currency: (*name).into(),
                                amount: fixture_cost(root, thread, purpose, currency),
                            })
                            .collect(),
                    })
                    .collect(),
            })?;
        }
        if (root + 1) % 16 == 0 {
            wait_calls(calls, calls.admitted_ticket()).await?;
        }
    }
    wait_calls(calls, calls.admitted_ticket()).await
}

fn cost_identity(rows: &[SessionCostRollup]) -> Value {
    Value::Array(
        rows.iter()
            .map(|row| {
                json!([
                    row.root_thread_id,
                    row.has_unpriced_usage,
                    row.estimated_costs,
                    row.purpose_costs
                        .iter()
                        .map(|purpose| json!([
                            purpose.purpose,
                            purpose.has_unpriced_usage,
                            purpose.estimated_costs
                        ]))
                        .collect::<Vec<_>>()
                ])
            })
            .collect(),
    )
}

fn expected_costs(roots: usize) -> Value {
    // Four threads sum to 10; four purposes sum to 10. Exact binary fractions avoid epsilon masks.
    Value::Array(
        (0..roots)
            .map(|root| {
                json!([
                    format!("root-{root:06}"),
                    false,
                    CURRENCIES
                        .iter()
                        .enumerate()
                        .map(|(currency, name)| RuntimeCostAmount {
                            currency: (*name).into(),
                            amount: ((root + 1) * 100 * (currency + 1)) as f64 / 1024.0,
                        })
                        .collect::<Vec<_>>(),
                    (0..PURPOSES)
                        .map(|purpose| json!([
                            format!("purpose-{purpose}"),
                            false,
                            CURRENCIES
                                .iter()
                                .enumerate()
                                .map(|(currency, name)| RuntimeCostAmount {
                                    currency: (*name).into(),
                                    amount: ((root + 1) * 10 * (purpose + 1) * (currency + 1))
                                        as f64
                                        / 1024.0,
                                })
                                .collect::<Vec<_>>()
                        ]))
                        .collect::<Vec<_>>()
                ])
            })
            .collect(),
    )
}

async fn parallel(
    calls: &CallsStore,
    records: &[InferenceBillingRecord],
) -> Result<(Duration, Vec<OperationSample>, Value)> {
    let read_store = calls.clone();
    let write_store = calls.clone();
    let records = records.to_vec();
    let mut leases = calls.observation().subscribe_reads();
    drop(leases.borrow_and_update());
    let started = Instant::now();
    let reader = tokio::spawn(async move {
        let mut samples = Vec::with_capacity(PARALLEL_READS);
        let expected = expected_history_digest(3_000)?;
        for _ in 0..PARALLEL_READS {
            let started = Instant::now();
            let rows = read_store.recent_performance_samples(3_000).await?;
            let elapsed = started.elapsed();
            ensure!(
                sample_digest(&rows)? == expected,
                "parallel read changed the latest sample identity"
            );
            samples.push(OperationSample::new(
                "parallel_history_read",
                HISTORY_SAMPLES,
                elapsed,
            ));
        }
        Ok::<_, anyhow::Error>(samples)
    });
    // Observe a real query entry, not a requirement that the old JSONL locking backend survives.
    // There are no sleeps, fake locks, or gates in the production read.
    if !matches!(
        tokio::time::timeout(Duration::from_secs(30), leases.changed()).await,
        Ok(Ok(()))
    ) {
        reader.abort();
        let _ = reader.await;
        bail!("parallel benchmark did not observe the real read entry");
    }
    let writer = tokio::spawn(async move {
        let mut samples = Vec::new();
        let started = Instant::now();
        for batch in records.chunks(BILLING_BATCH) {
            let (_, batch_samples) = save_billing(&write_store, batch).await?;
            samples.extend(batch_samples);
        }
        Ok::<_, anyhow::Error>((samples, started.elapsed()))
    });
    // Always join both workers, including when either side fails.
    let (read_result, write_result) = tokio::join!(reader, writer);
    let elapsed = started.elapsed();
    let mut samples = read_result.context("parallel reader task")??;
    let (write_samples, write_elapsed) = write_result.context("parallel writer task")??;
    samples.extend(write_samples);
    let written = PARALLEL_BATCHES * BILLING_BATCH;
    Ok((
        elapsed,
        samples,
        json!({
            "readOperations": PARALLEL_READS, "writtenRecords": written,
            "writerElapsedNanos": u64::try_from(write_elapsed.as_nanos())?,
            "writerRecordsPerSecond": written as f64 / write_elapsed.as_secs_f64(),
            "expectedRead": expected_history_digest(3_000)?
        }),
    ))
}
