use pl_tool_process::input::{ExecInputError, parse};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// `write_stdin` 的结构化输入。
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WriteStdinInput {
    /// Task id returned by exec's acceptance receipt.
    pub task_id: String,
    /// Text to write. Empty is valid only with closeStdin=true; use wait for polling.
    pub chars: String,
    /// Close stdin after the requested text is accepted. Empty text sends only EOF.
    #[serde(default)]
    pub close_stdin: bool,
    /// Positive combined stdout + stderr UTF-8 byte budget, clamped to 65536.
    #[serde(default)]
    pub max_output_chars: Option<usize>,
}

/// Strict stdin input validation shared with the authorization boundary.
pub fn parse_and_validate_stdin_input(raw: &str) -> Result<WriteStdinInput, ExecInputError> {
    let input: WriteStdinInput = parse(raw)?;
    if input.task_id.trim().is_empty() {
        return Err(ExecInputError::range(
            "taskId",
            "Expected an exec receipt taskId from this Thread.",
        ));
    }
    if input.chars.is_empty() && !input.close_stdin {
        return Err(ExecInputError::range(
            "chars",
            "Expected nonempty text or closeStdin=true for EOF; use wait to observe completion.",
        ));
    }
    if input.max_output_chars == Some(0) {
        return Err(ExecInputError::range(
            "maxOutputChars",
            "Expected a positive UTF-8 byte budget.",
        ));
    }
    Ok(input)
}
