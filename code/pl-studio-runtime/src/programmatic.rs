//! Product selection of the model-owned hosted coordinator.
use pl_model::{config::ResolvedModelRoute, protocol::WireApi, runtime::HostedTool};
pub(crate) fn hosted_tool(route: &ResolvedModelRoute) -> Option<HostedTool> {
    let supported = route.model.binding.transport.protocol == WireApi::Responses
        && route
            .model
            .capabilities
            .supports_programmatic_tool_calling()
        && route
            .model
            .binding
            .request
            .supports_programmatic_tool_calling()
        && route
            .endpoint
            .service_capabilities
            .responses_tools
            .programmatic_tool_calling;
    supported.then_some(HostedTool::ProgrammaticToolCalling)
}

#[cfg(test)]
mod tests {
    #[test]
    fn chatgpt_canonical_capabilities_prevent_automatic_programmatic_selection() {
        use pl_model::config::{AccountId, ModelRouteConfig, ReasoningEffort};
        use pl_protocol::studio::{AccountAuthenticationMethod, ChatGptAccountInfo};
        let mut config = crate::StudioConfig::default_config().unwrap();
        let mut account = pl_model::config::builtin_account_catalog()
            .unwrap()
            .templates
            .into_iter()
            .find(|t| t.id.as_str() == "openai")
            .unwrap()
            .account;
        account.bearer_token = None;
        account.bearer_token_env = None;
        let id = AccountId::new("siwc-capability").unwrap();
        let selector = ModelRouteConfig {
            account_id: id.clone(),
            model_id: "gpt-5.5".into(),
            effort: Some(ReasoningEffort::new("low")),
        };
        config.models.accounts.insert(id.clone(), account.clone());
        let api = config
            .models
            .resolve_route(crate::config::root_agent_route_id(), &selector)
            .unwrap();
        assert!(super::hosted_tool(&api).is_some());
        account.authentication = AccountAuthenticationMethod::ChatGpt;
        account.chatgpt_account = Some(ChatGptAccountInfo {
            issuer: "https://auth.openai.com".into(),
            subject: "synthetic".into(),
            client_id: "synthetic-issued".into(),
            email: None,
            plan_usage_enabled: true,
        });
        config.models.accounts.insert(id, account);
        let siwc = config
            .models
            .resolve_route(crate::config::root_agent_route_id(), &selector)
            .unwrap();
        assert!(
            !siwc
                .endpoint
                .service_capabilities
                .responses_tools
                .programmatic_tool_calling
        );
        assert!(super::hosted_tool(&siwc).is_none());
        assert!(!siwc.endpoint.service_capabilities.remote_compaction);
    }
}
