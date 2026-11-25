//! Freezes model inputs, refreshes context facts, and prepares compaction candidates.
mod compaction;
mod facts;
mod instructions;
mod migration;
mod mode_workflow;

#[cfg(test)]
pub(crate) use compaction::decode_receipt;
pub(crate) use compaction::{CompactionReceipt, LATEST_RECEIPT, preparer};
pub(crate) use instructions::{decode_instruction_binding, instruction_binding};
pub(crate) use migration::migrate_checkpoint_sources;

#[cfg(test)]
mod instruction_normalization_tests;
