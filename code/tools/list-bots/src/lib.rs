//! List the host-authorized bot facts without credentials or configuration.
use pl_agent_tool::typed::TypedTool;
use pl_tool_bot_support::BotSessionHost;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
#[derive(Debug, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Args {}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BotSummary<C> {
    pub id: String,
    pub name: String,
    pub connection: C,
    pub tools_enabled: bool,
}
#[derive(Debug)]
pub struct ListBots<H> {
    host: Arc<H>,
    scope: String,
}
impl<H: BotSessionHost> ListBots<H> {
    pub fn new(host: Arc<H>, scope: String) -> Self {
        Self { host, scope }
    }
}
impl<H: BotSessionHost> TypedTool for ListBots<H> {
    const NAME: &'static str = NAME;
    const DESCRIPTION: &'static str = DESCRIPTION;
    type Args = Args;
    type Context = ();
    type Output = Vec<BotSummary<H::Connection>>;
    type Error = H::Error;
    async fn execute(&self, _: Args, _: ()) -> Result<Self::Output, H::Error> {
        Ok(self
            .host
            .list_bots(&self.scope)
            .await?
            .into_iter()
            .map(|bot| BotSummary {
                id: bot.id,
                name: bot.name,
                connection: bot.connection,
                tools_enabled: bot.tools_enabled,
            })
            .collect())
    }
}

pub const NAME: &str = "list_bots";
pub const DESCRIPTION: &str = "List bots authorized for the current project. Returns ids, names, connection state and capabilities without credentials.";
pub fn declaration() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        NAME,
        DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<Args>(),
    )
    .expect("static bot definition")
}
