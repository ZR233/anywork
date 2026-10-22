//! Opaque one-level directory iterators. Recursive policy belongs to the host.
use super::*;
use crate::budget::{ByteLease, ResourceBudget};
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug)]
struct Cursor {
    reader: tokio::fs::ReadDir,
    path: PathBuf,
    display: String,
    parent: Option<String>,
    modified: Option<std::time::SystemTime>,
    pending: Option<RemoteDirectoryEntry>,
    _lease: ByteLease,
}
#[derive(Debug)]
struct DirectoryHandle {
    workspace: Option<String>,
    cursor: Mutex<Cursor>,
}
#[derive(Debug)]
pub(super) struct Directories {
    cursors: Mutex<HashMap<String, Arc<DirectoryHandle>>>,
    next: std::sync::atomic::AtomicU64,
    instance: String,
}
impl Directories {
    pub(super) fn new(instance: String) -> Self {
        Self {
            cursors: Default::default(),
            next: std::sync::atomic::AtomicU64::new(0),
            instance,
        }
    }
    pub(super) async fn open(
        &self,
        path: PathBuf,
        display: String,
        workspace: Option<String>,
        budget: &ResourceBudget,
        reply_limit: usize,
    ) -> Result<RemoteDirectoryListing, RemoteError> {
        let lease = budget
            .try_reserve(std::mem::size_of::<Cursor>() + display.len())
            .ok_or_else(|| {
                remote_error(
                    RemoteErrorCode::ResourceExhausted,
                    "directory handle budget exhausted",
                )
            })?;
        let reader = tokio::fs::read_dir(&path)
            .await
            .map_err(|e| io_error("open directory", e))?;
        let metadata = tokio::fs::metadata(&path)
            .await
            .map_err(|e| io_error("inspect directory", e))?;
        let id = format!(
            "{}-{}",
            self.instance,
            self.next.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        );
        let parent = path.parent().map(|v| v.to_string_lossy().into_owned());
        self.cursors.lock().await.insert(
            id.clone(),
            Arc::new(DirectoryHandle {
                workspace,
                cursor: Mutex::new(Cursor {
                    reader,
                    path,
                    display,
                    parent,
                    modified: metadata.modified().ok(),
                    pending: None,
                    _lease: lease,
                }),
            }),
        );
        match self.next(&id, budget, reply_limit).await {
            Ok(page) => Ok(page),
            Err(error) => {
                self.close(&id).await;
                Err(error)
            }
        }
    }
    pub(super) async fn next(
        &self,
        id: &str,
        budget: &ResourceBudget,
        reply_limit: usize,
    ) -> Result<RemoteDirectoryListing, RemoteError> {
        let cursor = self.cursors.lock().await.get(id).cloned().ok_or_else(|| {
            remote_error(RemoteErrorCode::InvalidCursor, "directory cursor is closed")
        })?;
        let mut cursor = cursor.cursor.lock().await;
        let modified = tokio::fs::metadata(&cursor.path)
            .await
            .map_err(|e| io_error("inspect directory cursor", e))?
            .modified()
            .ok();
        if modified != cursor.modified {
            drop(cursor);
            self.close(id).await;
            return Err(remote_error(
                RemoteErrorCode::InvalidCursor,
                "directory changed during enumeration",
            ));
        }
        let mut page = RemoteDirectoryListing {
            path: cursor.display.clone(),
            parent: cursor.parent.clone(),
            entries: Vec::new(),
            next_cursor: Some(id.to_owned()),
        };
        let budget = budget.allocation().fragment_bytes.min(reply_limit);
        let mut encoded = serde_json::to_vec(&RemoteResponse::Directories(page.clone()))
            .map_err(|e| remote_error(RemoteErrorCode::InvalidRequest, e.to_string()))?
            .len();
        let mut finished = false;
        loop {
            let entry = if let Some(entry) = cursor.pending.take() {
                entry
            } else {
                let Some(entry) = cursor
                    .reader
                    .next_entry()
                    .await
                    .map_err(|e| io_error("read directory entry", e))?
                else {
                    finished = true;
                    break;
                };
                let metadata = tokio::fs::symlink_metadata(entry.path())
                    .await
                    .map_err(|e| io_error("inspect directory entry", e))?;
                let is_symlink = metadata.file_type().is_symlink();
                let is_directory = if is_symlink {
                    tokio::fs::metadata(entry.path())
                        .await
                        .is_ok_and(|value| value.is_dir())
                } else {
                    metadata.is_dir()
                };
                let name = entry.file_name().to_string_lossy().into_owned();
                let path = if cursor.display == "." {
                    name.clone()
                } else {
                    format!("{}/{}", cursor.display.trim_end_matches('/'), name)
                };
                RemoteDirectoryEntry {
                    name,
                    path,
                    is_directory,
                    is_symlink,
                }
            };
            let cost = serde_json::to_vec(&entry)
                .map_err(|e| remote_error(RemoteErrorCode::InvalidRequest, e.to_string()))?
                .len()
                + 1;
            if encoded.saturating_add(cost) > budget {
                cursor.pending = Some(entry);
                if page.entries.is_empty() {
                    return Err(remote_error(
                        RemoteErrorCode::ResourceExhausted,
                        "directory entry exceeds current page grant",
                    ));
                }
                break;
            }
            encoded += cost;
            page.entries.push(entry);
        }
        drop(cursor);
        if finished {
            self.close(id).await;
            page.next_cursor = None;
        }
        Ok(page)
    }
    pub(super) async fn close(&self, id: &str) {
        let mut cursors = self.cursors.lock().await;
        cursors.remove(id);
        if cursors.len().saturating_mul(4) < cursors.capacity() {
            cursors.shrink_to_fit();
        }
    }
    pub(super) async fn close_workspace(&self, workspace: &str) {
        let mut cursors = self.cursors.lock().await;
        cursors.retain(|_, handle| handle.workspace.as_deref() != Some(workspace));
        if cursors.len().saturating_mul(4) < cursors.capacity() {
            cursors.shrink_to_fit();
        }
    }
    pub(super) async fn len(&self) -> usize {
        self.cursors.lock().await.len()
    }
    pub(super) async fn close_all(&self) {
        self.cursors.lock().await.clear();
    }
}
