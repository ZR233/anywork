//! Archive only a target-confirmed prefix. Unknown output cannot be recovered by replay.
use super::{CommandOutputArchive, ExecFailure};
use crate::command::CommandOutputSnapshot;
use pl_core::{context::ResourceReference, tool::opaque::ToolError};
pub(super) async fn retain<A: CommandOutputArchive>(
    archive: &A,
    thread_id: &str,
    snapshot: &CommandOutputSnapshot,
    stream: crate::command::CommandCaptureStream,
) -> Result<ResourceReference, ToolError> {
    snapshot.confirmed_bytes(stream).ok_or_else(|| {
        ToolError::new(ExecFailure::Process(
            "capture length is unknown; output was not archived".into(),
        ))
    })?;
    let reference = archive.retain(thread_id, snapshot, stream).await?;
    reference.validate().map_err(ToolError::new)?;
    Ok(reference)
}
