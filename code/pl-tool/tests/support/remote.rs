#![allow(dead_code)]
//! A real foreground helper process and its one immutable execution connection.
use anyhow::Context;
use pl_remote_helper::Executor;
use pl_tool::command::ExecutorCommandBackend;
use pl_tool::workspace_file::ExecutorWorkspaceFileBackend;
use std::{path::Path, process::Stdio, time::Duration};
use tokio::io::AsyncReadExt;
pub struct Helper {
    pub executor: Executor,
    pub files: ExecutorWorkspaceFileBackend,
    pub root: tempfile::TempDir,
    relay: tokio::process::Child,
    stderr: tokio::task::JoinHandle<std::io::Result<Vec<u8>>>,
    transport: tokio::task::JoinHandle<std::io::Result<()>>,
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
        let stderr = tokio::spawn(async move {
            let mut prefix = Vec::new();
            (&mut diagnostic)
                .take(16 * 1024)
                .read_to_end(&mut prefix)
                .await?;
            tokio::io::copy(&mut diagnostic, &mut tokio::io::sink()).await?;
            Ok(prefix)
        });
        let mut stdout = relay.stdout.take().context("stdout")?;
        let mut stdin = relay.stdin.take().context("stdin")?;
        let (transport, proxy) = tokio::io::duplex(64 * 1024);
        let forwarding = tokio::spawn(async move {
            // Client close delivers stdin EOF, while this process owner keeps stdout open until
            // exit. Dropping both OS pipe ends together would manufacture a server BrokenPipe.
            let (mut requests, mut responses) = tokio::io::split(proxy);
            let input = async {
                let result = tokio::io::copy(&mut requests, &mut stdin).await;
                // ChildStdin::shutdown does not close the Unix pipe; drop the owned handle.
                drop(stdin);
                result.map(|_| ())
            };
            let output = async {
                match tokio::io::copy(&mut stdout, &mut responses).await {
                    Err(error) if error.kind() == std::io::ErrorKind::BrokenPipe => {
                        tokio::io::copy(&mut stdout, &mut tokio::io::sink())
                            .await
                            .map(|_| ())
                    }
                    result => result.map(|_| ()),
                }
            };
            let (input, output) = tokio::join!(input, output);
            input?;
            output
        });
        let executor = Executor::remote(transport).await?;
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
            transport: forwarding,
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
        let diagnostic = self.stderr.await??;
        let transport = self.transport.await?;
        anyhow::ensure!(
            status.success(),
            "foreground helper failed: {status}: {}",
            String::from_utf8_lossy(&diagnostic),
        );
        transport?;
        Ok(())
    }
}
