//! Ordinary-file boundary: special files must never occupy a blocking worker indefinitely.
use std::fs::{File, OpenOptions};
use std::io;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

fn options() -> OpenOptions {
    let mut options = OpenOptions::new();
    options.custom_flags(libc::O_NONBLOCK | libc::O_NOFOLLOW);
    options
}

fn regular(file: File) -> io::Result<File> {
    if !file.metadata()?.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "path is not a regular file",
        ));
    }
    Ok(file)
}

pub(super) async fn read(path: PathBuf) -> io::Result<tokio::fs::File> {
    tokio::task::spawn_blocking(move || regular(options().read(true).open(path)?))
        .await
        .map_err(io::Error::other)?
        .map(tokio::fs::File::from_std)
}

pub(super) async fn create(path: PathBuf) -> io::Result<tokio::fs::File> {
    tokio::task::spawn_blocking(move || {
        let file = regular(
            options()
                .write(true)
                .create(true)
                .truncate(false)
                .open(path)?,
        )?;
        // Inspect the actual handle before truncation, including an existing target.
        file.set_len(0)?;
        Ok(file)
    })
    .await
    .map_err(io::Error::other)?
    .map(tokio::fs::File::from_std)
}

pub(super) fn append(path: &Path) -> io::Result<File> {
    regular(options().append(true).create(true).open(path)?)
}

pub(super) async fn copy(source: PathBuf, target: PathBuf) -> io::Result<u64> {
    tokio::task::spawn_blocking(move || {
        let mut source = regular(options().read(true).open(source)?)?;
        let mut target = regular(
            options()
                .write(true)
                .create(true)
                .truncate(false)
                .open(target)?,
        )?;
        target.set_len(0)?;
        target.set_permissions(source.metadata()?.permissions())?;
        io::copy(&mut source, &mut target)
    })
    .await
    .map_err(io::Error::other)?
}
