use std::collections::HashMap;
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use lsp_server::{Message, Notification, Request, RequestId, Response};
use serde_json::{Value, json};
use tokio::sync::{mpsc, oneshot};

use crate::runtime::{LspResult, LspRuntimeError};

use super::transport::{OutboundMessage, TransportSender};

type PendingResponseSender = oneshot::Sender<LspResult<Value>>;
type PendingRequests = Arc<Mutex<HashMap<RequestId, PendingResponseSender>>>;

struct PendingRequest<'a> {
    id: RequestId,
    pending: &'a PendingRequests,
    cancellation: mpsc::PermitIterator<'a, OutboundMessage>,
}

impl Drop for PendingRequest<'_> {
    fn drop(&mut self) {
        let pending = self
            .pending
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .remove(&self.id);
        if pending.is_some() {
            // A reserved slot makes cancellation synchronous even when the write queue is
            // full. The request was queued first; no detached cleanup task is needed.
            if let Some(permit) = self.cancellation.next() {
                permit.send(OutboundMessage::Message(
                    Notification::new("$/cancelRequest".into(), json!({ "id": self.id })).into(),
                ));
            }
        }
    }
}

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
        let result = tokio::time::timeout(timeout, async {
            // Reserve request and cancellation capacity together, avoiding deadlock between
            // concurrent requests that would each otherwise hold half their required slots.
            let mut permits =
                self.outbound.outbound.reserve_many(2).await.map_err(|_| {
                    LspRuntimeError::Unavailable("LSP writer channel closed".into())
                })?;
            let Some(request_permit) = permits.next() else {
                return Err(LspRuntimeError::Unavailable(
                    "LSP request slot unavailable".into(),
                ));
            };
            let (sender, receiver) = oneshot::channel();
            self.pending
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .insert(id.clone(), sender);
            let _pending = PendingRequest {
                id: id.clone(),
                pending: &self.pending,
                cancellation: permits,
            };
            request_permit.send(OutboundMessage::Message(
                Request::new(id.clone(), method.to_string(), params).into(),
            ));
            receiver.await.map_err(|_| {
                LspRuntimeError::Unavailable(format!("LSP request channel closed for {method}"))
            })?
        })
        .await;
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
        if let Some(sender) = self
            .pending
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .remove(&response.id)
        {
            let _ = sender.send(result);
        }
    }

    pub(crate) async fn fail_pending(&self, message: impl Into<String>) {
        let message = message.into();
        for (_, sender) in self
            .pending
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .drain()
        {
            let _ = sender.send(Err(LspRuntimeError::Unavailable(message.clone())));
        }
    }

    async fn send(&self, message: Message) -> LspResult<()> {
        tokio::time::timeout(Duration::from_secs(30), self.outbound.send(message))
            .await
            .map_err(|_| LspRuntimeError::Timeout("LSP notification write".into()))?
    }
}
