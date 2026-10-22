//! SSH stdio relay. The separately owned helper expires through its authenticated heartbeat lease.
use crate::ServerError;
use std::io;
use std::path::Path;
use std::process::Stdio;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub async fn run_stdio() -> Result<(), ServerError> {
    let directory = tempfile::Builder::new()
        .prefix("anywork-helper-")
        .tempdir_in("/tmp")?;
    let socket = directory.path().join("control.sock");
    let mut command = tokio::process::Command::new(std::env::current_exe()?);
    command
        .arg("--session-owner")
        .arg(&socket)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    // A new process group survives SSH relay EOF. Its only lifetime authority is the lease.
    // Business descendants remain parent-bound to their existing physical supervisor.
    command.process_group(0);
    let mut owner = command.spawn()?;
    let mut readiness = owner
        .stdout
        .take()
        .ok_or_else(|| io::Error::other("helper readiness pipe missing"))?;
    let mut ready = [0; 6];
    let received = tokio::time::timeout(
        std::time::Duration::from_secs(25),
        readiness.read_exact(&mut ready),
    )
    .await;
    match received {
        Ok(Ok(_)) if &ready == b"READY\n" => {}
        Ok(Ok(_)) => {
            let _ = owner.kill().await;
            let _ = owner.wait().await;
            return Err(
                io::Error::new(io::ErrorKind::InvalidData, "invalid helper readiness").into(),
            );
        }
        Ok(Err(error)) => {
            let _ = owner.kill().await;
            let _ = owner.wait().await;
            return Err(error.into());
        }
        Err(_) => {
            let _ = owner.kill().await;
            let _ = owner.wait().await;
            return Err(
                io::Error::new(io::ErrorKind::TimedOut, "helper owner startup timed out").into(),
            );
        }
    }
    let path = directory.keep();
    let result = attach_stdio(&socket).await;
    // Reap an owner that already exited, but do not terminate a live detached owner.
    let _ = owner.try_wait();
    drop(owner);
    drop(path);
    result
}

pub async fn attach_stdio(socket: &Path) -> Result<(), ServerError> {
    let stream = tokio::net::UnixStream::connect(socket).await?;
    let (mut read, mut write) = stream.into_split();
    let mut stdin = tokio::io::stdin();
    use std::os::fd::AsFd;
    // The HTTP/2 channel is binary: bypass stdio's line buffering. The duplicated descriptor
    // remains owned by this relay and uses Tokio's ordinary file IO adapter.
    let stdout = std::io::stdout().as_fd().try_clone_to_owned()?;
    let mut stdout = tokio::fs::File::from_std(std::fs::File::from(stdout));
    tokio::select! {
        result = tokio::io::copy(&mut stdin, &mut write) => { result?; write.shutdown().await?; },
        result = tokio::io::copy(&mut read, &mut stdout) => { result?; stdout.flush().await?; },
    }
    Ok(())
}
