use pl_core::{
    context::{ContextContent, OpaquePayload},
    model::{
        ModelError, ModelRequest, ModelSession, ModelStepOutput, ModelToolCall, PreparedModelCall,
    },
    thread::{ModelStepLimit, TurnInput},
};
use std::{
    collections::VecDeque,
    sync::{Arc, Mutex},
};

pub struct Calls {
    pub calls: VecDeque<(String, String)>,
    pub requests: Arc<Mutex<Vec<ModelRequest>>>,
}

impl ModelSession for Calls {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.requests.lock().unwrap().push(request.clone());
        let calls = self
            .calls
            .pop_front()
            .map(|(tool_id, raw)| ModelToolCall {
                call_id: request.attempt_id.clone(),
                tool_id,
                arguments: OpaquePayload::new("application/json", 1, raw).unwrap(),
                rejection: None,
                presentation_contract: None,
            })
            .into_iter()
            .collect();
        Ok(PreparedModelCall::new(async move {
            Ok(ModelStepOutput {
                turn_action: Default::default(),
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: Vec::new(),
                tool_calls: calls,
                private_context: None,
                usage: Default::default(),
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

pub fn turn(id: &str) -> TurnInput {
    TurnInput {
        turn_id: id.into(),
        attempt_prefix: format!("attempt-{id}"),
        content: vec![ContextContent::Text {
            text: "Run the registered tool".into(),
        }],
        max_model_steps: ModelStepLimit::Limited(4.try_into().unwrap()),
        cancellation: tokio_util::sync::CancellationToken::new(),
    }
}
