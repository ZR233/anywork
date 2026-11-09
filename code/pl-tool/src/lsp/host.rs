//! Local workspace LSP host: filesystem primitives plus supervised language servers.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use futures::FutureExt;
use futures::future::BoxFuture;
use pl_lsp::host::{
    LspHostBackend, LspHostError, LspHostFileStat, LspHostProcess, LspHostProcessExit,
    LspHostSpawnRequest,
};

use crate::command::LocalWorkerExecutable;
use crate::workspace::ToolPathPolicy;
use pl_remote_helper::client::{
    ManagedWorker, ProcessCommand, ProcessTermination, WorkerClientError,
};

/// 本地 workspace 的 LSP 宿主。
///
/// 文件原语在 workspace 边界内直接读取本地文件系统；language server 交给既有 helper
/// 的 per-child 监督 owner 启动，因此进程树随宿主生存，并在终止时按
/// `SIGTERM → 2s → SIGKILL` 整树回收，而不是只结束 leader。
#[derive(Debug, Clone)]
pub struct LocalLspHostBackend {
    policy: ToolPathPolicy,
    worker_executable: Result<Arc<dyn LocalWorkerExecutable>, String>,
}

impl LocalLspHostBackend {
    /// 构造绑定到 `workspace_root`、以 `worker_executable` 为监督者的本地 LSP 宿主。
    ///
    /// `worker_executable` 由宿主从既有 remote helper 资源注入，不在本层回退到 PATH 或
    /// 未监督 spawn。
    ///
    /// # Errors
    /// workspace 根无法解析为本地真实目录时返回错误。
    pub fn new<P>(
        workspace_root: impl Into<PathBuf>,
        worker_executable: P,
    ) -> Result<Self, LspHostError>
    where
        P: AsRef<Path> + std::fmt::Debug + Send + Sync + 'static,
    {
        let workspace_root = workspace_root.into();
        let policy =
            ToolPathPolicy::new(workspace_root.clone(), false, "lsp_host").map_err(host_error)?;
        Ok(Self {
            policy,
            worker_executable: Ok(Arc::new(worker_executable)),
        })
    }

    /// Preserve workspace configuration/status access when the supervised worker
    /// cannot be prepared. No process may start through this host.
    pub fn unavailable(
        workspace_root: impl Into<PathBuf>,
        reason: impl Into<String>,
    ) -> Result<Self, LspHostError> {
        let policy =
            ToolPathPolicy::new(workspace_root.into(), false, "lsp_host").map_err(host_error)?;
        Ok(Self {
            policy,
            worker_executable: Err(reason.into()),
        })
    }
}

impl LspHostBackend for LocalLspHostBackend {
    fn path_style(&self) -> pl_lsp::host::LspPathStyle {
        pl_lsp::host::LspPathStyle::Native
    }
    fn identity(&self) -> String {
        let worker = match &self.worker_executable {
            // A Studio build fixes the worker image. Temporary fd paths are
            // resource leases, not execution-host identities; reconstructing
            // tools must not restart healthy language servers.
            Ok(_) => "available".to_string(),
            Err(reason) => format!("unavailable:{reason}"),
        };
        format!("local:{}:{worker}", self.policy.root().display())
    }

    fn read_file<'a>(
        &'a self,
        path: &'a Path,
        max_bytes: u64,
    ) -> BoxFuture<'a, Result<Vec<u8>, LspHostError>> {
        async move {
            use tokio::io::AsyncReadExt;
            let resolved = self.resolve_existing(path)?;
            let file = tokio::fs::File::open(&resolved).await.map_err(host_error)?;
            let metadata = file.metadata().await.map_err(host_error)?;
            if !metadata.is_file() {
                return Err(LspHostError::new(format!(
                    "LSP document is not a file: {}",
                    resolved.display()
                )));
            }
            // Bounded read: never pull more than one byte past the limit, so the source
            // cannot force an unbounded allocation between the stat check and the read.
            let limit = max_bytes.saturating_add(1);
            let mut reader = file.take(limit);
            let mut bytes = Vec::new();
            reader.read_to_end(&mut bytes).await.map_err(host_error)?;
            if bytes.len() as u64 > max_bytes {
                return Err(LspHostError::new(format!(
                    "LSP document {} exceeds the {max_bytes} byte source limit",
                    resolved.display()
                )));
            }
            Ok(bytes)
        }
        .boxed()
    }

    fn stat<'a>(
        &'a self,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<Option<LspHostFileStat>, LspHostError>> {
        async move {
            match self.resolve_existing(path) {
                Ok(resolved) => {
                    let metadata = tokio::fs::metadata(&resolved).await.map_err(host_error)?;
                    Ok(Some(LspHostFileStat {
                        is_file: metadata.is_file(),
                        byte_size: metadata.len(),
                    }))
                }
                // `resolve_existing` conflates "absent" with boundary/permission failures.
                // Only a genuinely missing target is a `None`; every other failure — an
                // out-of-workspace path, a symlink boundary, or a permission error — must
                // surface instead of being hidden as "no host fact".
                Err(error) => {
                    match tokio::fs::symlink_metadata(self.policy.candidate(path)).await {
                        Err(io) if io.kind() == std::io::ErrorKind::NotFound => Ok(None),
                        _ => Err(error),
                    }
                }
            }
        }
        .boxed()
    }

    fn list_directory<'a>(
        &'a self,
        path: &'a Path,
        max_entries: usize,
    ) -> BoxFuture<'a, Result<Vec<String>, LspHostError>> {
        async move {
            // Contract matches the remote host and the trait doc: first-level *names*
            // (not paths), excluding link/reparse entries, for `glob_match` detection.
            let display = path.display().to_string();
            let resolved = self
                .policy
                .resolve_existing_directory(path, &display)
                .map_err(host_error)?;
            let mut entries = tokio::fs::read_dir(resolved).await.map_err(host_error)?;
            let mut names = Vec::new();
            while let Some(entry) = entries.next_entry().await.map_err(host_error)? {
                if !entry.file_type().await.map_err(host_error)?.is_symlink() {
                    if names.len() == max_entries {
                        return Err(LspHostError::new(format!(
                            "LSP directory exceeds {max_entries} entries"
                        )));
                    }
                    names.push(entry.file_name().to_string_lossy().into_owned());
                }
            }
            Ok(names)
        }
        .boxed()
    }

    fn spawn<'a>(
        &'a self,
        request: LspHostSpawnRequest,
    ) -> BoxFuture<'a, Result<LspHostProcess, LspHostError>> {
        async move {
            let worker = self
                .worker_executable
                .as_ref()
                .map_err(|reason| LspHostError::new(reason.clone()))?
                .clone();
            let mut specification = ProcessCommand::new(request.program)
                .args(request.args)
                .current_dir(self.resolve_existing(&request.cwd)?);
            for (key, value) in request.env {
                specification = specification.env(key, value);
            }
            let start = crate::command::CommandStartControl::new(
                request.deadline,
                request.cancellation,
                Default::default(),
            );
            let mut process =
                ManagedWorker::spawn_controlled(worker.worker_path(), specification, &start)
                    .await
                    .map_err(host_error)?;
            let stdin = process
                .take_stdin()
                .map(|io| Box::pin(io) as std::pin::Pin<Box<dyn tokio::io::AsyncWrite + Send>>);
            let stdout = process
                .take_stdout()
                .map(|io| Box::pin(io) as std::pin::Pin<Box<dyn tokio::io::AsyncRead + Send>>);
            let stderr = process
                .take_stderr()
                .map(|io| Box::pin(io) as std::pin::Pin<Box<dyn tokio::io::AsyncRead + Send>>);
            let control = process.control();
            let cleanup_failures = control.cleanup_failures();
            Ok(LspHostProcess::new(
                stdin,
                stdout,
                stderr,
                async move {
                    let _worker_owner = worker;
                    match process.wait().await {
                        Ok(exit) => Ok(LspHostProcessExit {
                            exit_code: match exit {
                                ProcessTermination::ExitCode(code) => Some(code),
                                ProcessTermination::Signal(_) => None,
                            },
                        }),
                        Err(error @ WorkerClientError::StartFailed { .. })
                            if cleanup_failures.borrow().is_none() =>
                        {
                            // ManagedWorker::wait has reaped the supervisor. A
                            // typed StartFailed means no business tree existed.
                            Err(LspHostError::reclaimed_start_failure(error.to_string()))
                        }
                        Err(error) => Err(host_error(error)),
                    }
                },
                move || {
                    async move {
                        if control.cancel().await.is_err() {
                            control.close();
                        }
                    }
                    .boxed()
                },
            ))
        }
        .boxed()
    }
}

impl LocalLspHostBackend {
    fn resolve_existing(&self, path: &Path) -> Result<PathBuf, LspHostError> {
        self.policy
            .resolve_existing_path(path, &path.display().to_string())
            .map_err(host_error)
    }
}

fn host_error(error: impl std::fmt::Display) -> LspHostError {
    LspHostError::new(error.to_string())
}
