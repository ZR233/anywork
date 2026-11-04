use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub(super) const SAMPLES: usize = 20;
const TARGET_MICROS: u64 = 500_000;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Span {
    pub selection_id: u64,
    pub generation: u64,
    pub item_id: String,
    pub selection_started_micros: u64,
    pub layout_completed_micros: u64,
    pub elapsed_micros: u64,
}

impl Span {
    fn validate(&self) -> Result<()> {
        ensure!(!self.item_id.is_empty(), "empty content witness");
        ensure!(
            self.layout_completed_micros
                .checked_sub(self.selection_started_micros)
                == Some(self.elapsed_micros),
            "owner span duration does not match its monotonic endpoints"
        );
        Ok(())
    }

    fn follows(&self, previous: &Self) -> Result<()> {
        ensure!(
            self.selection_id > previous.selection_id
                && self.generation > previous.generation
                && self.selection_started_micros >= previous.layout_completed_micros,
            "switch reused or reordered a selection/generation"
        );
        Ok(())
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
enum Status {
    NotExecuted,
    Failed,
    Observed,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Sample {
    index: usize,
    status: Status,
    thread_id: Option<String>,
    owner_span: Option<Span>,
    via_other_thread: Option<Span>,
    failure: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Group {
    pub mode: &'static str,
    pub requested_samples: usize,
    pub samples: Vec<Sample>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Summary {
    requested: usize,
    success: usize,
    failed: usize,
    not_executed: usize,
    p50_micros: Option<f64>,
    p95_micros: Option<u64>,
    max_micros: Option<u64>,
    target_micros: u64,
    pub meets_target: bool,
}

impl Group {
    pub fn new(mode: &'static str) -> Self {
        Self {
            mode,
            requested_samples: SAMPLES,
            samples: (1..=SAMPLES)
                .map(|index| Sample {
                    index,
                    status: Status::NotExecuted,
                    thread_id: None,
                    owner_span: None,
                    via_other_thread: None,
                    failure: None,
                })
                .collect(),
        }
    }

    pub fn fail_unexecuted(&mut self, offset: usize, thread: &str, failure: String) {
        let sample = &mut self.samples[offset];
        if sample.status == Status::NotExecuted {
            sample.status = Status::Failed;
            sample.thread_id = Some(thread.to_owned());
            sample.failure = Some(failure);
        }
    }

    /// Ingest even a nonzero probe's partial report before propagating its error.
    /// Slots absent from the CLI report remain explicitly not executed.
    pub fn ingest(
        &mut self,
        raw: &Value,
        offset: usize,
        requested: usize,
        thread: &str,
    ) -> Result<()> {
        ensure!(
            raw["schemaVersion"] == 1
                && raw["mode"] == self.mode
                && raw["requestedSamples"].as_u64() == Some(requested as u64),
            "probe header does not match the requested run"
        );
        let rows = raw["samples"].as_array().context("missing probe samples")?;
        ensure!(
            rows.len() <= requested && offset + requested <= self.samples.len(),
            "probe returned excess samples"
        );
        let mut previous: Option<Span> = None;
        let mut errors = Vec::new();
        let mut saw_failure = false;
        for (index, row) in rows.iter().enumerate() {
            let slot = offset + index;
            let parsed = (|| -> Result<(Span, Option<Span>)> {
                ensure!(
                    row["index"].as_u64() == Some((index + 1) as u64) && row["threadId"] == thread,
                    "probe sample index/thread mismatch"
                );
                ensure!(!saw_failure, "sample appears after a failed sample");
                ensure!(
                    row["status"] == "observed" && row["failure"].is_null(),
                    "sample failed: {}",
                    row["failure"]
                );
                let span: Span = serde_json::from_value(row.clone())?;
                span.validate()?;
                let via = if self.mode == "switch" {
                    let via: Span = serde_json::from_value(row["viaOtherThread"].clone())?;
                    via.validate()?;
                    if let Some(previous) = &previous {
                        via.follows(previous)?;
                    }
                    span.follows(&via)?;
                    Some(via)
                } else {
                    ensure!(row["viaOtherThread"].is_null(), "cold sample has a switch");
                    None
                };
                Ok((span, via))
            })();
            match parsed {
                Ok((span, via)) => {
                    previous = Some(span.clone());
                    self.samples[slot] = Sample {
                        index: slot + 1,
                        status: Status::Observed,
                        thread_id: Some(thread.to_owned()),
                        owner_span: Some(span),
                        via_other_thread: via,
                        failure: None,
                    };
                }
                Err(error) => {
                    saw_failure = true;
                    let failure = format!("sample {}: {error:#}", slot + 1);
                    self.fail_unexecuted(slot, thread, failure.clone());
                    errors.push(failure);
                }
            }
        }
        if raw["cleanup"]["driverClosed"] != true || raw["cleanup"]["vmServiceClosed"] != true {
            errors.push(format!(
                "probe connection cleanup failed: {}",
                raw["cleanup"]
            ));
        }
        if raw["completed"] != true || !raw["failure"].is_null() || rows.len() != requested {
            errors.push(format!(
                "probe incomplete: completed={}, failure={}, returned={}/{}",
                raw["completed"],
                raw["failure"],
                rows.len(),
                requested
            ));
        }
        ensure!(errors.is_empty(), "{}", errors.join("\n"));
        Ok(())
    }

    pub fn summary(&self) -> Summary {
        let mut values: Vec<u64> = self
            .samples
            .iter()
            .filter_map(|sample| sample.owner_span.as_ref().map(|span| span.elapsed_micros))
            .collect();
        values.sort_unstable();
        let count = values.len();
        let p50 = match count {
            0 => None,
            n if n % 2 == 0 => Some(values[n / 2 - 1] as f64 / 2.0 + values[n / 2] as f64 / 2.0),
            n => Some(values[n / 2] as f64),
        };
        let p95 = (count > 0).then(|| values[(95 * count).div_ceil(100) - 1]);
        Summary {
            requested: self.requested_samples,
            success: count,
            failed: self
                .samples
                .iter()
                .filter(|s| s.status == Status::Failed)
                .count(),
            not_executed: self
                .samples
                .iter()
                .filter(|s| s.status == Status::NotExecuted)
                .count(),
            p50_micros: p50,
            p95_micros: p95,
            max_micros: values.last().copied(),
            target_micros: TARGET_MICROS,
            meets_target: count == self.requested_samples
                && p95.is_some_and(|value| value <= TARGET_MICROS),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn row(index: usize, elapsed: u64) -> Value {
        json!({
            "index": index, "status": "observed", "threadId": "A",
            "selectionId": index, "generation": index, "itemId": "content",
            "selectionStartedMicros": 10, "layoutCompletedMicros": 10 + elapsed,
            "elapsedMicros": elapsed, "viaOtherThread": null
        })
    }

    fn probe(rows: Vec<Value>, requested: usize, completed: bool) -> Value {
        json!({
            "schemaVersion": 1, "mode": "cold", "requestedSamples": requested,
            "completed": completed, "samples": rows,
            "cleanup": {"driverClosed": true, "vmServiceClosed": true}
        })
    }

    #[test]
    fn nearest_rank_p95_and_median_keep_outlier_and_require_all_twenty() {
        let mut group = Group::new("cold");
        for offset in 0..19 {
            group
                .ingest(
                    &probe(vec![row(1, (offset as u64 + 1) * 1000)], 1, true),
                    offset,
                    1,
                    "A",
                )
                .unwrap();
        }
        assert!(!group.summary().meets_target);
        group
            .ingest(&probe(vec![row(1, 900_000)], 1, true), 19, 1, "A")
            .unwrap();
        let summary = group.summary();
        assert_eq!(summary.p50_micros, Some(10_500.0));
        assert_eq!(summary.p95_micros, Some(19_000));
        assert_eq!(summary.max_micros, Some(900_000));
        assert!(summary.meets_target);
    }

    #[test]
    fn partial_failure_preserves_missing_slots_and_rejects_forged_duration() {
        let mut group = Group::new("cold");
        group
            .ingest(&probe(vec![row(1, 40)], 1, true), 0, 1, "A")
            .unwrap();
        let mut invalid = row(1, 50);
        invalid["elapsedMicros"] = json!(0);
        assert!(
            group
                .ingest(&probe(vec![invalid], 1, false), 1, 1, "A")
                .is_err()
        );
        let summary = group.summary();
        assert_eq!(
            (summary.success, summary.failed, summary.not_executed),
            (1, 1, 18)
        );
        assert_eq!(summary.p95_micros, Some(40));
        assert!(!summary.meets_target);
    }

    #[test]
    fn switch_requires_a_fresh_b_then_a_and_preserves_connection_cleanup_failure() {
        let mut first = row(1, 40);
        first["selectionId"] = json!(4);
        first["generation"] = json!(8);
        first["selectionStartedMicros"] = json!(100);
        first["layoutCompletedMicros"] = json!(140);
        first["viaOtherThread"] = json!({
            "selectionId": 3, "generation": 7, "itemId": "B-content",
            "selectionStartedMicros": 10, "layoutCompletedMicros": 50, "elapsedMicros": 40,
        });
        let mut raw = probe(vec![first.clone()], 1, true);
        raw["mode"] = json!("switch");
        let mut group = Group::new("switch");
        group.ingest(&raw, 0, 1, "A").unwrap();
        assert_eq!(group.summary().success, 1);

        // The next A cannot reuse the already observed B owner.
        let mut repeated = first;
        repeated["index"] = json!(2);
        raw["requestedSamples"] = json!(20);
        raw["samples"].as_array_mut().unwrap().push(repeated);
        let mut group = Group::new("switch");
        assert!(group.ingest(&raw, 0, 20, "A").is_err());
        assert_eq!(group.summary().failed, 1);

        raw["requestedSamples"] = json!(1);
        raw["samples"].as_array_mut().unwrap().truncate(1);
        raw["cleanup"]["driverClosed"] = json!(false);
        let mut group = Group::new("switch");
        assert!(group.ingest(&raw, 0, 1, "A").is_err());
        assert_eq!(group.summary().success, 1);
        assert!(!group.summary().meets_target);
    }
}
