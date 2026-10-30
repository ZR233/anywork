//! Explicit disk benchmark; see benches/README.md for required directories and run metadata.

use std::collections::BTreeMap;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use criterion::{Criterion, Throughput};
use pl_studio_runtime::benchmark::{
    self, Case, Measurement, PreparedCase, SEED, TOKIO_WORKER_THREADS,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use tokio::runtime::Runtime;

const WARMUP_SECONDS: u64 = 3;
const MEASUREMENT_SECONDS: u64 = 5;
const CRITERION_SAMPLES: usize = 20;
const BOOTSTRAP_RESAMPLES: usize = 100_000;
const DISTRIBUTION_OPERATIONS: usize = 32;
const BLOCKING_THREADS: usize = 4;
const NOISE_THRESHOLD: f64 = 0.05;
const CONFIDENCE_LEVEL: f64 = 0.95;

#[derive(Clone, Copy)]
struct RunProfile {
    name: &'static str,
    warmup: Duration,
    measurement: Duration,
    samples: usize,
    distribution_operations: usize,
}

impl RunProfile {
    fn read() -> Result<Self> {
        let name = match std::env::var("PL_STATISTICS_BENCH_PROFILE") {
            Ok(name) => name,
            Err(std::env::VarError::NotPresent) => "standard".to_owned(),
            Err(error) => return Err(error).context("read statistics benchmark profile"),
        };
        match name.as_str() {
            "standard" => Ok(Self {
                name: "standard",
                warmup: Duration::from_secs(WARMUP_SECONDS),
                measurement: Duration::from_secs(MEASUREMENT_SECONDS),
                samples: CRITERION_SAMPLES,
                distribution_operations: DISTRIBUTION_OPERATIONS,
            }),
            "diagnostic" => Ok(Self {
                name: "diagnostic",
                warmup: Duration::from_millis(250),
                measurement: Duration::from_millis(500),
                samples: 10,
                distribution_operations: 4,
            }),
            _ => bail!("unknown statistics benchmark profile: {name}"),
        }
    }
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct RunMetadata {
    run_label: String,
    source_revision: String,
    source_tree_identity: String,
    rustc: String,
    machine: String,
    filesystem: String,
    optimization_profile: String,
}

impl RunMetadata {
    fn read() -> Result<Self> {
        let path = required_path("PL_STATISTICS_BENCH_METADATA_JSON")?;
        let metadata: Self = serde_json::from_slice(&std::fs::read(&path)?)
            .context("parse benchmark run metadata")?;
        for (name, value) in [
            ("runLabel", &metadata.run_label),
            ("sourceRevision", &metadata.source_revision),
            ("sourceTreeIdentity", &metadata.source_tree_identity),
            ("rustc", &metadata.rustc),
            ("machine", &metadata.machine),
            ("filesystem", &metadata.filesystem),
            ("optimizationProfile", &metadata.optimization_profile),
        ] {
            ensure!(
                !value.trim().is_empty(),
                "benchmark metadata {name} must not be empty"
            );
        }
        Ok(metadata)
    }
}

struct Artifacts {
    writer: BufWriter<File>,
    path: PathBuf,
}

impl Artifacts {
    fn create(root: &Path) -> Result<Self> {
        let file = tempfile::Builder::new()
            .prefix("statistics-pipeline-")
            .suffix(".jsonl")
            .tempfile_in(root)?;
        // create_new identity, retained even on errors; never overwrite an older run.
        let (file, path) = file.keep().context("retain benchmark artifacts")?;
        Ok(Self {
            writer: BufWriter::new(file),
            path,
        })
    }

    fn record(&mut self, value: impl Serialize) -> Result<()> {
        serde_json::to_writer(&mut self.writer, &value)?;
        self.writer.write_all(b"\n")?;
        Ok(())
    }

    fn flush(&mut self) -> Result<()> {
        self.writer.flush()?;
        self.writer.get_ref().sync_all()?;
        Ok(())
    }
}

fn required_path(variable: &str) -> Result<PathBuf> {
    let value = std::env::var_os(variable).with_context(|| {
        format!("{variable} must explicitly name a caller-owned path; no default is used")
    })?;
    ensure!(!value.is_empty(), "{variable} must not be empty");
    Ok(PathBuf::from(value))
}

fn required_directory(variable: &str) -> Result<PathBuf> {
    let path = required_path(variable)?;
    ensure!(path.is_dir(), "{variable} must name an existing directory");
    std::fs::canonicalize(path).context("canonicalize explicit benchmark directory")
}

fn measure_one(
    runtime: &Runtime,
    case: &Case,
    reusable: &mut Option<PreparedCase>,
    scratch: &Path,
) -> Result<Measurement> {
    if case.reusable() {
        if reusable.is_none() {
            *reusable = Some(runtime.block_on(case.prepare(scratch))?);
        }
        runtime.block_on(
            reusable
                .as_mut()
                .context("prepared reusable case")?
                .measure(),
        )
    } else {
        let mut fixture = runtime.block_on(case.prepare(scratch))?;
        // On failure Drop preserves the owned directory; main drops the runtime before returning.
        let measurement = runtime.block_on(fixture.measure())?;
        runtime.block_on(fixture.close())?;
        Ok(measurement)
    }
}

fn execute(
    runtime: &Runtime,
    scratch: &Path,
    artifacts: &mut Artifacts,
    profile: RunProfile,
) -> Result<()> {
    ensure!(
        !std::env::args().any(|arg| arg == "--test"
            || arg == "--profile-time"
            || arg.starts_with("--profile-time=")),
        "statistics_pipeline requires actual Criterion sampling, not test/profile mode"
    );
    // Preserve Criterion's own output selection and baseline/filter CLI. Frozen statistical
    // settings are applied last, so CLI cannot silently change the comparison contract.
    let mut criterion = Criterion::default()
        .configure_from_args()
        .warm_up_time(profile.warmup)
        .measurement_time(profile.measurement)
        .sample_size(profile.samples)
        .nresamples(BOOTSTRAP_RESAMPLES)
        .noise_threshold(NOISE_THRESHOLD)
        .confidence_level(CONFIDENCE_LEVEL);
    let mut completed = 0;
    let mut group = criterion.benchmark_group("statistics_pipeline");
    for case in benchmark::cases() {
        let mut reusable = None;
        let mut ran = false;
        let mut invocation = 0u64;
        group.throughput(Throughput::Elements(case.throughput_elements()));
        group.bench_function(&case.name, |bencher| {
            bencher.iter_custom(|iterations| {
                ran = iterations > 0;
                invocation += 1;
                let mut total = Duration::ZERO;
                let mut counts = BTreeMap::<String, u64>::new();
                let mut queue_mutations = 0;
                let mut queue_bytes = 0;
                for _ in 0..iterations {
                    let result = measure_one(runtime, &case, &mut reusable, scratch)
                        .expect("real statistics benchmark operation failed");
                    total += result.elapsed;
                    for (name, count) in result.observation.counters {
                        *counts.entry(name).or_default() += count;
                    }
                    queue_mutations =
                        queue_mutations.max(result.observation.queue_high_water_mutations);
                    queue_bytes = queue_bytes.max(result.observation.queue_high_water_bytes);
                }
                // Criterion does not expose whether iter_custom was called for calibration,
                // warmup, or measurement. These are explicitly NOT the percentile population.
                artifacts.record(json!({
                    "kind": "criterionInvocation", "case": case.name, "input": case.input,
                    "invocation": invocation, "iterations": iterations,
                    "throughputElementsPerIteration": case.throughput_elements(),
                    "measuredNanos": total.as_nanos().to_string(), "counters": counts,
                    "queueHighWaterMutations": queue_mutations, "queueHighWaterBytes": queue_bytes,
                    "phase": "criterionUnspecified"
                })).expect("write Criterion operation counts");
                total
            });
        });
        if ran {
            // Separate fixed-size pass after Criterion warmup/measurement. Every raw duration is
            // an actual operation; no Criterion per-batch mean enters the p50/p95 calculation.
            let mut durations = BTreeMap::<(String, usize), Vec<u64>>::new();
            for index in 0..profile.distribution_operations {
                let result = measure_one(runtime, &case, &mut reusable, scratch)?;
                for sample in &result.samples {
                    durations
                        .entry((sample.operation.into(), sample.units))
                        .or_default()
                        .push(sample.elapsed_nanos);
                }
                artifacts.record(json!({
                    "kind": "operationDistribution", "phase": "postWarmup",
                    "case": case.name, "input": case.input, "index": index,
                    "measuredNanos": result.elapsed.as_nanos().to_string(), "measurement": result
                }))?;
            }
            for ((operation, units), mut values) in durations {
                values.sort_unstable();
                let nearest_rank =
                    |percent: usize| values[(values.len() * percent).div_ceil(100) - 1];
                artifacts.record(json!({
                    "kind": "operationSummary", "phase": "postWarmup", "case": case.name,
                    "operation": operation, "units": units, "sampleCount": values.len(),
                    "quantileMethod": "nearestRank", "p50Nanos": nearest_rank(50),
                    "p95Nanos": nearest_rank(95),
                    "minimumNanos": values[0], "maximumNanos": values[values.len() - 1]
                }))?;
            }
            completed += 1;
        }
        if let Some(fixture) = reusable {
            runtime.block_on(fixture.close())?;
        }
        artifacts.flush()?;
    }
    group.finish();
    criterion.final_summary();
    if std::env::args().any(|arg| arg == "--list") {
        artifacts.record(json!({"kind": "listed", "executedCases": completed}))?;
        return artifacts.flush();
    }
    ensure!(
        completed > 0,
        "benchmark selector executed zero cases; no sampling evidence was produced"
    );
    artifacts.record(json!({"kind": "completed", "executedCases": completed}))?;
    artifacts.flush()?;
    Ok(())
}

fn run() -> Result<()> {
    let profile = RunProfile::read()?;
    let scratch = required_directory("PL_STATISTICS_BENCH_SCRATCH_ROOT")?;
    let artifact_root = required_directory("PL_STATISTICS_BENCH_ARTIFACTS_DIR")?;
    let metadata = RunMetadata::read()?;
    let run = tempfile::Builder::new()
        .prefix("statistics-run-")
        .tempdir_in(&scratch)?;
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(TOKIO_WORKER_THREADS)
        .max_blocking_threads(BLOCKING_THREADS)
        .thread_name("statistics-bench")
        .enable_all()
        .build()?;
    let mut artifacts = Artifacts::create(&artifact_root)?;
    let lockfile = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Cargo.lock");
    artifacts.record(json!({
        "kind": "run", "contractVersion": 1, "metadata": metadata,
        "lockfileSha256": hex::encode(Sha256::digest(std::fs::read(lockfile)?)),
        "seed": SEED, "tokioWorkerThreads": TOKIO_WORKER_THREADS, "blockingThreads": BLOCKING_THREADS,
        "os": std::env::consts::OS, "architecture": std::env::consts::ARCH,
        "availableParallelism": std::thread::available_parallelism()?.get(),
        "profile": profile.name,
        "warmupSeconds": profile.warmup.as_secs_f64(),
        "measurementSeconds": profile.measurement.as_secs_f64(),
        "criterionSampleSize": profile.samples, "bootstrapResamples": BOOTSTRAP_RESAMPLES,
        "distributionOperations": profile.distribution_operations,
        "noiseThreshold": NOISE_THRESHOLD, "confidenceLevel": CONFIDENCE_LEVEL,
        "sqlite": {"journal": "WAL", "synchronous": "FULL", "callsConnections": 2},
        "jsonlDurability": "production durability policy, not overridden; actual flush/sync counts recorded",
        "criterionOutput": "unchanged; consult the Criterion invocation output",
        "cases": benchmark::cases().iter().map(|case| json!({
            "name": format!("statistics_pipeline/{}", case.name), "input": case.input,
            "throughputElementsPerIteration": case.throughput_elements()
        })).collect::<Vec<_>>()
    }))?;
    artifacts.flush()?;
    eprintln!("statistics raw samples: {}", artifacts.path.display());
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        execute(&runtime, run.path(), &mut artifacts, profile)
    }));
    // No fixture directory can be deleted while a panic-abandoned task is still running.
    drop(runtime);
    match outcome {
        Ok(Ok(())) => {
            run.close()
                .context("remove owned benchmark run directory")?;
            Ok(())
        }
        failure => {
            let preserved = run.keep();
            let _ = artifacts.flush();
            match failure {
                Ok(Err(error)) => Err(error.context(format!(
                    "benchmark data preserved at {}",
                    preserved.display()
                ))),
                Err(payload) => {
                    let message = payload
                        .downcast_ref::<String>()
                        .map(String::as_str)
                        .or_else(|| payload.downcast_ref::<&str>().copied())
                        .unwrap_or("non-string panic");
                    bail!(
                        "benchmark failed: {message}; data preserved at {}",
                        preserved.display()
                    )
                }
                Ok(Ok(())) => unreachable!(),
            }
        }
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error:#}");
        std::process::exit(1);
    }
}
