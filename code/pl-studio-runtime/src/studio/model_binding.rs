//! One deferred model binding construction for UI/API and parent-agent continuation.
use anyhow::Result;
use pl_core::{model::ModelFactory, thread::DeferredModelUpdate};
use pl_model::{
    config::ResolvedModelRoute,
    runtime::{ModelRuntime, ThreadModel},
};

pub(crate) fn deferred_update(
    route: &ResolvedModelRoute,
    config: &crate::StudioConfig,
    modes: crate::mode::ThreadModeManager,
) -> Result<DeferredModelUpdate> {
    let search = pl_tool::search::plan_web_searches(
        &config.models,
        route,
        &config.web_search,
        &pl_tool::search::WebSearchDeepSeekOptions {
            enabled: config.deepseek_web_search.enabled,
            fetch_enabled: config.deepseek_web_search.fetch_enabled,
        },
    )?;
    let mut hosted = search.hosted_tools(&config.web_search)?;
    hosted.extend(crate::programmatic::hosted_tool(route));
    // The key has the existing model-binding identity domain. It never enters model context/logs.
    let key = crate::hash::canonical_json_hash(&serde_json::json!({
        "account": route.account_id, "endpoint": route.endpoint, "model": route.model.model_id,
        "effort": route.effort, "pricing": route.pricing_mode, "contextPolicy": route.context,
        "modelDefinition": route.model, "compaction": config.runtime.openai_compaction_mode,
        "hosted": hosted.iter().map(|tool| match tool {
            pl_model::runtime::HostedTool::WebSearch(options) => pl_protocol::ToolSpec::WebSearch { options: options.clone() },
            pl_model::runtime::HostedTool::ProgrammaticToolCalling => pl_protocol::ToolSpec::ProgrammaticToolCalling,
        }).collect::<Vec<_>>(),
    }));
    let model = ThreadModel::new(ModelRuntime::from_route(route)?, route.reasoning_config())
        .with_hosted_tools(hosted);
    Ok(DeferredModelUpdate::new(
        key,
        ModelFactory::new(model.clone()),
        crate::compaction::preparer(route, model, config.runtime.openai_compaction_mode, modes)?,
    ))
}
