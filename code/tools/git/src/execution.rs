use std::{collections::BTreeMap, fmt, future::Future, path::PathBuf, sync::Arc, time::Duration};

use crate::{
    GIT_TOKEN_ENV, GitCredential, GitCredentialOperation, GitCredentialProvider,
    GitCredentialRequest, GitError, GitOutput, GitWorkspaceConfig, write_askpass_script,
};

/// One explicit command, never a callback to an entire Git tool.
#[derive(Clone, PartialEq, Eq)]
pub struct GitCommand {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub cwd: PathBuf,
    pub env: BTreeMap<String, String>,
    pub timeout: Option<Duration>,
}

impl fmt::Debug for GitCommand {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let env = self
            .env
            .iter()
            .map(|(key, value)| {
                let value = if key.contains("TOKEN") || key.contains("PASSWORD") {
                    "[redacted]"
                } else {
                    value.as_str()
                };
                (key, value)
            })
            .collect::<BTreeMap<_, _>>();
        f.debug_struct("GitCommand")
            .field("program", &self.program)
            .field("args", &self.args)
            .field("cwd", &self.cwd)
            .field("env", &env)
            .field("timeout", &self.timeout)
            .finish()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitCommandOutput {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

/// A host-owned, restricted process service. Errors must not reveal secrets.
pub trait GitExecutor: fmt::Debug + Send + Sync {
    type Error: std::error::Error + Send + Sync + 'static;

    fn run(
        &self,
        command: GitCommand,
    ) -> impl Future<Output = Result<GitCommandOutput, Self::Error>> + Send;
}

/// Frozen command facts and a narrow execution capability.
#[derive(Debug)]
pub struct GitRunner<E> {
    pub config: GitWorkspaceConfig,
    executor: Arc<E>,
}

impl<E: GitExecutor> GitRunner<E> {
    pub fn new(config: GitWorkspaceConfig, executor: Arc<E>) -> Self {
        Self { config, executor }
    }

    pub async fn run_plain(
        &self,
        tool: &'static str,
        args: Vec<&str>,
    ) -> Result<GitOutput, GitError> {
        self.run_request(tool, self.command(args, BTreeMap::new()), None)
            .await
    }

    fn command(&self, args: Vec<&str>, env: BTreeMap<String, String>) -> GitCommand {
        let mut git_args = Vec::with_capacity(args.len() + 2);
        #[cfg(windows)]
        git_args.extend(["-c".to_string(), "core.longpaths=true".to_string()]);
        git_args.extend(args.into_iter().map(str::to_owned));
        GitCommand {
            program: self.config.git_binary.clone(),
            args: git_args,
            cwd: self.config.worktree.clone(),
            env,
            timeout: Some(Duration::from_secs(600)),
        }
    }

    async fn run_request(
        &self,
        tool: &'static str,
        command: GitCommand,
        credential: Option<&GitCredential>,
    ) -> Result<GitOutput, GitError> {
        let output = self
            .executor
            .run(command)
            .await
            .map_err(|source| GitError::capability(tool, source))?;
        let redact = |text: String| match credential {
            Some(credential) => text.replace(credential.expose(), "[redacted]"),
            None => text,
        };
        let outcome =
            GitOutput::command(output.status, redact(output.stdout), redact(output.stderr));
        if output.status == 0 {
            Ok(outcome)
        } else {
            Err(GitError::Command {
                tool,
                status: output.status,
                output: outcome,
            })
        }
    }
}

/// Network Git adds only an already-resolved credential provider.
#[derive(Debug)]
pub struct GitNetwork<E, P> {
    pub runner: GitRunner<E>,
    provider: Arc<P>,
}

impl<E: GitExecutor, P: GitCredentialProvider> GitNetwork<E, P> {
    pub fn new(runner: GitRunner<E>, provider: Arc<P>) -> Self {
        Self { runner, provider }
    }

    pub async fn run(
        &self,
        tool: &'static str,
        args: Vec<&str>,
        operation: GitCredentialOperation,
        remote: String,
    ) -> Result<GitOutput, GitError> {
        if self.runner.config.native_credentials {
            return self.runner.run_plain(tool, args).await;
        }
        let credential = self
            .provider
            .credential(GitCredentialRequest { operation, remote })
            .await
            .map_err(|source| GitError::capability(tool, source))?
            .ok_or_else(|| {
                GitError::invalid(tool, "project git account token is not configured")
            })?;
        let askpass = write_askpass_script(tool)?;
        let mut env = BTreeMap::new();
        env.insert("GIT_TERMINAL_PROMPT".to_string(), "0".to_string());
        env.insert("GIT_ASKPASS".to_string(), askpass.display().to_string());
        env.insert(GIT_TOKEN_ENV.to_string(), credential.expose().to_string());
        let request = self.runner.command(args, env);
        self.runner
            .run_request(tool, request, Some(&credential))
            .await
    }
}
