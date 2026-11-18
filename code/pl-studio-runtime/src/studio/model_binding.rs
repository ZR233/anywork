//! Model selection, context validation and construction for Native resource installation.
use anyhow::{Context, Result};
use pl_core::{
    context::ContextContent,
    model::ModelFactory,
    thread::{RuntimeModel, ThreadSnapshot},
};
use pl_model::{config::ResolvedModelRoute, runtime::ThreadModel};
use std::sync::Arc;

pub(crate) fn resolve_saved(
    snapshot: &ThreadSnapshot,
    config: &crate::StudioConfig,
) -> Result<ResolvedModelRoute> {
    if let Some((profile, _)) = super::model_route::saved_profile(snapshot)? {
        return Ok(super::delegation::resolve_child_route(config, &profile)?);
    }
    let selector = super::model_route::saved(snapshot)?
        .context("Thread has no frozen model route")?
        .route;
    let route = config
        .models
        .resolve_route(crate::config::root_agent_route_id(), &selector)?;
    super::delegation::validate_credential(&route)?;
    Ok(route)
}

pub(crate) fn validate_media(
    state: &ThreadSnapshot,
    model: &pl_model::model::ModelInfo,
    additional: &[ContextContent],
) -> Result<()> {
    let history = state
        .context
        .records
        .iter()
        .flat_map(|record| &record.content);
    let pending = state
        .inputs
        .iter()
        .filter(|record| record.state == pl_core::thread::input::InputState::Pending)
        .flat_map(|record| &record.input.context);
    pl_model::runtime::validate_attachment_content(history.chain(pending).chain(additional), model)
        .map_err(|error| {
            crate::PureError::ConfigError(format!(
                "所选模型无法读取当前会话的附件，请选择支持这些附件的模型：{error}"
            ))
            .into()
        })
}

pub(crate) fn validate_context(
    snapshot: &ThreadSnapshot,
    route: &ResolvedModelRoute,
) -> Result<ThreadModel> {
    validate_media(snapshot, &route.model, &[])?;
    let model = ThreadModel::new(
        pl_model::runtime::from_route(route)?,
        route.reasoning_config(),
    );
    model.validate_context_origin(&snapshot.context)?;
    Ok(model)
}

pub(crate) fn deferred_update(
    route: &ResolvedModelRoute,
    config: &crate::StudioConfig,
    modes: crate::mode::ThreadModeManager,
) -> Result<RuntimeModel> {
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
    configured_model(route, config, modes, hosted)
}

pub(crate) fn configured_model(
    route: &ResolvedModelRoute,
    config: &crate::StudioConfig,
    modes: crate::mode::ThreadModeManager,
    hosted: Vec<pl_model::runtime::HostedTool>,
) -> Result<RuntimeModel> {
    // The key has the existing model-binding identity domain. It never enters model context/logs.
    let key = crate::hash::canonical_json_hash(&serde_json::json!({
        "account": route.account_id, "endpoint": route.endpoint, "model": route.model.model_id,
        "effort": route.effort, "pricing": route.pricing_mode, "contextPolicy": route.context,
        "modelDefinition": route.model, "compaction": config.runtime.openai_compaction_mode,
        "hosted": hosted.iter().map(|tool| match tool {
            pl_model::runtime::HostedTool::WebSearch(options) => crate::ToolSpec::WebSearch { options: options.clone() },
            pl_model::runtime::HostedTool::ProgrammaticToolCalling => crate::ToolSpec::ProgrammaticToolCalling,
        }).collect::<Vec<_>>(),
    }));
    let model = ThreadModel::new(
        pl_model::runtime::from_route(route)?,
        route.reasoning_config(),
    )
    .with_hosted_tools(hosted);
    Ok(RuntimeModel::new(
        key,
        ModelFactory::new(model.clone()),
        crate::compaction::preparer(
            route,
            model,
            config.runtime.openai_compaction_mode,
            modes,
            &config.models,
        )?,
    ))
}

/// Prepares matching provider and tools from one settings/catalog cut.
pub(crate) struct NativeModelConfiguration {
    pub route: ResolvedModelRoute,
    pub model: RuntimeModel,
    pub config: crate::StudioConfig,
    revision: (u64, u64),
}

pub(crate) struct NativeBundleOwner<'a> {
    pub id: &'a str,
    pub session: &'a crate::session::SessionRuntime,
    pub factory: &'a super::StudioThreadFactory,
    pub config: &'a crate::config::ConfigRuntime,
    pub thread: &'a pl_core::thread::ThreadHandle,
    pub snapshot: &'a ThreadSnapshot,
}

impl NativeModelConfiguration {
    pub fn resolve(
        config_owner: &crate::config::ConfigRuntime,
        snapshot: &ThreadSnapshot,
    ) -> Result<Self> {
        let (settings, catalog) = config_owner.read_with_catalog()?;
        let route = resolve_saved(snapshot, &settings.config)?;
        validate_context(snapshot, &route)?;
        let model = deferred_update(&route, &settings.config, config_owner.thread_mode_manager())?;
        Ok(Self {
            route,
            model,
            config: settings.config,
            revision: (settings.revision, catalog.revision),
        })
    }

    pub fn desired(&self) -> String {
        format!(
            "{}:{}:{}",
            self.revision.0,
            self.revision.1,
            self.model.identity()
        )
    }

    pub async fn prepare_bundle(
        self,
        owner: NativeBundleOwner<'_>,
        cancellation: tokio_util::sync::CancellationToken,
        desired: Arc<str>,
        is_current: impl Fn() -> bool + Send + Sync + 'static,
    ) -> Result<pl_core::thread::RuntimeBundle> {
        use pl_core::thread::{RuntimeBinding, RuntimeBundle, RuntimeTools};

        let NativeBundleOwner {
            id,
            session,
            factory,
            config: config_owner,
            thread,
            snapshot,
        } = owner;
        // Freeze exposure and resolve every fallible control input before physical allocation.
        let profiles = config_owner.agent_profiles_snapshot()?;
        let child = snapshot
            .extensions
            .contains_key(super::model_route::AGENT_PROFILE_EXTENSION);
        let controls = if child {
            Vec::new()
        } else {
            let selection = super::delegation::saved(snapshot)?
                .context("Thread has no frozen delegation selection")?;
            session.agent_control_tools_for_thread(id, thread, &profiles, selection)?
        };
        let (tools, _, binding) = factory
            .refresh_thread_tools(
                id,
                snapshot,
                &self.config,
                &self.route,
                cancellation.clone(),
            )
            .await?;
        let facts = super::StudioThreadFactory::bundle_facts(&binding, snapshot);
        let registrations = tools
            .into_registrations()
            .into_iter()
            .chain(controls)
            .map(|registration| registration.guard_authorization(&binding.authorization))
            .collect();
        let config_owner = config_owner.clone();
        let revision = self.revision;
        let profile_revision = profiles.revision;
        let apply_model = snapshot.runtime_bundle.model_identity.as_deref()
            != Some(self.model.identity())
            || !snapshot.model_available;
        Ok(RuntimeBundle {
            base: thread.runtime_bundle_base(snapshot),
            desired,
            model: apply_model.then_some(self.model),
            model_context_revision: apply_model.then_some(snapshot.context.revision),
            tools: Some(RuntimeTools {
                registrations,
                binding: RuntimeBinding::new(binding),
                facts,
            }),
            application: None,
            is_current: Arc::new(move || {
                !cancellation.is_cancelled()
                    && config_owner
                        .native_runtime_revision()
                        .is_ok_and(|current| current == revision)
                    && (child
                        || config_owner
                            .agent_profiles_snapshot()
                            .is_ok_and(|current| current.revision == profile_revision))
                    && is_current()
            }),
        })
    }
}
