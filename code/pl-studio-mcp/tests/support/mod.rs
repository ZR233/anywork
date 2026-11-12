use std::{
    collections::BTreeSet,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use pl_studio_mcp::{
    HostCatalog, HostError, HostInvocation, HostOperation, HostResult, HostTool, HostTools,
};
use serde_json::{Value, json};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

pub const TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Default)]
pub struct State {
    pub calls: AtomicUsize,
    pub active: AtomicUsize,
    pub started: Notify,
    pub ended: Notify,
    pub wait_token: Mutex<Option<CancellationToken>>,
    pub echoes: Mutex<BTreeSet<u64>>,
}

#[derive(Clone, Default)]
pub struct Backend(pub Arc<State>);

struct Active(Arc<State>);

impl Drop for Active {
    fn drop(&mut self) {
        self.0.active.fetch_sub(1, Ordering::SeqCst);
        self.0.ended.notify_one();
    }
}

impl HostTools for Backend {
    async fn catalog(&self) -> Result<HostCatalog, HostError> {
        Ok(vec![HostTool {
            operation: HostOperation::WaitAgent,
            description: "fixture host port".into(),
            input_schema: json!({"type":"object"}).as_object().unwrap().clone(),
        }])
    }

    async fn invoke(
        &self,
        request: HostInvocation,
        cancellation: CancellationToken,
    ) -> Result<HostResult, HostError> {
        self.0.calls.fetch_add(1, Ordering::SeqCst);
        self.0.active.fetch_add(1, Ordering::SeqCst);
        let _active = Active(self.0.clone());
        if request.arguments.get("wait") == Some(&json!(true)) {
            *self.0.wait_token.lock().unwrap() = Some(cancellation.clone());
            self.0.started.notify_one();
            cancellation.cancelled().await;
            return Err(HostError::Closed);
        }
        if let Some(size) = request.arguments.get("generate").and_then(Value::as_u64) {
            return Ok(HostResult {
                value: Value::String("x".repeat(size as usize)),
                is_error: false,
            });
        }
        if let Some(id) = request.arguments.get("id").and_then(Value::as_u64) {
            assert!(self.0.echoes.lock().unwrap().insert(id), "replayed call");
            // Yield so streams overlap without artificial business timeouts.
            tokio::task::yield_now().await;
        }
        Ok(HostResult {
            is_error: request.arguments.get("error") == Some(&json!(true)),
            value: Value::Object(request.arguments),
        })
    }
}

pub fn invocation(arguments: Value) -> HostInvocation {
    HostInvocation {
        operation: HostOperation::WaitAgent,
        arguments: arguments.as_object().unwrap().clone(),
    }
}
