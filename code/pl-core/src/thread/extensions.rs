//! Versioned opaque application records with atomic compare-and-swap batches.
use super::*;
use std::collections::BTreeMap;

/// Current application record. Revision belongs to Thread; format/version belong to the producer.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExtensionRecord {
    pub revision: u64,
    pub payload: OpaquePayload,
}

/// Frozen inputs to a host projection. Missing keys and membership of enumerated
/// formats are significant. Unrelated writes cannot invalidate the projection.
#[derive(Debug, Clone, Default)]
pub struct ExtensionInputs {
    revisions: BTreeMap<String, Option<u64>>,
    formats: Vec<String>,
}

impl ExtensionInputs {
    pub fn capture(snapshot: &BTreeMap<String, ExtensionRecord>, keys: &[&str]) -> Self {
        let mut inputs = Self::default();
        inputs.include_keys(snapshot, keys);
        inputs
    }

    pub fn include_keys(&mut self, snapshot: &BTreeMap<String, ExtensionRecord>, keys: &[&str]) {
        self.revisions.extend(keys.iter().map(|&key| {
            (
                key.to_owned(),
                snapshot.get(key).map(|entry| entry.revision),
            )
        }));
    }

    pub fn include_format(&mut self, snapshot: &BTreeMap<String, ExtensionRecord>, format: &str) {
        self.formats.push(format.to_owned());
        self.revisions.extend(
            snapshot
                .iter()
                .filter(|(_, record)| record.payload.format() == format)
                .map(|(id, record)| (id.clone(), Some(record.revision))),
        );
    }

    pub(super) fn validate(
        &self,
        current: &BTreeMap<String, ExtensionRecord>,
    ) -> Result<(), ThreadError> {
        for (id, &expected) in &self.revisions {
            let actual = current.get(id).map(|record| record.revision);
            if actual != expected {
                return Err(ThreadError::ExtensionConflict {
                    id: id.clone(),
                    expected,
                    actual,
                });
            }
        }
        if !self.formats.is_empty() {
            for (id, record) in current {
                if !self.revisions.contains_key(id)
                    && self
                        .formats
                        .iter()
                        .any(|format| format == record.payload.format())
                {
                    return Err(ThreadError::ExtensionConflict {
                        id: id.clone(),
                        expected: None,
                        actual: Some(record.revision),
                    });
                }
            }
        }
        Ok(())
    }
}

/// Connects a newly projected instruction record to the extension version actually
/// assigned by the owner. Compaction may discard the record before installation.
#[derive(Debug, Clone)]
pub struct InstructionRevisionBinding {
    pub record_id: String,
    pub extension_id: String,
}

impl InstructionRevisionBinding {
    pub(super) fn resolve(
        &self,
        replacement: &mut ReplaceContext,
        state: &ThreadSnapshot,
    ) -> Result<(), ThreadError> {
        if let Some(record) = replacement
            .records
            .iter_mut()
            .find(|record| record.id == self.record_id)
        {
            let ContextSource::InstructionSnapshot { revision, .. } = &mut record.source else {
                return Err(ThreadError::InvalidContext);
            };
            *revision = state
                .extensions
                .get(&self.extension_id)
                .ok_or(ThreadError::InvalidContext)?
                .revision;
        }
        Ok(())
    }
}

/// Explicit extension mutations cannot grant framework authority.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "value")]
pub enum ExtensionMutation {
    Put {
        id: String,
        expected_revision: Option<u64>,
        payload: OpaquePayload,
    },
    Delete {
        id: String,
        expected_revision: u64,
    },
}

/// Committed versions, including deletion tombstones, retained for cold replay.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "value")]
pub enum ExtensionChange {
    Put { id: String, record: ExtensionRecord },
    Delete { id: String, revision: u64 },
}

impl Owner {
    pub(super) fn mutate_extensions(
        &mut self,
        mutations: Vec<ExtensionMutation>,
    ) -> Result<BTreeMap<String, ExtensionRecord>, ThreadError> {
        let result = stage_extensions(&mut self.state, mutations)?;
        self.publish()?;
        Ok(result)
    }

    pub(super) fn update_application(
        &mut self,
        update: ApplicationUpdate,
    ) -> Result<ThreadSnapshot, ThreadError> {
        if !self.pending.is_empty() {
            return Err(ThreadError::PendingTools);
        }
        let mut candidate = self.state.clone();
        stage_extensions(&mut candidate, update.mutations)?;
        super::facts::stage_facts(&mut candidate, update.facts)?;
        self.state = candidate;
        self.publish()?;
        Ok(self.state.clone())
    }
}

/// One atomic application checkpoint: opaque state mutations and its actual model projection.
#[derive(Debug)]
pub struct ApplicationUpdate {
    pub mutations: Vec<ExtensionMutation>,
    pub facts: Vec<RuntimeFact>,
}

pub(super) fn stage_extensions(
    state: &mut ThreadSnapshot,
    mutations: Vec<ExtensionMutation>,
) -> Result<BTreeMap<String, ExtensionRecord>, ThreadError> {
    if state.lifecycle != ThreadLifecycle::Open {
        return Err(ThreadError::Closed);
    }
    let mut records = state.extensions.clone();
    let mut sequence = state.extension_sequence;
    let mut changes = state.extension_changes.to_vec();
    for mutation in mutations {
        let (id, expected) = match &mutation {
            ExtensionMutation::Put {
                id,
                expected_revision,
                ..
            } => (id, *expected_revision),
            ExtensionMutation::Delete {
                id,
                expected_revision,
            } => (id, Some(*expected_revision)),
        };
        if id.is_empty() {
            return Err(ThreadError::InvalidIdentity);
        }
        let actual = records.get(id).map(|record| record.revision);
        if actual != expected {
            return Err(ThreadError::ExtensionConflict {
                id: id.clone(),
                expected,
                actual,
            });
        }
        sequence = sequence
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        match mutation {
            ExtensionMutation::Put { id, payload, .. } => {
                let record = ExtensionRecord {
                    revision: sequence,
                    payload,
                };
                records.insert(id.clone(), record.clone());
                changes.push(ExtensionChange::Put { id, record });
            }
            ExtensionMutation::Delete { id, .. } => {
                records.remove(&id);
                changes.push(ExtensionChange::Delete {
                    id,
                    revision: sequence,
                });
            }
        }
    }
    state.extensions = records.clone();
    state.extension_sequence = sequence;
    state.extension_changes = changes.into();
    Ok(records)
}
