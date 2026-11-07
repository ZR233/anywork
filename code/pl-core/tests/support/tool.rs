use std::sync::{Arc, Mutex};

use pl_core::context::OpaquePayload;
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, ToolError},
};

#[derive(Debug)]
struct RecordingTool {
    log: Arc<Mutex<Vec<String>>>,
}

impl pl_agent_tool::Tool for RecordingTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text(
                    "RecordingTool",
                    "Text tool for core runtime tests",
                )
                .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.log.lock().expect("tool log").push(context.call_id);
        Ok(ToolOutput::new(
            input.clone(),
            vec![crate::support::text(input.content())],
        ))
    }
}

pub fn tool(id: &str, log: &Arc<Mutex<Vec<String>>>) -> Registration {
    Registration::prepare(id.into(), OpaquePayload::text(format!("Tool {id}")))
        .expect("valid tool identity")
        .attach(pl_core::tool::opaque::RuntimeTool::new(RecordingTool {
            log: log.clone(),
        }))
        .foreground_coexisting()
}
