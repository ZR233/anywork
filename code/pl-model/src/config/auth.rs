//! Native OpenAI/ChatGPT 账号认证方式与脱敏注册元数据。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AccountAuthenticationMethod {
    #[default]
    ApiKey,
    ChatGpt,
}
