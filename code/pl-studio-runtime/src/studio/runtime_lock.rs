use std::fs::{File, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::{Arc, Mutex};

use crate::{StudioError, StudioResult};
use fs4::{FileExt, TryLockError};
use serde::Serialize;

use super::runtime_options::StudioHostKind;

#[derive(Debug)]
pub(super) struct RuntimeLock {
    file: File,
}

#[derive(Clone, Default)]
pub(super) struct RuntimeLockOwner {
    lock: Arc<Mutex<Option<Arc<RuntimeLock>>>>,
}

impl RuntimeLockOwner {
    pub(super) fn new(lock: Option<Arc<RuntimeLock>>) -> Self {
        Self {
            lock: Arc::new(Mutex::new(lock)),
        }
    }

    pub(super) fn release(&self) {
        let mut lock = match self.lock.lock() {
            Ok(lock) => lock,
            Err(poisoned) => poisoned.into_inner(),
        };
        lock.take();
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeLockMetadata<'a> {
    pid: u32,
    host: &'a str,
    started_at: u64,
}

impl RuntimeLock {
    pub(super) fn acquire(path: &Path, host: StudioHostKind) -> StudioResult<Self> {
        let parent = path.parent().ok_or_else(|| {
            StudioError::invalid_argument("Studio runtime lock path has no parent directory")
        })?;
        std::fs::create_dir_all(parent).map_err(|error| {
            tracing::error!(error = %error, "failed to create Studio runtime directory");
            StudioError::storage()
        })?;
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(path)
            .map_err(|error| {
                tracing::error!(error = %error, "failed to open Studio runtime lock");
                StudioError::storage()
            })?;
        match FileExt::try_lock(&file) {
            Ok(()) => {}
            Err(TryLockError::WouldBlock) => return Err(StudioError::instance_busy()),
            Err(TryLockError::Error(error)) => {
                tracing::error!(error = %error, "failed to acquire Studio runtime lock");
                return Err(StudioError::storage());
            }
        }
        let metadata = RuntimeLockMetadata {
            pid: std::process::id(),
            host: host.as_str(),
            started_at: u64::try_from(super::ids::unix_seconds()).unwrap_or(0),
        };
        let encoded = serde_json::to_vec(&metadata).map_err(|error| {
            tracing::error!(error = %error, "failed to encode Studio runtime lock metadata");
            StudioError::internal()
        })?;
        // The OS lock is the exclusive-owner authority. These bytes only describe the
        // live holder; they must be visible to local readers, not durable after a crash.
        // Forcing this diagnostic write to disk stalls startup behind unrelated IO.
        file.set_len(0)
            .and_then(|()| file.seek(SeekFrom::Start(0)))
            .and_then(|_| file.write_all(&encoded))
            .map_err(|error| {
                tracing::error!(error = %error, "failed to write Studio runtime lock metadata");
                StudioError::storage()
            })?;
        Ok(Self { file })
    }
}

impl Drop for RuntimeLock {
    fn drop(&mut self) {
        if let Err(error) = FileExt::unlock(&self.file) {
            tracing::warn!(error = %error, "failed to release Studio runtime lock explicitly");
        }
    }
}
