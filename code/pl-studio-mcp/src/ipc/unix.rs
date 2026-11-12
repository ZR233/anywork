use std::{io, os::unix::fs::PermissionsExt};

use tokio::net::{UnixListener, UnixStream};

pub(in crate::ipc) type Stream = UnixStream;

pub(in crate::ipc) struct Lease(tempfile::TempDir);

impl Lease {
    pub fn close(&mut self) -> io::Result<()> {
        // Keep the lease on failure so close can retry cleanup.
        match std::fs::remove_dir_all(self.0.path()) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }
}

pub(in crate::ipc) struct Listener(UnixListener);

impl Listener {
    pub async fn accept(&self) -> io::Result<Stream> {
        self.0.accept().await.map(|(stream, _)| stream)
    }
}

pub(in crate::ipc) async fn bind() -> io::Result<(Listener, Lease, String)> {
    // A short OS temporary directory, deliberately independent of session path length.
    // tempfile creates the directory atomically with mode 0700 on Unix.
    let directory = tempfile::Builder::new().prefix("awm-").tempdir_in("/tmp")?;
    std::fs::set_permissions(directory.path(), std::fs::Permissions::from_mode(0o700))?;
    let path = directory.path().join("host.sock");
    let listener = UnixListener::bind(&path)?;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    let endpoint = path
        .to_str()
        .ok_or_else(|| io::Error::other("host IPC endpoint is not UTF-8"))?
        .to_owned();
    Ok((Listener(listener), Lease(directory), endpoint))
}

pub(in crate::ipc) async fn connect(endpoint: &str) -> io::Result<Stream> {
    UnixStream::connect(endpoint).await
}
