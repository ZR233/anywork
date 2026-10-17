//! OpenSSH argv 与一次性命令边界。
//!
//! 连接参数（端口、用户、私钥、代理）由 `~/.ssh/config` 的 Host 别名解析，
//! 这里只传别名本身；无密码时 BatchMode 固定关闭交互认证与提示，有密码时通过受控本地
//! `SSH_ASKPASS` 单次注入本地 OpenSSH 子进程环境。

use std::path::Path;

use process_wrap::tokio::{ChildWrapper, CommandWrap};
use tempfile::TempDir;
use tokio::process::Command;

use super::SshServerProfile;
use crate::remote::{RemoteClientError, SshAuthFailure};
use pl_remote_helper::process::wrap_parent_bound_command;

const SSH_ASKPASS_SECRET_ENV: &str = "ANYWORK_SSH_ASKPASS_SECRET";

pub(super) struct PreparedSshCommand {
    pub(super) command: CommandWrap,
    pub(super) _askpass_dir: Option<TempDir>,
}

pub(super) fn is_ssh_auth_failure(stderr: &str) -> bool {
    let lower = stderr.to_ascii_lowercase();
    lower.contains("permission denied")
        || lower.contains("authentication failed")
        || lower.contains("too many authentication failures")
}

fn parse_ssh_auth_methods(diagnostic: &str) -> Vec<String> {
    for line in diagnostic.lines() {
        let lower = line.to_ascii_lowercase();
        let Some(start) = lower.find("permission denied (") else {
            continue;
        };
        let methods_start = start + "permission denied (".len();
        let Some(end) = lower[methods_start..].find(')') else {
            continue;
        };
        return lower[methods_start..methods_start + end]
            .split(',')
            .map(str::trim)
            .filter(|item| !item.is_empty())
            .map(str::to_string)
            .collect();
    }
    Vec::new()
}

pub(super) fn auth_failure(diagnostic: &str) -> SshAuthFailure {
    SshAuthFailure::new(diagnostic.trim(), parse_ssh_auth_methods(diagnostic))
}

pub(super) fn classify_ssh_stderr(prefix: &str, stderr: &str) -> RemoteClientError {
    let trimmed = stderr.trim();
    if is_ssh_auth_failure(trimmed) {
        RemoteClientError::AuthenticationFailed(auth_failure(trimmed))
    } else {
        RemoteClientError::Protocol(format!("{prefix}: {trimmed}"))
    }
}

fn write_ssh_askpass_script(dir: &Path) -> Result<std::path::PathBuf, RemoteClientError> {
    #[cfg(windows)]
    {
        let script_path = dir.join("anywork-ssh-askpass.cmd");
        let content = format!("@echo off\r\necho %{SSH_ASKPASS_SECRET_ENV}%\r\n");
        std::fs::write(&script_path, content).map_err(|error| {
            RemoteClientError::Protocol(format!("failed to write ssh askpass script: {error}"))
        })?;
        Ok(script_path)
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let script_path = dir.join("anywork-ssh-askpass.sh");
        let content = format!("#!/bin/sh\nprintf '%s\\n' \"${SSH_ASKPASS_SECRET_ENV}\"\n");
        std::fs::write(&script_path, content).map_err(|error| {
            RemoteClientError::Protocol(format!("failed to write ssh askpass script: {error}"))
        })?;
        std::fs::set_permissions(&script_path, std::fs::Permissions::from_mode(0o700)).map_err(
            |error| {
                RemoteClientError::Protocol(format!(
                    "failed to set ssh askpass script permissions: {error}"
                ))
            },
        )?;
        Ok(script_path)
    }
}

pub(super) fn validate_profile(profile: &SshServerProfile) -> Result<(), RemoteClientError> {
    super::super::ssh_config::validate_alias(&profile.alias)?;
    for (field, value) in [
        ("hostName", profile.host_name.as_str()),
        ("username", profile.username.as_str()),
    ] {
        if value.trim().is_empty()
            || value.chars().any(char::is_control)
            || (matches!(field, "hostName" | "username") && value.starts_with('-'))
        {
            return Err(RemoteClientError::Protocol(format!(
                "SSH server {field} is invalid"
            )));
        }
    }
    if profile.port == 0 {
        return Err(RemoteClientError::Protocol(
            "SSH server port must be greater than zero".to_string(),
        ));
    }
    Ok(())
}

pub(super) async fn ssh_command(
    profile: &SshServerProfile,
    ssh_config: &super::super::ssh_config::SshConfigFile,
    password: Option<&str>,
) -> Result<PreparedSshCommand, RemoteClientError> {
    let mut command = Command::new("ssh");
    command
        .arg("-T")
        // SSH 进程只承载 stdio 协议，不需要 X11；显式关闭可避免用户 ssh
        // 配置中的 ForwardX11 设置向远端注入图形会话并产生 xauth 警告。
        .arg("-x")
        .args([
            "-o",
            "ConnectTimeout=15",
            "-o",
            "ServerAliveInterval=15",
            "-o",
            "ServerAliveCountMax=3",
        ]);
    let askpass_dir = match password.filter(|secret| !secret.is_empty()) {
        Some(secret) => {
            let temp_dir = tempfile::tempdir().map_err(|error| {
                RemoteClientError::Protocol(format!(
                    "failed to create ssh askpass directory: {error}"
                ))
            })?;
            let script_path = write_ssh_askpass_script(temp_dir.path())?;
            command
                .args([
                    "-o",
                    "BatchMode=no",
                    "-o",
                    "NumberOfPasswordPrompts=1",
                    "-o",
                    "PreferredAuthentications=publickey,keyboard-interactive,password",
                ])
                .env("SSH_ASKPASS", &script_path)
                .env("SSH_ASKPASS_REQUIRE", "force")
                .env("DISPLAY", "anywork:0")
                .env(SSH_ASKPASS_SECRET_ENV, secret);
            Some(temp_dir)
        }
        None => {
            command.args(["-o", "BatchMode=yes"]);
            None
        }
    };
    if ssh_config.is_explicit() {
        command.arg("-F").arg(ssh_config.path());
    }
    command.arg("--").arg(&profile.alias);
    Ok(PreparedSshCommand {
        command: wrap_parent_bound_command(command),
        _askpass_dir: askpass_dir,
    })
}

/// OpenSSH invokes the account shell; all bootstrap syntax belongs to POSIX sh.
pub(super) fn posix_remote_command(script: &str) -> String {
    format!("exec /bin/sh -c '{}'", script.replace('\'', "'\\''"))
}

pub(super) async fn run_ssh_capture(
    profile: &SshServerProfile,
    ssh_config: &super::super::ssh_config::SshConfigFile,
    password: Option<&str>,
    remote_command: &str,
) -> Result<String, RemoteClientError> {
    let mut prepared = ssh_command(profile, ssh_config, password).await?;
    prepared
        .command
        .command_mut()
        .arg(posix_remote_command(remote_command));
    let output = run_bounded_ssh(
        &mut prepared.command,
        None,
        "probe",
        std::time::Duration::from_secs(30),
    )
    .await?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(classify_ssh_stderr("ssh command failed", &stderr));
    }
    String::from_utf8(output.stdout)
        .map_err(|error| RemoteClientError::Protocol(format!("ssh output is not UTF-8: {error}")))
}

/// Owns the child through bounded timeout cleanup. Dropping the caller also
/// requests termination through the process-tree wrapper.
pub(super) async fn run_bounded_ssh(
    command: &mut CommandWrap,
    input: Option<&[u8]>,
    stage: &'static str,
    timeout: std::time::Duration,
) -> Result<std::process::Output, RemoteClientError> {
    use tokio::io::AsyncWriteExt;
    command
        .command_mut()
        .stdin(if input.is_some() {
            std::process::Stdio::piped()
        } else {
            std::process::Stdio::null()
        })
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    let mut child = command.spawn().map_err(|error| {
        RemoteClientError::Protocol(format!("SSH {stage} spawn failed: {error}"))
    })?;
    let stdout = child.stdout().take();
    let stderr = child.stderr().take();
    let stdin = child.stdin().take();
    let operation = async {
        let write = async {
            if let (Some(mut stdin), Some(bytes)) = (stdin, input) {
                stdin.write_all(bytes).await?;
                stdin.shutdown().await?;
            }
            Ok::<_, std::io::Error>(())
        };
        let (status, stdout, stderr, ()) = tokio::try_join!(
            child.wait(),
            capture_bounded(stdout, 65536),
            capture_bounded(stderr, 4096),
            write
        )?;
        Ok::<_, std::io::Error>(std::process::Output {
            status,
            stdout,
            stderr,
        })
    };
    match tokio::time::timeout(timeout, operation).await {
        Ok(Ok(output)) => Ok(output),
        result => {
            let reason = match result {
                Ok(Err(error)) => error.to_string(),
                Err(_) => "timed out".into(),
                Ok(Ok(_)) => unreachable!(),
            };
            terminate_ssh_child(&mut child, stage)
                .await
                .map_err(|error| {
                    RemoteClientError::Protocol(format!(
                        "SSH {stage} cleanup failed after {reason}: {error}"
                    ))
                })?;
            Err(RemoteClientError::Protocol(format!("SSH {stage} {reason}")))
        }
    }
}

/// Requests process-tree termination and bounds the local reap wait. The caller
/// retains the wrapper until this attempt finishes or reports a cleanup error.
pub(super) async fn terminate_ssh_child(
    child: &mut Box<dyn ChildWrapper>,
    stage: &str,
) -> Result<(), RemoteClientError> {
    let termination = child.start_kill();
    tokio::time::timeout(std::time::Duration::from_secs(2), child.wait())
        .await
        .map_err(|_| RemoteClientError::Protocol(format!("SSH {stage} cleanup timed out")))?
        .map_err(|error| {
            RemoteClientError::Protocol(format!("failed to reap SSH {stage}: {error}"))
        })?;
    if let Err(error) = termination {
        tracing::debug!(%stage, %error, "SSH termination request failed, but the process exited");
    }
    Ok(())
}

async fn capture_bounded<R: tokio::io::AsyncRead + Unpin>(
    reader: Option<R>,
    limit: usize,
) -> std::io::Result<Vec<u8>> {
    use tokio::io::AsyncReadExt;
    let Some(mut reader) = reader else {
        return Ok(Vec::new());
    };
    let mut retained = Vec::new();
    let mut buffer = [0; 4096];
    loop {
        let count = reader.read(&mut buffer).await?;
        if count == 0 {
            return Ok(retained);
        }
        retained.extend_from_slice(&buffer[..count.min(limit.saturating_sub(retained.len()))]);
    }
}

pub(super) async fn initialization_diagnostic(
    stderr: Option<tokio::process::ChildStderr>,
) -> Result<String, RemoteClientError> {
    use tokio::io::AsyncReadExt;
    let Some(stderr) = stderr else {
        return Ok(String::new());
    };
    let mut bytes = Vec::new();
    stderr.take(4096).read_to_end(&mut bytes).await?;
    Ok(String::from_utf8_lossy(&bytes).trim().to_string())
}
