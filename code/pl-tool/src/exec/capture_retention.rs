//! 初次保存与显式重试共用的捕获确认、修复和归档边界。
use super::{CommandOutputArchive, ExecFailure};
use crate::command::{CommandBackend, CommandOutputSnapshot};
use pl_core::{
    context::ResourceReference,
    thread::cold::{ColdStoreError, OutputStorageFault, StorageFaultKind},
    tool::opaque::ToolError,
};
use std::sync::Arc;

/// 两条路径都先核验唯一写入者的事实，再按原计划修复与归档，不推测未知捕获已完整。
pub(super) async fn retain<B: CommandBackend, A: CommandOutputArchive>(
    backend: &B,
    archive: &A,
    thread_id: &str,
    snapshot: &CommandOutputSnapshot,
) -> Result<ResourceReference, ToolError> {
    if snapshot.capture_usage.is_none() {
        return Err(ToolError::new(ExecFailure::Process(format!(
            "capture producer did not confirm its result; unverified capture was not archived: {}",
            snapshot.message
        ))));
    }
    if let Some(repair) = snapshot.capture_repair() {
        let mut committed_len = repair.committed_len;
        for chunk in &repair.chunks {
            committed_len = backend
                .repair_output_chunk(
                    &snapshot.capture_file,
                    chunk.stream,
                    committed_len,
                    &chunk.pending,
                )
                .await
                .map_err(|error| {
                    let source = ColdStoreError {
                        source: Box::new(std::io::Error::other(format!(
                            "command output capture repair failed: {error}"
                        ))),
                    };
                    ToolError::new(OutputStorageFault::new(
                        StorageFaultKind::WriteFailed,
                        Arc::new(source),
                    ))
                })?;
        }
    }
    let reference = archive.retain(thread_id, snapshot).await?;
    reference.validate().map_err(ToolError::new)?;
    Ok(reference)
}
