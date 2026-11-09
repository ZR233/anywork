use pl_tool_process::input::{ExecInputError, parse};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// `exec` 的结构化输入。
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExecInput {
    /// The shell command to execute.
    pub command: String,
    /// Optional working directory. Use `.` for the workspace root or a workspace-relative path
    /// such as `src`. SSH execution rejects absolute paths; local absolute paths remain subject to
    /// the active permission and workspace policy.
    #[serde(default)]
    pub cwd: Option<PathBuf>,
    /// Positive seconds from process-manager admission, including startup (default: 60).
    /// Approval time is excluded; receiving a background receipt does not reset this deadline.
    #[serde(default)]
    // Keep zero expressible so the shared semantic validator can reject the original value
    // before authorization, without a model substituting null/default to satisfy the schema.
    pub timeout_seconds: Option<u64>,
    /// Positive combined stdout + stderr UTF-8 byte budget (default and maximum: 65536).
    /// Metadata, JSON escaping and protocol wrappers are additional and do not consume this budget.
    ///
    /// The wire field name keeps the historical `maxOutputChars`, but the unit is bytes: the
    /// projection truncates the visible stdout/stderr text by `String` byte length, so multi-byte
    /// characters are charged for their real encoded size. A backend may additionally declare its
    /// own byte ceiling through `CommandBackend::model_output_bytes_cap`.
    #[serde(default)]
    pub max_output_chars: Option<usize>,
}

/// Validated exec arguments. Only this module can construct a validated value.
#[derive(Debug)]
pub struct ValidatedExecInput(ExecInput);

impl ValidatedExecInput {
    pub fn cwd(&self) -> Option<&Path> {
        self.0.cwd.as_deref()
    }
    pub fn into_input(self) -> ExecInput {
        self.0
    }
}

/// Strict, side-effect-free parsing; does not normalize the actual shell command.
pub fn parse_and_validate_exec_input(raw: &str) -> Result<ValidatedExecInput, ExecInputError> {
    let input: ExecInput = parse(raw)?;
    if input.command.trim().is_empty() {
        return Err(ExecInputError {
            code: "exec.empty_command",
            field: Some("command".into()),
            detail: "Expected a nonblank shell command.".into(),
            source: None,
        });
    }
    if input.timeout_seconds == Some(0) {
        return Err(ExecInputError::range(
            "timeoutSeconds",
            "Expected a positive integer in seconds.",
        ));
    }
    if input.max_output_chars == Some(0) {
        return Err(ExecInputError::range(
            "maxOutputChars",
            "Expected a positive UTF-8 byte budget.",
        ));
    }
    Ok(ValidatedExecInput(input))
}
