//! Observation boundary for one Thread's canonical execution uploads root.
//! The caller derives the key from the actual original Thread identity using
//! SessionFiles::new's documented SHA-256 mapping, never from a descriptor.

use std::{
    fs,
    io::{self, Error, ErrorKind},
    path::{Path, PathBuf},
};

pub(super) struct ThreadUploads {
    workspace: PathBuf,
    relative_root: PathBuf,
    canonical_root: PathBuf,
}

impl ThreadUploads {
    pub fn for_thread_key(workspace: &Path, thread_key: &str) -> io::Result<Self> {
        if thread_key.len() != 64
            || !thread_key
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
        {
            return Err(invalid(
                "Thread key must be its canonical lowercase SHA-256",
            ));
        }
        let workspace = fs::canonicalize(workspace)?;
        // Canonical SessionFiles::uploads layout, centralized in this observer.
        let relative_root = PathBuf::from(".anywork")
            .join("sessions")
            .join(thread_key)
            .join("uploads");
        let expected_root = workspace.join(&relative_root);
        let canonical_root = fs::canonicalize(&expected_root)?;
        if canonical_root != expected_root || !fs::metadata(&canonical_root)?.is_dir() {
            return Err(invalid(
                "current Thread uploads root was redirected or is not a directory",
            ));
        }
        Ok(Self {
            workspace,
            relative_root,
            canonical_root,
        })
    }

    pub fn resolve(&self, path: &str) -> io::Result<PathBuf> {
        if path.is_empty()
            || path.contains(['\\', '\0', '\n', '\r', ':'])
            || path
                .split('/')
                .any(|part| part.is_empty() || matches!(part, "." | ".."))
        {
            return Err(invalid(
                "execution file must be a canonical relative POSIX path",
            ));
        }
        let relative = Path::new(path);
        let tail = relative.strip_prefix(&self.relative_root).map_err(|_| {
            invalid("execution file is not under this Thread's SessionFiles/uploads root")
        })?;
        if relative.is_absolute() || tail.as_os_str().is_empty() {
            return Err(invalid(
                "execution file must name a file below this Thread's uploads root",
            ));
        }
        let canonical = fs::canonicalize(self.workspace.join(relative))?;
        if !canonical.starts_with(&self.workspace)
            || !canonical.starts_with(&self.canonical_root)
            || !fs::metadata(&canonical)?.is_file()
        {
            return Err(invalid(
                "execution file escapes the current Thread uploads root or is not regular",
            ));
        }
        Ok(canonical)
    }
}

fn invalid(message: &'static str) -> Error {
    Error::new(ErrorKind::InvalidInput, message)
}
