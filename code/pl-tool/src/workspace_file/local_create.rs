//! Cancellation-safe ownership of local user-file Create workers and pending cleanup.

use std::io::{self, Read, Seek, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use pl_protocol::Result;
use pl_remote_helper::file_create::{CreateFile, CreateReceipt};
use pl_remote_helper::workspace_dir::WorkspaceDir;
use sha2::{Digest, Sha256};
use tokio::sync::{Mutex as AsyncMutex, Semaphore};
use tokio::task::JoinHandle;

type Outcome = std::result::Result<(), Arc<CreateFailure>>;

/// Thread-owned local Create jobs. Clones share admission, serialization and cleanup ownership.
///
/// Cancelling an individual create only stops its observation. The worker retains its serial
/// permit and physical transaction. The host must keep this owner until `close` succeeds;
/// dropping the final clone is not an asynchronous shutdown operation.
#[derive(Debug, Clone, Default)]
pub struct LocalFileCreateOwner(Arc<Owner>);

#[derive(Debug)]
struct Owner {
    registry: Mutex<Registry>,
    serial: Arc<Semaphore>,
}

impl Default for Owner {
    fn default() -> Self {
        Self {
            registry: Mutex::new(Registry::default()),
            serial: Arc::new(Semaphore::new(1)),
        }
    }
}

#[derive(Debug, Default)]
struct Registry {
    sealed: bool,
    operations: Vec<Arc<Operation>>,
}

#[derive(Debug, Default)]
struct Operation {
    // Only this per-operation async lock is held while joining. The registry is never held
    // across a wait or I/O. Cancellation leaves the unique JoinHandle in this slot.
    task: AsyncMutex<Task>,
    staging: Arc<Staging>,
    // Monotonic: publish only after joining every actual task and releasing its stage.
    // A worker's pending=false alone is not proof its JoinHandle has been observed.
    drained: AtomicBool,
}

#[derive(Debug, Default)]
struct Staging {
    file: Mutex<Option<CreateFile>>,
    pending: AtomicBool,
}

#[derive(Debug, Default)]
struct Task {
    running: Option<JoinHandle<Outcome>>,
    create_result: Option<Outcome>,
}

#[derive(Debug, thiserror::Error)]
#[error("local Create failed (physical receipt: {receipt:?}): {source}; cleanup: {cleanup:?}")]
struct CreateFailure {
    receipt: Option<CreateReceipt>,
    #[source]
    source: io::Error,
    cleanup: Option<io::Error>,
}

impl LocalFileCreateOwner {
    /// Seals admission, joins all accepted workers and retries their retained staging cleanup.
    ///
    /// This operation is cancellation-safe and repeatable: a cancelled close leaves every
    /// running handle in its original slot; a cleanup failure retains its exact directory
    /// capability and file owner. A sealed owner never accepts a later create.
    ///
    /// # Errors
    /// Reports retained cleanup failures. The host must retain this owner and retry;
    /// previous create failures without remaining resources do not prevent closure.
    pub async fn close(&self) -> Result<()> {
        let operations = {
            let mut registry = self
                .0
                .registry
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            registry.sealed = true;
            self.0.serial.close();
            registry.operations.clone()
        };
        let mut failures = Vec::new();
        for operation in &operations {
            if let Err(error) = operation.close().await {
                failures.push(error.to_string());
            }
        }
        {
            let mut registry = self
                .0
                .registry
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            registry
                .operations
                .retain(|operation| !operation.is_drained());
        }
        if failures.is_empty() {
            Ok(())
        } else {
            Err(crate::tool_error("write_file", failures.join("; ")))
        }
    }

    pub(super) async fn create(
        &self,
        root: WorkspaceDir,
        relative: PathBuf,
        bytes: Arc<[u8]>,
    ) -> Result<()> {
        let permit = self
            .0
            .serial
            .clone()
            .acquire_owned()
            .await
            .map_err(|_| crate::tool_error("write_file", "local Create owner is closed"))?;
        let operation;
        {
            let mut registry = self
                .0
                .registry
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if registry.sealed {
                return Err(crate::tool_error(
                    "write_file",
                    "local Create owner is closed",
                ));
            }
            // The operation is not observable until its handle has been installed. The same
            // short registry lock linearizes this registration with close's seal/snapshot.
            let mut accepted = Operation::default();
            let staging = accepted.staging.clone();
            let handle = tokio::task::spawn_blocking(move || {
                let _permit = permit;
                create_and_cleanup(root, &relative, &bytes, &staging)
            });
            accepted.task.get_mut().running = Some(handle);
            operation = Arc::new(accepted);
            registry.operations.push(operation.clone());
        }
        let result = operation.wait_create().await;
        if operation.is_drained() {
            self.0
                .registry
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .operations
                .retain(|registered| !Arc::ptr_eq(registered, &operation));
        }
        result.map_err(|error| crate::tool_error("write_file", error))
    }
}

impl Operation {
    async fn wait_create(&self) -> Outcome {
        let mut task = self.task.lock().await;
        if task.create_result.is_none() {
            let result = join(&mut task.running).await;
            task.create_result = Some(result);
        }
        self.publish_drained(&task);
        task.create_result.clone().unwrap_or_else(|| {
            Err(failure(
                io::Error::other("Create result is unavailable"),
                None,
                None,
            ))
        })
    }

    fn has_staging(&self) -> bool {
        self.staging.pending.load(Ordering::Acquire)
    }

    fn is_drained(&self) -> bool {
        self.drained.load(Ordering::Acquire)
    }

    fn publish_drained(&self, task: &Task) {
        if task.running.is_none() && !self.has_staging() {
            self.drained.store(true, Ordering::Release);
        }
    }

    async fn close(&self) -> Outcome {
        // Join the original operation even if its requesting future no longer exists.
        let _original = self.wait_create().await;
        let mut task = self.task.lock().await;
        if task.running.is_none() && self.has_staging() {
            let staging = self.staging.clone();
            task.running = Some(tokio::task::spawn_blocking(move || cleanup(&staging)));
        }
        let result = if task.running.is_some() {
            join(&mut task.running).await
        } else {
            Ok(())
        };
        self.publish_drained(&task);
        result
    }
}

async fn join(slot: &mut Option<JoinHandle<Outcome>>) -> Outcome {
    let result = match slot.as_mut() {
        Some(handle) => handle.await,
        None => {
            return Err(failure(
                io::Error::other("Create worker is missing"),
                None,
                None,
            ));
        }
    };
    // Remove every observed terminal handle, including JoinError, before propagating it.
    slot.take();
    result.unwrap_or_else(|error| {
        Err(failure(
            io::Error::other(format!(
                "Create worker outcome requires verification: {error}"
            )),
            None,
            None,
        ))
    })
}

fn create_and_cleanup(
    root: WorkspaceDir,
    relative: &std::path::Path,
    bytes: &[u8],
    staging: &Staging,
) -> Outcome {
    let created = root
        .begin(relative)
        .map_err(|error| failure(error, None, None))?;
    let mut slot = staging
        .file
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    *slot = Some(created);
    staging.pending.store(true, Ordering::Release);
    let Some(file) = slot.as_mut() else {
        return Err(failure(
            io::Error::other("Create owner was not installed"),
            None,
            None,
        ));
    };
    let written = (|| {
        file.file_mut()?.write_all(bytes)?;
        file.file_mut()?.rewind()?;
        let mut digest = Sha256::new();
        let mut buffer = [0_u8; 64 * 1024];
        loop {
            let count = file.file_mut()?.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            digest.update(&buffer[..count]);
        }
        if digest.finalize() != Sha256::digest(bytes) {
            return Err(io::Error::other(
                "Create staging checksum differs from original bytes",
            ));
        }
        file.publish()
    })();
    let cleaned = file.cleanup();
    let receipt = file.receipt();
    let result = match (written, cleaned) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(source), Ok(())) => Err(failure(source, Some(receipt), None)),
        (Ok(()), Err(source)) => Err(failure(source, Some(receipt), None)),
        (Err(source), Err(cleanup)) => Err(failure(source, Some(receipt), Some(cleanup))),
    };
    if receipt.staging_removed
        && receipt.directory_sync != pl_remote_helper::file_create::DirectorySync::Pending
    {
        slot.take();
        staging.pending.store(false, Ordering::Release);
    }
    result
}

fn cleanup(staging: &Staging) -> Outcome {
    let mut slot = staging
        .file
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if let Some(file) = slot.as_mut() {
        file.cleanup()
            .map_err(|error| failure(error, Some(file.receipt()), None))?;
        slot.take();
    }
    staging.pending.store(false, Ordering::Release);
    Ok(())
}

fn failure(
    source: io::Error,
    receipt: Option<CreateReceipt>,
    cleanup: Option<io::Error>,
) -> Arc<CreateFailure> {
    Arc::new(CreateFailure {
        receipt,
        source,
        cleanup,
    })
}
