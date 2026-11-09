//! Send a text message with the host-frozen idempotency identity.
use crate::support::{BotSessionHost, SendStatus};
use pl_agent_tool::typed::TypedTool;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
#[derive(Debug, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Args {
    pub bot_id: String,
    pub chat_id: String,
    pub text: String,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Output<S, R> {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub status: SendStatus,
    pub segments: Vec<S>,
    pub receipt: R,
}
#[derive(Debug)]
pub struct SendBotMessage<H> {
    host: Arc<H>,
    scope: String,
}
impl<H: BotSessionHost> SendBotMessage<H> {
    pub fn new(host: Arc<H>, scope: String) -> Self {
        Self { host, scope }
    }
}
impl<H: BotSessionHost> TypedTool for SendBotMessage<H> {
    const NAME: &'static str = NAME;
    const DESCRIPTION: &'static str = DESCRIPTION;
    type Args = Args;
    type Context = String;
    type Output = Output<H::Segment, H::Receipt>;
    type Error = H::Error;
    async fn execute(&self, input: Args, operation_id: String) -> Result<Self::Output, H::Error> {
        let result = self
            .host
            .send_message(
                &self.scope,
                operation_id.clone(),
                input.bot_id.clone(),
                input.chat_id.clone(),
                input.text,
            )
            .await?;
        Ok(Output {
            operation_id,
            bot_id: input.bot_id,
            chat_id: input.chat_id,
            status: result.status,
            segments: result.segments,
            receipt: result.receipt,
        })
    }
}

pub const NAME: &str = "send_bot_message";
pub const DESCRIPTION: &str = "Send a text message through a project-authorized bot. This is an external write and is not a readonly or programmatic tool.";
pub fn declaration() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        NAME,
        DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<Args>(),
    )
    .expect("static bot definition")
}
