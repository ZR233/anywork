use std::{error::Error, fmt};

use pl_tool_git::GitError;

use super::HostGitExecutionError;

/// A public Git diagnostic that retains its private, typed domain failure.
///
/// The standard error chain deliberately stops here: Anywork may persist every
/// message in that chain. Only trusted host code should inspect [`Self::original`];
/// formatting or serializing that original error can disclose private sources.
pub struct GitHostError {
    original: GitError,
    diagnostic: String,
}

impl GitHostError {
    pub(super) fn new(tool: &'static str, original: GitError) -> Self {
        let diagnostic = public_diagnostic(tool, &original);
        Self {
            original,
            diagnostic,
        }
    }

    /// Returns the original domain failure, including native sources and observations.
    ///
    /// This is a trusted diagnostic accessor, not a public error presentation.
    pub fn original(&self) -> &GitError {
        &self.original
    }
}

impl fmt::Display for GitHostError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.diagnostic)
    }
}

impl fmt::Debug for GitHostError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("GitHostError")
            .field("diagnostic", &self.diagnostic)
            .finish_non_exhaustive()
    }
}

impl Error for GitHostError {}

fn public_diagnostic(tool: &'static str, error: &GitError) -> String {
    match error {
        // These diagnostics are authored by the independent tools from public
        // arguments and validation facts, not by injected host capabilities.
        GitError::Arguments(_) | GitError::Invalid { .. } | GitError::Command { .. } => {
            error.to_string()
        }
        GitError::Askpass { tool, message, .. } => format!("tool {tool}: {message}"),
        GitError::Capability { source, .. } => {
            if let Some(HostGitExecutionError(_source)) =
                source.downcast_ref::<HostGitExecutionError>()
            {
                format!("tool {tool}: git command execution failed")
            } else {
                format!("tool {tool}: git credential provider failed")
            }
        }
        GitError::AfterCommands { source, .. } => public_diagnostic(tool, source),
    }
}
