use std::collections::BTreeMap;
use std::fmt;
use std::future::Future;
use std::path::PathBuf;
use std::time::Duration;

/// 通用命令执行请求。
#[derive(Clone, PartialEq, Eq)]
pub struct ExecutionRequest {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub cwd: PathBuf,
    pub env: BTreeMap<String, String>,
    pub timeout: Option<Duration>,
}

impl fmt::Debug for ExecutionRequest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let env = self
            .env
            .keys()
            .map(|key| {
                let value = if key.contains("TOKEN") || key.contains("PASSWORD") {
                    "[redacted]"
                } else {
                    self.env.get(key).map(String::as_str).unwrap_or_default()
                };
                (key, value)
            })
            .collect::<BTreeMap<_, _>>();
        f.debug_struct("ExecutionRequest")
            .field("program", &self.program)
            .field("args", &self.args)
            .field("cwd", &self.cwd)
            .field("env", &env)
            .field("timeout", &self.timeout)
            .finish()
    }
}

/// 通用命令执行结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExecutionOutput {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

/// shell/process 类工具共用的执行后端。
///
/// 实现方负责在指定工作目录运行命令，并遵守请求中给出的环境和超时。
pub trait ExecutionBackend: fmt::Debug + Send + Sync {
    type Error: fmt::Display + Send + 'static;

    fn run(
        &self,
        request: ExecutionRequest,
    ) -> impl Future<Output = std::result::Result<ExecutionOutput, Self::Error>> + Send;
}

/// 由装配层绑定执行位置，复用同一公共进程接口。
#[derive(Debug, Clone)]
pub struct ExecutorExecutionBackend {
    executor: Result<pl_remote_helper::Executor, pl_remote_helper::ExecutionError>,
}

impl Default for ExecutorExecutionBackend {
    fn default() -> Self {
        Self {
            executor: pl_remote_helper::Executor::local(),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ExecutionFailure {
    #[error(transparent)]
    Spawn(#[from] pl_remote_helper::SpawnError),
    #[error(transparent)]
    Execution(#[from] pl_remote_helper::ExecutionError),
    #[error("command timed out; cleanup is owned by the executor")]
    TimedOut,
}

impl ExecutorExecutionBackend {
    pub fn new(executor: pl_remote_helper::Executor) -> Self {
        Self {
            executor: Ok(executor),
        }
    }

    pub async fn run_classified(
        &self,
        request: ExecutionRequest,
    ) -> Result<ExecutionOutput, ExecutionFailure> {
        let started = tokio::time::Instant::now();
        let executor = self
            .executor
            .as_ref()
            .map_err(|cause| ExecutionFailure::Execution(cause.clone()))?;
        let program = request.program.to_str().ok_or_else(|| {
            pl_remote_helper::ExecutionError::InvalidInput("program path is not UTF-8".into())
        })?;
        let cwd = request.cwd.to_str().ok_or_else(|| {
            pl_remote_helper::ExecutionError::InvalidInput("working directory is not UTF-8".into())
        })?;
        let mut command = executor.command(program);
        command
            .args(request.args)
            .current_dir(cwd)
            .envs(request.env)
            .stdout(pl_remote_helper::Stdio::Piped)
            .stderr(pl_remote_helper::Stdio::Piped);
        let execute = async {
            let child = command.spawn().await?;
            Ok::<_, ExecutionFailure>(child.wait_with_output().await?)
        };
        let output = match request.timeout {
            Some(duration) => tokio::time::timeout_at(started + duration, execute)
                .await
                .map_err(|_| ExecutionFailure::TimedOut)??,
            None => execute.await?,
        };
        Ok(ExecutionOutput {
            status: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }
}

impl ExecutionBackend for ExecutorExecutionBackend {
    type Error = ExecutionFailure;
    async fn run(&self, request: ExecutionRequest) -> Result<ExecutionOutput, Self::Error> {
        self.run_classified(request).await
    }
}
