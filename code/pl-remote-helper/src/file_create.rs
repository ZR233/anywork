//! Directory-capability transactions for exclusive creation of complete ordinary files.
//!
//! The host owns admission and write policy. These blocking operations pin directory objects,
//! not their position in the ambient namespace; callers must revalidate any path they publish.

use crate::workspace_dir::WorkspaceDir;
use cap_std::fs::{Dir, OpenOptions};
use std::ffi::OsString;
use std::fs::File;
use std::io;
use std::path::Path;

/// Facts preserved independently of later cleanup failures.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CreateReceipt {
    /// The complete file has been linked at the target name without replacing an entry.
    pub published: bool,
    /// The transaction's private staging name no longer exists.
    pub staging_removed: bool,
    /// The parent directory's last namespace change has crossed a persistence barrier.
    pub directory_sync: DirectorySync,
}

/// Directory durability is distinct from atomic visibility and file synchronization.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DirectorySync {
    Pending,
    Synced,
    /// The host has no supported directory persistence barrier (currently Windows).
    Unsupported,
}

/// Unique owner of a private staging name and the directories authorizing its publication.
///
/// All methods are blocking. Keep this owner after any failure and retry `cleanup`; neither
/// cleanup nor Drop ever resolves an ambient path or removes the published target.
#[derive(Debug)]
pub struct CreateFile {
    _root: WorkspaceDir,
    parent: Dir,
    staging: OsString,
    target: OsString,
    file: Option<File>,
    receipt: CreateReceipt,
}

impl WorkspaceDir {
    /// Creates an exclusive private stage below this root, creating missing real directories.
    ///
    /// # Errors
    /// Rejects absolute paths, parent traversal, links/reparse points and existing targets.
    /// Propagates directory, random-source and exclusive-open errors without an ambient fallback.
    pub fn begin(&self, relative: &Path) -> io::Result<CreateFile> {
        let (parent, target) = self.parent_and_name(relative, true)?;
        let parent = parent.0.try_clone()?;
        require_missing(&parent, target)?;
        let mut options = OpenOptions::new();
        options.read(true).write(true).create_new(true);
        #[cfg(unix)]
        {
            use cap_std::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        for _ in 0..16 {
            let mut random = [0_u8; 16];
            getrandom::fill(&mut random).map_err(io::Error::other)?;
            let staging = OsString::from(format!(".anywork-create-{}", hex::encode(random)));
            match parent.open_with(&staging, &options) {
                Ok(file) => {
                    return Ok(CreateFile {
                        _root: self.clone(),
                        parent,
                        staging,
                        target: target.to_owned(),
                        file: Some(file.into_std()),
                        receipt: CreateReceipt {
                            published: false,
                            staging_removed: false,
                            directory_sync: DirectorySync::Pending,
                        },
                    });
                }
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
                Err(error) => return Err(error),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "Create staging name collisions exhausted",
        ))
    }
}

impl CreateFile {
    /// Borrows the owned ordinary staging file for writing and integrity verification.
    ///
    /// # Errors
    /// Rejects a transaction whose file has already been closed for cleanup.
    pub fn file_mut(&mut self) -> io::Result<&mut File> {
        self.file
            .as_mut()
            .ok_or_else(|| io::Error::other("Create staging file is closed"))
    }

    /// Returns physical facts, including when publication succeeded but cleanup failed.
    pub fn receipt(&self) -> CreateReceipt {
        self.receipt
    }

    /// Synchronizes the file and publishes its complete bytes without replacing any target.
    /// Repeated calls after publication never link or publish again.
    ///
    /// # Errors
    /// Returns sync, target-conflict or hard-link errors. Unsupported hard links are not
    /// replaced with an ambient rename. Inspect `receipt` before deciding how to recover.
    pub fn publish(&mut self) -> io::Result<()> {
        if self.receipt.published {
            return Ok(());
        }
        self.file_mut()?.sync_all()?;
        require_missing(&self.parent, &self.target)?;
        self.parent
            .hard_link(&self.staging, &self.parent, &self.target)?;
        // No fallible operation may obscure this publication fact.
        self.receipt.published = true;
        self.receipt.directory_sync = DirectorySync::Pending;
        Ok(())
    }

    /// Closes and removes only the private staging name, then synchronizes the pinned parent.
    /// Safe both before publication (abort) and afterward. Failures retain this retryable owner.
    ///
    /// # Errors
    /// Returns the first unlink or directory-sync failure; both independent steps are tried.
    /// A failure never changes `published` back to false.
    pub fn cleanup(&mut self) -> io::Result<()> {
        self.file.take();
        // Even a previously synced parent needs a fresh barrier after a retry unlinks the
        // stage. A failed barrier must never inherit a successful receipt from an older try.
        self.receipt.directory_sync = DirectorySync::Pending;
        let unlink = if self.receipt.staging_removed {
            Ok(())
        } else {
            self.parent.remove_file(&self.staging)
        };
        let unlink = match unlink {
            Ok(()) => {
                self.receipt.staging_removed = true;
                Ok(())
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                self.receipt.staging_removed = true;
                Ok(())
            }
            Err(error) => Err(error),
        };
        let sync = self.sync_parent();
        unlink.and(sync)
    }

    #[cfg(unix)]
    fn sync_parent(&mut self) -> io::Result<()> {
        // Dir may use an O_PATH descriptor on Linux. Reopen this very directory through
        // its capability, not its ambient name, to obtain a sync-capable read descriptor.
        self.parent.open(".")?.sync_all()?;
        self.receipt.directory_sync = DirectorySync::Synced;
        Ok(())
    }

    #[cfg(not(unix))]
    fn sync_parent(&mut self) -> io::Result<()> {
        self.receipt.directory_sync = DirectorySync::Unsupported;
        Ok(())
    }
}

impl Drop for CreateFile {
    fn drop(&mut self) {
        // Explicit cleanup is the error-reporting/retry boundary. This final fallback can
        // only address our stage through its pinned parent, never a replacement pathname.
        if !self.receipt.staging_removed {
            let _ = self.cleanup();
        }
    }
}

fn require_missing(parent: &Dir, name: &std::ffi::OsStr) -> io::Result<()> {
    match parent.symlink_metadata(name) {
        Ok(_) => Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "Create target already exists (file, directory or link)",
        )),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}
