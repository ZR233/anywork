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
pub use thread::{
    CommandAccess, CommandOutputArchive, ExecFailure, ThreadExecTool, ThreadWriteStdinTool,
};

/// Reads the exit status from the command author's original domain facts.
pub fn saved_command_exit_code(details: Option<&serde_json::Value>) -> Option<i32> {
    details?
        .get("command")?
        .get("exitCode")?
        .as_i64()?
        .try_into()
        .ok()
}

/// Reads the reliable capture references kept by the author's command result.
pub fn saved_command_resources(
    details: Option<&serde_json::Value>,
) -> Result<Vec<pl_core::context::ResourceReference>, pl_core::tool::opaque::ToolError> {
    use pl_core::tool::opaque::ToolError;
    let Some(command) = details.and_then(|details| details.get("command")) else {
        return Ok(Vec::new());
    };
    let command = command.as_object().ok_or_else(|| {
        ToolError::new(std::io::Error::other(
            "saved command details must be an object",
        ))
    })?;
    ["stdoutResource", "stderrResource"]
        .into_iter()
        .filter_map(|key| command.get(key).filter(|value| !value.is_null()))
        .map(|value| {
            let reference: pl_core::context::ResourceReference =
                serde_json::from_value(value.clone()).map_err(ToolError::new)?;
            reference.validate().map_err(ToolError::new)?;
            Ok(reference)
        })
        .collect()
}
pub const TOOL_EXEC: &str = "exec_command";
pub const TOOL_WRITE_STDIN: &str = "write_stdin";
