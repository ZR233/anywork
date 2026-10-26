//! Context consumes the same Config/Mode baseline registered by the original projection owner.
//! This is policy projection only: no second receiver, observer task, account cache or resolver.
use anyhow::Result;
use pl_protocol::studio::ConfigProjectionStamp;
use pl_protocol::thread_facets::context::CurrentContextPolicy;

pub(in crate::studio::runtime) fn current_policy(
    config: &crate::StudioConfig,
    route: Option<&pl_protocol::ThreadModelRouteSnapshot>,
    sources: ConfigProjectionStamp,
    mode_revision: u64,
) -> Result<Option<CurrentContextPolicy>> {
    let Some(route) = route.filter(|route| route.available) else {
        return Ok(None);
    };
    let account_id = pl_model::config::AccountId::new(route.account_id.clone())?;
    let Some(account) = config.models.accounts.get(&account_id) else {
        return Ok(None);
    };
    // effective_catalog owns account overrides and the model layer's final context resolution.
    // Do not rederive safety limits here, and do not fill the frozen usage from this current policy.
    let Some(entry) = account
        .effective_catalog(None)?
        .into_iter()
        .find(|entry| entry.model.model_id == route.model_id && entry.enabled)
    else {
        return Ok(None);
    };
    Ok(Some(CurrentContextPolicy {
        sources,
        mode_revision,
        route_revision: route.revision,
        context_window: entry.context.context_window,
        max_context_window: entry.model.max_context_window,
        input_token_limit: entry.context.input_token_limit,
        auto_compact_limit: entry.context.auto_compact_limit,
        unavailable: entry.context.unavailable,
        adjustment: entry.context.adjustment,
    }))
}
