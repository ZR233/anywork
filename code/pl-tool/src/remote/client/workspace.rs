//! 物理 workspace handle 只属于真实在途操作与探测事务。
//!
//! 缓存只保留弱引用；逻辑 backend 不持有物理句柄。最后一个使用者释放后，句柄先登记为
//! 本连接的待释放责任，再经同一物理连接发送 `closeWorkspace`；确认后责任才消失。
//!
//! 每个活跃 handle 还占着 helper 公告的 workspace 根描述符份额。该份额由连接的活跃表持有，
//! 与真实使用者通过 `Arc` 共享：同一 opaque id 只计一次，`closeWorkspace` 确认只删除注册责任，
//! 描述符本身要等最后一个真实使用者结束才归还；连接终态时整表清空，远端由 helper 自行回收。

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::{Mutex as SyncMutex, Weak};

use pl_protocol::remote::{RemoteRequest, RemoteResponse};
use tokio::sync::oneshot;

use super::super::error::RemoteClientError;
use super::RemoteClient;
use super::fds::WorkspaceRetained;
use super::session::{ActivityGuard, StreamLease, response_kind};

/// Cache of the workspace handles currently open on one physical connection.
pub(in crate::remote) type WorkspaceCache = SyncMutex<HashMap<String, CachedWorkspace>>;

/// A cache entry never owns the handle; only real users keep a workspace open.
#[derive(Debug)]
pub(in crate::remote) struct CachedWorkspace {
    pub(in crate::remote) lease: Weak<WorkspaceLease>,
}

/// One workspace root the helper opened and this connection keeps charged.
///
/// Handing the root over is explicit: while it is unclaimed, dropping it closes the handle on this same
/// connection, so a caller that disappears after the helper created the root never leaves an unknown
/// remote workspace or a stranded descriptor charge behind.
#[derive(Debug)]
pub(in crate::remote) struct OpenedWorkspace {
    id: String,
    path: String,
    retained: Arc<WorkspaceRetained>,
    /// Closes the root unless the caller accepted it.
    claim: UnclaimedRoot,
}

/// Closing guard of one root that no caller has accepted yet.
#[derive(Debug)]
struct UnclaimedRoot {
    client: RemoteClient,
    id: String,
    armed: bool,
}

impl Drop for UnclaimedRoot {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }
        // Nobody claimed this root: only register and start the release on this same connection. The
        // registry entry and its persistent descriptors stay until the helper's strict acknowledgement
        // or the connection's terminal state — the only two facts that may drop them — so an unclaimed
        // guard can never return the root's budget ahead of the real release.
        close_workspace(self.client.clone(), self.id.clone());
    }
}

impl OpenedWorkspace {
    /// Accepts the root: from now on the caller owns its release responsibility.
    pub(in crate::remote) fn into_parts(mut self) -> (String, String, Arc<WorkspaceRetained>) {
        self.claim.armed = false;
        (self.id, self.path, self.retained)
    }
}

/// One physical workspace handle: valid only on the connection that opened it.
#[derive(Debug)]
pub(in crate::remote) struct WorkspaceLease {
    client: RemoteClient,
    id: String,
    path: String,
    alias: String,
    cache: Weak<WorkspaceCache>,
    /// Shared with the connection's active table: one root never charges twice.
    _retained: Arc<WorkspaceRetained>,
    _activity: ActivityGuard,
}

impl WorkspaceLease {
    /// Binds one opened root to its logical alias and the cache of its connection.
    ///
    /// The cache keeps only a weak reference, so the handle is released exactly when its last user
    /// drops this lease, not when a table entry is replaced.
    pub(in crate::remote) fn bind(
        client: RemoteClient,
        opened: OpenedWorkspace,
        alias: String,
        cache: Arc<WorkspaceCache>,
    ) -> Arc<Self> {
        let activity = ActivityGuard::new(client.inner.clone());
        let (id, path, retained) = opened.into_parts();
        let lease = Arc::new(Self {
            client,
            id,
            path,
            alias,
            cache: Arc::downgrade(&cache),
            _retained: retained,
            _activity: activity,
        });
        cache
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(
                lease.path.clone(),
                CachedWorkspace {
                    lease: Arc::downgrade(&lease),
                },
            );
        lease
    }

    /// The opaque helper-assigned handle identity of this connection.
    pub(in crate::remote) fn id(&self) -> &str {
        &self.id
    }

    /// The canonical POSIX workspace root returned by the helper.
    pub(in crate::remote) fn path(&self) -> &str {
        &self.path
    }

    /// Whether this handle belongs to the given physical connection.
    pub(in crate::remote) fn is_connection(&self, client: &RemoteClient) -> bool {
        self.client.is_same_connection(client)
    }
}

impl Drop for WorkspaceLease {
    fn drop(&mut self) {
        tracing::trace!(
            alias = %self.alias,
            connection = self.client.instance(),
            "releasing remote workspace handle"
        );
        if let Some(cache) = self.cache.upgrade() {
            let mut cache = cache
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if cache
                .get(&self.path)
                .is_some_and(|entry| std::ptr::eq(entry.lease.as_ptr(), self))
            {
                cache.remove(&self.path);
            }
        }
        close_workspace(self.client.clone(), self.id.clone());
    }
}

impl RemoteClient {
    /// Opens one workspace on its own tracked owner and hands the claimable root to the caller.
    ///
    /// The owner does the whole transaction itself: the descriptor reservation that opened the root is
    /// split into the persistent share and the temporary open peak (released as soon as the open phase
    /// really ended), so a caller deadline can never leave a half-charged handle. A caller that drops
    /// the receiver — or that never gets to claim — makes the owner close the handle it just created
    /// on this same connection instead of leaking an unknown remote workspace.
    pub(in crate::remote) fn open_workspace_owned(
        &self,
        lease: StreamLease,
        path: String,
    ) -> oneshot::Receiver<Result<OpenedWorkspace, RemoteClientError>> {
        let (ready, opened) = oneshot::channel();
        let owner =
            self.inner
                .tasks
                .track_future(open_workspace_owner(self.clone(), lease, path, ready));
        tokio::spawn(owner);
        opened
    }

    /// Returns the cached handle for `path` on this connection, if a real user still holds it.
    pub(in crate::remote) fn cached_workspace(
        &self,
        cache: &WorkspaceCache,
        path: &str,
    ) -> Option<Arc<WorkspaceLease>> {
        let cache = cache
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let lease = cache.get(path)?.lease.upgrade()?;
        drop(cache);
        lease.is_connection(self).then_some(lease)
    }
}

/// Runs one `openWorkspace` transaction to a decided result and keeps its charge claimable.
async fn open_workspace_owner(
    client: RemoteClient,
    lease: StreamLease,
    path: String,
    ready: oneshot::Sender<Result<OpenedWorkspace, RemoteClientError>>,
) {
    let opened = match open_workspace(client.clone(), lease, path).await {
        Ok(opened) => opened,
        Err(error) => {
            let _ = ready.send(Err(error));
            return;
        }
    };
    // A receiver that is dropped — before this send or after it — drops the root, and its claim guard
    // then releases the remote handle on this same connection.
    let _ = ready.send(Ok(opened));
}

/// Runs the open transaction and splits the persistent root charge out of its own reservation.
async fn open_workspace(
    client: RemoteClient,
    lease: StreamLease,
    path: String,
) -> Result<OpenedWorkspace, RemoteClientError> {
    let (response, mut ownership) = lease
        .into_request(RemoteRequest::OpenWorkspace { path })
        .await?;
    let opened = match response {
        RemoteResponse::WorkspaceOpened(opened) => opened,
        response => {
            return Err(RemoteClientError::protocol(format!(
                "expected an opened workspace, received {}",
                response_kind(&response)
            )));
        }
    };
    // The persistent share and the temporary part come from the same reservation: the open peak is
    // held until the helper really finished opening, then only the root's share stays charged.
    let retained_fds = client.inner.fds.limits().costs.workspace_retained;
    let share = ownership.take_fds().and_then(|fds| {
        let (share, rest) = fds.into_workspace_root(retained_fds);
        drop(rest);
        share
    });
    let Some(permit) = share else {
        // The helper has already created the root, so an uncharged handle must be closed on this same
        // connection instead of being left behind without local accounting.
        let id = opened.workspace_id;
        close_workspace(client, id.clone());
        return Err(RemoteClientError::protocol(format!(
            "openWorkspace for '{id}' kept no persistent descriptor share"
        )));
    };
    let Some(retained) = client.inner.charge_workspace(&opened.workspace_id, permit) else {
        // The connection ended while this root was being opened: its connection-end cleanup reclaims the
        // handle, so no local charge is registered and the caller learns the open did not complete.
        return Err(RemoteClientError::Disconnected);
    };
    tracing::trace!(
        connection = client.instance(),
        workspace = %opened.workspace_id,
        permits = retained.permits(),
        "opened remote workspace root"
    );
    Ok(OpenedWorkspace {
        id: opened.workspace_id.clone(),
        path: opened.canonical_path,
        retained,
        claim: UnclaimedRoot {
            client,
            id: opened.workspace_id,
            armed: true,
        },
    })
}

/// Releases one physical workspace handle on its own connection.
///
/// The handle is registered as an outstanding responsibility *before* the request is attempted and
/// stays registered until the helper confirmed the release or the whole connection ended. A failed
/// release retires that physical connection explicitly, so the helper reclaims what the local table
/// can no longer mirror.
pub(in crate::remote) fn close_workspace(client: RemoteClient, workspace_id: String) {
    if client.is_disconnected() {
        // The driver is already terminal: the helper can no longer answer, and its connection-end
        // cleanup owns every handle. The physical connection itself stays owned by the endpoint
        // registry until its cleanup is confirmed.
        tracing::debug!(
            connection = client.instance(),
            "workspace handle released with the ended connection"
        );
        return;
    }
    client.inner.begin_workspace_close(&workspace_id);
    let Ok(runtime) = tokio::runtime::Handle::try_current() else {
        // No runtime can deliver the release. The responsibility stays registered (so the
        // connection is never treated as idle) and the first failure reason records why.
        client.inner.retain_reason(format!(
            "workspace release for {workspace_id} has no runtime to run on"
        ));
        return;
    };
    let tasks = client.inner.tasks.clone();
    let released = tasks.track_future(async move {
        match client
            .request(RemoteRequest::CloseWorkspace {
                workspace_id: workspace_id.clone(),
            })
            .await
        {
            Ok(_) => client.inner.finish_workspace_close(&workspace_id),
            Err(error) if error.is_disconnect() => {
                // The physical connection is ending: `observe_closed` hands the handle to the
                // helper's connection-end cleanup and only then drops this responsibility. A
                // connection that is merely closing is not treated as reaped here.
                tracing::debug!(
                    connection = client.instance(),
                    %error,
                    "workspace release interrupted by the ending connection"
                );
            }
            Err(error) => {
                // The local registry can no longer mirror the helper's handles: retire this
                // physical connection and let the helper reclaim everything it still owns.
                client
                    .inner
                    .retain_reason(format!("closeWorkspace for {workspace_id} failed: {error}"));
                client
                    .inner
                    .request_abort(format!("workspace release failed: {error}"));
            }
        }
    });
    runtime.spawn(released);
}
