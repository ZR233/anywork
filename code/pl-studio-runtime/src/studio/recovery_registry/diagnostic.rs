//! Recovery publication renders typed facts, never arbitrary error Display/source text.
use crate::agent::worktree::{RemoteClientError, RemoteExecutionError, WorktreeError};

pub(in crate::studio) fn bounded(message: &str) -> String {
    message.chars().take(2048).collect()
}

pub(in crate::studio) fn failure(error: &(dyn std::error::Error + 'static)) -> String {
    let mut parts = Vec::new();
    let mut cause = Some(error);
    let mut remote = false;
    for _ in 0..16 {
        let Some(error) = cause else {
            break;
        };
        if let Some(error) = error.downcast_ref::<WorktreeError>() {
            parts.push(error.safe_diagnostic());
            break;
        } else if let Some(error) = error.downcast_ref::<RemoteClientError>() {
            // Reuse the worktree boundary's closed-vocabulary SSH renderer. Its source remains
            // the original transport error; neither auth nor protocol is a local IO category.
            parts.push(WorktreeError::Remote { operation: "SSH transport", source: error.clone() }.safe_diagnostic());
            break;
        } else if let Some(error) = error.downcast_ref::<RemoteExecutionError>() {
            remote = true;
            parts.push(match error {
                RemoteExecutionError::WorkingDirectory => "remote command: working directory rejected",
                RemoteExecutionError::Spawn { .. } => "remote command: spawn failed",
                RemoteExecutionError::OutputMissing => "remote command: output stream missing",
                RemoteExecutionError::UnexpectedCapture => "remote command: unexpected capture receipt",
                RemoteExecutionError::Buffer { .. } => "remote command: output buffer failed",
                RemoteExecutionError::Read { .. } => "remote command: output read failed",
                RemoteExecutionError::Wait { .. } => "remote command: wait failed; unstructured details withheld",
                RemoteExecutionError::TimedOut { .. } => "remote command: timed out",
            }.into());
        } else if let Some(error) = error.downcast_ref::<std::io::Error>() {
            parts.push(format!("{} {:?}; os_code={:?}", if remote { "remote I/O" } else { "I/O" }, error.kind(), error.raw_os_error()));
        } else if let Some(error) = error.downcast_ref::<pl_protocol::studio::StudioError>() {
            let correlation = &error.correlation_id;
            let correlation = if correlation.len() <= 96
                && correlation.chars().all(|character| character.is_ascii_alphanumeric() || matches!(character, '-' | '_'))
            { correlation.as_str() } else { "unavailable" };
            parts.push(format!("Studio {}; correlation_id={correlation}", error.code.label()));
        } else if let Some(error) = error.downcast_ref::<crate::thread_assembler::ThreadCloseFailure>() {
            parts.push(format!("original Thread close phase={:?}", error.phase));
        } else if let Some(error) = error.downcast_ref::<crate::studio::thread_factory::FactoryCloseFailure>() {
            parts.extend(error.issues.iter().take(4).map(|issue| format!("original factory close phase={}", issue.phase_label())));
        } else if let Some(error) = error.downcast_ref::<crate::studio::agent_host::workspace_preparation::WorkspaceCloseFailure>() {
            parts.extend(error.issues.iter().take(4).map(|issue| format!("original workspace close phase={:?}", issue.phase)));
        } else if let Some(error) = error.downcast_ref::<sea_orm::DbErr>() {
            parts.push(format!("database {}", match error {
                sea_orm::DbErr::Conn(_) => "connection failure",
                sea_orm::DbErr::Exec(_) => "write failure",
                sea_orm::DbErr::Query(_) => "read failure",
                _ => "operation failure",
            }));
        } else if error.is::<std::str::Utf8Error>() || error.is::<std::string::FromUtf8Error>() {
            parts.push("inspection output: invalid UTF-8".into());
        }
        cause = error.source();
    }
    if parts.is_empty() {
        parts.push("cause unavailable; unstructured details withheld".into());
    }
    bounded(&parts.join("; "))
}
