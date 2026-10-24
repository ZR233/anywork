//! Physical, resumable file handles. Transfer policy and retries belong to the host.
use super::*;
use crate::budget::{ByteLease, ResourceBudget};
use crate::file_create::CreateFile;
use crate::workspace_dir::WorkspaceDir;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::os::unix::fs::MetadataExt;
use std::path::PathBuf;
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};

mod admission;
mod cleanup;
use cleanup::{ClosingFile, StagingCleanup, cleanup_stage};

type CreateOwner = Arc<std::sync::Mutex<CreateFile>>;

#[derive(Debug)]
enum WriteStage {
    Create(CreateOwner),
    Replace(tempfile::TempPath),
}

impl WriteStage {
    fn into_cleanup(self) -> StagingCleanup {
        match self {
            Self::Create(owner) => StagingCleanup::Create(owner),
            Self::Replace(path) => StagingCleanup::replace_stage(path),
        }
    }
}

#[derive(Debug)]
enum FileState {
    Read {
        file: tokio::fs::File,
        revision: String,
        length: u64,
        digest: String,
    },
    Write {
        file: tokio::fs::File,
        temporary: WriteStage,
        target: PathBuf,
        mode: RemoteWriteMode,
        offset: u64,
        length: u64,
        ranges: BTreeMap<u64, (u64, ByteLease)>,
    },
    Committed {
        length: u64,
        digest: String,
        cleanup: Option<StagingCleanup>,
    },
    Failed {
        error: RemoteError,
        cleanup: StagingCleanup,
    },
    Cleanup(Arc<ClosingFile>),
    Closing,
}
#[derive(Debug)]
struct Transfer {
    workspace: String,
    file: Mutex<FileState>,
    _lease: ByteLease,
    closing: std::sync::atomic::AtomicBool,
    commit_lock: Option<Arc<Mutex<()>>>,
}
#[derive(Debug)]
pub(super) struct Transfers {
    entries: Mutex<HashMap<String, Arc<Transfer>>>,
    next: std::sync::atomic::AtomicU64,
    instance: String,
    commits: Mutex<HashMap<PathBuf, std::sync::Weak<Mutex<()>>>>,
    admission: admission::Admission,
}
impl Transfers {
    pub(super) fn new(instance: String) -> Self {
        Self {
            entries: Default::default(),
            next: std::sync::atomic::AtomicU64::new(0),
            instance,
            commits: Default::default(),
            admission: Default::default(),
        }
    }
    pub(super) fn admit(&self, workspace: &str) -> Result<admission::OpeningLease, RemoteError> {
        self.admission.enter(workspace)
    }
    pub(super) fn forget_closed_workspace(&self, workspace: &str) {
        self.admission.forget_closed_workspace(workspace);
    }
    fn ensure_transfer_open(&self, entry: &Transfer) -> Result<(), RemoteError> {
        ensure_open(entry)?;
        if !self.admission.is_open(&entry.workspace) {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "transfer is closing",
            ));
        }
        Ok(())
    }
    async fn insert(
        &self,
        workspace: String,
        file: FileState,
        lease: ByteLease,
    ) -> Result<RemoteTransferStatus, RemoteError> {
        let id = format!(
            "{}-{}",
            self.instance,
            self.next.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        );
        let status = status(&id, &file)?;
        let commit_lock = if let FileState::Write { target, .. } = &file {
            let mut commits = self.commits.lock().await;
            commits.retain(|_, lock| lock.strong_count() > 0);
            let lock = commits
                .get(target)
                .and_then(std::sync::Weak::upgrade)
                .unwrap_or_else(|| Arc::new(Mutex::new(())));
            commits.insert(target.clone(), Arc::downgrade(&lock));
            Some(lock)
        } else {
            None
        };
        let entry = Transfer {
            workspace,
            file: Mutex::new(file),
            _lease: lease,
            closing: std::sync::atomic::AtomicBool::new(false),
            commit_lock,
        };
        self.entries.lock().await.insert(id, Arc::new(entry));
        Ok(status)
    }
    async fn get(&self, id: &str) -> Result<Arc<Transfer>, RemoteError> {
        self.entries
            .lock()
            .await
            .get(id)
            .cloned()
            .ok_or_else(|| remote_error(RemoteErrorCode::PathNotFound, "transfer is closed"))
    }
    pub(super) async fn open_read(
        &self,
        workspace: String,
        path: PathBuf,
        budget: &ResourceBudget,
    ) -> Result<RemoteTransferStatus, RemoteError> {
        let lease = budget
            .try_reserve(std::mem::size_of::<Transfer>())
            .ok_or_else(exhausted)?;
        let mut file = regular_file::read(path)
            .await
            .map_err(|e| io_error("open transfer source", e))?;
        let metadata = file
            .metadata()
            .await
            .map_err(|e| io_error("inspect transfer source", e))?;
        let expected = revision(&metadata);
        let chunk = budget.fragment_bytes();
        // The owning RPC reserved its progress/reply quantum before opening this handle.
        let mut bytes = vec![0; chunk];
        let mut digest = Sha256::new();
        loop {
            let count = file
                .read(&mut bytes)
                .await
                .map_err(|e| io_error("hash transfer source", e))?;
            if count == 0 {
                break;
            }
            digest.update(&bytes[..count]);
        }
        check_revision(&file, &expected).await?;
        file.rewind()
            .await
            .map_err(|e| io_error("rewind transfer source", e))?;
        self.insert(
            workspace,
            FileState::Read {
                file,
                revision: expected,
                length: metadata.len(),
                digest: hex::encode(digest.finalize()),
            },
            lease,
        )
        .await
    }
    pub(super) async fn begin_write(
        &self,
        workspace: String,
        target: PathBuf,
        mode: RemoteWriteMode,
        length: u64,
        budget: &ResourceBudget,
        create: Option<(WorkspaceDir, PathBuf)>,
    ) -> Result<RemoteTransferStatus, RemoteError> {
        let lease = budget
            .try_reserve(std::mem::size_of::<Transfer>() + target.as_os_str().len())
            .ok_or_else(exhausted)?;
        let (file, temporary) = if let Some((root, relative)) = create {
            let (file, owner) = tokio::task::spawn_blocking(move || {
                let mut owner = root.begin(&relative)?;
                let file = owner.file_mut()?.try_clone()?;
                Ok::<_, io::Error>((file, Arc::new(std::sync::Mutex::new(owner))))
            })
            .await
            .map_err(|e| io_error("create capability stage task", io::Error::other(e)))?
            .map_err(|e| io_error("create capability stage", e))?;
            (file, WriteStage::Create(owner))
        } else {
            let parent = target
                .parent()
                .ok_or_else(|| {
                    remote_error(
                        RemoteErrorCode::InvalidRequest,
                        "write target has no parent",
                    )
                })?
                .to_owned();
            tokio::fs::create_dir_all(&parent)
                .await
                .map_err(|e| io_error("create transfer directory", e))?;
            let temporary = tokio::task::spawn_blocking(move || {
                tempfile::Builder::new()
                    .prefix(".anywork-transfer-")
                    .tempfile_in(parent)
            })
            .await
            .map_err(|e| io_error("create transfer task", io::Error::other(e)))?
            .map_err(|e| io_error("create transfer staging", e))?;
            let (file, temporary) = temporary.into_parts();
            (file, WriteStage::Replace(temporary))
        };
        self.insert(
            workspace,
            FileState::Write {
                file: tokio::fs::File::from_std(file),
                temporary,
                target,
                mode,
                offset: 0,
                length,
                ranges: BTreeMap::new(),
            },
            lease,
        )
        .await
    }
    pub(super) async fn read(
        &self,
        id: &str,
        offset: u64,
        max_bytes: usize,
    ) -> Result<(RemoteResponse, Vec<u8>), RemoteError> {
        let transfer = self.get(id).await?;
        // A sealed transfer rejects new IO without waiting behind a blocked finalizer.
        self.ensure_transfer_open(&transfer)?;
        let mut file_state = transfer.file.lock().await;
        self.ensure_transfer_open(&transfer)?;
        let FileState::Read {
            file,
            revision,
            length,
            ..
        } = &mut *file_state
        else {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "transfer is not readable",
            ));
        };
        check_revision(file, revision).await?;
        if offset > *length || max_bytes == 0 {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "invalid transfer range",
            ));
        }
        let count = (*length - offset).min(max_bytes as u64) as usize;
        let mut bytes = vec![0; count];
        file.seek(std::io::SeekFrom::Start(offset))
            .await
            .map_err(|e| io_error("seek transfer", e))?;
        file.read_exact(&mut bytes)
            .await
            .map_err(|e| io_error("read transfer", e))?;
        check_revision(file, revision).await?;
        Ok((
            RemoteResponse::ByteRange {
                offset,
                total_len: *length,
            },
            bytes,
        ))
    }
    pub(super) async fn write(
        &self,
        id: &str,
        offset: u64,
        expected: &str,
        bytes: &[u8],
        budget: &ResourceBudget,
    ) -> Result<RemoteResponse, RemoteError> {
        if hex::encode(Sha256::digest(bytes)) != expected {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "transfer chunk checksum mismatch",
            ));
        }
        let entry = self.get(id).await?;
        self.ensure_transfer_open(&entry)?;
        let mut file_state = entry.file.lock().await;
        self.ensure_transfer_open(&entry)?;
        let FileState::Write {
            file,
            offset: confirmed,
            length,
            ranges,
            ..
        } = &mut *file_state
        else {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "transfer no longer accepts chunks",
            ));
        };
        let end = offset.checked_add(bytes.len() as u64).ok_or_else(|| {
            remote_error(RemoteErrorCode::InvalidRequest, "chunk offset overflow")
        })?;
        if offset < *confirmed
            || end > *length
            || bytes.is_empty()
            || ranges
                .range(..end)
                .next_back()
                .is_some_and(|(_, (stored_end, _))| *stored_end > offset)
        {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "chunk overlaps confirmed data or exceeds transfer length",
            ));
        }
        let range_memory = budget
            .try_reserve(std::mem::size_of::<(u64, u64, ByteLease)>())
            .ok_or_else(exhausted)?;
        let write = async {
            file.seek(std::io::SeekFrom::Start(offset)).await?;
            file.write_all(bytes).await?;
            file.flush().await
        }
        .await;
        if let Err(error) = write {
            let failure = io_error("write transfer chunk", error);
            let previous = std::mem::replace(&mut *file_state, FileState::Closing);
            let FileState::Write {
                file, temporary, ..
            } = previous
            else {
                unreachable!()
            };
            drop(file);
            let cleanup = temporary.into_cleanup();
            *file_state = FileState::Failed {
                error: failure.clone(),
                cleanup,
            };
            return Err(failure);
        }
        ranges.insert(offset, (end, range_memory));
        while let Some((end, _memory)) = ranges.remove(confirmed) {
            *confirmed = end;
        }
        Ok(RemoteResponse::ChunkWritten {
            offset,
            length: bytes.len() as u64,
            confirmed_offset: *confirmed,
        })
    }
    pub(super) async fn commit(
        &self,
        id: &str,
        length: u64,
        expected: &str,
        quantum: usize,
    ) -> Result<RemoteTransferStatus, RemoteError> {
        let entry = self.get(id).await?;
        self.ensure_transfer_open(&entry)?;
        let mut file_state = entry.file.lock().await;
        self.ensure_transfer_open(&entry)?;
        if !matches!(*file_state, FileState::Write { .. }) {
            return status(id, &file_state);
        }
        let _commit = match entry.commit_lock.as_ref() {
            Some(lock) => Some(lock.lock().await),
            None => None,
        };
        let previous = std::mem::replace(&mut *file_state, FileState::Closing);
        let FileState::Write {
            mut file,
            temporary,
            target,
            mode,
            offset,
            length: declared,
            ranges,
        } = previous
        else {
            unreachable!()
        };
        let cleanup = match &temporary {
            WriteStage::Create(owner) => StagingCleanup::Create(owner.clone()),
            WriteStage::Replace(path) => StagingCleanup::Replace(path.to_path_buf()),
        };
        let mut actual = String::new();
        let result = async {
            if offset != length || declared != length || !ranges.is_empty() {
                return Err(remote_error(
                    RemoteErrorCode::InvalidRequest,
                    "transfer length or final checksum mismatch",
                ));
            }
            file.flush()
                .await
                .map_err(|e| io_error("flush transfer", e))?;
            file.rewind()
                .await
                .map_err(|e| io_error("rewind transfer", e))?;
            let mut digest = Sha256::new();
            let mut buffer = vec![0; quantum];
            loop {
                let count = file
                    .read(&mut buffer)
                    .await
                    .map_err(|e| io_error("verify transfer", e))?;
                if count == 0 {
                    break;
                }
                digest.update(&buffer[..count]);
            }
            actual = hex::encode(digest.finalize());
            if actual != expected {
                return Err(remote_error(
                    RemoteErrorCode::InvalidRequest,
                    "transfer final checksum mismatch",
                ));
            }
            file.sync_all()
                .await
                .map_err(|e| io_error("sync transfer", e))?;
            drop(file);
            if let WriteStage::Create(owner) = temporary {
                return tokio::task::spawn_blocking(move || {
                    owner
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .publish()
                })
                .await
                .map_err(|e| {
                    remote_error(
                        RemoteErrorCode::OutcomeUnknown,
                        format!("Create publication task did not return: {e}"),
                    )
                })?
                .map_err(|e| io_error("publish Create transfer", e));
            }
            let WriteStage::Replace(temporary) = temporary else {
                unreachable!()
            };
            tokio::task::spawn_blocking(move || -> io::Result<()> {
                let parent = target
                    .parent()
                    .ok_or_else(|| io::Error::other("target parent missing"))?;
                match std::fs::symlink_metadata(&target) {
                    Ok(metadata) if !metadata.is_file() || metadata.file_type().is_symlink() => {
                        return Err(io::Error::new(
                            io::ErrorKind::InvalidInput,
                            "write target is not a regular file",
                        ));
                    }
                    Ok(_) => {}
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error),
                }
                match mode {
                    RemoteWriteMode::Create => {
                        return Err(io::Error::other("Create transfer lost its directory owner"));
                    }
                    RemoteWriteMode::Overwrite => {
                        if let Ok(metadata) = std::fs::metadata(&target) {
                            std::fs::set_permissions(&temporary, metadata.permissions())?;
                        }
                        temporary.persist(&target).map_err(|e| e.error)?;
                    }
                    RemoteWriteMode::Append => {
                        regular_file::append_staged(&temporary, &target)?;
                        temporary.close()?;
                    }
                }
                std::fs::File::open(parent)?.sync_all()
            })
            .await
            .map_err(|e| io_error("commit transfer task", io::Error::other(e)))?
            .map_err(|e| io_error("commit transfer", e))?;
            Ok::<_, RemoteError>(())
        }
        .await;
        if let StagingCleanup::Create(owner) = &cleanup {
            let published = owner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .receipt()
                .published;
            if published {
                let finalized = cleanup_stage(&cleanup).await;
                *file_state = FileState::Committed {
                    length,
                    digest: actual,
                    cleanup: finalized.as_ref().err().map(|_| cleanup),
                };
                // Status/replayed Commit report the immutable publication fact; close retries
                // finalization. Never turn an already-visible Create into a failed/unstarted one.
                if let Err(error) = finalized {
                    return Err(remote_error(
                        RemoteErrorCode::OutcomeUnknown,
                        format!(
                            "Create is published; staging/durability cleanup pending: {}",
                            error.message
                        ),
                    ));
                }
                result?;
                return status(id, &file_state);
            }
        }
        *file_state = match result {
            Ok(()) => FileState::Committed {
                length,
                digest: actual,
                cleanup: None,
            },
            Err(error) => FileState::Failed { error, cleanup },
        };
        status(id, &file_state)
    }
    pub(super) async fn status(&self, id: &str) -> Result<RemoteTransferStatus, RemoteError> {
        let entry = self.get(id).await?;
        let file_state = entry.file.lock().await;
        if let FileState::Read { file, revision, .. } = &*file_state {
            check_revision(file, revision).await?;
        }
        status(id, &file_state)
    }
    pub(super) async fn close(&self, id: &str) -> Result<(), RemoteError> {
        let Some(entry) = self.entries.lock().await.get(id).cloned() else {
            return Ok(());
        };
        entry
            .closing
            .store(true, std::sync::atomic::Ordering::Release);
        let closing = {
            let mut state = entry.file.lock().await;
            if matches!(*state, FileState::Closing) {
                return Err(remote_error(
                    RemoteErrorCode::OutcomeUnknown,
                    "transfer commit outcome is unresolved",
                ));
            }
            if !matches!(*state, FileState::Cleanup(_)) {
                let previous = std::mem::replace(&mut *state, FileState::Closing);
                let (cleanup, publication) = match previous {
                    FileState::Write {
                        file, temporary, ..
                    } => {
                        drop(file);
                        (Some(temporary.into_cleanup()), None)
                    }
                    FileState::Failed { cleanup, .. } => (Some(cleanup), None),
                    FileState::Committed {
                        length,
                        digest,
                        cleanup,
                    } => (cleanup, Some((length, digest))),
                    FileState::Read { .. } => (None, None),
                    FileState::Cleanup(_) | FileState::Closing => unreachable!(),
                };
                // Install the complete owner/receipt before the first await after taking state.
                *state = FileState::Cleanup(Arc::new(ClosingFile::new(cleanup, publication)));
            }
            let FileState::Cleanup(closing) = &*state else {
                unreachable!()
            };
            closing.clone()
        };
        // The immutable publication stays in this same state-owned Arc. Only the finalizer's
        // inner mutex serializes cleanup waits, so status never waits behind physical cleanup.
        closing.finish().await?;
        {
            let mut entries = self.entries.lock().await;
            entries.remove(id);
            if entries.len().saturating_mul(4) < entries.capacity() {
                entries.shrink_to_fit();
            }
        }
        let mut commits = self.commits.lock().await;
        drop(entry);
        commits.retain(|_, lock| lock.strong_count() > 0);
        if commits.is_empty() {
            commits.shrink_to_fit();
        }
        Ok(())
    }
    pub(super) async fn close_workspace(&self, workspace: &str) -> Result<(), RemoteError> {
        self.admission.seal_workspace(workspace).await;
        let ids = self
            .entries
            .lock()
            .await
            .iter()
            .filter(|(_, entry)| entry.workspace == workspace)
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        self.close_ids(ids).await
    }
    pub(super) async fn len(&self) -> usize {
        self.entries.lock().await.len()
    }
    pub(super) async fn close_all(&self) -> Result<(), RemoteError> {
        self.admission.seal_all().await;
        let ids = self.entries.lock().await.keys().cloned().collect();
        self.close_ids(ids).await
    }
    async fn close_ids(&self, ids: Vec<String>) -> Result<(), RemoteError> {
        use futures::{StreamExt, stream::FuturesUnordered};
        let mut closing = ids
            .iter()
            .map(|id| self.close(id))
            .collect::<FuturesUnordered<_>>();
        let mut failures = Vec::new();
        while let Some(result) = closing.next().await {
            if let Err(error) = result {
                failures.push(error.message);
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            Err(remote_error(RemoteErrorCode::Io, failures.join("; ")))
        }
    }
}
fn status(id: &str, value: &FileState) -> Result<RemoteTransferStatus, RemoteError> {
    let (offset, total_len, revision, sha256, committed) = match value {
        FileState::Read {
            length,
            revision,
            digest,
            ..
        } => (
            0,
            Some(*length),
            Some(revision.clone()),
            Some(digest.clone()),
            false,
        ),
        FileState::Write { offset, length, .. } => (*offset, Some(*length), None, None, false),
        FileState::Committed { length, digest, .. } => {
            (*length, Some(*length), None, Some(digest.clone()), true)
        }
        FileState::Failed { error, .. } => return Err(error.clone()),
        FileState::Cleanup(closing) if closing.publication.is_some() => {
            let (length, digest) = closing
                .publication
                .as_ref()
                .expect("publication checked above");
            (*length, Some(*length), None, Some(digest.clone()), true)
        }
        FileState::Closing | FileState::Cleanup(_) => {
            return Err(remote_error(
                RemoteErrorCode::OutcomeUnknown,
                "transfer is committing or awaiting cleanup",
            ));
        }
    };
    Ok(RemoteTransferStatus {
        transfer_id: id.to_owned(),
        offset,
        total_len,
        revision,
        sha256,
        committed,
    })
}
fn revision(value: &std::fs::Metadata) -> String {
    format!(
        "{}:{}:{}:{}:{}:{}:{}",
        value.dev(),
        value.ino(),
        value.len(),
        value.mtime(),
        value.mtime_nsec(),
        value.ctime(),
        value.ctime_nsec()
    )
}
async fn check_revision(file: &tokio::fs::File, expected: &str) -> Result<(), RemoteError> {
    let actual = revision(
        &file
            .metadata()
            .await
            .map_err(|e| io_error("inspect transfer identity", e))?,
    );
    if actual != expected {
        return Err(remote_error(
            RemoteErrorCode::SourceChanged,
            "transfer source changed",
        ));
    }
    Ok(())
}
fn exhausted() -> RemoteError {
    remote_error(
        RemoteErrorCode::ResourceExhausted,
        "file transfer resource budget exhausted",
    )
}

fn ensure_open(entry: &Transfer) -> Result<(), RemoteError> {
    if entry.closing.load(std::sync::atomic::Ordering::Acquire) {
        Err(remote_error(
            RemoteErrorCode::InvalidRequest,
            "transfer is closing",
        ))
    } else {
        Ok(())
    }
}
