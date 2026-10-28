//! Explicit, retained initialization of a Thread's current history database.

use super::*;
use futures::{
    FutureExt,
    future::{BoxFuture, Shared},
};
use std::sync::{Arc, Mutex};

pub(crate) type ExecutionIdentityMigration =
    Arc<dyn Fn(&mut pl_core::thread::ThreadSnapshot) -> Result<()> + Send + Sync>;

/// Only the lifecycle owner may choose a logical origin. File existence never chooses it.
#[derive(Clone)]
pub(crate) enum HistoryInitialization {
    New,
    ImportV2 {
        source_database: PathBuf,
        legacy_state: super::super::state::StateStore,
        migrate_execution_identity: ExecutionIdentityMigration,
    },
}

#[derive(Debug, thiserror::Error)]
enum PreparationFailure {
    #[error("{0:#}")]
    Failed(#[source] anyhow::Error),
    #[error("history preparation worker did not complete: {0}")]
    Interrupted(#[source] Arc<tokio::task::JoinError>),
}

type Completion = Shared<BoxFuture<'static, std::result::Result<(), Arc<PreparationFailure>>>>;

/// The weak history registry retains this slot even if every initialization waiter is cancelled.
/// It contains the real join future, not a notification standing in for a SQL commit.
#[derive(Clone, Default)]
pub(super) struct PreparationSlot(Arc<Mutex<Option<Arc<Preparation>>>>);

struct Preparation {
    completion: Completion,
    prepared_path: PathBuf,
    origin: Mutex<Option<HistoryInitialization>>,
}

impl Preparation {
    async fn finish(&self) -> Result<()> {
        let result = self
            .completion
            .clone()
            .await
            .map_err(anyhow::Error::new)
            .with_context(|| {
                format!(
                    "history preparation owns {} (the current path may already be published)",
                    self.prepared_path.display()
                )
            });
        if result.is_ok() {
            self.origin
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .take();
        }
        result
    }
}

impl PreparationSlot {
    pub(super) fn pending_or_failed(&self) -> bool {
        let slot = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        slot.as_ref()
            .is_some_and(|job| !matches!(job.completion.peek(), Some(Ok(()))))
    }

    pub(super) async fn finish(&self) -> Result<()> {
        let job = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        match job {
            Some(job) => job.finish().await,
            None => Ok(()),
        }
    }
}

impl super::HistoryStoreShare {
    pub(crate) fn preparation_pending_or_failed(&self) -> bool {
        self.preparation.pending_or_failed()
    }

    pub(in crate::studio::storage) fn confirmed_failed_initialization(
        &self,
    ) -> Option<HistoryStore> {
        // Match registration/start_preparation lock order: preparation, then retained owner. A
        // finished Tokio worker whose Shared join has not been observed is deliberately not Failed.
        let slot = self
            .preparation
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !slot.as_ref().is_some_and(|job| {
            matches!(job.completion.peek(), Some(Err(error))
            if matches!(error.as_ref(), PreparationFailure::Failed(_)))
        }) {
            return None;
        }
        self.retained
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) async fn drain_preparation(&self) -> Result<()> {
        let result = self.preparation.finish().await;
        if result.is_ok() {
            self.retained
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .take();
        }
        result
    }
}

impl HistoryStore {
    pub(super) fn preparation_retention(&self) -> Arc<Mutex<Option<HistoryStore>>> {
        // Same lock order as start_preparation. Registration cannot miss a job that starts
        // concurrently before or after this registry share is installed.
        let job = self
            .state
            .preparation
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut registered = self
            .state
            .preparation_owner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let retained = registered.upgrade().unwrap_or_else(|| {
            let slot = Arc::new(Mutex::new(None));
            *registered = Arc::downgrade(&slot);
            slot
        });
        if job
            .as_ref()
            .is_some_and(|job| !matches!(job.completion.peek(), Some(Ok(()))))
        {
            *retained
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(self.clone());
        }
        retained
    }
    #[cfg(test)]
    fn fail_after_publication(&self) -> Result<()> {
        ensure!(
            !self
                .state
                .fail_publication_confirmation
                .swap(false, std::sync::atomic::Ordering::AcqRel),
            "injected loss of history publication confirmation (move already completed)"
        );
        Ok(())
    }
    /// Registers once, then waits for the same owned worker. Cancellation only abandons waiting.
    /// Repeated calls, including calls after failure, observe the original result.
    pub(crate) async fn initialize(&self, origin: HistoryInitialization) -> Result<()> {
        let job = {
            let mut slot = self
                .state
                .preparation
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            match slot.as_ref() {
                Some(job) => job.clone(),
                None => {
                    let name = self
                        .state
                        .path
                        .file_name()
                        .context("history path has no filename")?;
                    let prepared_path = self.state.path.with_file_name(format!(
                        ".{}.prepare-{}.sqlite",
                        name.to_string_lossy(),
                        crate::studio::new_id("history")
                    ));
                    let job = self.start_preparation(origin, prepared_path);
                    *slot = Some(job.clone());
                    job
                }
            }
        };
        let result = job.finish().await;
        if result.is_ok() {
            self.release_preparation_owner();
        }
        result
    }

    /// Explicit recovery of a *known failed* attempt. Panics and unobserved joins are not retried.
    /// The same owned preparation path/origin is retained; canonical publication is checked first.
    pub(crate) async fn retry_initialization(&self) -> Result<()> {
        let job = {
            let mut slot = self
                .state
                .preparation
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let previous = slot
                .as_ref()
                .context("history has no initialization to retry")?;
            ensure!(
                matches!(previous.completion.peek(), Some(Err(error))
                if matches!(error.as_ref(), PreparationFailure::Failed(_))),
                "history initialization is not a confirmed failed operation"
            );
            let origin = previous
                .origin
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone()
                .context("failed preparation origin is absent")?;
            let job = self.start_preparation(origin, previous.prepared_path.clone());
            *slot = Some(job.clone());
            job
        };
        let result = job.finish().await;
        if result.is_ok() {
            self.release_preparation_owner();
        }
        result
    }

    pub(super) async fn wait_for_initialization(&self) -> Result<()> {
        #[cfg(test)]
        if let Some(tx) = self.state.reader_before_init.lock().await.take() {
            let _ = tx.send(());
        }
        let result = self.state.preparation.finish().await;
        if result.is_ok() {
            self.release_preparation_owner();
        }
        result
    }

    fn release_preparation_owner(&self) {
        if let Some(owner) = self
            .state
            .preparation_owner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .upgrade()
        {
            owner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .take();
        }
    }

    fn start_preparation(
        &self,
        origin: HistoryInitialization,
        prepared_path: PathBuf,
    ) -> Arc<Preparation> {
        if let Some(owner) = self
            .state
            .preparation_owner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .upgrade()
        {
            *owner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(self.clone());
        }
        let store = self.clone();
        let worker_origin = origin.clone();
        let worker_path = prepared_path.clone();
        // No await between spawn and slot publication. The slot retains the JoinHandle in Shared;
        // neither cancellation nor shutdown takes it out while waiting.
        let worker = tokio::spawn(async move {
            let _barrier = store.state.init.clone().write_owned().await;
            prepare(&store, &worker_path, worker_origin).await
        });
        Arc::new(Preparation {
            completion: async move {
                match worker.await {
                    Ok(Ok(())) => Ok(()),
                    Ok(Err(error)) => Err(Arc::new(PreparationFailure::Failed(error))),
                    Err(error) => Err(Arc::new(PreparationFailure::Interrupted(Arc::new(error)))),
                }
            }
            .boxed()
            .shared(),
            prepared_path,
            origin: Mutex::new(Some(origin)),
        })
    }
}

async fn prepare(
    store: &HistoryStore,
    prepared: &Path,
    origin: HistoryInitialization,
) -> Result<()> {
    let target = &store.state.path;
    validate_path(target).await?;
    if tokio::fs::try_exists(target).await? {
        current::inspect_ready(target, &store.state.thread_id).await?;
        // A preceding move may have succeeded before its directory-sync confirmation was lost.
        sync_published(target).await?;
        return Ok(());
    }
    if let HistoryInitialization::ImportV2 {
        source_database, ..
    } = &origin
    {
        validate_path(source_database).await?;
        ensure!(
            tokio::fs::try_exists(source_database).await?,
            "v2 history source is absent"
        );
        ensure!(
            source_database != target,
            "history source and target must be distinct"
        );
    }
    let parent = target.parent().context("history path has no parent")?;
    tokio::fs::create_dir_all(parent).await?;
    validate_path(prepared).await?;
    if !tokio::fs::try_exists(prepared).await? {
        // Physical ownership only. The caller's explicit origin is passed unchanged to Migrator.
        tokio::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(prepared)
            .await?;
    }
    #[cfg(test)]
    if let Some((entered, release)) = store.state.init_gate.lock().await.take() {
        let _ = entered.send(());
        let _ = release.await;
    }
    let db = connect(prepared).await?;
    let outcome = std::panic::AssertUnwindSafe(current::initialize(
        &db,
        &store.state.thread_id,
        origin,
        #[cfg(test)]
        store.state.migration_fault.clone(),
    ))
    .catch_unwind()
    .await;
    let checkpoint = if matches!(&outcome, Ok(Ok(()))) {
        checkpoint_and_close(&db).await
    } else {
        Ok(())
    };
    // close is always awaited, even after a migration/checkpoint failure. No detached SQL worker
    // can outlive the retained preparation's completion or release its initialization barrier.
    let closed = db.close().await;
    let outcome = match outcome {
        Ok(result) => result,
        Err(panic) => {
            let _ = closed;
            std::panic::resume_unwind(panic);
        }
    };
    if let Err(close) = closed {
        let close = crate::studio::startup::cleanup_error(close);
        return Err(match outcome.and(checkpoint) {
            Ok(()) => close,
            Err(error) => close.context(error),
        });
    }
    outcome?;
    checkpoint?;
    sync_published(prepared).await?;
    let source = prepared.to_owned();
    let destination = target.clone();
    tokio::task::spawn_blocking(move || {
        // Lifecycle/data-root admission and init are held throughout. Check again immediately before
        // the existing no-overwrite owned-path capability; never replace an unknown target.
        validate_path_sync(&source)?;
        validate_path_sync(&destination)?;
        pl_tool::workspace::move_owned_path(&source, &destination)
            .context("publish current history (a sync failure may follow a completed move)")
    })
    .await??;
    #[cfg(test)]
    store.fail_after_publication()?;
    Ok(())
}

async fn checkpoint_and_close(db: &DatabaseConnection) -> Result<()> {
    let row = db
        .query_one_raw(statement("PRAGMA wal_checkpoint(TRUNCATE)", vec![]))
        .await?
        .context("SQLite returned no checkpoint result")?;
    ensure!(
        row.try_get_by_index::<i64>(0)? == 0
            && row.try_get_by_index::<i64>(1)? == 0
            && row.try_get_by_index::<i64>(2)? == 0,
        "prepared history WAL checkpoint is busy"
    );
    Ok(())
}

async fn validate_path(path: &Path) -> Result<()> {
    let owned = path.to_owned();
    tokio::task::spawn_blocking(move || validate_path_sync(&owned)).await?
}

pub(super) async fn validate_database_path(path: &Path) -> Result<()> {
    validate_path(path).await?;
    for suffix in ["-wal", "-shm"] {
        let mut name = path.as_os_str().to_owned();
        name.push(suffix);
        validate_path(Path::new(&name)).await?;
    }
    Ok(())
}

fn validate_path_sync(path: &Path) -> Result<()> {
    let absolute = std::path::absolute(path)?;
    let root = absolute
        .ancestors()
        .last()
        .context("history path has no root")?;
    pl_tool::workspace::path_safety::validate_path_for_write(root, &absolute)?;
    if let Ok(metadata) = std::fs::symlink_metadata(&absolute) {
        ensure!(metadata.is_file(), "history path is not a regular file");
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            // This is a path-safety preflight, not an existence proof. A concurrent SQLite close
            // can unlink a WAL/SHM after lookup but before stat reports its metadata (nlink=0).
            // Absence is already allowed here; only an actual second link aliases another path.
            // The readonly open/readiness gate still rejects a missing canonical database.
            ensure!(
                metadata.nlink() <= 1,
                "history path has invalid hard-link count {}: {}",
                metadata.nlink(),
                absolute.display()
            );
        }
    }
    Ok(())
}

async fn sync_published(path: &Path) -> Result<()> {
    let path = path.to_owned();
    tokio::task::spawn_blocking(move || -> Result<()> {
        validate_path_sync(&path)?;
        std::fs::File::open(&path)?.sync_all()?;
        #[cfg(not(windows))]
        std::fs::File::open(path.parent().context("history path has no parent")?)?.sync_all()?;
        Ok(())
    })
    .await?
}
