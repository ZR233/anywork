//! Metadata-only access through the same Session captured by the content reader.

use anyhow::{Result, ensure};
use pl_core::chat::{ChatItemMetadataRead, ChatLifecycle};
use pl_protocol::{ThreadContentField, ThreadItem, TimelineLifecycle};

use super::{TimelineContentReader, field::wire_field};
use crate::studio::runtime::chat_item::{item_shell, static_state};

/// The canonical static shell and complete field lengths, never a body preview.
pub(crate) struct TimelineItemMetadata {
    pub shell: ThreadItem,
    pub fields: Vec<TimelineFieldLength>,
    pub saved: bool,
    pub lifecycle: TimelineLifecycle,
}

pub(crate) struct TimelineFieldLength {
    pub field: ThreadContentField,
    pub total_bytes: u64,
}

pub(crate) enum TimelineMetadataRead {
    Present(Box<TimelineItemMetadata>),
    /// No currently provable item; this is not a canonical Remove or a tombstone.
    Missing {
        item_id: String,
    },
}

impl TimelineContentReader {
    /// Reads 1..=100 unique item identities in request order without loading their body previews.
    /// Session alone reconciles resident/cold facts and enforces the complete batch metadata budget.
    /// This does not hydrate a window, publish a notification or activate execution.
    ///
    /// # Errors
    /// Invalid identity batches, invalidated reads, budget/storage failures, or inconsistent typed
    /// metadata. In particular, an unavailable newer shell never falls back to an older cold value.
    pub(crate) async fn read_metadata(
        &self,
        item_ids: &[String],
    ) -> Result<Vec<TimelineMetadataRead>> {
        let reads = self.session.read_metadata(item_ids).await?;
        let mut result = Vec::with_capacity(reads.len());
        for read in reads {
            match read {
                ChatItemMetadataRead::Missing { item_id } => {
                    result.push(TimelineMetadataRead::Missing { item_id });
                }
                ChatItemMetadataRead::Present(metadata) => {
                    let shell = item_shell(&metadata.meta, metadata.revision)?;
                    ensure!(
                        shell.thread_id == self.thread_id
                            && shell.id == metadata.item_id
                            && shell.turn_id == metadata.turn_id
                            && shell.ordinal == metadata.order,
                        "Timeline metadata identity differs from its canonical shell"
                    );
                    ensure!(
                        static_state(shell.state()) == *shell.state(),
                        "Timeline metadata unexpectedly contains dynamic content"
                    );
                    let mut fields = Vec::with_capacity(metadata.fields.len());
                    for (field, total_bytes) in metadata.fields {
                        let field = wire_field(&field).ok_or_else(|| {
                            anyhow::anyhow!("Timeline metadata contains an unsupported field")
                        })?;
                        fields.push(TimelineFieldLength { field, total_bytes });
                    }
                    let lifecycle = match metadata.lifecycle {
                        ChatLifecycle::Streaming => TimelineLifecycle::Streaming,
                        ChatLifecycle::Terminal => TimelineLifecycle::Terminal,
                    };
                    ensure!(
                        shell.state().is_terminal()
                            == matches!(lifecycle, TimelineLifecycle::Terminal),
                        "Timeline metadata lifecycle differs from its canonical shell"
                    );
                    result.push(TimelineMetadataRead::Present(Box::new(
                        TimelineItemMetadata {
                            shell,
                            fields,
                            saved: metadata.saved,
                            lifecycle,
                        },
                    )));
                }
            }
        }
        Ok(result)
    }
}
