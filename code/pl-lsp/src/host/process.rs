use std::io;
use std::pin::Pin;

use pl_remote_helper::process::{
    BackgroundChild, spawn_background_command, wrap_background_command,
};
use tokio::process::Command;

use super::{LspHostProcess, LspHostReader, LspHostWriter};

pub(crate) enum LspChild {
    Local(BackgroundChild),
    Hosted(LspHostProcess),
}

impl LspChild {
    pub(crate) fn startup_failure(&self) -> Option<&str> {
        match self {
            Self::Hosted(child) => child.startup_failure(),
            Self::Local(_) => None,
        }
    }
    pub(crate) fn take_stdin(&mut self) -> Option<LspHostWriter> {
        match self {
            Self::Local(child) => child
                .stdin
                .take()
                .map(|stdin| Box::pin(stdin) as LspHostWriter),
            Self::Hosted(child) => child.take_stdin(),
        }
    }

    pub(crate) fn take_stdout(&mut self) -> Option<LspHostReader> {
        match self {
            Self::Local(child) => child
                .stdout
                .take()
                .map(|stdout| Box::pin(stdout) as LspHostReader),
            Self::Hosted(child) => child.take_stdout(),
        }
    }

    pub(crate) fn take_stderr(&mut self) -> Option<LspHostReader> {
        match self {
            Self::Local(child) => child
                .stderr
                .take()
                .map(|stderr| Box::pin(stderr) as LspHostReader),
            Self::Hosted(child) => child.take_stderr(),
        }
    }

    pub(crate) async fn wait(&mut self) -> Result<(), String> {
        match self {
            Self::Local(child) => child
                .process
                .wait()
                .await
                .map(|_| ())
                .map_err(|error| error.to_string()),
            Self::Hosted(child) => child
                .wait()
                .await
                .map(|_| ())
                .map_err(|error| error.to_string()),
        }
    }

    /// 请求终止并等待整棵进程树真实退出。
    ///
    /// `Ok(Some(issue))` 表示已确认回收但请求路径降级；`Ok(None)` 为完全优雅；
    /// `Err` 表示无法确认回收，调用方必须保留 child owner 以便复用/重试。
    pub(crate) async fn terminate_and_wait(&mut self) -> Result<Option<String>, String> {
        match self {
            Self::Local(child) => {
                let kill_issue = match Pin::from(child.process.kill()).await {
                    Ok(()) => None,
                    Err(error) => Some(format!("LSP process kill request failed: {error}")),
                };
                match child.process.wait().await {
                    Ok(_status) => Ok(kill_issue),
                    Err(error) => Err(error.to_string()),
                }
            }
            Self::Hosted(child) => child
                .terminate()
                .await
                .map(|()| None)
                .map_err(|error| error.to_string()),
        }
    }
}

/// 非 Linux 原生宿主派生 LSP 后台子进程的统一入口。
///
/// 复用跨端进程工厂的 Job Object / process group 所有权和平台 I/O 驱动，
/// 不在 LSP 内维护另一套创建标志、管道读取或进程树策略。
pub(crate) fn spawn_background(command: Command) -> io::Result<BackgroundChild> {
    spawn_background_command(&mut wrap_background_command(command)).map_err(io::Error::from)
}
