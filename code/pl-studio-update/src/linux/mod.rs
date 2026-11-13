//! Linux's installer boundary. PackageKit owns package operations; this adapter
//! owns verified bytes, authorization, clean-exit handoff and user restart.

mod helper;
pub use helper::run_helper;

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::os::fd::AsRawFd;
use std::process::Stdio;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin, Command};

use crate::error::io_error;
use crate::{StudioUpdate, StudioUpdateCancellation, StudioUpdateError, StudioUpdateErrorCode};

const HELPER: &str = "/opt/anywork/libexec/anywork-update-helper";
const APP: &str = "/opt/anywork/anywork";
const MESSAGE_LIMIT: u64 = 64 * 1024;
const AUTHORIZATION_LIMIT: Duration = Duration::from_secs(120);

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    update: StudioUpdate,
    signature: String,
    source: String,
    app_pid: u32,
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum Reply {
    Ready,
    Committed,
    Cancelled,
    Finished { error: Option<String> },
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Receipt {
    update: StudioUpdate,
    error: Option<String>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CommitState {
    Pending,
    Sent,
    Acknowledged,
}

pub(crate) struct LinuxHandoff {
    child: Child,
    input: Option<ChildStdin>,
    output: BufReader<tokio::process::ChildStdout>,
    commit_state: CommitState,
    // The original process retains this until the supervisor acknowledges the
    // sealed file. The supervisor/root installer then own independent handles.
    _sealed: File,
}

impl LinuxHandoff {
    pub(crate) async fn abort(&mut self) -> Result<(), StudioUpdateError> {
        if self.commit_state != CommitState::Pending {
            return Err(StudioUpdateError::new(
                StudioUpdateErrorCode::CancellationTooLate,
                "installation ownership has already transferred",
            ));
        }
        self.input.take();
        self.child.wait().await.map_err(io_error)?;
        Ok(())
    }

    pub(crate) async fn commit(&mut self) -> Result<(), StudioUpdateError> {
        match self.commit_state {
            CommitState::Acknowledged => return Ok(()),
            CommitState::Sent => {
                return Err(StudioUpdateError::new(
                    StudioUpdateErrorCode::InstallerOutcomeUnknown,
                    "installer commit acknowledgement was lost",
                ));
            }
            CommitState::Pending => {}
        }
        let input = self
            .input
            .as_mut()
            .ok_or_else(|| launch_error("handoff is closed"))?;
        input.write_all(b"commit\n").await.map_err(io_error)?;
        // From a complete commit write, a lost ACK is an unknown handoff
        // outcome. Never kill the supervisor: it may already own installation.
        self.commit_state = CommitState::Sent;
        input.flush().await.map_err(io_error)?;
        match read_reply(&mut self.output).await? {
            Reply::Committed => {
                self.commit_state = CommitState::Acknowledged;
                self.input.take();
                Ok(())
            }
            _ => Err(launch_error("installer did not acknowledge clean shutdown")),
        }
    }
}

impl Drop for LinuxHandoff {
    fn drop(&mut self) {
        // Before commit, EOF aborts authorization/installation. After commit the
        // independent supervisor intentionally outlives the application.
        self.input.take();
        if self.commit_state == CommitState::Pending {
            let _ = self.child.start_kill();
        }
    }
}

pub(crate) async fn prepare(
    lease: &File,
    update: &StudioUpdate,
    signature: &str,
    cancellation: &StudioUpdateCancellation,
) -> Result<LinuxHandoff, StudioUpdateError> {
    use std::os::unix::fs::MetadataExt;
    if std::env::current_exe().map_err(io_error)? != std::path::Path::new(APP) {
        return Err(launch_error(
            "in-app installation requires running the official installed .deb application",
        ));
    }
    let installed = std::fs::symlink_metadata(HELPER).map_err(|e| {
        launch_error(format!(
            "the official .deb installation is required for in-app updates: {e}"
        ))
    })?;
    if !installed.is_file() || installed.uid() != 0 || installed.mode() & 0o022 != 0 {
        return Err(launch_error(
            "the installed update helper is not protected by root ownership",
        ));
    }
    let file = lease.try_clone().map_err(io_error)?;
    let asset = update.installer.clone();
    let signature_text = signature.to_owned();
    let sealed = tokio::task::spawn_blocking(move || {
        let mut source = file;
        source.seek(SeekFrom::Start(0)).map_err(io_error)?;
        let fd = rustix::fs::memfd_create(
            "anywork-update",
            rustix::fs::MemfdFlags::ALLOW_SEALING | rustix::fs::MemfdFlags::CLOEXEC,
        )
        .map_err(|e| io_error(e.into()))?;
        let mut target = File::from(fd);
        std::io::copy(&mut source.take(asset.size + 1), &mut target).map_err(io_error)?;
        rustix::fs::fcntl_add_seals(
            &target,
            rustix::fs::SealFlags::WRITE
                | rustix::fs::SealFlags::GROW
                | rustix::fs::SealFlags::SHRINK
                | rustix::fs::SealFlags::SEAL,
        )
        .map_err(|e| io_error(e.into()))?;
        target.seek(SeekFrom::Start(0)).map_err(io_error)?;
        crate::verification::verify(
            &mut target,
            &asset,
            include_str!("../anywork.pub"),
            &signature_text,
        )?;
        Ok::<_, StudioUpdateError>(target)
    })
    .await
    .map_err(|e| launch_error(format!("installer snapshot failed: {e}")))??;
    let request = Request {
        update: update.clone(),
        signature: signature.to_owned(),
        source: format!("/proc/{}/fd/{}", std::process::id(), sealed.as_raw_fd()),
        app_pid: std::process::id(),
    };
    let mut command = Command::new(HELPER);
    command
        .arg("supervise")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .process_group(0);
    let mut child = command.spawn().map_err(io_error)?;
    let input = child
        .stdin
        .take()
        .ok_or_else(|| launch_error("missing installer input"))?;
    let output = child
        .stdout
        .take()
        .ok_or_else(|| launch_error("missing installer output"))?;
    let mut handoff = LinuxHandoff {
        child,
        input: Some(input),
        output: BufReader::new(output),
        commit_state: CommitState::Pending,
        _sealed: sealed,
    };
    let ready = tokio::select! {
        biased;
        _ = cancellation.cancelled() => Err(StudioUpdateError::new(StudioUpdateErrorCode::Cancelled,
            "update installation was cancelled")),
        result = tokio::time::timeout(AUTHORIZATION_LIMIT, async {
            send(handoff.input.as_mut().unwrap(), &request).await?;
            read_reply(&mut handoff.output).await
        }) =>
            result.unwrap_or_else(|_| Err(launch_error("system authorization timed out"))),
    };
    match ready {
        Ok(Reply::Ready) => Ok(handoff),
        result => {
            // Closing input is a protocol abort; join the supervisor's actual
            // cleanup, which also waits for its privileged child.
            handoff.input.take();
            let status = handoff.child.wait().await.map_err(io_error)?;
            match result {
                Err(e) => Err(e),
                Ok(Reply::Cancelled) => Err(StudioUpdateError::new(
                    StudioUpdateErrorCode::Cancelled,
                    "system authorization was cancelled",
                )),
                Ok(Reply::Finished { error: Some(error) }) => Err(launch_error(error)),
                _ => Err(launch_error(format!(
                    "installer preparation failed: {status}"
                ))),
            }
        }
    }
}

async fn send(
    writer: &mut (impl tokio::io::AsyncWrite + Unpin),
    value: &impl Serialize,
) -> Result<(), StudioUpdateError> {
    let mut bytes = serde_json::to_vec(value).map_err(|e| launch_error(e.to_string()))?;
    bytes.push(b'\n');
    if bytes.len() as u64 > MESSAGE_LIMIT {
        return Err(launch_error("installer message exceeded its size limit"));
    }
    writer.write_all(&bytes).await.map_err(io_error)?;
    writer.flush().await.map_err(io_error)
}

async fn line(
    reader: &mut (impl tokio::io::AsyncBufRead + Unpin),
) -> Result<String, StudioUpdateError> {
    let mut bytes = Vec::new();
    let count = reader
        .take(MESSAGE_LIMIT + 1)
        .read_until(b'\n', &mut bytes)
        .await
        .map_err(io_error)?;
    if count == 0 || count as u64 > MESSAGE_LIMIT || bytes.last() != Some(&b'\n') {
        return Err(launch_error(
            "installer channel closed or exceeded its message limit",
        ));
    }
    String::from_utf8(bytes).map_err(|e| launch_error(e.to_string()))
}

async fn read_reply(
    reader: &mut (impl tokio::io::AsyncBufRead + Unpin),
) -> Result<Reply, StudioUpdateError> {
    serde_json::from_str(&line(reader).await?).map_err(|e| launch_error(e.to_string()))
}

fn launch_error(message: impl Into<String>) -> StudioUpdateError {
    StudioUpdateError::new(StudioUpdateErrorCode::InstallerLaunchFailed, message)
}

/// Consume only installer outcomes, never reconstruct a verified installer lease.
pub fn take_installation_failure() -> Result<Option<(StudioUpdate, String)>, StudioUpdateError> {
    // Development/test processes do not own the installed application's receipt.
    if std::env::current_exe().map_err(io_error)? != std::path::Path::new(APP) {
        return Ok(None);
    }
    let path = dirs::state_dir()
        .ok_or_else(|| launch_error("user state directory unavailable"))?
        .join("anywork/update-result.json");
    let file = match std::fs::File::open(&path) {
        Ok(file) => file,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(io_error(e)),
    };
    let mut bytes = Vec::new();
    file.take(MESSAGE_LIMIT + 1)
        .read_to_end(&mut bytes)
        .map_err(io_error)?;
    if bytes.len() as u64 > MESSAGE_LIMIT {
        return Err(launch_error("invalid update receipt size"));
    }
    let result: Receipt =
        serde_json::from_slice(&bytes).map_err(|e| launch_error(e.to_string()))?;
    crate::manifest::validate_update(&result.update)?;
    std::fs::remove_file(path).map_err(io_error)?;
    Ok(result.error.map(|error| (result.update, error)))
}
