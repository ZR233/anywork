//! Protocol-neutral LSP host over the same process and filesystem executor.
use super::{
    LspHostBackend, LspHostError, LspHostFileStat, LspHostProcess, LspHostProcessExit,
    LspHostSpawnRequest, LspPathStyle,
};
use futures::{FutureExt, future::BoxFuture};
use pl_remote_helper::{Executor, Stdio, TargetPath};
use std::path::Path;

#[derive(Debug, Clone)]
pub struct ExecutorLspHost {
    executor: Executor,
    root: TargetPath,
}

impl ExecutorLspHost {
    pub fn new(executor: Executor, root: &str) -> Result<Self, LspHostError> {
        let root = executor.path(root).map_err(host_error)?;
        Ok(Self { executor, root })
    }
    fn path(&self, path: &Path) -> Result<TargetPath, LspHostError> {
        self.executor
            .join_path(
                &self.root,
                path.to_str()
                    .ok_or_else(|| LspHostError::new("LSP path is not UTF-8"))?,
            )
            .map_err(host_error)
    }
}

impl LspHostBackend for ExecutorLspHost {
    fn path_style(&self) -> LspPathStyle {
        if self.executor.target_info().os == "windows" {
            LspPathStyle::Native
        } else {
            LspPathStyle::Posix
        }
    }
    fn identity(&self) -> String {
        format!("executor:{:?}:{}", self.executor.id(), self.root.as_str())
    }
    fn read_file<'a>(
        &'a self,
        path: &'a Path,
        max_bytes: u64,
    ) -> BoxFuture<'a, Result<Vec<u8>, LspHostError>> {
        async move {
            use tokio::io::AsyncReadExt;
            let path = self.path(path)?;
            let mut reader = self
                .executor
                .fs()
                .read(&path)
                .await
                .map_err(host_error)?
                .take(max_bytes.saturating_add(1));
            let mut bytes = Vec::new();
            reader.read_to_end(&mut bytes).await.map_err(host_error)?;
            if bytes.len() as u64 > max_bytes {
                return Err(LspHostError::new("LSP document exceeds its byte limit"));
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
            let path = self.path(path)?;
            self.executor
                .fs()
                .metadata(&path)
                .await
                .map(|metadata| {
                    metadata.map(|metadata| LspHostFileStat {
                        is_file: metadata.is_file,
                        byte_size: metadata.len,
                    })
                })
                .map_err(host_error)
        }
        .boxed()
    }
    fn list_directory<'a>(
        &'a self,
        path: &'a Path,
        max_entries: usize,
    ) -> BoxFuture<'a, Result<Vec<String>, LspHostError>> {
        async move {
            let path = self.path(path)?;
            let mut directory = self
                .executor
                .fs()
                .read_dir(&path)
                .await
                .map_err(host_error)?;
            let mut names = Vec::new();
            while let Some(entry) = directory.next().await.map_err(host_error)? {
                if entry.is_symlink {
                    continue;
                }
                if names.len() == max_entries {
                    return Err(LspHostError::new("LSP directory exceeds its entry limit"));
                }
                names.push(entry.name);
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
            let cwd = self.path(&request.cwd)?;
            let mut command = self.executor.command(request.program);
            command.args(request.args).envs(request.env).current_dir(cwd.as_str()).stdin(Stdio::Piped).stdout(Stdio::Piped).stderr(Stdio::Piped);
            let mut child = tokio::select! {
                biased;
                _ = request.cancellation.cancelled() => return Err(LspHostError::new("LSP startup cancelled")),
                result = tokio::time::timeout_at(request.deadline, command.spawn()) => result.map_err(|_| LspHostError::new("LSP startup timed out"))?.map_err(host_error)?,
            };
            // Transfer protocol input before constructing any root-wait future.
            let stdin = child.stdin.take().map(|pipe| Box::pin(pipe) as super::LspHostWriter);
            let stdout = child.stdout.take().map(|pipe| Box::pin(pipe) as super::LspHostReader);
            let stderr = child.stderr.take().map(|pipe| Box::pin(pipe) as super::LspHostReader);
            let cancel = tokio_util::sync::CancellationToken::new(); let stop = cancel.clone();
            Ok(LspHostProcess::new(stdin, stdout, stderr, async move {
                let exit = tokio::select! {
                    result = child.wait() => result,
                    _ = stop.cancelled() => { child.start_kill().await.map_err(host_error)?; child.wait().await },
                }.map_err(host_error)?;
                Ok(LspHostProcessExit { exit_code: exit.code() })
            }, move || async move { cancel.cancel(); }.boxed()))
        }.boxed()
    }
}

fn host_error(error: impl std::fmt::Display) -> LspHostError {
    LspHostError::new(error.to_string())
}
