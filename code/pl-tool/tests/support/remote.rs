#![allow(dead_code)]
//! A real foreground helper process and its one immutable execution connection.
use anyhow::Context;
use pl_remote_helper::Executor;
use pl_tool::command::ExecutorCommandBackend;
use pl_tool::workspace_file::ExecutorWorkspaceFileBackend;
use std::{path::Path, process::Stdio, time::Duration};
pub struct Helper {
    pub executor: Executor,
    pub files: ExecutorWorkspaceFileBackend,
    pub root: tempfile::TempDir,
    relay: tokio::process::Child,
    stderr: tokio::task::JoinHandle<std::io::Result<u64>>,
}
impl Helper {
    pub async fn start(executable: &Path) -> anyhow::Result<Self> {
        let root = tempfile::tempdir()?;
        let mut relay = tokio::process::Command::new(executable)
            .arg("--stdio")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()?;
        let mut diagnostic = relay.stderr.take().context("stderr")?;
        let stderr =
            tokio::spawn(
                async move { tokio::io::copy(&mut diagnostic, &mut tokio::io::sink()).await },
            );
        let executor = Executor::remote(tokio::io::join(
            relay.stdout.take().context("stdout")?,
            relay.stdin.take().context("stdin")?,
        ))
        .await?;
        let files = ExecutorWorkspaceFileBackend::new(
            executor.clone(),
            root.path().to_str().context("UTF-8 root")?,
        )?;
        Ok(Self {
            executor,
            files,
            root,
            relay,
            stderr,
        })
    }
    pub fn commands(&self) -> anyhow::Result<ExecutorCommandBackend> {
        Ok(ExecutorCommandBackend::new(
            self.executor.clone(),
            self.root.path().to_str().context("UTF-8 root")?,
            pl_tool::environment::ExecutionEnvironment::for_ssh(
                pl_tool::environment::ExecutionOs::Linux,
                pl_tool::environment::ShellDialect::Bash,
                "/bin/bash",
            ),
        )?)
    }
    pub async fn close(mut self) -> anyhow::Result<()> {
        self.executor.close().await?;
        let status = tokio::time::timeout(Duration::from_secs(3), self.relay.wait()).await??;
        anyhow::ensure!(status.success(), "foreground helper failed: {status}");
        self.stderr.await??;
        Ok(())
    }
}
