//! Host-owned incremental traversal and cursors shared by local and remote adapters.
use super::{WorkspaceFileListEntry, WorkspaceFileListRequest, WorkspaceFileListResult};
use futures::{StreamExt, stream::BoxStream};
use pl_protocol::Result;
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

pub(crate) type Entries = BoxStream<'static, Result<WorkspaceFileListEntry>>;
struct Walk {
    entries: Entries,
    query: String,
    pending: Option<String>,
    stop: CancellationToken,
}
struct Cursor {
    walk: Arc<tokio::sync::Mutex<Walk>>,
    stop: CancellationToken,
    expires: tokio::time::Instant,
}
#[derive(Default)]
struct State {
    entries: HashMap<String, Cursor>,
    expiry: BTreeMap<tokio::time::Instant, Vec<String>>,
}
struct Inner {
    state: Mutex<State>,
    changed: Arc<Notify>,
    stop: CancellationToken,
    started: std::sync::atomic::AtomicBool,
}
impl Drop for Inner {
    fn drop(&mut self) {
        self.stop.cancel();
    }
}
#[derive(Clone)]
pub(crate) struct ListingPager(Arc<Inner>);
impl std::fmt::Debug for ListingPager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ListingPager").finish_non_exhaustive()
    }
}
impl Default for ListingPager {
    fn default() -> Self {
        Self(Arc::new(Inner {
            state: Mutex::new(State::default()),
            changed: Arc::new(Notify::new()),
            stop: CancellationToken::new(),
            started: std::sync::atomic::AtomicBool::new(false),
        }))
    }
}
impl ListingPager {
    fn start_reaper(&self) {
        if self
            .0
            .started
            .swap(true, std::sync::atomic::Ordering::AcqRel)
        {
            return;
        }
        let inner = self.0.clone();
        let weak = Arc::downgrade(&inner);
        let changed = inner.changed.clone();
        let stop = inner.stop.clone();
        tokio::spawn(async move {
            loop {
                let notification = changed.notified();
                tokio::pin!(notification);
                notification.as_mut().enable();
                let deadline = {
                    let Some(inner) = weak.upgrade() else {
                        return;
                    };
                    let mut state = inner
                        .state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    let now = tokio::time::Instant::now();
                    while state
                        .expiry
                        .first_key_value()
                        .is_some_and(|(deadline, _)| *deadline <= now)
                    {
                        let (deadline, ids) = state.expiry.pop_first().unwrap();
                        for id in ids {
                            if state
                                .entries
                                .get(&id)
                                .is_some_and(|entry| entry.expires == deadline)
                            {
                                remove_cursor(&mut state, &id);
                            }
                        }
                    }
                    state
                        .expiry
                        .first_key_value()
                        .map(|(deadline, _)| *deadline)
                };
                match deadline {
                    Some(deadline) => {
                        tokio::select! { _ = stop.cancelled() => return, _ = notification => {}, _ = tokio::time::sleep_until(deadline) => {} }
                    }
                    None => {
                        tokio::select! { _ = stop.cancelled() => return, _ = notification => {} }
                    }
                }
            }
        });
    }
}
impl ListingPager {
    pub(crate) fn close(&self, id: &str) {
        remove_cursor(
            &mut self
                .0
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
            id,
        );
        self.0.changed.notify_waiters();
    }
    pub(crate) async fn page(
        &self,
        request: WorkspaceFileListRequest,
        open: impl std::future::Future<Output = Result<Entries>> + Send,
    ) -> Result<WorkspaceFileListResult> {
        if request.max_files == 0 {
            return Err(crate::tool_error(
                "list_files",
                "page size must be positive",
            ));
        }
        self.start_reaper();
        let query = serde_json::to_string(
            &serde_json::json!({"path":request.path,"cwd":request.cwd,
            "glob":request.glob,"includeDirs":request.include_dirs,"recovery":request.implicit_recovery}),
        )?;
        let (id, walk) = if let Some(id) = request.cursor.as_ref() {
            let state = self
                .0
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let cursor = state.entries.get(id).ok_or_else(|| {
                crate::tool_error(
                    "list_files",
                    "directory cursor expired; start a new listing",
                )
            })?;
            (id.clone(), cursor.walk.clone())
        } else {
            let entries = open.await?;
            let walk = Arc::new(tokio::sync::Mutex::new(Walk {
                entries,
                query: query.clone(),
                pending: None,
                stop: CancellationToken::new(),
            }));
            let mut identity = [0_u8; 16];
            getrandom::fill(&mut identity)
                .map_err(|error| crate::tool_error("list_files", error))?;
            let id = hex::encode(identity);
            (id, walk)
        };
        let mut guard = PageGuard {
            inner: Arc::downgrade(&self.0),
            id: id.clone(),
            committed: false,
        };
        let mut traversal = walk.lock().await;
        let stop = traversal.stop.clone();
        if traversal.query != query {
            return Err(crate::tool_error(
                "list_files",
                "cursor belongs to a different listing",
            ));
        }
        let mut files = Vec::new();
        let mut finished = false;
        let mut scanned = 0usize;
        // Recovery is deliberately a lower-priority bounded observation, not an exhaustive search.
        let scan_budget = request
            .max_files
            .saturating_mul(std::thread::available_parallelism().map_or(1, usize::from))
            .saturating_mul(std::mem::size_of::<WorkspaceFileListEntry>())
            .max(request.max_files);
        if let Some(pending) = traversal.pending.take() {
            files.push(pending);
        }
        while files.len() <= request.max_files {
            if request.implicit_recovery && scanned >= scan_budget {
                break;
            }
            let entry = tokio::select! {
                _ = stop.cancelled() => return Err(crate::tool_error("list_files", "directory cursor closed")),
                entry = traversal.entries.next() => entry,
            };
            let Some(entry) = entry else {
                finished = true;
                break;
            };
            let entry = entry?;
            scanned = scanned.saturating_add(entry.path.len());
            if entry.is_dir && !request.include_dirs {
                continue;
            }
            let relative = entry
                .path
                .strip_prefix(request.path.trim_end_matches('/'))
                .map(|p| p.trim_start_matches('/'))
                .unwrap_or(&entry.path);
            if !crate::file::matches_pattern(&entry.path, Some(&request.glob))
                && !crate::file::matches_pattern(relative, Some(&request.glob))
            {
                continue;
            }
            files.push(if entry.is_dir {
                format!("{}/", entry.path.trim_end_matches('/'))
            } else {
                entry.path
            });
        }
        if files.len() > request.max_files {
            traversal.pending = files.pop();
        }
        files.sort();
        drop(traversal);
        let truncated = !finished;
        let next_cursor = if truncated && !request.implicit_recovery {
            let expires = tokio::time::Instant::now() + Duration::from_secs(300);
            let mut state = self
                .0
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if stop.is_cancelled() {
                return Err(crate::tool_error("list_files", "directory cursor closed"));
            }
            if let Some(previous) = state.entries.insert(
                id.clone(),
                Cursor {
                    walk,
                    expires,
                    stop,
                },
            ) && let Some(ids) = state.expiry.get_mut(&previous.expires)
            {
                ids.retain(|value| value != &id);
                if ids.is_empty() {
                    state.expiry.remove(&previous.expires);
                }
            }
            state.expiry.entry(expires).or_default().push(id.clone());
            self.0.changed.notify_waiters();
            Some(id)
        } else {
            remove_cursor(
                &mut self
                    .0
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner),
                &id,
            );
            None
        };
        guard.committed = true;
        Ok(WorkspaceFileListResult {
            files,
            truncated,
            next_cursor,
        })
    }
}

pub(crate) fn skip_directory(path: &str, implicit_recovery: bool) -> bool {
    let name = path
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or(path);
    matches!(name, ".git" | "target" | "node_modules")
        || (implicit_recovery && name == "commands" && path.contains(".anywork/sessions/"))
}

fn remove_cursor(state: &mut State, id: &str) {
    if let Some(cursor) = state.entries.remove(id) {
        cursor.stop.cancel();
        if let Some(ids) = state.expiry.get_mut(&cursor.expires) {
            ids.retain(|entry| entry != id);
            if ids.is_empty() {
                state.expiry.remove(&cursor.expires);
            }
        }
    }
    if state.entries.is_empty() {
        state.entries.shrink_to_fit();
    }
}
struct PageGuard {
    inner: std::sync::Weak<Inner>,
    id: String,
    committed: bool,
}
impl Drop for PageGuard {
    fn drop(&mut self) {
        if !self.committed
            && let Some(inner) = self.inner.upgrade()
        {
            remove_cursor(
                &mut inner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner),
                &self.id,
            );
            inner.changed.notify_waiters();
        }
    }
}
