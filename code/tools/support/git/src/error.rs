use std::error::Error;

use crate::GitOutput;

pub type BoxError = Box<dyn Error + Send + Sync>;

/// Failures retain the concrete capability source and any observed commands.
#[derive(Debug, thiserror::Error)]
pub enum GitError {
    #[error(transparent)]
    Arguments(#[from] pl_agent_tool::typed::ArgumentError),
    #[error("tool {tool}: {message}")]
    Invalid { tool: &'static str, message: String },
    #[error("tool {tool}: {source}")]
    Capability {
        tool: &'static str,
        #[source]
        source: BoxError,
    },
    #[error("tool {tool}: {message}: {source}")]
    Askpass {
        tool: &'static str,
        message: &'static str,
        #[source]
        source: std::io::Error,
    },
    #[error("git command {tool} failed with exit code {status}")]
    Command {
        tool: &'static str,
        status: i32,
        output: GitOutput,
    },
    #[error("{source}")]
    AfterCommands {
        #[source]
        source: Box<GitError>,
        completed: Vec<GitOutput>,
    },
}

impl GitError {
    pub fn invalid(tool: &'static str, message: impl Into<String>) -> Self {
        Self::Invalid {
            tool,
            message: message.into(),
        }
    }

    pub fn capability(tool: &'static str, source: impl Error + Send + Sync + 'static) -> Self {
        Self::Capability {
            tool,
            source: Box::new(source),
        }
    }

    pub fn after_commands(self, completed: Vec<GitOutput>) -> Self {
        if completed.is_empty() {
            self
        } else {
            Self::AfterCommands {
                source: Box::new(self),
                completed,
            }
        }
    }

    /// The failed command, or the last completed command before a later failure.
    pub fn observed(&self) -> Option<&GitOutput> {
        match self {
            Self::Command { output, .. } => Some(output),
            Self::AfterCommands { source, completed } => {
                source.observed().or_else(|| completed.last())
            }
            _ => None,
        }
    }
}

pub fn non_empty(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.trim().is_empty())
}

pub fn required_text(
    tool: &'static str,
    value: Option<String>,
    field: &str,
) -> Result<String, GitError> {
    non_empty(value)
        .ok_or_else(|| GitError::invalid(tool, format!("missing string field `{field}`")))
}
