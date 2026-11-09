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

    /// Safe command facts suitable for delivery independently of the private source.
    ///
    /// A single command retains its original payload. A multi-step failure also
    /// includes every completed command and the failed command (when available)
    /// in execution order under `observations`, while keeping the last command's
    /// original fields at the top level.
    pub fn observed(&self) -> Option<GitOutput> {
        let mut observations = Vec::new();
        self.collect_observations(&mut observations);
        let mut payload = observations.last()?.payload().clone();
        if matches!(self, Self::AfterCommands { .. }) {
            payload["observations"] = observations
                .iter()
                .map(|output| output.payload().clone())
                .collect();
        }
        Some(GitOutput::new(payload))
    }

    fn collect_observations<'a>(&'a self, observations: &mut Vec<&'a GitOutput>) {
        match self {
            Self::Command { output, .. } => observations.push(output),
            Self::AfterCommands { source, completed } => {
                observations.extend(completed);
                source.collect_observations(observations);
            }
            _ => {}
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn observed_single_command_payload_is_unchanged() {
        let output = GitOutput::command(17, "partial output".into(), "command failed".into());
        let error = GitError::Command {
            tool: "git_push",
            status: 17,
            output: output.clone(),
        };
        assert_eq!(error.observed(), Some(output));
        assert!(
            GitError::invalid("git_push", "missing branch")
                .observed()
                .is_none()
        );
    }
}
