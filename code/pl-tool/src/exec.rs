//! Command tools adapted to the Thread-owned process manager and reliable output store.
mod capture_retention;
mod input;
mod output;
mod progress;
mod thread;
pub use input::{ExecInputError, parse_and_validate_exec_input, parse_and_validate_stdin_input};
pub use output::permission_denied;
pub use pl_tool_command::exec::{ExecInput, ValidatedExecInput, exec_definition};
pub use pl_tool_command::write_stdin::{WriteStdinInput, write_stdin_definition};
pub use thread::{CommandAccess, CommandOutputArchive, ExecFailure, ThreadExecTool};
pub const TOOL_EXEC: &str = "exec";
pub const TOOL_WRITE_STDIN: &str = "write_stdin";
