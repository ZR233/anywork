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

/// Appends staged content by publishing a complete replacement. A failed copy cannot leave
/// a partial append in the target; the caller serializes commits to this physical path.
pub(super) fn append_staged(source: &Path, target: &Path) -> io::Result<()> {
    use std::io::{Seek, SeekFrom};
    use std::os::unix::fs::MetadataExt;
    let parent = target
        .parent()
        .ok_or_else(|| io::Error::other("append target parent missing"))?;
    let mut merged = tempfile::Builder::new()
        .prefix(".anywork-transfer-")
        .tempfile_in(parent)?;
    let before = match options().read(true).open(target) {
        Ok(file) => {
            let mut existing = regular(file)?;
            let before = existing.metadata()?;
            merged.as_file().set_permissions(before.permissions())?;
            io::copy(&mut existing, &mut merged)?;
            let after = existing.metadata()?;
            if before.len() != after.len()
                || before.mtime() != after.mtime()
                || before.mtime_nsec() != after.mtime_nsec()
                || before.ctime() != after.ctime()
                || before.ctime_nsec() != after.ctime_nsec()
            {
                return Err(io::Error::other("append target changed during staging"));
            }
            Some(after)
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => None,
        Err(error) => return Err(error),
    };
    let mut source = regular(options().read(true).open(source)?)?;
    source.seek(SeekFrom::Start(0))?;
    io::copy(&mut source, &mut merged)?;
    merged.as_file().sync_all()?;
    if let Some(before) = before {
        let current = std::fs::symlink_metadata(target)?;
        if before.dev() != current.dev()
            || before.ino() != current.ino()
            || before.ctime() != current.ctime()
            || before.ctime_nsec() != current.ctime_nsec()
        {
            return Err(io::Error::other("append target changed before publication"));
        }
        merged.persist(target).map_err(|error| error.error)?;
    } else {
        merged
            .persist_noclobber(target)
            .map_err(|error| error.error)?;
    }
    Ok(())
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
        use std::os::unix::fs::MetadataExt;
        let source_metadata = source.metadata()?;
        let target_metadata = target.metadata()?;
        if source_metadata.dev() == target_metadata.dev()
            && source_metadata.ino() == target_metadata.ino()
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "copy source and target identify the same file",
            ));
        }
        target.set_len(0)?;
        target.set_permissions(source_metadata.permissions())?;
        io::copy(&mut source, &mut target)
    })
    .await
    .map_err(io::Error::other)?
}
