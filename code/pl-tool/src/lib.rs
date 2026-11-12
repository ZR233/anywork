//! Explicitly installed tools. Thread execution and lifecycle mechanisms belong to pl-core.

// Shared integration fixtures can also exercise crate-private transport leases.
#[cfg(test)]
extern crate self as pl_tool;

pub mod file_display;
pub mod image;
pub mod image_card;
pub mod image_generation;
pub mod mcp;
pub mod media;
pub mod session;

pub mod workspace;

pub mod ask_user;
pub mod binding;
pub mod finish_turn;
pub mod session_note;
pub mod todo;

fn unix_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        .min(i64::MAX as u64) as i64
}

fn tool_error(tool: &str, error: impl std::fmt::Display) -> pl_protocol::PureError {
    pl_protocol::PureError::ToolExecutionFailed {
        tool: tool.to_owned(),
        error: error.to_string(),
    }
}

pub mod git;
pub mod lsp;

pub mod command;
pub mod exec;
pub mod execution;
pub mod remote;

pub mod container;
pub mod file;
pub mod shell;
pub mod workspace_file;

pub mod skill;

pub mod search;

pub mod approval;

pub mod environment;

pub mod discovery;

pub mod task_control;

pub mod thread_catalog;

pub mod collaboration;

pub mod bots;

#[cfg(test)]
#[path = "../tests/support/helper.rs"]
mod test_fixture_helper;

#[cfg(test)]
#[path = "../tests/support/remote.rs"]
mod test_fixture_remote;
pub mod lua;
