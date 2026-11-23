use super::{AccountId, AccountModelKey, AgentRoleId, ReasoningEffort};
use crate::{model::ModelDefinition, protocol::ProtocolEndpoint};
/// 完成引用校验后可直接创建模型 account 的角色路由。
#[derive(Debug, Clone)]
pub struct ResolvedModelRoute {
    pub pricing_mode: crate::model::PricingMode,
    pub role: AgentRoleId,
    pub account_id: AccountId,
    pub endpoint: ProtocolEndpoint,
    pub model: ModelDefinition,
    pub context: crate::model::ModelContextResolution,
    pub effort: Option<ReasoningEffort>,
    pub service_tier: Option<String>,
}

impl ResolvedModelRoute {
    /// Freezes an explicit catalog service tier. `None` leaves the choice to the endpoint.
    ///
    /// # Errors
    /// Rejects an ID outside this model's catalog or an invalid wire assignment.
    pub fn with_service_tier(mut self, requested: Option<&str>) -> pl_protocol::Result<Self> {
        crate::service_tiers::validate(&self.model, requested)?;
        self.service_tier = requested.map(str::to_owned);
        Ok(self)
    }

    /// 返回该已解析路由的稳定目录身份。
    pub fn key(&self) -> AccountModelKey {
        AccountModelKey {
            account_id: self.account_id.as_str().to_owned(),
            model_id: self.model.base.slug.clone(),
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
