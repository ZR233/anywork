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
    stream: crate::command::CommandCaptureStream,
) -> Result<(ResourceReference, u64), ToolError> {
    if snapshot.capture_usage.is_none() {
        return Err(ToolError::new(ExecFailure::Process(format!(
            "capture producer did not confirm its result; unverified capture was not archived: {}",
            snapshot.message
        ))));
    }
    let mut repaired = snapshot.clone();
    if let Some(repair) = snapshot.capture_repair() {
        let mut confirmed = repair.confirmed;
        for chunk in repair.chunks.iter().filter(|chunk| chunk.stream == stream) {
            let path = match chunk.stream {
                crate::command::CommandCaptureStream::Stdout => &snapshot.capture_file,
                crate::command::CommandCaptureStream::Stderr => &snapshot.stderr_capture_file,
            };
            let committed_len = backend
                .repair_output_chunk(
                    path,
                    chunk.stream,
                    confirmed.get(chunk.stream),
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
            confirmed.set(chunk.stream, committed_len);
        }
        repaired.capture_offsets = confirmed;
    }
    let reference = archive.retain(thread_id, &repaired, stream).await?;
    reference.validate().map_err(ToolError::new)?;
    Ok((reference, repaired.capture_offsets.get(stream)))
}
