//! Physical directory authority shared by confined reads, managed roots and Create.

use std::ffi::OsStr;
use std::fs::File;
use std::io::{self, Read};
use std::path::{Component, Path};
use std::sync::Arc;

use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptionsFollowExt, OpenOptionsSyncExt};
use cap_std::fs::{Dir, OpenOptions};

/// A host-granted directory object, not a promise about its ambient namespace position.
/// All operations are blocking; the caller must own their worker through completion.
#[derive(Debug, Clone)]
pub struct WorkspaceDir(pub(crate) Arc<Dir>);

impl WorkspaceDir {
    /// Opens the host's trusted ambient authority grant. Descendants use relative no-follow IO.
    /// # Errors
    /// Propagates the platform directory-open failure.
    pub fn open(root: &Path) -> io::Result<Self> {
        Dir::open_ambient_dir(root, cap_std::ambient_authority()).map(|dir| Self(Arc::new(dir)))
    }

    /// Opens an existing descendant, rejecting links including the descendant root itself.
    /// # Errors
    /// Rejects absolute/parent paths, links/reparse points, missing or non-directory entries.
    pub fn open_dir(&self, relative: &Path) -> io::Result<Self> {
        self.descend(&relative_names(relative)?, false)
    }

    /// Creates missing real directories and opens the descendant through the same authority.
    /// # Errors
    /// As `open_dir`, except missing components are exclusively created or safely reopened.
    pub fn ensure_dir(&self, relative: &Path) -> io::Result<Self> {
        self.descend(&relative_names(relative)?, true)
    }

    pub(crate) fn parent_and_name<'p>(
        &self,
        relative: &'p Path,
        create_parents: bool,
    ) -> io::Result<(Self, &'p OsStr)> {
        let mut names = relative_names(relative)?;
        let name = names.pop().ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, "workspace file has no name")
        })?;
        Ok((self.descend(&names, create_parents)?, name))
    }

    fn descend(&self, names: &[&OsStr], create: bool) -> io::Result<Self> {
        let mut dir = self.clone();
        for name in names {
            let next = match dir.0.open_dir_nofollow(name) {
                Ok(next) => next,
                Err(error) if create && error.kind() == io::ErrorKind::NotFound => {
                    match dir.0.create_dir(name) {
                        Ok(()) => {}
                        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
                        Err(error) => return Err(error),
                    }
                    dir.0.open_dir_nofollow(name)?
                }
                Err(error) => return Err(error),
            };
            reject_reparse(&next.dir_metadata()?)?;
            dir = Self(Arc::new(next));
        }
        Ok(dir)
    }

    /// Opens a no-follow ordinary file with nonblocking special-file handling.
    /// # Errors
    /// Rejects links, directories, FIFOs, devices and other non-regular handles. The returned
    /// handle remains bound to the authorized object even if its parent pathname is replaced.
    fn open_regular(&self, relative: &Path) -> io::Result<File> {
        let (parent, name) = self.parent_and_name(relative, false)?;
        let mut options = OpenOptions::new();
        options.read(true).follow(FollowSymlinks::No).nonblock(true);
        let file = parent.0.open_with(name, &options)?;
        require_regular(file)
    }

    /// Reads at most `max_bytes + 1` from the actual ordinary-file handle. With no caller
    /// ceiling, the initial handle length is the finite snapshot budget (text reads).
    /// # Errors
    /// Rejects non-regular files, oversized files, growth past the budget and IO failures.
    pub fn read(&self, relative: &Path, max_bytes: Option<usize>) -> io::Result<Vec<u8>> {
        read_bounded(self.open_regular(relative)?, max_bytes)
    }
}

/// Reads a file explicitly authorized by the host's external-path policy. Unlike WorkspaceDir
/// this is ambient authority, not confinement. It shares handle/type and byte-budget checks.
/// # Errors
/// Rejects final links, non-regular handles, oversized/growing files and IO failures.
pub fn read_ambient(path: &Path, max_bytes: Option<usize>) -> io::Result<Vec<u8>> {
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No).nonblock(true);
    let file = cap_std::fs::File::open_ambient_with(path, &options, cap_std::ambient_authority())?;
    read_bounded(require_regular(file)?, max_bytes)
}

fn require_regular(file: cap_std::fs::File) -> io::Result<File> {
    let metadata = file.metadata()?;
    reject_reparse(&metadata)?;
    if !metadata.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "workspace entry is not a regular file",
        ));
    }
    Ok(file.into_std())
}

fn read_bounded(file: File, max_bytes: Option<usize>) -> io::Result<Vec<u8>> {
    let length = file.metadata()?.len();
    let maximum = match max_bytes {
        Some(maximum) => u64::try_from(maximum).map_err(io::Error::other)?,
        None => length,
    };
    if length > maximum {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "workspace file exceeds read byte limit",
        ));
    }
    let limit = maximum
        .checked_add(1)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "read byte limit overflows"))?;
    let mut bytes = Vec::new();
    file.take(limit).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > maximum {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "workspace file grew beyond read byte limit",
        ));
    }
    Ok(bytes)
}

fn relative_names(relative: &Path) -> io::Result<Vec<&OsStr>> {
    let mut names = Vec::new();
    for component in relative.components() {
        match component {
            Component::Normal(name) => names.push(name),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    "workspace path must be relative without parent traversal",
                ));
            }
        }
    }
    Ok(names)
}

#[cfg(windows)]
pub(crate) fn reject_reparse(metadata: &cap_std::fs::Metadata) -> io::Result<()> {
    use cap_std::fs::MetadataExt;
    if metadata.file_attributes()
        & windows::Win32::Storage::FileSystem::FILE_ATTRIBUTE_REPARSE_POINT.0
        != 0
    {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "workspace entry is a Windows reparse point",
        ));
    }
    Ok(())
}

#[cfg(not(windows))]
pub(crate) fn reject_reparse(_metadata: &cap_std::fs::Metadata) -> io::Result<()> {
    Ok(())
}
