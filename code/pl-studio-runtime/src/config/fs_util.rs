//! Filesystem primitives shared by the configuration-owner resources.
//!
//! Resource directories are user-editable, so every scan re-verifies the on-disk
//! shape instead of trusting an earlier one: a directory or document must be a
//! real (non-symlink) entry, document reads are bounded, and a content digest is
//! the only document revision.

use std::fs;
use std::io::{self, Read};
use std::path::Path;
use std::sync::{Arc, Mutex, PoisonError};

use sha2::{Digest, Sha256};
use tokio::sync::watch;

/// Whether a resource directory exists once [`ensure_regular_dir`] accepted its shape.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum DirectoryPresence {
    Present,
    Absent,
}

/// Why [`ensure_regular_dir`] refused a resource directory.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum DirectoryError {
    /// The entry is a symlink; owners never follow user-controlled links.
    Symlink,
    /// The entry exists but is not a directory.
    NotDirectory,
    /// The filesystem refused the check; the raw error is preserved.
    Io(io::Error),
}

/// Verifies `path` is a real directory.
///
/// A missing directory is [`DirectoryPresence::Absent`] so callers treat the
/// resource as empty instead of failing the whole scan; symlinks and other
/// kinds are refused so a user cannot redirect the owner elsewhere.
pub(crate) fn ensure_regular_dir(path: &Path) -> Result<DirectoryPresence, DirectoryError> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => {
            Ok(DirectoryPresence::Present)
        }
        Ok(metadata) if metadata.file_type().is_symlink() => Err(DirectoryError::Symlink),
        Ok(_) => Err(DirectoryError::NotDirectory),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(DirectoryPresence::Absent),
        Err(error) => Err(DirectoryError::Io(error)),
    }
}

/// Why a document read was refused before its bytes could be returned.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum DocumentReadError {
    /// The entry is missing; the raw error is preserved for callers that
    /// propagate it as their own IO failure.
    NotFound(io::Error),
    /// The entry is a symlink.
    Symlink,
    /// The entry exists but is not a regular file.
    NotRegularFile,
    /// The file is larger than the caller's limit, measured before and after
    /// the read so a file growing during the read cannot bypass the cap.
    TooLarge { limit: u64 },
    /// The filesystem refused the read; the raw error is preserved.
    Io(io::Error),
}

impl DocumentReadError {
    fn from_io(error: io::Error) -> Self {
        if error.kind() == io::ErrorKind::NotFound {
            Self::NotFound(error)
        } else {
            Self::Io(error)
        }
    }
}

/// Reads a real (non-symlink) regular file without a size bound.
pub(crate) fn read_regular_file(path: &Path) -> Result<Vec<u8>, DocumentReadError> {
    read_regular_file_bounded(path, u64::MAX)
}

/// Reads a real (non-symlink) regular file, refusing anything larger than
/// `limit` bytes.
pub(crate) fn read_regular_file_bounded(
    path: &Path,
    limit: u64,
) -> Result<Vec<u8>, DocumentReadError> {
    let metadata = fs::symlink_metadata(path).map_err(DocumentReadError::from_io)?;
    if metadata.file_type().is_symlink() {
        return Err(DocumentReadError::Symlink);
    }
    if !metadata.is_file() {
        return Err(DocumentReadError::NotRegularFile);
    }
    if metadata.len() > limit {
        return Err(DocumentReadError::TooLarge { limit });
    }
    let file = fs::File::open(path).map_err(DocumentReadError::from_io)?;
    let mut bytes = Vec::new();
    file.take(limit.saturating_add(1))
        .read_to_end(&mut bytes)
        .map_err(DocumentReadError::from_io)?;
    if bytes.len() as u64 > limit {
        return Err(DocumentReadError::TooLarge { limit });
    }
    Ok(bytes)
}

/// Reads an optional document: a missing file is `None`; every other failure
/// propagates unchanged.
pub(crate) fn read_optional_file(path: &Path) -> io::Result<Option<Vec<u8>>> {
    match fs::read(path) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

/// Content digest revision: identical `(relative_path, bytes)` always map to the
/// same non-zero value that fits a JavaScript safe integer.
pub fn document_revision(relative_path: &str, bytes: &[u8]) -> u64 {
    let mut hasher = Sha256::new();
    hasher.update(relative_path.as_bytes());
    hasher.update([0]);
    hasher.update(bytes);
    let digest = hasher.finalize();
    let mut raw = [0u8; 8];
    raw.copy_from_slice(&digest[..8]);
    (u64::from_be_bytes(raw) & i64::MAX as u64).max(1)
}

/// State whose `revision` advances once per published change.
pub(crate) trait RevisionedState {
    fn revision(&self) -> u64;
    fn revision_mut(&mut self) -> &mut u64;
}

/// One published resource state plus its change channel.
///
/// `read` and `subscribe` are cache-only. A change is applied under the state
/// lock and only a real change advances the revision and wakes subscribers.
/// The channel always carries the published revision, so a subscriber created
/// before any change still observes the same revision as `read`.
#[derive(Clone)]
pub(crate) struct WatchedResource<T> {
    state: Arc<Mutex<T>>,
    updates: Arc<watch::Sender<u64>>,
}

impl<T: RevisionedState> WatchedResource<T> {
    pub(crate) fn new(state: T) -> Self {
        let (updates, _) = watch::channel(state.revision());
        Self {
            state: Arc::new(Mutex::new(state)),
            updates: Arc::new(updates),
        }
    }
}

impl<T: RevisionedState + Clone> WatchedResource<T> {
    /// Applies `change` under the state lock. When it reports a real change the
    /// revision advances exactly once and subscribers receive the new value.
    /// Returns the published state and whether a new revision was published.
    pub(crate) fn publish(&self, change: impl FnOnce(&mut T) -> bool) -> (T, bool) {
        let mut state = self.lock();
        if !change(&mut state) {
            return (state.clone(), false);
        }
        let revision = state
            .revision()
            .checked_add(1)
            .expect("resource revision exhausted");
        *state.revision_mut() = revision;
        let published = state.clone();
        drop(state);
        self.updates.send_replace(revision);
        (published, true)
    }
}

impl<T> WatchedResource<T> {
    pub(crate) fn read(&self) -> T
    where
        T: Clone,
    {
        self.lock().clone()
    }

    /// Subscribes to resource changes; the channel value is the latest revision.
    pub(crate) fn subscribe(&self) -> watch::Receiver<u64> {
        self.updates.subscribe()
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, T> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, Clone, PartialEq, Eq)]
    struct Counter {
        revision: u64,
        value: u64,
    }

    impl RevisionedState for Counter {
        fn revision(&self) -> u64 {
            self.revision
        }

        fn revision_mut(&mut self) -> &mut u64 {
            &mut self.revision
        }
    }

    #[test]
    fn channel_starts_at_the_published_revision_and_only_advances_on_change() {
        let resource = WatchedResource::new(Counter {
            revision: 1,
            value: 0,
        });
        let mut changes = resource.subscribe();
        assert_eq!(*changes.borrow_and_update(), resource.read().revision);
        let (unchanged, published) = resource.publish(|state| {
            if state.value == 0 {
                return false;
            }
            state.value = 1;
            true
        });
        assert!(!published);
        assert_eq!(
            unchanged,
            Counter {
                revision: 1,
                value: 0
            }
        );
        assert!(!changes.has_changed().unwrap());
        let (state, published) = resource.publish(|state| {
            state.value = 1;
            true
        });
        assert!(published);
        assert_eq!(
            state,
            Counter {
                revision: 2,
                value: 1
            }
        );
        assert!(changes.has_changed().unwrap());
        assert_eq!(*changes.borrow_and_update(), 2);
        assert_eq!(resource.read(), state);
    }

    #[test]
    fn document_reads_reject_other_kinds_and_oversized_files() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();
        let file = root.join("document.toml");
        fs::write(&file, b"  ,  ").unwrap();
        assert_eq!(
            read_regular_file_bounded(&file, 2),
            Err(DocumentReadError::TooLarge { limit: 2 })
        );
        assert_eq!(
            read_regular_file_bounded(&file, 6).unwrap(),
            b"  ,  ".to_vec()
        );
        assert!(matches!(
            read_regular_file(root),
            Err(DocumentReadError::NotRegularFile)
        ));
        assert!(matches!(
            read_regular_file(&root.join("missing.toml")),
            Err(DocumentReadError::NotFound(error)) if error.kind() == io::ErrorKind::NotFound
        ));
        assert_eq!(
            read_optional_file(&root.join("missing.toml")).unwrap(),
            None
        );
        assert_eq!(read_optional_file(&file).unwrap(), Some(b"  ,  ".to_vec()));
    }

    #[test]
    fn directories_are_present_absent_or_refused_by_shape() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();
        fs::create_dir(root.join("real")).unwrap();
        fs::write(root.join("file"), b"").unwrap();
        assert_eq!(
            ensure_regular_dir(&root.join("real")).unwrap(),
            DirectoryPresence::Present
        );
        assert_eq!(
            ensure_regular_dir(&root.join("missing")).unwrap(),
            DirectoryPresence::Absent
        );
        assert!(matches!(
            ensure_regular_dir(&root.join("file")),
            Err(DirectoryError::NotDirectory)
        ));
    }

    #[cfg(unix)]
    #[test]
    fn links_are_refused_for_directories_and_documents() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();
        fs::create_dir(root.join("real")).unwrap();
        fs::write(root.join("document.toml"), b"").unwrap();
        std::os::unix::fs::symlink(root.join("real"), root.join("dir-link")).unwrap();
        std::os::unix::fs::symlink(root.join("document.toml"), root.join("file-link.toml"))
            .unwrap();
        assert!(matches!(
            ensure_regular_dir(&root.join("dir-link")),
            Err(DirectoryError::Symlink)
        ));
        assert!(matches!(
            read_regular_file(&root.join("file-link.toml")),
            Err(DocumentReadError::Symlink)
        ));
    }

    #[test]
    fn document_revision_is_stable_nonzero_and_content_addressed() {
        let first = document_revision("mcp/host/a.toml", b"a");
        assert_eq!(first, document_revision("mcp/host/a.toml", b"a"));
        assert_ne!(first, document_revision("mcp/host/b.toml", b"a"));
        assert_ne!(first, document_revision("mcp/host/a.toml", b"b"));
        assert!((1..=i64::MAX as u64).contains(&first));
    }
}
