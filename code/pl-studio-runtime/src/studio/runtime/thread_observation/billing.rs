//! The realtime observer submits only diagnostic/performance projections.
use super::super::ModelPerformanceOwner;
use crate::studio::thread_projection::PreparedAccounting;
use anyhow::Result;

pub(super) fn record(
    owner: &ModelPerformanceOwner,
    root: &str,
    accounting: &PreparedAccounting,
) -> Result<()> {
    for fact in accounting.facts.iter() {
        if fact.auxiliary {
            owner.record_auxiliary_inference(
                root,
                &accounting.thread_id,
                &fact.record,
                fact.status,
            )?;
        } else {
            owner.record_inference(root, &accounting.thread_id, &fact.record, fact.status)?;
        }
    }
    Ok(())
}
