//! Read one bot chat, preserving typed unsupported-media observations.
use crate::support::{BotSessionHost, ReadMessages};
use pl_agent_tool::typed::TypedTool;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
#[derive(Debug, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Args {
    pub bot_id: String,
    pub chat_id: String,
    #[serde(default)]
    pub start_time: Option<i64>,
    #[serde(default)]
    pub end_time: Option<i64>,
    #[serde(default)]
    pub cursor: Option<String>,
    #[serde(default)]
    pub limit: Option<u32>,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Output<M> {
    pub bot_id: String,
    pub chat_id: String,
    pub messages: Vec<M>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}
#[derive(Debug)]
pub struct ReadBotMessages<H> {
    host: Arc<H>,
    scope: String,
}
impl<H: BotSessionHost> ReadBotMessages<H> {
    pub fn new(host: Arc<H>, scope: String) -> Self {
        Self { host, scope }
    }
}
impl<H: BotSessionHost> TypedTool for ReadBotMessages<H> {
    const NAME: &'static str = NAME;
    const DESCRIPTION: &'static str = DESCRIPTION;
    type Args = Args;
    type Context = ();
    type Output = Output<H::Message>;
    type Error = H::Error;
    async fn execute(&self, input: Args, _: ()) -> Result<Self::Output, H::Error> {
        let page = self
            .host
            .read_messages(
                &self.scope,
                ReadMessages {
                    bot_id: input.bot_id.clone(),
                    chat_id: input.chat_id.clone(),
                    start_time: input.start_time,
                    end_time: input.end_time,
                    cursor: input.cursor,
                    limit: input.limit,
                },
            )
            .await?;
        Ok(Output {
            bot_id: input.bot_id,
            chat_id: input.chat_id,
            messages: page.items,
            next_cursor: page.next_cursor,
        })
    }
}

pub const NAME: &str = "read_bot_messages";
pub const DESCRIPTION: &str = "Read typed bot messages for one chat. Unsupported media is reported explicitly and is not treated as an attachment.";
pub fn declaration() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        NAME,
        DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<Args>(),
    )
    .expect("static bot definition")
}
