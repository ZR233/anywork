use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::Duration;

use lsp_server::{Message, Notification, Request, RequestId, Response};
use serde_json::Value;
use tokio::sync::{Mutex, oneshot};

use crate::runtime::{LspResult, LspRuntimeError};

use super::transport::TransportSender;

type PendingResponseSender = oneshot::Sender<LspResult<Value>>;
type PendingRequests = Arc<Mutex<HashMap<RequestId, PendingResponseSender>>>;

#[derive(Clone)]
pub(crate) struct RpcClient {
    outbound: TransportSender,
    pending: PendingRequests,
    next_id: Arc<AtomicI32>,
}

impl RpcClient {
    pub(crate) fn new(outbound: TransportSender) -> Self {
        Self {
            outbound,
            pending: Arc::new(Mutex::new(HashMap::new())),
            next_id: Arc::new(AtomicI32::new(1)),
        }
    }

    pub(crate) async fn request(
        &self,
        method: &str,
        params: Value,
        timeout: Duration,
    ) -> LspResult<Value> {
        let id = RequestId::from(self.next_id.fetch_add(1, Ordering::Relaxed));
        let (sender, receiver) = oneshot::channel();
        self.pending.lock().await.insert(id.clone(), sender);
        let result = tokio::time::timeout(timeout, async {
            self.outbound
                .send(Request::new(id.clone(), method.to_string(), params).into())
                .await?;
            receiver.await.map_err(|_| {
                LspRuntimeError::Unavailable(format!("LSP request channel closed for {method}"))
            })?
        })
        .await;
        self.pending.lock().await.remove(&id);
        result.unwrap_or_else(|_| Err(LspRuntimeError::Timeout(method.to_string())))
    }

    pub(crate) async fn notify(&self, method: &str, params: Value) -> LspResult<()> {
        self.send(Notification::new(method.to_string(), params).into())
            .await
    }

    pub(crate) async fn respond(&self, response: Response) -> LspResult<()> {
        self.send(response.into()).await
    }

    pub(crate) async fn complete(&self, response: Response) {
        let result = response
            .response_result
            .map_err(|error| LspRuntimeError::Server {
                code: i64::from(error.code),
                message: error.message,
            });
        if let Some(sender) = self.pending.lock().await.remove(&response.id) {
            let _ = sender.send(result);
        }
    }

    pub(crate) async fn fail_pending(&self, message: impl Into<String>) {
        let message = message.into();
        for (_, sender) in self.pending.lock().await.drain() {
            let _ = sender.send(Err(LspRuntimeError::Unavailable(message.clone())));
        }
    }

    async fn send(&self, message: Message) -> LspResult<()> {
        tokio::time::timeout(Duration::from_secs(30), self.outbound.send(message))
            .await
            .map_err(|_| LspRuntimeError::Timeout("LSP notification write".into()))?
    }
}
