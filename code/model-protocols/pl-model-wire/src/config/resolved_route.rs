use super::{AccountId, AccountModelKey, AgentRoleId, ReasoningEffort};
use crate::{model::ModelInfo, protocol::ProtocolEndpoint};
/// 完成引用校验后可直接创建模型 account 的角色路由。
#[derive(Debug, Clone)]
pub struct ResolvedModelRoute {
    pub pricing_mode: crate::model::PricingMode,
    pub role: AgentRoleId,
    pub account_id: AccountId,
    pub endpoint: ProtocolEndpoint,
    pub model: ModelInfo,
    pub context: crate::model::ModelContextResolution,
    pub effort: Option<ReasoningEffort>,
}

impl ResolvedModelRoute {
    /// 返回该已解析路由的稳定目录身份。
    pub fn key(&self) -> AccountModelKey {
        AccountModelKey {
            account_id: self.account_id.as_str().to_owned(),
            model_id: self.model.model_id.clone(),
        }
    }

    /// Interprets this route's reasoning choice once for model request preparation.
    pub fn reasoning_config(&self) -> Option<crate::completion::ReasoningConfig> {
        self.effort
            .as_ref()
            .map(|effort| crate::completion::ReasoningConfig {
                effort: Some(effort.as_str().to_owned()),
                summary: Some(if effort.is_none() {
                    crate::completion::ReasoningSummary::Disabled
                } else {
                    crate::completion::ReasoningSummary::Enabled
                }),
            })
    }
}
