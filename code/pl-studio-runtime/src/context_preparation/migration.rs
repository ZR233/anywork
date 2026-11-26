//! Preparation-related repairs at the persisted checkpoint migration boundary.
use super::compaction::LATEST_RECEIPT;

/// Producer payload conversion is confined to the persisted checkpoint migration boundary.
pub(crate) fn migrate_checkpoint_sources(
    checkpoint: &mut crate::studio::storage::legacy_checkpoint::ThreadCheckpoint,
) -> anyhow::Result<()> {
    use pl_core::context::ContextSource;
    for record in std::sync::Arc::make_mut(&mut checkpoint.state.context.records) {
        if let ContextSource::Runtime { source_id } = &record.source
            && ((source_id == "studio.workspace"
                && record.id == format!("workspace:{}", checkpoint.thread_id))
                || (source_id == "studio.workflow"
                    && record.id == format!("workflow:{}:initial", checkpoint.thread_id)))
        {
            record.source = ContextSource::RuntimeFact {
                source_id: source_id.clone(),
            };
        }
    }
    let Some(record) = checkpoint.state.extensions.get(LATEST_RECEIPT) else {
        return Ok(());
    };
    if record.payload.format() != "pl.studio.compaction" || record.payload.version() != 1 {
        return Ok(());
    }
    let receipt = crate::studio::producer_migration::compaction_receipt(
        record.payload.version(),
        record.payload.content(),
    )?;
    if receipt.error.is_some() || receipt.implementation.as_deref() != Some("native") {
        return Ok(());
    }
    for record in std::sync::Arc::make_mut(&mut checkpoint.state.context.records) {
        pl_model::runtime::migrate_legacy_compaction(
            record,
            &receipt.inference_id,
            receipt.binding.clone(),
        )?;
    }
    Ok(())
}
