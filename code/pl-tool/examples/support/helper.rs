//! 观察入口共享的 helper 进程所有权。
//!
//! 成功、失败、超时与取消都必须走同一条收尾路径：退出裁决 → stderr 排空 → 后代回收。
//! 拒绝在未真正 wait/reap 的情况下把 helper 留在后台，也不把非零退出当成成功。
#![allow(dead_code)]

use std::collections::VecDeque;
use std::path::Path;
use std::process::{ExitStatus, Stdio};
use std::time::{Duration, Instant};

use anyhow::{Context, ensure};
use pl_tool::remote::RemoteClient;
use tokio::io::AsyncReadExt;
use tokio::process::{Child, ChildStderr, ChildStdin, ChildStdout};

use crate::outcome::TaskOwner;

const STDERR_LIMIT: usize = 64 * 1024;

/// 该场景期望的 helper 退出结果。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExitExpectation {
    /// 调用方显式发送单向 `Shutdown` 后正常退出：必须以成功状态退出。
    ///
    /// 只关本地句柄（transport EOF）不是成功收尾，helper 会以非零状态报告连接意外结束。
    Success,
    /// 控制流意外 EOF、租约过期等失败收尾：必须以非零状态退出，不能被当成成功。
    Failure,
}

/// 显式发送单向 `Shutdown`，等真实断连，再走完整 client teardown。
///
/// 正常收尾必须由请求触发：只调用 `close()`（关本地句柄）会让 helper 把控制流当成意外 EOF
/// 并以非零状态退出，因此成功场景一律走这里，失败场景才允许裸 `close()`。
///
/// `wait_disconnected()` 只证明传输 driver 结束；完整 teardown 还要 `close()` 并核对最终状态。
/// 这里不吞任何错误：若生产实现把预期 peer EOF 归类为 `Disconnected` 或其他错误，原错误连同
/// source 一起返回，由传输 owner 决定分类，绝不按字符串当成成功。
pub async fn request_graceful_shutdown(client: &RemoteClient) -> anyhow::Result<()> {
    client
        .request_shutdown()
        .await
        .context("the helper rejected the one-way shutdown request")?;
    tokio::time::timeout(Duration::from_secs(30), client.wait_disconnected())
        .await
        .context("the helper did not close the transport after shutdown")?;
    client
        .close()
        .await
        .context("full client teardown after the one-way shutdown failed")?;
    ensure!(
        client.is_disconnected(),
        "the client still reports a live transport after full teardown"
    );
    Ok(())
}

/// 一个真实 helper 进程及其全部清理责任。
pub struct Helper {
    child: Child,
    stdout: Option<ChildStdout>,
    stdin: Option<ChildStdin>,
    stderr: Option<tokio::task::JoinHandle<anyhow::Result<String>>>,
    stderr_drained: bool,
    descendants: Vec<u32>,
    status: Option<ExitStatus>,
}

impl Helper {
    /// 启动 `pl-remote-helper --serve`；只能用 `PURE_HELPER_BIN` 覆盖可执行文件路径。
    pub async fn start() -> anyhow::Result<Self> {
        let executable =
            std::env::var("PURE_HELPER_BIN").unwrap_or_else(|_| "pl-remote-helper".to_string());
        let mut child = tokio::process::Command::new(executable)
            .arg("--serve")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .context("failed to start pl-remote-helper --serve")?;
        // 进程已经启动：任何管道提取失败都必须先真正回收，不能交给 kill_on_drop 兜底。
        let Some(stdout) = child.stdout.take() else {
            reap(&mut child).await;
            anyhow::bail!("helper stdout pipe is unavailable");
        };
        let Some(stdin) = child.stdin.take() else {
            reap(&mut child).await;
            anyhow::bail!("helper stdin pipe is unavailable");
        };
        let Some(stderr) = child.stderr.take() else {
            reap(&mut child).await;
            anyhow::bail!("helper stderr pipe is unavailable");
        };
        let stderr = tokio::spawn(drain_stderr(stderr));
        Ok(Self {
            child,
            stdout: Some(stdout),
            stdin: Some(stdin),
            stderr: Some(stderr),
            stderr_drained: false,
            descendants: Vec::new(),
            status: None,
        })
    }

    /// helper 的物理进程 id，用于读取 `/proc` 资源事实。
    pub fn id(&self) -> u32 {
        self.child.id().unwrap_or_default()
    }

    /// 用生产 typed client 完成 hello 握手，取得该连接的客户端。
    pub async fn connect(&mut self) -> anyhow::Result<RemoteClient> {
        // 与 `take_pipes` 相同的原子交接语义。
        let (stdout, stdin) = self.take_pipes()?;
        Ok(RemoteClient::connect(stdout, stdin).await?)
    }

    /// 直接取出 stdio 管道，供用生产传输扮演对端的观察场景使用。
    pub fn take_pipes(&mut self) -> anyhow::Result<(ChildStdout, ChildStdin)> {
        // 原子交接：两根管道都在时一次性取出，任一缺失都不改变 ownership，
        // 避免“stdout 已取走、stdin 失败”留下无法回收的半交接状态。
        if self.stdout.is_none() || self.stdin.is_none() {
            anyhow::bail!(
                "helper stdio was already taken (stdout={}, stdin={})",
                self.stdout.is_some(),
                self.stdin.is_some()
            );
        }
        let stdout = self.stdout.take().context("helper stdout disappeared")?;
        let stdin = self.stdin.take().context("helper stdin disappeared")?;
        Ok((stdout, stdin))
    }

    /// 登记本次场景在远端启动的后代进程，收尾时逐个核对消失。
    pub fn register_descendant(&mut self, pid: u32) {
        if !self.descendants.contains(&pid) {
            self.descendants.push(pid);
        }
    }

    /// 等待 helper 退出。
    ///
    /// 超时不是“已清理”：先请求终止并真正 `wait` 到进程退出，然后以错误报告；
    /// stderr 与后代核对仍由 [`Self::finish`] 继续执行。
    pub async fn wait_exit(
        &mut self,
        expectation: ExitExpectation,
        deadline: Duration,
    ) -> anyhow::Result<ExitStatus> {
        let status = match self.status {
            Some(status) => status,
            None => match tokio::time::timeout(deadline, self.child.wait()).await {
                Ok(result) => result.context("failed to wait for the helper process")?,
                Err(_) => {
                    let _ = self.child.kill().await;
                    let _ = self.child.wait().await;
                    anyhow::bail!(
                        "helper did not exit within {deadline:?}; it was terminated and reaped"
                    );
                }
            },
        };
        self.status = Some(status);
        match expectation {
            ExitExpectation::Success => ensure!(
                status.success(),
                "helper exited with an unexpected failure status: {status}"
            ),
            ExitExpectation::Failure => ensure!(
                !status.success(),
                "helper exit was expected to report a failure, got success: {status}"
            ),
        }
        Ok(status)
    }

    /// 排空并交回有界 stderr 诊断；调用前应已退出。
    ///
    /// EOF、读错误、任务失败与超时是四类不同结果：读错误与任务失败原样传播，
    /// 超时先 abort 再真实 join，绝不把任务 detached 留在后台。
    pub async fn stderr(&mut self) -> anyhow::Result<String> {
        let Some(mut task) = self.stderr.take() else {
            anyhow::ensure!(self.stderr_drained, "helper stderr pipe was never taken");
            return Ok(String::new());
        };
        self.stderr_drained = true;
        match tokio::time::timeout(Duration::from_secs(10), &mut task).await {
            Ok(Ok(Ok(text))) => Ok(text),
            Ok(Ok(Err(error))) => Err(error.context("helper stderr read failed")),
            Ok(Err(join)) => Err(anyhow::Error::new(join).context("helper stderr task failed")),
            Err(_) => {
                task.abort();
                // 真实 abort + join：取消是预期结果，其他 join 失败必须报告。
                match task.await {
                    Ok(_) => {}
                    Err(join) if join.is_cancelled() => {}
                    Err(join) => {
                        anyhow::bail!("helper stderr task did not join after abort: {join}");
                    }
                }
                anyhow::bail!("helper stderr did not drain after exit")
            }
        }
    }

    /// 核对本次登记的后代进程都已消失。
    pub async fn verify_descendants(&self) -> anyhow::Result<()> {
        for pid in &self.descendants {
            wait_until_process_gone(*pid, Duration::from_secs(15)).await?;
        }
        Ok(())
    }

    /// 统一收尾：退出裁决 → stderr 排空 → 后代回收，任一步失败都报告。
    pub async fn finish(
        mut self,
        expectation: ExitExpectation,
        deadline: Duration,
    ) -> anyhow::Result<String> {
        let exit = self.wait_exit(expectation, deadline).await;
        let stderr = self.stderr().await;
        let descendants = self.verify_descendants().await;
        let mut failures = Vec::new();
        if let Err(error) = &exit {
            failures.push(format!("exit: {error:#}"));
        }
        if let Err(error) = &stderr {
            failures.push(format!("stderr: {error:#}"));
        }
        if let Err(error) = &descendants {
            failures.push(format!("descendants: {error:#}"));
        }
        if failures.is_empty() {
            Ok(stderr.unwrap_or_default())
        } else {
            anyhow::bail!("helper cleanup failed: {}", failures.join("; "))
        }
    }
}

async fn reap(child: &mut Child) {
    let _ = child.kill().await;
    let _ = child.wait().await;
}

/// 排空 helper stderr，保留有界尾部并如实区分 EOF 与读错误。
///
/// 有界语义只影响保留长度（超出部分丢弃并计数），不影响错误传播：
/// 读错误必须作为失败返回，不能像 EOF 一样静默结束。
async fn drain_stderr(mut stderr: ChildStderr) -> anyhow::Result<String> {
    // 真正的有界**尾部**：滑动窗口保留最后 STDERR_LIMIT 字节（终态诊断在末尾），
    // 被挤出的旧字节只计数，不改变“保留的是尾部”这一语义。
    let mut tail: VecDeque<u8> = VecDeque::with_capacity(STDERR_LIMIT + 1);
    let mut dropped = 0usize;
    let mut buffer = [0u8; 4096];
    loop {
        let count = match stderr.read(&mut buffer).await {
            // helper 关闭 stderr：正常 EOF。
            Ok(0) => break,
            Ok(count) => count,
            Err(error) => {
                // 失败路径保留已读尾部，便于定位；source 原样保留。
                let seen = String::from_utf8_lossy(tail.make_contiguous()).into_owned();
                return Err(anyhow::Error::new(error).context(format!(
                    "helper stderr read failed after {dropped} dropped byte(s); tail: {seen}"
                )));
            }
        };
        for &byte in &buffer[..count] {
            if tail.len() == STDERR_LIMIT {
                tail.pop_front();
                dropped += 1;
            }
            tail.push_back(byte);
        }
    }
    let mut text = String::from_utf8_lossy(tail.make_contiguous()).into_owned();
    if dropped > 0 {
        text.push_str(&format!(
            "\n[stderr truncated: {dropped} leading bytes dropped]"
        ));
    }
    anyhow::Ok(text)
}

/// 统一场景收尾：先 cancel+join 全部本地 task，再裁决 helper 退出、排空 stderr、回收后代。
///
/// 只有“场景主体成功 + 全部清理成功”才允许 drop 拥有目录；否则通过 `TempDir::keep()` 保留本次
/// fixture 并报告真实路径，绝不把“本地 abort/ join 完成”当作远端或暂存责任已经收束的证据。
pub async fn finish_scenario(
    outcome: anyhow::Result<()>,
    tasks: &mut TaskOwner,
    helper: Helper,
    fixture: Option<tempfile::TempDir>,
    expectation: ExitExpectation,
    deadline: Duration,
    check: impl FnOnce(&str, Option<&std::path::Path>) -> anyhow::Result<()>,
) -> anyhow::Result<()> {
    let tasks_cleanup = tasks.shutdown().await;
    // helper 先真实退出、stderr 排空、后代回收；只有这一步成功后才把拥有目录交回检查，
    // 因为 TempDir 的自动删除会掩盖远端遗留的暂存或半成品。
    let helper_cleanup = helper
        .finish(expectation, deadline)
        .await
        .and_then(|stderr| check(&stderr, fixture.as_ref().map(tempfile::TempDir::path)));
    let mut failures: Vec<String> = Vec::new();
    if let Err(error) = &tasks_cleanup {
        failures.push(format!("tasks: {error:#}"));
    }
    if let Err(error) = &helper_cleanup {
        failures.push(format!("helper: {error:#}"));
    }
    if outcome.is_ok() && failures.is_empty() {
        drop(fixture);
        return Ok(());
    }
    let retained = match fixture {
        Some(fixture) => fixture.keep(),
        None => std::path::PathBuf::from("<no owned fixture>"),
    };
    let mut combined = match outcome {
        Ok(()) => anyhow::anyhow!("scenario completed but its cleanup failed"),
        Err(error) => error,
    };
    if !failures.is_empty() {
        combined = combined.context(format!("cleanup: {}", failures.join("; ")));
    }
    Err(combined.context(format!("owned fixture retained at {}", retained.display())))
}

pub fn process_alive(pid: u32) -> bool {
    Path::new(&format!("/proc/{pid}")).exists()
}

pub async fn wait_until_process_gone(pid: u32, deadline: Duration) -> anyhow::Result<()> {
    let deadline = Instant::now() + deadline;
    while process_alive(pid) {
        ensure!(
            Instant::now() < deadline,
            "process {pid} still exists after the cleanup deadline"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    Ok(())
}
