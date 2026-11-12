use crate::command::{
    CommandBackend, CommandCaptureStream, CommandOutputSizes, CommandOutputTarget,
    CommandSpawnRequest, CommandStartControl, ManagedCommand, command_output_model_path,
};
use pl_protocol::{PureError, Result};
use pl_remote_helper::{Executor, TargetPath};
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;
#[derive(Debug, Clone)]
pub struct WorkspaceExecutionBinding {
    pub executor: Executor,
    pub root: TargetPath,
}

#[derive(Debug, Clone)]
pub struct ExecutorCommandBackend {
    executor: Executor,
    root: TargetPath,
    environment: crate::environment::ExecutionEnvironment,
    child_environment: BTreeMap<String, String>,
}
impl ExecutorCommandBackend {
    pub fn new(
        executor: Executor,
        root: &str,
        environment: crate::environment::ExecutionEnvironment,
    ) -> std::result::Result<Self, pl_remote_helper::ExecutionError> {
        Ok(Self {
            root: executor.path(root)?,
            executor,
            environment,
            child_environment: BTreeMap::new(),
        })
    }
    pub fn local(root: impl Into<std::path::PathBuf>) -> Result<Self> {
        let executor = Executor::local().map_err(exec_error)?;
        let root = root.into();
        Self::new(
            executor,
            root.to_str()
                .ok_or_else(|| exec_error("workspace path is not UTF-8"))?,
            crate::environment::ExecutionEnvironment::detect_local(),
        )
        .map_err(exec_error)
    }
    pub fn with_child_environment(mut self, environment: BTreeMap<String, String>) -> Self {
        self.child_environment = environment;
        self
    }
    pub fn with_execution_environment(
        mut self,
        environment: crate::environment::ExecutionEnvironment,
    ) -> Self {
        self.environment = environment;
        self
    }
    pub fn binding(&self) -> WorkspaceExecutionBinding {
        WorkspaceExecutionBinding {
            executor: self.executor.clone(),
            root: self.root.clone(),
        }
    }
    pub fn executor(&self) -> &Executor {
        &self.executor
    }
    pub fn canonical_workspace_path(&self) -> &str {
        self.root.as_str()
    }
    pub fn is_same_binding(&self, other: &Self) -> bool {
        self.executor.id() == other.executor.id() && self.root == other.root
    }
    pub fn resolve_protocol_cwd(&self, cwd: Option<&Path>) -> Result<String> {
        let path = cwd
            .map(|cwd| cwd.to_str().ok_or_else(|| exec_error("cwd is not UTF-8")))
            .transpose()?
            .unwrap_or(".");
        self.executor
            .join_path(&self.root, path)
            .map(|path| path.as_str().into())
            .map_err(exec_error)
    }
    pub(crate) async fn validate_cwd(&self, cwd: &str) -> Result<()> {
        let path = self.executor.path(cwd).map_err(exec_error)?;
        let path = self
            .executor
            .fs()
            .canonicalize(&path)
            .await
            .map_err(exec_error)?;
        if !path_within(self.executor(), &path, &self.root) {
            return Err(exec_error(
                "working directory resolves outside the workspace",
            ));
        }
        if !self
            .executor
            .fs()
            .metadata(&path)
            .await
            .map_err(exec_error)?
            .is_some_and(|metadata| metadata.is_dir)
        {
            return Err(exec_error("working directory is not a directory"));
        }
        Ok(())
    }
    fn workspace_files(&self) -> crate::workspace_file::ExecutorWorkspaceFileBackend {
        crate::workspace_file::ExecutorWorkspaceFileBackend::new(
            self.executor.clone(),
            self.root.as_str(),
        )
        .expect("existing target path")
    }
    async fn spawn_controlled(
        &self,
        command: &mut pl_remote_helper::Command,
        start: Option<CommandStartControl>,
    ) -> Result<pl_remote_helper::Child> {
        if let Some(start) = start {
            start.check().map_err(exec_error)?;
            start.mark_start_attempted();
            tokio::select! {
                _ = start.stopped() => Err(exec_error("command startup cancelled")),
                result = tokio::time::timeout_at(start.deadline(),command.spawn()) => result.map_err(|_|exec_error("command startup timed out"))?.map_err(exec_error),
            }
        } else {
            command.spawn().await.map_err(exec_error)
        }
    }
}

pub(crate) fn managed_child(
    mut child: pl_remote_helper::Child,
    _limit: Option<u64>,
) -> ManagedCommand {
    use crate::command::{CommandExit, CommandIo, CommandReader, CommandWriter};
    let pid = child.id();
    let io = CommandIo {
        stdin: child
            .stdin
            .take()
            .map(|pipe| Box::pin(pipe) as CommandWriter),
        stdout: child
            .stdout
            .take()
            .map(|pipe| Box::pin(pipe) as CommandReader),
        stderr: child
            .stderr
            .take()
            .map(|pipe| Box::pin(pipe) as CommandReader),
    };
    let (capture_owner, capture) = tokio::sync::oneshot::channel();
    ManagedCommand::new(pid,io,move |cancel| async move {
        let status=tokio::select! { result=child.wait()=>result, _=cancel.cancelled()=>{child.start_kill().await.map_err(|error|error.to_string())?;child.wait().await} }.map_err(|error|error.to_string())?;
        // Root exit is published before waiting for reader/capture completion.
        let _ = capture_owner.send(child);
        Ok(CommandExit { exit_code:status.code(),signal:match status {pl_remote_helper::ProcessExit::Signal(signal)=>Some(signal),_=>None} })
    }).with_capture_completion(async move {
        let mut child=capture.await.map_err(|_|"capture owner ended before root observation".to_owned())?;
        child.finish_capture().await.map_err(|error|error.to_string())
    })
}
fn exec_error(error: impl std::fmt::Display) -> PureError {
    crate::tool_error("exec", error)
}
impl CommandBackend for ExecutorCommandBackend {
    type Error = PureError;

    async fn resolve_cwd(
        &self,
        cwd: Option<&Path>,
        allow_workspace_escape: bool,
    ) -> Result<String> {
        let cwd = self.resolve_protocol_cwd(cwd)?;
        if !allow_workspace_escape {
            self.validate_cwd(&cwd).await?;
        }
        Ok(cwd)
    }

    async fn output_target(
        &self,
        session_id: &str,
        tool_id: &str,
        _call_id: &str,
        _command: &str,
    ) -> Result<CommandOutputTarget> {
        let model_file = command_output_model_path(session_id, tool_id);
        let target = self
            .executor
            .join_path(
                &self.root,
                model_file
                    .to_str()
                    .ok_or_else(|| exec_error("output path is not UTF-8"))?,
            )
            .map_err(exec_error)?;
        let stderr_model =
            crate::workspace::SessionFiles::new(session_id).command_stderr_output(tool_id);
        let stderr = self
            .executor
            .join_path(
                &self.root,
                stderr_model
                    .to_str()
                    .ok_or_else(|| exec_error("capture path is not UTF-8"))?,
            )
            .map_err(exec_error)?;
        Ok(CommandOutputTarget::new(
            target.as_str(),
            model_file,
            stderr.as_str(),
            stderr_model,
        ))
    }

    async fn spawn(&self, request: CommandSpawnRequest) -> Result<ManagedCommand> {
        let argv = crate::command::shell::argv_for_environment(&self.environment, &request.command);
        let (program, args) = argv
            .split_first()
            .ok_or_else(|| exec_error("shell argv is empty"))?;
        let mut command = self.executor.command(program);
        command
            .args(args)
            .current_dir(&request.cwd)
            .envs(self.child_environment.clone())
            .env_remove("BASH_ENV")
            .env_remove("ENV")
            .stdin(pl_remote_helper::Stdio::Piped)
            .stdout(pl_remote_helper::Stdio::Piped)
            .stderr(pl_remote_helper::Stdio::Piped)
            .capture(pl_remote_helper::CaptureSpec {
                stdout_path: request
                    .output_target
                    .capture_file()
                    .to_str()
                    .ok_or_else(|| exec_error("capture path is not UTF-8"))?
                    .into(),
                stderr_path: request
                    .output_target
                    .stream_capture_file(CommandCaptureStream::Stderr)
                    .to_str()
                    .ok_or_else(|| exec_error("capture path is not UTF-8"))?
                    .into(),
                max_bytes: request.capture_limit_bytes,
            });
        let child = self
            .spawn_controlled(&mut command, Some(request.start_control))
            .await?;
        Ok(managed_child(child, Some(request.capture_limit_bytes)))
    }

    async fn prepare_output(
        &self,
        target: &CommandOutputTarget,
        _command: &str,
        _working_directory: &str,
        _capture_limit_bytes: u64,
    ) -> Result<()> {
        crate::workspace::prepare_command_capture(&self.workspace_files(), target.model_file())
            .await?;
        // The remote helper owns the capture beside the remote workspace and streams it to the live
        // observer; there is no local fragment, so the local committed length starts at zero.
        Ok(())
    }

    async fn publish_output(&self, _target: &CommandOutputTarget) -> Result<()> {
        Ok(())
    }

    async fn collect_output_artifacts(
        &self,
        _target: &CommandOutputTarget,
        _sizes: CommandOutputSizes,
    ) -> Result<Vec<Value>> {
        Ok(Vec::new())
    }
}

fn path_within(executor: &Executor, path: &TargetPath, root: &TargetPath) -> bool {
    if executor.target_info().os == "windows" {
        std::path::Path::new(path.as_str()).starts_with(root.as_str())
    } else {
        let root = root.as_str().trim_end_matches('/');
        root.is_empty() || path.as_str() == root || path.as_str().starts_with(&format!("{root}/"))
    }
}
