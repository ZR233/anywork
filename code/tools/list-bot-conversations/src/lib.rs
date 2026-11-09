//! Conversation pagination over the host's authorized bot service.
use pl_agent_tool::typed::TypedTool;
use pl_tool_bot_support::BotSessionHost;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
#[derive(Debug, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Args {
    pub bot_id: String,
    #[serde(default)]
    pub cursor: Option<String>,
    #[serde(default)]
    pub limit: Option<u32>,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Output<C> {
    pub bot_id: String,
    pub conversations: Vec<C>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}
#[derive(Debug)]
pub struct ListBotConversations<H> {
    host: Arc<H>,
    scope: String,
}
impl<H: BotSessionHost> ListBotConversations<H> {
    pub fn new(host: Arc<H>, scope: String) -> Self {
        Self { host, scope }
    }
}
impl<H: BotSessionHost> TypedTool for ListBotConversations<H> {
    const NAME: &'static str = NAME;
    const DESCRIPTION: &'static str = DESCRIPTION;
    type Args = Args;
    type Context = ();
    type Output = Output<H::Conversation>;
    type Error = H::Error;
    async fn execute(&self, input: Args, _: ()) -> Result<Self::Output, H::Error> {
        let page = self
            .host
            .list_conversations(&self.scope, input.bot_id.clone(), input.cursor, input.limit)
            .await?;
        Ok(Output {
            bot_id: input.bot_id,
            conversations: page.items,
            next_cursor: page.next_cursor,
        })
    }
}

pub const NAME: &str = "list_bot_conversations";
pub const DESCRIPTION: &str = "List group chats the bot belongs to and locally observed direct chats. Pagination cursor is bound to the bot.";
pub fn declaration() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        NAME,
        DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<Args>(),
    )
    .expect("static bot definition")
}
