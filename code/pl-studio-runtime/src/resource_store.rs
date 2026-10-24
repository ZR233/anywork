//! Persistent resource bytes, independent of tool payload formats and session SQL schemas.

mod remote;
pub use remote::RemoteCommandOutputArchive;
use std::{
    fs::File,
    io::{Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptionsFollowExt, OpenOptionsSyncExt};
use cap_std::fs::{Dir, DirEntry, Metadata, OpenOptions, ReadDir};
use pl_core::context::{ResourceReadError, ResourceReader, ResourceReference};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

const ID_PREFIX: &str = "pl.studio.resource:";
const PENDING_PREFIX: &str = ".anywork-resource-v1-";

/// Identity prefix owned by this store; the only producer of durable tool media references.
pub const RESOURCE_ID_PREFIX: &str = ID_PREFIX;

/// Largest single **command capture** this store will archive.
///
/// This ceiling is deliberately scoped to the command-output archive, not to every retained resource:
/// an attachment, import or other user resource keeps its existing unbounded streaming semantics, and
/// the generic `retain_file`/`retain_bytes` paths impose no such limit. The command capture copy is
/// bounded in chunks, never read whole into memory, and a capture past this ceiling is refused with a
/// typed error instead of being copied without bound. It sits above the command operation's own
/// capture ceiling, so a complete capture plus its framing headers still archives, while a runaway
/// capture cannot fill the disk with one copy.
pub const MAX_COMMAND_ARCHIVE_BYTES: u64 = 32 * 1024 * 1024;

/// Content-addressed resource service rooted in a host-selected persistent directory.
/// Clones share immutable objects; closing a Thread never deletes another Thread's bytes.
#[derive(Debug, Clone)]
pub struct FileResourceStore {
    root: Arc<ResourceStoreRoot>,
}

#[derive(Debug)]
struct ResourceStoreRoot {
    path: PathBuf,
    trusted_parent: Option<PathBuf>,
    authority: Mutex<Option<Arc<Dir>>>,
    #[cfg(all(test, unix))]
    directory_sync_failures: std::sync::atomic::AtomicUsize,
    #[cfg(all(test, unix))]
    sync_fault_waits_for_unlink: std::sync::atomic::AtomicBool,
}

/// Rebuildable enumeration progress. Only this store can issue/advance it; it pins the directory.
#[derive(Debug)]
pub(crate) struct OwnedResourceScan {
    authority: Arc<ResourceStoreRoot>,
    entries: ReadDir,
}

/// A store-issued entry, not an ambient path or permission supplied by a caller.
#[derive(Debug)]
pub(crate) struct OwnedResourceObject {
    authority: Arc<ResourceStoreRoot>,
    entry: DirEntry,
    metadata: Metadata,
    id: Option<String>,
}

impl OwnedResourceObject {
    pub(crate) fn resource_id(&self) -> Option<&str> {
        self.id.as_deref()
    }
}

#[derive(Debug)]
pub(crate) struct OwnedResourceBatch {
    pub(crate) objects: Vec<OwnedResourceObject>,
    pub(crate) continuation: Option<OwnedResourceScan>,
}

/// A completed namespace obligation, not a claim of identical power-loss durability on every OS.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum DirectorySyncOutcome {
    #[cfg(unix)]
    Synced,
    #[cfg(windows)]
    Unsupported,
    #[cfg(unix)]
    NotRequired,
}

/// Issued only after content sync, publication, own-stage cleanup and the available barrier.
pub(crate) struct ResourceRetention {
    reference: ResourceReference,
    directory_sync: DirectorySyncOutcome,
}

impl ResourceRetention {
    pub(crate) fn into_parts(self) -> (ResourceReference, DirectorySyncOutcome) {
        (self.reference, self.directory_sync)
    }

    fn into_reference(self) -> ResourceReference {
        let (reference, outcome) = self.into_parts();
        // Generic resource APIs promise exact retained content, not a portable directory flush.
        // Windows' Unsupported is explicitly accepted without being relabelled as Synced.
        match outcome {
            #[cfg(unix)]
            DirectorySyncOutcome::Synced => reference,
            #[cfg(windows)]
            DirectorySyncOutcome::Unsupported => reference,
            #[cfg(unix)]
            DirectorySyncOutcome::NotRequired => unreachable!("retention changes a namespace"),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ResourceStoreError {
    #[error("resource store IO failed at {path}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("resource byte stream could not be read")]
    Read(#[source] std::io::Error),
    #[error("resource exceeds the {limit}-byte retention ceiling")]
    TooLarge { limit: u64 },
    #[error("resource source is not a regular file: {0}")]
    NotFile(PathBuf),
    #[error("resource identity is not owned by this store")]
    Identity,
    #[error("resource metadata or bytes failed integrity validation")]
    Integrity(#[from] pl_core::context::ResourceError),
    #[error("resource worker failed")]
    Worker(#[from] tokio::task::JoinError),
    #[error(
        "resource store contains an unknown, linked or replaced object; local recovery required"
    )]
    Layout,
    #[error("resource maintenance batch must contain at most 128 entries")]
    Batch,
    #[error("resource directory synchronization failed")]
    DirectorySync(#[source] std::io::Error),
}

impl FileResourceStore {
    /// Query before any write, even if the store directory does not exist yet. Only Windows
    /// intentionally lacks the portable barrier; an actual Unix sync error is never downgraded.
    pub(crate) fn preflight_directory_sync() -> Result<DirectorySyncOutcome, ResourceStoreError> {
        sync_directory(None).map_err(ResourceStoreError::DirectorySync)
    }

    pub(crate) fn validate_owned_reference(
        reference: &ResourceReference,
    ) -> Result<(), ResourceStoreError> {
        resource_name(reference).map(|_| ())
    }

    /// Selects the persistent directory without creating files or reading configuration.
    pub fn new(root: PathBuf) -> Self {
        Self::with_parent(root, None)
    }

    /// Host-owned managed descendants reject links below their explicit parent grant. The grant
    /// itself may be a legitimate Studio-home alias, like the existing ambient constructor.
    pub(crate) fn beneath(trusted_parent: PathBuf, root: PathBuf) -> Self {
        Self::with_parent(root, Some(trusted_parent))
    }

    fn with_parent(root: PathBuf, trusted_parent: Option<PathBuf>) -> Self {
        Self {
            root: Arc::new(ResourceStoreRoot {
                path: root,
                trusted_parent,
                authority: Mutex::new(None),
                #[cfg(all(test, unix))]
                directory_sync_failures: std::sync::atomic::AtomicUsize::new(0),
                #[cfg(all(test, unix))]
                sync_fault_waits_for_unlink: std::sync::atomic::AtomicBool::new(false),
            }),
        }
    }

    /// Test-only persistence fault injection; never part of the production resource interface.
    #[cfg(all(test, unix))]
    pub(crate) fn inject_directory_sync_failures_after_unlink(&self, count: usize) {
        self.root
            .directory_sync_failures
            .store(count, std::sync::atomic::Ordering::SeqCst);
        self.root
            .sync_fault_waits_for_unlink
            .store(true, std::sync::atomic::Ordering::SeqCst);
    }

    fn directory(&self, create: bool) -> Result<Option<Arc<Dir>>, ResourceStoreError> {
        if create {
            Self::preflight_directory_sync()?;
        }
        let mut slot = self
            .root
            .authority
            .lock()
            .map_err(|_| ResourceStoreError::Layout)?;
        if let Some(directory) = slot.as_ref() {
            return Ok(Some(directory.clone()));
        }
        match open_store_directory(&self.root, create) {
            Ok(directory) => {
                let directory = Arc::new(directory);
                *slot = Some(directory.clone());
                Ok(Some(directory))
            }
            Err(ResourceStoreError::Io { source, .. })
                if !create && source.kind() == std::io::ErrorKind::NotFound =>
            {
                Ok(None)
            }
            Err(error) => Err(error),
        }
    }

    /// Enumerates only formally named ordinary objects through the captured directory capability.
    /// The Bot operation owner must await this worker even when its caller leaves.
    pub(crate) async fn owned_batch(
        &self,
        continuation: Option<OwnedResourceScan>,
        max_entries: usize,
    ) -> Result<OwnedResourceBatch, ResourceStoreError> {
        if !(1..=128).contains(&max_entries) {
            return Err(ResourceStoreError::Batch);
        }
        let store = self.clone();
        tokio::task::spawn_blocking(move || {
            let mut scan = match continuation {
                Some(scan) if Arc::ptr_eq(&scan.authority, &store.root) => scan,
                Some(_) => return Err(ResourceStoreError::Identity),
                None => {
                    let Some(directory) = store.directory(false)? else {
                        return Ok(OwnedResourceBatch {
                            objects: Vec::new(),
                            continuation: None,
                        });
                    };
                    OwnedResourceScan {
                        authority: store.root.clone(),
                        entries: directory.entries().map_err(ResourceStoreError::Read)?,
                    }
                }
            };
            let mut objects = Vec::with_capacity(max_entries);
            for _ in 0..max_entries {
                let Some(entry) = scan.entries.next() else {
                    return Ok(OwnedResourceBatch {
                        objects,
                        continuation: None,
                    });
                };
                let entry = entry.map_err(ResourceStoreError::Read)?;
                let kind = entry.file_type().map_err(ResourceStoreError::Read)?;
                if !kind.is_file() || kind.is_symlink() {
                    return Err(ResourceStoreError::Layout);
                }
                let name = entry.file_name();
                let name = name.to_str().ok_or(ResourceStoreError::Layout)?;
                let id = if valid_hash(name) {
                    Some(format!("{ID_PREFIX}{name}"))
                } else if name.strip_prefix(PENDING_PREFIX).is_some_and(|suffix| {
                    suffix.len() == 16 && suffix.bytes().all(|byte| byte.is_ascii_alphanumeric())
                }) {
                    None
                } else {
                    return Err(ResourceStoreError::Layout);
                };
                let file = entry
                    .open_with(&regular_options())
                    .map_err(ResourceStoreError::Read)?;
                let metadata = file.metadata().map_err(ResourceStoreError::Read)?;
                require_regular(&metadata)?;
                objects.push(OwnedResourceObject {
                    authority: store.root.clone(),
                    entry,
                    metadata,
                    id,
                });
            }
            Ok(OwnedResourceBatch {
                objects,
                continuation: Some(scan),
            })
        })
        .await?
    }

    /// Deletes only entries issued by this exact store. Empty batches still repay the namespace
    /// sync obligation. A failure never authorizes a caller to resolve/delete an ambient path.
    pub(crate) async fn remove_owned_batch(
        &self,
        objects: Vec<OwnedResourceObject>,
    ) -> Result<DirectorySyncOutcome, ResourceStoreError> {
        if objects.len() > 128 {
            return Err(ResourceStoreError::Batch);
        }
        if objects
            .iter()
            .any(|object| !Arc::ptr_eq(&object.authority, &self.root))
        {
            return Err(ResourceStoreError::Identity);
        }
        let store = self.clone();
        tokio::task::spawn_blocking(move || {
            let capability = Self::preflight_directory_sync()?;
            let Some(directory) = store.directory(false)? else {
                return Ok(capability);
            };
            let mut has_unlink = false;
            for object in objects {
                let file = match object.entry.open_with(&regular_options()) {
                    Ok(file) => file,
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                    Err(error) => return Err(ResourceStoreError::Read(error)),
                };
                let actual = file.metadata().map_err(ResourceStoreError::Read)?;
                require_regular(&actual)?;
                if !same_object(&object.metadata, &actual) {
                    return Err(ResourceStoreError::Layout);
                }
                // Both validation and unlink address this entry through its pinned directory.
                // Producer exclusion is supplied by the Bot owner, not a per-store copy of refs.
                object
                    .entry
                    .remove_file()
                    .map_err(ResourceStoreError::Read)?;
                has_unlink = true;
            }
            store.sync_directory(&directory, has_unlink)
        })
        .await?
    }

    fn sync_directory(
        &self,
        directory: &Dir,
        _has_unlink: bool,
    ) -> Result<DirectorySyncOutcome, ResourceStoreError> {
        #[cfg(all(test, unix))]
        if (_has_unlink
            || !self
                .root
                .sync_fault_waits_for_unlink
                .load(std::sync::atomic::Ordering::SeqCst))
            && self
                .root
                .directory_sync_failures
                .try_update(
                    std::sync::atomic::Ordering::SeqCst,
                    std::sync::atomic::Ordering::SeqCst,
                    |remaining| remaining.checked_sub(1),
                )
                .is_ok()
        {
            self.root
                .sync_fault_waits_for_unlink
                .store(false, std::sync::atomic::Ordering::SeqCst);
            return Err(ResourceStoreError::DirectorySync(std::io::Error::new(
                std::io::ErrorKind::Unsupported,
                "injected namespace barrier failure",
            )));
        }
        sync_directory(Some(directory)).map_err(ResourceStoreError::DirectorySync)
    }

    /// Retains exact source bytes. The capture is not removed, including on failure.
    ///
    /// # Errors
    /// Rejects non-files, invalid media descriptions, corrupt existing objects and IO failure.
    pub async fn retain_file(
        &self,
        source: &Path,
        media_type: &str,
    ) -> Result<ResourceReference, ResourceStoreError> {
        let source = source.to_owned();
        let media_type = media_type.to_owned();
        let store = self.clone();
        tokio::task::spawn_blocking(move || retain(&store, &source, media_type, None))
            .await?
            .map(ResourceRetention::into_reference)
    }

    /// Retains a completed command capture under the command-archive ceiling.
    ///
    /// It shares the exact streaming copy and idempotent content-addressed identity of
    /// [`Self::retain_file`], but bounds the copy at [`MAX_COMMAND_ARCHIVE_BYTES`] so a runaway capture
    /// cannot fill the disk. The limit is scoped to this command path only: it never narrows the
    /// generic resource/attachment semantics.
    ///
    /// # Errors
    /// Returns [`ResourceStoreError::TooLarge`] for a capture past the ceiling and the same IO,
    /// integrity and metadata failures as [`Self::retain_file`].
    pub async fn retain_command_capture(
        &self,
        source: &Path,
    ) -> Result<ResourceReference, ResourceStoreError> {
        let source = source.to_owned();
        let store = self.clone();
        tokio::task::spawn_blocking(move || {
            retain(
                &store,
                &source,
                "application/octet-stream".to_owned(),
                Some(MAX_COMMAND_ARCHIVE_BYTES),
            )
        })
        .await?
        .map(ResourceRetention::into_reference)
    }

    /// Retains exact in-memory bytes with the same immutable identity and durability as file captures.
    ///
    /// # Errors
    /// Returns invalid media metadata, existing-content corruption, or storage failure.
    pub async fn retain_bytes(
        &self,
        bytes: Arc<[u8]>,
        media_type: &str,
    ) -> Result<ResourceReference, ResourceStoreError> {
        self.retain_bytes_with_receipt(bytes, media_type)
            .await
            .map(ResourceRetention::into_reference)
    }

    pub(crate) async fn retain_bytes_with_receipt(
        &self,
        bytes: Arc<[u8]>,
        media_type: &str,
    ) -> Result<ResourceRetention, ResourceStoreError> {
        let store = self.clone();
        let media_type = media_type.to_owned();
        tokio::task::spawn_blocking(move || {
            retain_input(
                &store,
                ResourceInput {
                    reader: std::io::Cursor::new(bytes),
                    source_path: None,
                },
                media_type,
                None,
            )
        })
        .await?
    }

    /// Builds an archive adapter only for commands whose capture is on the local host.
    pub fn local_command_archive(&self) -> LocalCommandOutputArchive {
        LocalCommandOutputArchive(self.clone())
    }
}

/// Local-capture adapter; remote capture needs a remote read adapter before this store.
#[derive(Debug, Clone)]
pub struct LocalCommandOutputArchive(FileResourceStore);

impl pl_tool::exec::CommandOutputArchive for LocalCommandOutputArchive {
    async fn retain(
        &self,
        _: &str,
        snapshot: &pl_tool::command::CommandOutputSnapshot,
    ) -> Result<ResourceReference, pl_core::tool::opaque::ToolError> {
        self.0
            .retain_command_capture(&snapshot.capture_file)
            .await
            .map_err(retention_failure)
    }
}

/// Maps a resource retention failure to the tool boundary.
///
/// A real disk failure — the capture could not be copied or made durable — is reported as the typed
/// storage category core latches, so the Thread pauses further admission instead of continuing as if
/// the bytes were archived. An oversized or malformed source is a policy refusal that leaves the
/// capture intact for inspection, so it stays a plain tool error rather than a Thread-wide pause. The
/// category is chosen from the typed error, never parsed out of its text.
fn retention_failure(error: ResourceStoreError) -> pl_core::tool::opaque::ToolError {
    match error {
        ResourceStoreError::Io { source, .. }
        | ResourceStoreError::Read(source)
        | ResourceStoreError::DirectorySync(source) => retention_io_fault(source),
        other => pl_core::tool::opaque::ToolError::new(other),
    }
}

/// Maps a local disk failure while staging or retaining bytes to the typed storage category.
///
/// The remote archive stages the transfer locally before it content-addresses it, so a local write or
/// flush failure has to reach core as the same typed storage fact a local capture failure does; a
/// remote *transfer* failure stays a plain tool error because it is not a storage fault.
fn retention_io_fault(error: std::io::Error) -> pl_core::tool::opaque::ToolError {
    let source = pl_core::thread::cold::ColdStoreError {
        source: Box::new(error),
    };
    pl_core::tool::opaque::ToolError::new(pl_core::thread::cold::OutputStorageFault::new(
        pl_core::thread::cold::StorageFaultKind::BlobFailed,
        Arc::new(source),
    ))
}

impl ResourceReader for FileResourceStore {
    async fn read(
        &self,
        reference: ResourceReference,
        cancellation: CancellationToken,
    ) -> Result<Arc<[u8]>, ResourceReadError> {
        if cancellation.is_cancelled() {
            return Err(ResourceReadError::Cancelled);
        }
        let store = self.clone();
        let retained = reference.clone();
        let bytes = tokio::task::spawn_blocking(move || {
            let name = resource_name(&retained)?;
            let directory = store
                .directory(false)?
                .ok_or(ResourceStoreError::Identity)?;
            let file = directory
                .open_with(name, &regular_options())
                .map_err(ResourceStoreError::Read)?;
            require_regular(&file.metadata().map_err(ResourceStoreError::Read)?)?;
            let mut bytes = Vec::new();
            file.take(retained.byte_len().saturating_add(1))
                .read_to_end(&mut bytes)
                .map_err(ResourceStoreError::Read)?;
            Ok::<_, ResourceStoreError>(bytes)
        })
        .await
        .map_err(|error| unavailable(ResourceStoreError::Worker(error)))?
        .map_err(unavailable)?;
        if cancellation.is_cancelled() {
            return Err(ResourceReadError::Cancelled);
        }
        reference.verify(&bytes)?;
        Ok(Arc::from(bytes))
    }
}

fn unavailable(source: ResourceStoreError) -> ResourceReadError {
    ResourceReadError::Unavailable {
        source: Box::new(source),
    }
}

fn retain_command_capture_file(
    root: &Arc<ResourceStoreRoot>,
    mut source: File,
) -> Result<ResourceReference, ResourceStoreError> {
    source
        .seek(SeekFrom::Start(0))
        .map_err(ResourceStoreError::Read)?;
    retain_input(
        &FileResourceStore { root: root.clone() },
        ResourceInput {
            reader: source,
            source_path: None,
        },
        "application/octet-stream".to_owned(),
        Some(MAX_COMMAND_ARCHIVE_BYTES),
    )
    .map(ResourceRetention::into_reference)
}

fn retain(
    store: &FileResourceStore,
    source: &Path,
    media_type: String,
    limit: Option<u64>,
) -> Result<ResourceRetention, ResourceStoreError> {
    let source_error = |source_error| ResourceStoreError::Io {
        path: source.to_owned(),
        source: source_error,
    };
    let input = File::open(source).map_err(source_error)?;
    if !input.metadata().map_err(source_error)?.is_file() {
        return Err(ResourceStoreError::NotFile(source.to_owned()));
    }
    retain_input(
        store,
        ResourceInput {
            reader: input,
            source_path: Some(source.to_owned()),
        },
        media_type,
        limit,
    )
}

struct ResourceInput<R> {
    reader: R,
    source_path: Option<PathBuf>,
}

fn retain_input(
    store: &FileResourceStore,
    mut input: ResourceInput<impl Read>,
    media_type: String,
    limit: Option<u64>,
) -> Result<ResourceRetention, ResourceStoreError> {
    let root = store.root.path.as_path();
    let store_error = |source_error| ResourceStoreError::Io {
        path: root.to_owned(),
        source: source_error,
    };
    let directory = store.directory(true)?.ok_or(ResourceStoreError::Identity)?;
    // tempfile owns naming/collision handling only. Its ambient Drop cleanup is disabled before
    // creation; all publication/unlink below uses the pinned directory, even after a rename.
    let temporary = tempfile::Builder::new()
        .prefix(PENDING_PREFIX)
        .rand_bytes(16)
        .disable_cleanup(true)
        .make_in(root, |path| {
            let name = path
                .file_name()
                .ok_or_else(|| std::io::Error::other("resource stage has no name"))?;
            let mut options = OpenOptions::new();
            options
                .read(true)
                .write(true)
                .create_new(true)
                .follow(FollowSymlinks::No);
            directory
                .open_with(name, &options)
                .map(|file| file.into_std())
        })
        .map_err(store_error)?;
    let name = temporary
        .path()
        .file_name()
        .ok_or(ResourceStoreError::Identity)?
        .to_owned();
    let mut temporary = ResourceTemporary {
        file: temporary.into_file(),
        directory: directory.clone(),
        name,
    };
    let mut digest = Sha256::new();
    let mut length = 0_u64;
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = input
            .reader
            .read(&mut buffer)
            .map_err(|source| match &input.source_path {
                Some(path) => ResourceStoreError::Io {
                    path: path.clone(),
                    source,
                },
                None => ResourceStoreError::Read(source),
            })?;
        if count == 0 {
            break;
        }
        length = length
            .checked_add(count as u64)
            .ok_or_else(|| store_error(std::io::Error::other("resource length overflow")))?;
        // Refuse a source past the caller's ceiling while copying, before writing the chunk that would
        // cross it: a huge file is never materialized as an unbounded second copy, and the caller gets
        // a typed reason instead of a silently truncated object. `None` keeps the generic
        // resource/attachment semantics unbounded.
        if let Some(limit) = limit
            && length > limit
        {
            return Err(ResourceStoreError::TooLarge { limit });
        }
        temporary
            .file
            .write_all(&buffer[..count])
            .map_err(store_error)?;
        digest.update(&buffer[..count]);
    }
    let hash = hex::encode(digest.finalize());
    let reference = ResourceReference::new(
        format!("{ID_PREFIX}{hash}"),
        format!("sha256:{hash}"),
        length,
        media_type,
    )?;
    temporary.file.sync_all().map_err(store_error)?;
    let destination = resource_name(&reference)?;
    match directory.hard_link(&temporary.name, &directory, destination) {
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            // Preserve a conflicting object for diagnosis. Never overwrite historical bytes.
            verify_file(&directory, destination, &reference)?;
        }
        Err(error) => {
            return Err(ResourceStoreError::Io {
                path: root.join(destination),
                source: error,
            });
        }
    }
    directory
        .remove_file(&temporary.name)
        .map_err(store_error)?;
    let directory_sync = store.sync_directory(&directory, true)?;
    Ok(ResourceRetention {
        reference,
        directory_sync,
    })
}

fn resource_name(reference: &ResourceReference) -> Result<&str, ResourceStoreError> {
    reference.validate()?;
    let hash = reference
        .id()
        .strip_prefix(ID_PREFIX)
        .ok_or(ResourceStoreError::Identity)?;
    if !valid_hash(hash) || reference.content_digest() != format!("sha256:{hash}") {
        return Err(ResourceStoreError::Identity);
    }
    Ok(hash)
}

fn verify_file(
    directory: &Dir,
    name: &str,
    reference: &ResourceReference,
) -> Result<(), ResourceStoreError> {
    let mut input = directory
        .open_with(name, &regular_options())
        .map_err(ResourceStoreError::Read)?;
    require_regular(&input.metadata().map_err(ResourceStoreError::Read)?)?;
    if input.metadata().map_err(ResourceStoreError::Read)?.len() != reference.byte_len() {
        return Err(ResourceStoreError::Integrity(
            pl_core::context::ResourceError::ContentMismatch,
        ));
    }
    let mut digest = Sha256::new();
    let mut length = 0_u64;
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = input.read(&mut buffer).map_err(ResourceStoreError::Read)?;
        if count == 0 {
            break;
        }
        length = length
            .checked_add(count as u64)
            .filter(|length| *length <= reference.byte_len())
            .ok_or(ResourceStoreError::Integrity(
                pl_core::context::ResourceError::ContentMismatch,
            ))?;
        digest.update(&buffer[..count]);
    }
    if length != reference.byte_len()
        || format!("sha256:{}", hex::encode(digest.finalize())) != reference.content_digest()
    {
        return Err(ResourceStoreError::Integrity(
            pl_core::context::ResourceError::ContentMismatch,
        ));
    }
    Ok(())
}

struct ResourceTemporary {
    file: File,
    directory: Arc<Dir>,
    name: std::ffi::OsString,
}

impl Drop for ResourceTemporary {
    fn drop(&mut self) {
        // Failure is recoverable by the store's formally named pending-object sweep. Never use
        // tempfile's ambient TempPath cleanup after the directory namespace may have changed.
        let _ = self.directory.remove_file(&self.name);
    }
}

fn regular_options() -> OpenOptions {
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No).nonblock(true);
    options
}

fn require_regular(metadata: &Metadata) -> Result<(), ResourceStoreError> {
    if !metadata.is_file() || metadata.is_symlink() {
        return Err(ResourceStoreError::Layout);
    }
    #[cfg(windows)]
    {
        use cap_std::fs::MetadataExt;
        if metadata.file_attributes() & 0x400 != 0 {
            return Err(ResourceStoreError::Layout);
        }
    }
    Ok(())
}

fn valid_hash(hash: &str) -> bool {
    hash.len() == 64
        && hash
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn same_object(expected: &Metadata, actual: &Metadata) -> bool {
    #[cfg(unix)]
    {
        use cap_std::fs::MetadataExt;
        expected.dev() == actual.dev() && expected.ino() == actual.ino()
    }
    #[cfg(windows)]
    {
        use cap_std::fs::MetadataExt;
        expected.volume_serial_number().is_some()
            && expected.file_index().is_some()
            && expected.volume_serial_number() == actual.volume_serial_number()
            && expected.file_index() == actual.file_index()
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = (expected, actual);
        false
    }
}

fn sync_directory(directory: Option<&Dir>) -> std::io::Result<DirectorySyncOutcome> {
    #[cfg(unix)]
    {
        if let Some(directory) = directory {
            directory.open(".")?.sync_all()?;
            Ok(DirectorySyncOutcome::Synced)
        } else {
            Ok(DirectorySyncOutcome::NotRequired)
        }
    }
    #[cfg(windows)]
    {
        let _ = directory;
        Ok(DirectorySyncOutcome::Unsupported)
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = directory;
        Err(std::io::Error::new(
            std::io::ErrorKind::Unsupported,
            "resource directory persistence barrier is unsupported",
        ))
    }
}

fn open_store_directory(root: &ResourceStoreRoot, create: bool) -> Result<Dir, ResourceStoreError> {
    use std::path::Component;
    let io_error = |source| ResourceStoreError::Io {
        path: root.path.clone(),
        source,
    };
    let Some(parent) = &root.trusted_parent else {
        // The public constructor is an explicit host ambient-directory grant, not model path
        // permission. Preserve existing aliases; every later operation uses the captured Dir.
        if create {
            std::fs::create_dir_all(&root.path).map_err(io_error)?;
        }
        return Dir::open_ambient_dir(&root.path, cap_std::ambient_authority()).map_err(io_error);
    };
    let relative = root.path.strip_prefix(parent).map_err(|_| {
        io_error(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "managed resource root is outside its parent grant",
        ))
    })?;
    let mut names = Vec::new();
    for component in relative.components() {
        match component {
            Component::Normal(name) => names.push(name.to_owned()),
            Component::CurDir => {}
            Component::ParentDir | Component::Prefix(_) | Component::RootDir => {
                return Err(io_error(std::io::Error::new(
                    std::io::ErrorKind::InvalidInput,
                    "resource root contains parent traversal",
                )));
            }
        }
    }
    let mut directory = Dir::open_ambient_dir(
        std::fs::canonicalize(parent).map_err(io_error)?,
        cap_std::ambient_authority(),
    )
    .map_err(io_error)?;
    for name in names {
        let child = match directory.open_dir_nofollow(&name) {
            Ok(child) => child,
            Err(error) if create && error.kind() == std::io::ErrorKind::NotFound => {
                match directory.create_dir(&name) {
                    Ok(()) => {}
                    Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
                    Err(error) => return Err(io_error(error)),
                }
                directory.open_dir_nofollow(&name).map_err(io_error)?
            }
            Err(error) => return Err(io_error(error)),
        };
        // A recovery scan may be the first capture after a failed parent barrier. Repay it
        // before caching even a read capability, or a subsequent retain could bypass that debt.
        // The final retention receipt also records this platform's barrier capability.
        let _parent_sync =
            sync_directory(Some(&directory)).map_err(ResourceStoreError::DirectorySync)?;
        directory = child;
        #[cfg(windows)]
        {
            use cap_std::fs::MetadataExt;
            if directory
                .dir_metadata()
                .map_err(io_error)?
                .file_attributes()
                & 0x400
                != 0
            {
                return Err(io_error(std::io::Error::new(
                    std::io::ErrorKind::PermissionDenied,
                    "resource root is a reparse point",
                )));
            }
        }
    }
    Ok(directory)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The command-archive ceiling is a typed refusal on the command path only, not a new generic limit.
    #[tokio::test]
    async fn the_command_archive_ceiling_is_scoped_to_the_command_path() {
        let root = tempfile::tempdir().expect("an isolated retention root");
        let store = FileResourceStore::new(root.path().to_path_buf());
        let source = root.path().join("capture.bin");
        let oversized = vec![0_u8; MAX_COMMAND_ARCHIVE_BYTES as usize + 1];
        std::fs::write(&source, &oversized).expect("the oversized capture is written");

        let error = store
            .retain_command_capture(&source)
            .await
            .expect_err("a command capture past the ceiling is a typed refusal");
        assert!(matches!(
            error,
            ResourceStoreError::TooLarge { limit } if limit == MAX_COMMAND_ARCHIVE_BYTES
        ));

        // The generic resource/attachment path keeps its unbounded streaming semantics: the same
        // oversized source still archives, so the command ceiling is not a new generic limit.
        store
            .retain_file(&source, "application/octet-stream")
            .await
            .expect("a generic resource is not bounded by the command archive ceiling");
    }

    /// A repeated command-archive retry re-saves the same bytes under the same identity.
    #[tokio::test]
    async fn repeating_the_command_archive_retry_is_idempotent() {
        let root = tempfile::tempdir().expect("an isolated retention root");
        let store = FileResourceStore::new(root.path().to_path_buf());
        let source = root.path().join("capture.bin");
        let accepted = b"accepted capture fragment".to_vec();
        std::fs::write(&source, &accepted).expect("the capture fragment is written");

        let first = store
            .retain_command_capture(&source)
            .await
            .expect("the first archive stores the fragment");
        let retry = store
            .retain_command_capture(&source)
            .await
            .expect("a repeated retry stores the same fragment");
        assert_eq!(
            first, retry,
            "a repeated retry produces the same content-addressed reference, not a duplicate"
        );
        assert_eq!(retry.byte_len(), accepted.len() as u64);
    }

    /// A local disk failure is the typed storage fact core latches; a policy refusal is not.
    #[test]
    fn retention_failure_maps_local_io_to_the_typed_storage_fault() {
        let io_failure =
            retention_failure(ResourceStoreError::Read(std::io::Error::other("disk full")));
        let fault = io_failure
            .source
            .downcast_ref::<pl_core::thread::cold::OutputStorageFault>()
            .expect("a local IO failure is the typed storage fault core latches");
        assert_eq!(
            fault.kind,
            pl_core::thread::cold::StorageFaultKind::BlobFailed
        );

        let refusal = retention_failure(ResourceStoreError::TooLarge {
            limit: MAX_COMMAND_ARCHIVE_BYTES,
        });
        assert!(
            refusal
                .source
                .downcast_ref::<pl_core::thread::cold::OutputStorageFault>()
                .is_none(),
            "an oversized source is a policy refusal, not a Thread-wide storage fault"
        );
    }
}
