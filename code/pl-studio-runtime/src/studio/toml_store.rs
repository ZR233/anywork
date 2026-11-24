//! Shared owner of the three revisioned Studio TOML documents.
//!
//! Each document has one in-process owner ([`RevisionedTomlStore`]): the
//! canonical path plus the published cache behind one lock. A mutation clones
//! the cache, applies the change, bumps `revision` and persists atomically;
//! only a durable write publishes the new cache, so a failed write leaves both
//! the file and the cache untouched.

use std::future::Future;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use anyhow::{Context, Result};
use serde::Serialize;
use version_migrate::Versioned;

use crate::toml_schema::LoadedDocument;

pub(super) async fn write_file_atomically_async(path: PathBuf, contents: String) -> Result<()> {
    tokio::task::spawn_blocking(move || {
        pl_tool::workspace::write_file_atomically(&path, contents.as_bytes())
    })
    .await??;
    Ok(())
}

/// A document persisted through the blocking write boundary, so it must be
/// owned and sendable across it.
pub(super) trait RevisionedDocument: Clone + Serialize + Versioned + Send + 'static {
    const KIND: &'static str;
    const VERSION_KEY: &'static str;

    fn revision_mut(&mut self) -> &mut u64;
}

fn encode<D: RevisionedDocument>(document: &D) -> Result<String> {
    crate::toml_schema::encode(document, D::VERSION_KEY)
        .with_context(|| format!("failed to serialize {}", D::KIND))
}

/// Reads the document at `path` through `load` when the file exists. A missing
/// file is a fresh installation and yields `fresh` instead of an error; every
/// other read failure propagates before any document is published.
pub(super) async fn load_document<D, Load, Fut>(
    path: PathBuf,
    fresh: impl FnOnce() -> D,
    load: Load,
) -> Result<D>
where
    Load: FnOnce(PathBuf, String) -> Fut,
    Fut: Future<Output = Result<D>>,
{
    let content = match tokio::fs::read_to_string(&path).await {
        Ok(content) => content,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(fresh()),
        Err(error) => return Err(error.into()),
    };
    load(path, content).await
}

/// Returns the loaded document, persisting the upgraded bytes exactly once when
/// the typed chain migrated an older source. Re-opening it is then a pure read.
pub(super) async fn persist_migrated<D: RevisionedDocument>(
    path: &Path,
    loaded: LoadedDocument<D>,
) -> Result<D> {
    if loaded.migrated {
        write_file_atomically_async(path.to_path_buf(), encode(&loaded.document)?).await?;
    }
    Ok(loaded.document)
}

/// One revisioned TOML document: the canonical file plus the published cache.
#[derive(Clone)]
pub(super) struct RevisionedTomlStore<D> {
    path: PathBuf,
    inner: Arc<Mutex<D>>,
}

impl<D> RevisionedTomlStore<D> {
    pub(super) fn new(path: PathBuf, document: D) -> Self {
        Self {
            path,
            inner: Arc::new(Mutex::new(document)),
        }
    }

    /// Synchronous read access to the published cache; never touches the file.
    pub(super) fn lock(&self) -> MutexGuard<'_, D> {
        self.inner.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

impl<D: RevisionedDocument> RevisionedTomlStore<D> {
    /// Writes the current cache to the canonical file; an existing file is never
    /// overwritten. Only a fresh installation uses it, so that a later loss of
    /// the file is detected instead of silently recreating an empty document.
    pub(super) async fn persist_if_absent(&self) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        tokio::task::spawn_blocking(move || {
            if path.exists() {
                return Ok(());
            }
            let document = inner.lock().unwrap_or_else(PoisonError::into_inner);
            let contents = encode(&*document)?;
            pl_tool::workspace::write_file_atomically(&path, contents.as_bytes())
                .map_err(Into::into)
        })
        .await?
    }

    /// Applies `change` to a candidate clone under the store lock. `Ok(false)`
    /// is an idempotent no-op. The candidate is persisted before it replaces
    /// the published cache, so a failed write keeps the previous revision.
    pub(super) async fn mutate(
        &self,
        change: impl FnOnce(&mut D) -> Result<bool> + Send + 'static,
    ) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        tokio::task::spawn_blocking(move || {
            let mut document = inner.lock().unwrap_or_else(PoisonError::into_inner);
            let mut candidate = document.clone();
            if !change(&mut candidate)? {
                return Ok(());
            }
            let revision = candidate.revision_mut();
            *revision = revision.saturating_add(1);
            let contents = encode(&candidate)?;
            pl_tool::workspace::write_file_atomically(&path, contents.as_bytes())?;
            *document = candidate;
            Ok(())
        })
        .await?
    }
}
