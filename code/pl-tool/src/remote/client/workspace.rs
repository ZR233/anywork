//! Workspace handles are retained by actual users and admitted operations, never by the cache.
use super::*;
use crate::environment::ExecutionEnvironment;
use std::sync::{Mutex as SyncMutex, Weak};

pub(in crate::remote) type WorkspaceCache = SyncMutex<HashMap<(String, String), CachedWorkspace>>;

#[derive(Debug)]
pub(in crate::remote) struct CachedWorkspace {
    pub lease: Weak<WorkspaceLease>,
    pub environment: ExecutionEnvironment,
}

#[derive(Debug)]
pub(in crate::remote) struct WorkspaceLease {
    inner: Weak<RemoteClientInner>,
    pub id: String,
    pub path: String,
    cache: Weak<WorkspaceCache>,
    server: String,
}

impl WorkspaceLease {
    pub(in crate::remote) fn is_connection(&self, client: &RemoteClient) -> bool {
        self.inner.ptr_eq(&Arc::downgrade(&client.inner))
    }
}

impl RemoteClient {
    pub(in crate::remote) async fn open_workspace_lease(
        &self,
        path: String,
        server: String,
        cache: Arc<WorkspaceCache>,
    ) -> Result<Arc<WorkspaceLease>, RemoteClientError> {
        let (mut send, receive) = oneshot::channel();
        let inner = self.inner.clone();
        self.inner.streams.spawn(async move {
            let result = async {
                let submitted = tokio::select! {
                    biased;
                    () = send.closed() => return Err(RemoteClientError::Cancelled),
                    submitted = submit_request(&inner, RemoteRequest::OpenWorkspace { path }, &[]) => submitted?,
                };
                let reply = submitted.await.unwrap_or(Err(RemoteClientError::Disconnected))?;
                let RemoteResponse::WorkspaceOpened(opened) = reply.response else {
                    return Err(RemoteClientError::Protocol(
                        "unexpected workspace open response".into(),
                    ));
                };
                Ok(Arc::new(WorkspaceLease {
                    inner: Arc::downgrade(&inner),
                    id: opened.workspace_id,
                    path: opened.canonical_path,
                    cache: Arc::downgrade(&cache),
                    server,
                }))
            }
            .await;
            // A cancelled opener leaves its lease here, where Drop has complete release ownership.
            let _ = send.send(result);
        });
        receive
            .await
            .unwrap_or(Err(RemoteClientError::Disconnected))
    }
}

impl Drop for WorkspaceLease {
    fn drop(&mut self) {
        if let Some(cache) = self.cache.upgrade() {
            let mut cache = cache
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let key = (self.server.clone(), self.path.clone());
            if cache
                .get(&key)
                .is_some_and(|entry| std::ptr::eq(entry.lease.as_ptr(), self))
            {
                cache.remove(&key);
            }
        }
        if let Some(inner) = self.inner.upgrade() {
            close_workspace(inner, self.id.clone());
        }
    }
}

pub(super) fn close_workspace(inner: Arc<RemoteClientInner>, workspace_id: String) {
    let tasks = inner.streams.clone();
    tasks.spawn(async move {
        if inner.disconnected.is_cancelled() {
            return;
        }
        let result = request_inner(&inner, RemoteRequest::CloseWorkspace { workspace_id }, &[])
            .await
            .and_then(expect_ack);
        if let Err(error) = result {
            // A failed release invalidates this connection; its server owner reclaims every handle.
            retain_disconnect_reason(&inner, format!("close workspace: {error}"));
            inner.disconnected.cancel();
        }
    });
}
