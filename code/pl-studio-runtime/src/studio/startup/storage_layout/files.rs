//! Preserve file identity, reject unsafe paths and copy complete SQLite families.

use crate::studio::paths::StudioPaths;
use anyhow::{Context, Result, ensure};
use sha2::{Digest, Sha256};
use std::io::Read;
use std::path::{Path, PathBuf};

pub(super) fn original_path(paths: &StudioPaths, source: &Path) -> Result<PathBuf> {
    let relative = source.strip_prefix(paths.home().join("migration-backups"))?;
    let mut components = relative.components();
    components.next().context("missing backup operation")?;
    Ok(paths.home().join(components.as_path()))
}
pub(super) fn validate_family(database: &Path) -> Result<()> {
    if !database.try_exists()? {
        let [_, wal, shm] = crate::studio::paths::sqlite_family_paths(database);
        for path in [wal, shm] {
            ensure!(!path.try_exists()?, "orphan SQLite sidecar");
        }
    }
    Ok(())
}

/// Copy without following links or overwriting a conflicting file; a previously copied exact file
/// proves an interrupted step. Unknown source entries remain only in the preserved root.
pub(super) async fn copy_tree(home: &Path, source: &Path, target: &Path) -> Result<()> {
    let (home, source, target) = (home.to_owned(), source.to_owned(), target.to_owned());
    tokio::task::spawn_blocking(move || copy_tree_sync(&home, &source, &target)).await?
}
fn copy_tree_sync(home: &Path, source: &Path, target: &Path) -> Result<()> {
    pl_tool::workspace::path_safety::validate_path_for_write(home, target)?;
    let meta = std::fs::symlink_metadata(source)?;
    ensure!(
        !pl_tool::workspace::path_safety::is_link_or_reparse(&meta),
        "migration refuses links: {}",
        source.display()
    );
    if meta.is_dir() {
        std::fs::create_dir_all(target)?;
        for entry in std::fs::read_dir(source)? {
            let entry = entry?;
            copy_tree_sync(home, &entry.path(), &target.join(entry.file_name()))?;
        }
        #[cfg(unix)]
        std::fs::File::open(target)?.sync_all()?;
    } else {
        ensure!(meta.is_file(), "migration source is not a regular file");
        if target.try_exists()? {
            ensure!(
                file_digest(source)? == file_digest(target)?,
                "conflicting migration copy: {}",
                target.display()
            );
        } else {
            let parent = target.parent().context("copy target has no parent")?;
            std::fs::create_dir_all(parent)?;
            // tempfile passes paths directly to Win32 when persisting, unlike std's file APIs.
            // Canonicalize the checked, existing parent so both paths use extended-length syntax
            // on Windows. Keep this native spelling local; storage identities remain unchanged.
            let parent = std::fs::canonicalize(parent)?;
            let destination =
                parent.join(target.file_name().context("copy target has no filename")?);
            let mut temporary = tempfile::NamedTempFile::new_in(&parent)?;
            std::io::copy(&mut std::fs::File::open(source)?, &mut temporary)?;
            temporary.as_file().sync_all()?;
            temporary.persist_noclobber(&destination)?;
            ensure!(
                file_digest(source)? == file_digest(target)?,
                "migration copy changed bytes"
            );
        }
        #[cfg(unix)]
        std::fs::File::open(target.parent().context("copy target parent")?)?.sync_all()?;
    }
    Ok(())
}
fn file_digest(path: &Path) -> Result<(u64, String)> {
    let mut file = std::fs::File::open(path)?;
    let mut hash = Sha256::new();
    let mut length = 0;
    let mut buffer = [0_u8; 65536];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hash.update(&buffer[..count]);
        length += count as u64;
    }
    Ok((length, hex::encode(hash.finalize())))
}
pub(super) async fn ensure_tree_safe(home: &Path, path: &Path) -> Result<()> {
    let (home, path) = (home.to_owned(), path.to_owned());
    tokio::task::spawn_blocking(move || {
        let mut pending = vec![path];
        while let Some(path) = pending.pop() {
            pl_tool::workspace::path_safety::validate_path_for_write(&home, &path)?;
            let meta = std::fs::symlink_metadata(&path)?;
            ensure!(
                !pl_tool::workspace::path_safety::is_link_or_reparse(&meta),
                "migration source contains a link"
            );
            if meta.is_dir() {
                for entry in std::fs::read_dir(path)? {
                    pending.push(entry?.path());
                }
            } else {
                ensure!(meta.is_file(), "migration source contains a non-file");
            }
        }
        Ok(())
    })
    .await?
}
