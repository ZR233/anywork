//! Explicit file decisions only; stale/error results are retained and never automatically retried.
use super::super::evidence::{self, Evidence};
use anyhow::{Context, Result};
use pl_studio_runtime::StudioRuntime;
use serde::{Deserialize, Serialize};
use std::{collections::BTreeSet, io::Read};

const MAX_DECISIONS: usize = 256;
const MAX_DECISION_BYTES: u64 = 128 * 1024;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Decision {
    operation_id: String,
    interaction_id: String,
    expected_revision: u64,
    resolution: pl_protocol::InteractionResolution,
}

#[derive(Default)]
pub(super) struct Decisions {
    // A filename is a single delivery: replacements/edits do not silently resubmit it.
    processed: BTreeSet<std::ffi::OsString>,
    applied: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DecisionReceipt<T> {
    file_name: String,
    input_bytes: u64,
    input_sha256: Option<String>,
    operation_id: Option<String>,
    interaction_id: Option<String>,
    expected_revision: Option<u64>,
    receipt: Option<T>,
    error: Option<String>,
}

impl Decisions {
    pub fn applied_this_tick(&self) -> bool {
        self.applied
    }

    pub async fn process(
        &mut self,
        runtime: &StudioRuntime,
        root: &str,
        evidence: &Evidence,
        scene: &super::super::Boundary,
        manifest: &mut evidence::Manifest,
    ) -> Result<()> {
        scene.check()?;
        self.applied = false;
        let directory = evidence.root().join("decisions");
        let metadata = std::fs::symlink_metadata(&directory)?;
        anyhow::ensure!(
            metadata.is_dir() && !metadata.file_type().is_symlink(),
            "decisions directory replaced or symlinked"
        );
        let mut files = Vec::new();
        for entry in std::fs::read_dir(directory)? {
            let entry = entry?;
            if entry
                .path()
                .extension()
                .is_some_and(|extension| extension == "json")
                && !self.processed.contains(&entry.file_name())
            {
                evidence.check_limit(
                    files.len() + self.processed.len() < MAX_DECISIONS,
                    "decision budget exceeded (256)",
                )?;
                files.push(entry);
            }
        }
        files.sort_by_key(|entry| entry.file_name());
        for entry in files {
            scene.check()?;
            let index = self.processed.len();
            self.processed.insert(entry.file_name());
            let mut receipt = DecisionReceipt {
                file_name: entry.file_name().to_string_lossy().into_owned(),
                input_bytes: 0,
                input_sha256: None,
                operation_id: None,
                interaction_id: None,
                expected_revision: None,
                receipt: None,
                error: None,
            };
            let parsed: Result<Decision> = (|| {
                let metadata = std::fs::symlink_metadata(entry.path())?;
                anyhow::ensure!(
                    metadata.is_file() && !metadata.file_type().is_symlink(),
                    "decision must be a regular file, never a symlink"
                );
                receipt.input_bytes = metadata.len();
                anyhow::ensure!(
                    metadata.len() <= MAX_DECISION_BYTES,
                    "decision exceeds 128 KiB"
                );
                let mut bytes = Vec::new();
                std::fs::File::open(entry.path())?
                    .take(MAX_DECISION_BYTES + 1)
                    .read_to_end(&mut bytes)?;
                anyhow::ensure!(
                    bytes.len() as u64 <= MAX_DECISION_BYTES,
                    "decision grew past 128 KiB"
                );
                receipt.input_bytes = bytes.len() as u64;
                receipt.input_sha256 = Some(evidence::sha256(&bytes));
                // Retain exact submitted bytes separately from the API's typed receipt.
                evidence.raw(
                    &format!("decision-inputs/{index:03}.json"),
                    &receipt.file_name,
                    &bytes,
                )?;
                serde_json::from_slice(&bytes).context("invalid typed decision JSON")
            })();
            match parsed {
                Ok(decision) => {
                    receipt.operation_id = Some(decision.operation_id.clone());
                    receipt.interaction_id = Some(decision.interaction_id.clone());
                    receipt.expected_revision = Some(decision.expected_revision);
                    if let Err(error) = scene.check() {
                        receipt.error = Some(format!("not admitted: {error:#}"));
                    } else {
                        let admitted = std::time::Instant::now();
                        match runtime
                            .resolve_interaction(
                                decision.operation_id,
                                root.into(),
                                decision.expected_revision,
                                decision.interaction_id,
                                decision.resolution,
                            )
                            .await
                        {
                            Ok(actual) => {
                                receipt.receipt = Some(actual);
                                self.applied = true;
                            }
                            Err(error) => receipt.error = Some(format!("{error:#}")),
                        }
                        scene.returned("resolve_interaction", admitted, manifest);
                    }
                }
                Err(error) => receipt.error = Some(format!("{error:#}")),
            }
            evidence.json(
                &format!("decision-receipts/{index:03}.json"),
                &receipt.file_name,
                &receipt,
            )?;
            // A stop during resolve waits for its actual receipt, then refuses every later file.
            scene.check()?;
            println!(
                "操作者决议已处理一次；回执：{}",
                evidence
                    .root()
                    .join(format!("decision-receipts/{index:03}.json"))
                    .display()
            );
        }
        Ok(())
    }
}
