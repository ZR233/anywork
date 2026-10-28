//! Studio Settings 命令层：把各类设置更新请求写入配置 runtime 并发布 canonical snapshot。

use anyhow::{Context, Result, bail};
use pl_protocol::ThreadModeId;
use pl_protocol::studio::{
    CommandEffectPoint, CreateAccountRequest, RemoveAccountModelRequest, RemoveAccountRequest,
    SetAccountBillingKindRequest, SetAccountModelEnabledRequest, SetDefaultAccountRequest,
    SetThreadModelRouteRequest, SettingsCommandReply, SettingsFieldUpdate, SettingsStateResponse,
    ThreadModelRouteCommandReply, UpdatePermissionSettingsRequest, UpdateSettingsFieldRequest,
};

use crate::PermissionMode;
use crate::account_usage::account_usage_query_kind;
use crate::config::{AccountId, ModelRouteConfig, ReasoningEffort};
use crate::first_run::AccountTemplateKind;

use super::StudioRuntime;

mod account_edit;
mod account_patch;
mod acp;
mod acp_install;
mod view;

use account_edit::invalid_settings_argument;
pub(crate) use view::{
    account_settings, model_catalog_snapshot, settings_config_snapshot, settings_state_response,
};
use view::{normalized_optional, normalized_string_list};

impl StudioRuntime {
    pub(super) fn read_settings_response(&self) -> Result<SettingsStateResponse> {
        // 同一 Settings command 边界内取得配置与 ACP 投影：不会看到"提交已生效但身份未对齐"的中间态。
        // 外层是命令边界错误，内层是投影错误；两层都保留为命令错误，不丢弃任何一层。
        self.config_runtime
            .with_consistent_snapshot(|state, catalog| {
                let acp_accounts = self
                    .acp_auth
                    .settings_view(state.revision, state.canonical_config())?;
                settings_state_response(state, catalog, acp_accounts)
            })
            .map_err(anyhow::Error::from)
            .flatten()
    }

    /// `SettingsConfig` topic 的单域 canonical 快照：与命令回执使用同一投影与同一序列化边界。
    pub(super) fn read_settings_config_state(
        &self,
    ) -> Result<crate::StudioSettingsConfigStateSnapshot> {
        let projected = self
            .config_runtime
            .with_consistent_snapshot(|state, _catalog| {
                let acp_accounts = self
                    .acp_auth
                    .settings_view(state.revision, state.canonical_config())?;
                settings_config_snapshot(state, acp_accounts)
            })?;
        let config = projected?;
        Ok(crate::StudioSettingsConfigStateSnapshot {
            state: pl_protocol::ObservedResource::ready(config.revision, config.updated_at, config),
        })
    }

    /// Reads the canonical built-in account and model catalog.
    pub fn load_account_catalog(&self) -> Result<pl_protocol::AccountCatalogSnapshot> {
        let mut snapshot = pl_model::config::builtin_account_catalog()?.snapshot()?;
        for template in &mut snapshot.templates {
            template.supports_usage_query = Some(
                account_usage_query_kind(AccountTemplateKind::from_key(&template.id)?).is_some(),
            );
        }
        // Keep the PL base revision in the hash input: it also covers transport profiles
        // that are not represented by the catalog DTO itself.
        let value = serde_json::to_value(&snapshot)?;
        snapshot.revision = crate::hash::canonical_json_hash(&value);
        Ok(snapshot)
    }

    /// Reads the secret-free canonical Settings snapshot from the in-memory owner.
    pub fn read_settings(&self) -> Result<SettingsStateResponse> {
        self.read_settings_response()
    }

    /// Applies one typed settings field/resource mutation.
    ///
    /// The closure starts from the runtime's canonical desired configuration,
    /// so a command never carries an old sibling field back into the store.
    /// Route model and effort updates deliberately have separate variants; the
    /// unchanged half is resolved from the current canonical route.
    pub async fn apply_settings_field(
        &self,
        request: UpdateSettingsFieldRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let mark_skills_stale = matches!(
            &request.update,
            SettingsFieldUpdate::SkillsEnabled { .. }
                | SettingsFieldUpdate::SkillsAutoLearn { .. }
                | SettingsFieldUpdate::SkillsSystemEnabled { .. }
                | SettingsFieldUpdate::SkillsProjectDir { .. }
                | SettingsFieldUpdate::SkillsUserDir { .. }
                | SettingsFieldUpdate::SkillsExternalDirs { .. }
                | SettingsFieldUpdate::SkillsDisabled { .. }
                | SettingsFieldUpdate::SkillsAutoLearnMinToolCalls { .. }
        );
        let effect = match &request.update {
            SettingsFieldUpdate::GeneralFollowActiveTurn { .. }
            | SettingsFieldUpdate::GeneralCompactTimeline { .. }
            | SettingsFieldUpdate::GeneralSidebarWidth { .. }
            | SettingsFieldUpdate::GeneralPinnedThreadIds { .. }
            | SettingsFieldUpdate::GeneralPinnedProjectIds { .. } => CommandEffectPoint::Immediate,
            _ => CommandEffectPoint::FutureSession,
        };
        let mut changed = false;
        let update = request.update;
        let state = self.config_runtime.update_with_effective(
            request.expected_revision,
            |desired, effective| {
                let mut config = desired.clone();
                let route_validation_config = if matches!(
                    &update,
                    SettingsFieldUpdate::ModeModel { .. }
                        | SettingsFieldUpdate::ModeReasoningEffort { .. }
                        | SettingsFieldUpdate::RoleModel { .. }
                        | SettingsFieldUpdate::RoleReasoningEffort { .. }
                ) {
                    effective
                } else {
                    &config
                };
                match update {
                    SettingsFieldUpdate::DelegationMode { value } => {
                        config.delegation.mode = value;
                    }
                    SettingsFieldUpdate::DelegationPreference { value } => {
                        config.delegation.preference = value;
                    }
                    SettingsFieldUpdate::InstructionBaseOverride { value } => {
                        config.instructions.base_override = value;
                    }
                    SettingsFieldUpdate::InstructionDeveloper { value } => {
                        config.instructions.developer = value;
                    }
                    SettingsFieldUpdate::InstructionUser { value } => {
                        config.instructions.user = value;
                    }
                    SettingsFieldUpdate::ProjectDocMaxBytes { value } => {
                        config.instructions.project_doc_max_bytes = usize::try_from(value)
                            .map_err(|_| {
                                pl_protocol::PureError::ConfigError(
                                    "projectDocMaxBytes exceeds this platform".to_string(),
                                )
                            })?;
                    }
                    SettingsFieldUpdate::ProjectDocFallbackFilenames { value } => {
                        config.instructions.project_doc_fallback_filenames =
                            normalized_string_list(value);
                    }
                    SettingsFieldUpdate::SkillsEnabled { value } => config.skills.enabled = value,
                    SettingsFieldUpdate::SkillsAutoLearn { value } => {
                        config.skills.auto_learn = value;
                    }
                    SettingsFieldUpdate::SkillsSystemEnabled { value } => {
                        config.skills.system.enabled = value;
                    }
                    SettingsFieldUpdate::SkillsProjectDir { value } => {
                        config.skills.project_dir = value
                    }
                    SettingsFieldUpdate::SkillsUserDir { value } => config.skills.user_dir = value,
                    SettingsFieldUpdate::SkillsExternalDirs { value } => {
                        config.skills.external_dirs = normalized_string_list(value);
                    }
                    SettingsFieldUpdate::SkillsDisabled { value } => {
                        config.skills.disabled = normalized_string_list(value);
                    }
                    SettingsFieldUpdate::SkillsAutoLearnMinToolCalls { value } => {
                        config.skills.auto_learn_min_tool_calls = value;
                    }
                    SettingsFieldUpdate::McpServerEnabled { id, value } => {
                        apply_mcp_server_enabled(&mut config, &id, value)?;
                    }
                    SettingsFieldUpdate::McpServerTransport { id, transport } => {
                        apply_mcp_server_transport(&mut config, &id, &transport)?;
                    }
                    SettingsFieldUpdate::McpServerEndpoint { id, endpoint } => {
                        apply_mcp_server_endpoint(&mut config, &id, &endpoint)?;
                    }
                    SettingsFieldUpdate::GeneralFollowActiveTurn { value } => {
                        config.ui.follow_active_turn = value;
                    }
                    SettingsFieldUpdate::GeneralCompactTimeline { value } => {
                        config.ui.compact_timeline = value;
                    }
                    SettingsFieldUpdate::GeneralSidebarWidth { value } => {
                        if !value.is_none_or(|width| (300..=440).contains(&width)) {
                            return Err(pl_protocol::PureError::ConfigError(
                                "sidebar width must be between 300 and 440".to_string(),
                            ));
                        }
                        config.ui.sidebar_width = value;
                    }
                    SettingsFieldUpdate::GeneralPinnedThreadIds { value } => {
                        if value.len() > 64 {
                            return Err(pl_protocol::PureError::ConfigError(
                                "at most 64 pinned sessions are supported".to_string(),
                            ));
                        }
                        config.ui.pinned_thread_ids = normalized_string_list(value);
                    }
                    SettingsFieldUpdate::GeneralPinnedProjectIds { value } => {
                        if value.len() > 64 {
                            return Err(pl_protocol::PureError::ConfigError(
                                "at most 64 pinned projects are supported".to_string(),
                            ));
                        }
                        config.ui.pinned_project_ids = normalized_string_list(value);
                    }
                    SettingsFieldUpdate::WebSearchMode { value } => {
                        config.web_search.mode = parse_web_search_mode(&value)?;
                    }
                    SettingsFieldUpdate::WebSearchContextSize { value } => {
                        config.web_search.context_size =
                            parse_web_search_context_size(value.as_deref())?;
                    }
                    SettingsFieldUpdate::WebSearchAllowedDomains { value } => {
                        config.web_search.allowed_domains = normalized_string_list(value);
                    }
                    SettingsFieldUpdate::WebSearchCountry { value } => {
                        update_web_search_location(&mut config, |location| {
                            location.country = normalized_optional(value);
                        });
                    }
                    SettingsFieldUpdate::WebSearchRegion { value } => {
                        update_web_search_location(&mut config, |location| {
                            location.region = normalized_optional(value);
                        });
                    }
                    SettingsFieldUpdate::WebSearchCity { value } => {
                        update_web_search_location(&mut config, |location| {
                            location.city = normalized_optional(value);
                        });
                    }
                    SettingsFieldUpdate::WebSearchTimezone { value } => {
                        update_web_search_location(&mut config, |location| {
                            location.timezone = normalized_optional(value);
                        });
                    }
                    SettingsFieldUpdate::DeepSeekWebSearchEnabled { value } => {
                        config.deepseek_web_search.enabled = value;
                    }
                    SettingsFieldUpdate::DeepSeekWebFetchEnabled { value } => {
                        config.deepseek_web_search.fetch_enabled = value;
                    }
                    SettingsFieldUpdate::ModeModel {
                        mode_id,
                        account_id,
                        model_id,
                    } => {
                        let mode =
                            ThreadModeId::new(mode_id.trim().to_string()).map_err(|error| {
                                pl_protocol::PureError::ConfigError(error.to_string())
                            })?;
                        let effort = config
                            .mode_model_routes
                            .get(&mode)
                            .filter(|route| {
                                route.account_id.as_str() == account_id.trim()
                                    && route.model_id == model_id.trim()
                            })
                            .and_then(|route| route.effort.as_ref().map(|value| value.as_str()));
                        let route = validated_route(
                            route_validation_config,
                            &format!("Thread Mode {mode}"),
                            &account_id,
                            &model_id,
                            effort,
                        )
                        .map_err(|error| pl_protocol::PureError::ConfigError(error.to_string()))?;
                        config.mode_model_routes.insert(mode, route);
                    }
                    SettingsFieldUpdate::ModeReasoningEffort { mode_id, effort } => {
                        let mode =
                            ThreadModeId::new(mode_id.trim().to_string()).map_err(|error| {
                                pl_protocol::PureError::ConfigError(error.to_string())
                            })?;
                        let current =
                            config
                                .mode_model_routes
                                .get(&mode)
                                .cloned()
                                .ok_or_else(|| {
                                    pl_protocol::PureError::ConfigError(format!(
                                        "Thread Mode {mode} has no model route"
                                    ))
                                })?;
                        let route = validated_route(
                            route_validation_config,
                            &format!("Thread Mode {mode}"),
                            current.account_id.as_str(),
                            &current.model_id,
                            effort.as_deref(),
                        )
                        .map_err(|error| pl_protocol::PureError::ConfigError(error.to_string()))?;
                        config.mode_model_routes.insert(mode, route);
                    }
                    SettingsFieldUpdate::RoleModel {
                        role,
                        account_id,
                        model_id,
                    } => {
                        let role_key = role.trim();
                        if role_key == crate::config::ROOT_AGENT_ROUTE_KEY {
                            return Err(pl_protocol::PureError::ConfigError(
                                "planner is a root identity, not a configurable child model role"
                                    .to_string(),
                            ));
                        }
                        let role_id = crate::AgentRoleId::new(role_key.to_string())?;
                        let current =
                            crate::config::effective_system_profile_route(&config, role_key)?;
                        let effort = (current.account_id.as_str() == account_id.trim()
                            && current.model_id == model_id.trim())
                        .then(|| current.effort.as_ref().map(|value| value.as_str()))
                        .flatten();
                        let route = validated_route(
                            route_validation_config,
                            &format!("role {role_key}"),
                            &account_id,
                            &model_id,
                            effort,
                        )
                        .map_err(|error| pl_protocol::PureError::ConfigError(error.to_string()))?;
                        config.models.routes.insert(role_id, route);
                    }
                    SettingsFieldUpdate::RoleReasoningEffort { role, effort } => {
                        let role_key = role.trim();
                        if role_key == crate::config::ROOT_AGENT_ROUTE_KEY {
                            return Err(pl_protocol::PureError::ConfigError(
                                "planner is a root identity, not a configurable child model role"
                                    .to_string(),
                            ));
                        }
                        let role_id = crate::AgentRoleId::new(role_key.to_string())?;
                        let current =
                            crate::config::effective_system_profile_route(&config, role_key)?;
                        let route = validated_route(
                            route_validation_config,
                            &format!("role {role_key}"),
                            current.account_id.as_str(),
                            &current.model_id,
                            effort.as_deref(),
                        )
                        .map_err(|error| pl_protocol::PureError::ConfigError(error.to_string()))?;
                        config.models.routes.insert(role_id, route);
                    }
                }
                config.validate_declarations()?;
                changed = desired != &config;
                Ok(config)
            },
        )?;
        self.publish_settings_state()?;
        if mark_skills_stale {
            self.skills.mark_all_stale().await;
        }
        self.settings_command_reply(request.operation_id, &state, changed, effect)
    }

    pub fn save_permission_settings(
        &self,
        request: UpdatePermissionSettingsRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let mode = PermissionMode::from_label(&request.mode)
            .ok_or_else(|| invalid_settings_argument("Unsupported permission mode"))?;
        let mut changed = false;
        let state = self
            .config_runtime
            .update(request.expected_revision, |config| {
                let mut config = config.clone();
                changed = config.runtime.permission_mode != mode;
                config.runtime.permission_mode = mode;
                Ok(config)
            })?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            request.operation_id,
            &state,
            changed,
            CommandEffectPoint::FutureSession,
        )
    }

    pub async fn reload_settings(&self, expected_revision: u64) -> Result<SettingsStateResponse> {
        self.config_runtime.reload_from_disk(expected_revision)?;
        self.publish_settings_state()?;
        self.skills.mark_all_stale().await;
        self.read_settings_response()
    }

    pub async fn create_account(
        &self,
        request: CreateAccountRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let state = self.config_runtime.update_with_effective(
            request.expected_revision,
            |desired, effective| {
                let id = AccountId::new(request.account.account_id.trim())?;
                if desired.models.accounts.contains_key(&id) {
                    return Err(pl_protocol::PureError::ConfigError(
                        "account already exists; use a field patch".into(),
                    ));
                }
                let account = account_edit::account_edit(request.account, effective)
                    .map_err(|error| pl_protocol::PureError::ConfigError(error.to_string()))?;
                account.to_single_config(effective)
            },
        )?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            request.operation_id,
            &state,
            true,
            CommandEffectPoint::FutureSession,
        )
    }

    /// Applies only the target model's enablement intent against the latest account.
    pub fn set_account_model_enabled(
        &self,
        request: SetAccountModelEnabledRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let account_id = AccountId::new(request.account_id.clone())?;
        let mut changed = false;
        let state = self.config_runtime.update_with_effective(
            request.expected_revision,
            |desired, effective| {
                let mut next = desired.clone();
                // The effective account validates online membership. The config owner removes
                // its non-persistent overlay before saving, without promoting discovered models.
                let mut account = effective
                    .models
                    .accounts
                    .get(&account_id)
                    .cloned()
                    .ok_or_else(|| {
                        pl_protocol::PureError::ConfigError(format!(
                            "unknown account: {account_id}"
                        ))
                    })?;
                account.set_model_enabled(&request.model_id, request.enabled)?;
                changed = desired.models.accounts.get(&account_id).is_some_and(|old| {
                    old.model_enabled_overrides() != account.model_enabled_overrides()
                });
                next.models.accounts.insert(account_id.clone(), account);
                Ok(next)
            },
        )?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            request.operation_id,
            &state,
            changed,
            CommandEffectPoint::FutureSession,
        )
    }

    /// `None` clears the override; explicit `Unknown` remains a distinct persisted intent.
    pub fn set_account_billing_kind(
        &self,
        request: SetAccountBillingKindRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let account_id = AccountId::new(request.account_id.clone())?;
        let mut changed = false;
        let state = self
            .config_runtime
            .update(request.expected_revision, |desired| {
                let mut next = desired.clone();
                let account = next.models.accounts.get_mut(&account_id).ok_or_else(|| {
                    pl_protocol::PureError::ConfigError(format!("unknown account: {account_id}"))
                })?;
                let value = request.billing_kind.value();
                changed = account.billing_kind != value;
                account.billing_kind = value;
                Ok(next)
            })?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            request.operation_id,
            &state,
            changed,
            CommandEffectPoint::FutureSession,
        )
    }

    pub fn set_default_account(
        &self,
        request: SetDefaultAccountRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let current = self.config_runtime.read()?;
        let account_id = AccountId::new(request.account_id.trim())?;
        let account = current
            .config
            .models
            .accounts
            .get(&account_id)
            .ok_or_else(|| invalid_settings_argument("Default account does not exist"))?;
        let models = account
            .selectable_catalog(Some(pl_model::model::ModelType::Text))?
            .into_iter()
            .map(|entry| entry.model)
            .collect::<Vec<_>>();
        let current_route = current
            .config
            .mode_model_routes
            .get(&ThreadModeId::simple())
            .filter(|route| route.account_id == account_id);
        let model = current_route
            .and_then(|route| models.iter().find(|model| model.model_id == route.model_id))
            .or_else(|| {
                current
                    .config
                    .models
                    .routes
                    .values()
                    .find(|route| route.account_id == account_id)
                    .and_then(|route| models.iter().find(|model| model.model_id == route.model_id))
            })
            .or_else(|| models.first())
            .ok_or_else(|| invalid_settings_argument("Default account has no usable models"))?;
        let effort = current_route
            .and_then(|route| (route.model_id == model.model_id).then_some(route.effort.as_ref()))
            .flatten()
            .map(|effort| effort.as_str().to_string())
            .or_else(|| model.default_effort());
        let route = validated_route(
            &current.config,
            "Default account",
            account_id.as_str(),
            &model.model_id,
            effort.as_deref(),
        )?;
        let mut next = current.config.clone();
        next.mode_model_routes.insert(ThreadModeId::simple(), route);
        let state = self
            .config_runtime
            .replace(request.expected_revision, next)?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            request.operation_id,
            &state,
            current.canonical_config() != state.canonical_config(),
            CommandEffectPoint::FutureSession,
        )
    }

    pub fn remove_account_model(
        &self,
        request: RemoveAccountModelRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let account_id = AccountId::new(request.account_id.trim())?;
        let model_id = request.model_id.trim();
        if model_id.is_empty() {
            return Err(invalid_settings_argument(
                "Model model_id must not be empty",
            ));
        }
        let mut changed = false;
        let state = self.config_runtime.update_with_effective(
            request.expected_revision,
            |desired, _effective| {
                let mut next = desired.clone();
                let account = next.models.accounts.get_mut(&account_id).ok_or_else(|| {
                    pl_protocol::PureError::ConfigError(format!(
                        "account does not exist: {account_id}"
                    ))
                })?;
                account.remove_manual_model(model_id)?;
                next.validate_declarations()?;
                changed = desired != &next;
                Ok(next)
            },
        )?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            request.operation_id,
            &state,
            changed,
            CommandEffectPoint::FutureSession,
        )
    }

    pub async fn remove_account(
        &self,
        request: RemoveAccountRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let current = self.config_runtime.read()?;
        let next = crate::config_editor::remove_account(
            &current.config,
            &request.account_id,
            request.replacement_account_id.as_deref(),
        )?;
        let state = self
            .config_runtime
            .replace(request.expected_revision, next)?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            request.operation_id,
            &state,
            current.canonical_config() != state.canonical_config(),
            CommandEffectPoint::FutureSession,
        )
    }

    pub async fn save_thread_model_route(
        &self,
        thread_id: &str,
        request: SetThreadModelRouteRequest,
    ) -> Result<ThreadModelRouteCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let _guard = self.lifecycle_lock.lock().await;
        let record = self.read_owned_thread(thread_id).await?;
        anyhow::ensure!(
            self.bots.config_for_thread(thread_id).await?.is_none(),
            "该会话的模型由机器人统一管理，请打开机器人设置修改"
        );
        anyhow::ensure!(
            record.parent_thread_id.is_none(),
            "child Thread model routes are frozen by their Agent Profile"
        );
        let thread = self.ensure_thread_owner(thread_id).await?;
        let state = thread.snapshot();
        let settings = self.config_runtime.read()?;
        if settings.revision != request.expected_settings_revision {
            return Err(crate::ConfigRuntimeError::StaleRevision {
                expected: request.expected_settings_revision,
                actual: settings.revision,
            }
            .into());
        }
        let route_extension_id = crate::studio::model_route::MODEL_ROUTE_EXTENSION;
        let previous = state
            .extensions
            .get(route_extension_id)
            .context("Thread has no saved model route")?;
        if previous.revision != request.expected_model_route_revision {
            return Err(crate::ConfigRuntimeError::StaleRevision {
                expected: request.expected_model_route_revision,
                actual: previous.revision,
            }
            .into());
        }
        let mode = crate::studio::thread_projection::saved_mode(&state)?
            .unwrap_or_else(|| record.mode.clone());
        crate::mode::saved_registered_mode(&state)?
            .or_else(|| self.thread_modes.snapshot().mode(&mode))
            .context("current Thread Mode is unavailable")?;
        let selector = validated_route(
            &settings.config,
            &format!("Thread {thread_id}"),
            &request.account_id,
            &request.model_id,
            request.effort.as_deref(),
        )?;
        let route = settings
            .config
            .models
            .resolve_route(crate::config::root_agent_route_id(), &selector)?;

        Self::validate_model_media(&state, &route.model, &[])?;
        pl_model::runtime::ThreadModel::new(
            pl_model::runtime::ModelRuntime::from_route(&route)?,
            route.reasoning_config(),
        )
        .validate_context_origin(&state.context)?;
        let committed = match thread
            .queue_deferred_model_update_if_current(
                self.deferred_model_update(&route, &settings.config)?,
                pl_core::thread::DeferredModelUpdatePrecondition::commit_sequence(
                    state.commit_sequence,
                ),
                vec![pl_core::thread::extensions::ExtensionMutation::Put {
                    id: route_extension_id.into(),
                    expected_revision: Some(request.expected_model_route_revision),
                    payload: crate::studio::model_route::encode(&selector)?,
                }],
            )
            .await
        {
            Ok(committed) => committed,
            Err(pl_core::thread::ThreadError::ExtensionConflict {
                id,
                expected: Some(expected),
                actual: Some(actual),
            }) if id == route_extension_id => {
                return Err(crate::ConfigRuntimeError::StaleRevision { expected, actual }.into());
            }
            Err(error) => return Err(error.into()),
        };
        let route_changed = previous.payload
            != committed
                .extensions
                .get(route_extension_id)
                .context("committed route missing")?
                .payload;
        let route_revision = committed
            .extensions
            .get(route_extension_id)
            .context("committed route missing")?
            .revision;
        self.tool_catalog_updates.notify_one();

        let mut confirmed_settings = settings.clone();
        let mut default_changed = false;
        let mut mode_default_saved = false;
        let mut warning = None;
        for _ in 0..3 {
            let latest = self.config_runtime.read()?;
            let mut config = latest.canonical_config().clone();
            let candidate = match validated_route(
                &latest.config,
                &format!("Thread Mode {mode}"),
                &request.account_id,
                &request.model_id,
                request.effort.as_deref(),
            ) {
                Ok(candidate) => candidate,
                Err(error) => {
                    warning = Some(format!(
                        "current Thread was updated, but its Mode default was not saved: {error}"
                    ));
                    break;
                }
            };
            config.mode_model_routes.insert(mode.clone(), candidate);
            match self.config_runtime.replace(latest.revision, config) {
                Ok(updated) => {
                    default_changed = latest.canonical_config() != updated.canonical_config();
                    confirmed_settings = updated.clone();
                    if let Err(error) = self.publish_settings_state() {
                        warning = Some(format!(
                            "current Thread and Mode default were saved, but the Settings event was not published: {error}"
                        ));
                    }
                    mode_default_saved = true;
                    break;
                }
                Err(crate::ConfigRuntimeError::StaleRevision { .. }) => continue,
                Err(error) => {
                    warning = Some(format!(
                        "current Thread was updated, but its Mode default was not saved: {error}"
                    ));
                    break;
                }
            }
        }
        if !mode_default_saved && warning.is_none() {
            warning = Some(
                "current Thread was updated, but its Mode default conflicted repeatedly".into(),
            );
        }
        let snapshot = self.thread_snapshot(thread_id).await?;
        let runtime = snapshot
            .runtime
            .context("Thread runtime snapshot is unavailable")?;
        let mut targets =
            vec![self.resource_stamp(format!("thread-route:{thread_id}"), route_revision)];
        if mode_default_saved {
            targets.push(self.resource_stamp("settings", confirmed_settings.revision));
        }
        Ok(ThreadModelRouteCommandReply {
            runtime,
            receipt: self.command_receipt(
                request.operation_id,
                route_changed || default_changed,
                targets,
                CommandEffectPoint::NextTurn,
                false,
            ),
            settings: self.read_settings_response()?,
            mode_default_saved,
            warning,
        })
    }
}

fn parse_web_search_mode(value: &str) -> pl_protocol::Result<pl_protocol::search::WebSearchMode> {
    match value.trim() {
        "disabled" => Ok(pl_protocol::search::WebSearchMode::Disabled),
        "cached" => Ok(pl_protocol::search::WebSearchMode::Cached),
        "indexed" => Ok(pl_protocol::search::WebSearchMode::Indexed),
        "live" => Ok(pl_protocol::search::WebSearchMode::Live),
        _ => Err(pl_protocol::PureError::ConfigError(
            "Unsupported web search mode".to_string(),
        )),
    }
}

fn parse_web_search_context_size(
    value: Option<&str>,
) -> pl_protocol::Result<Option<pl_protocol::WebSearchContextSize>> {
    match value.map(str::trim).filter(|value| !value.is_empty()) {
        None => Ok(None),
        Some("low") => Ok(Some(pl_protocol::WebSearchContextSize::Low)),
        Some("medium") => Ok(Some(pl_protocol::WebSearchContextSize::Medium)),
        Some("high") => Ok(Some(pl_protocol::WebSearchContextSize::High)),
        Some(_) => Err(pl_protocol::PureError::ConfigError(
            "Unsupported web search context size".to_string(),
        )),
    }
}

fn update_web_search_location(
    config: &mut crate::StudioConfig,
    update: impl FnOnce(&mut pl_protocol::search::WebSearchLocation),
) {
    let location = config
        .web_search
        .location
        .get_or_insert_with(Default::default);
    update(location);
    if location.is_empty() {
        config.web_search.location = None;
    }
}

fn mcp_server_id(id: &str) -> Option<String> {
    let id = id.trim().to_string();
    if id.is_empty() { None } else { Some(id) }
}

fn apply_mcp_server_enabled(
    config: &mut crate::StudioConfig,
    id: &str,
    enabled: bool,
) -> pl_protocol::Result<()> {
    let Some(id) = mcp_server_id(id) else {
        return Ok(());
    };
    if crate::config::mcp::is_builtin_mcp_server_id(&id) {
        config.mcp.builtin_servers.entry(id).or_default().enabled = enabled;
        return Ok(());
    }
    config.mcp.servers.entry(id).or_default().enabled = enabled;
    Ok(())
}

fn apply_mcp_server_transport(
    config: &mut crate::StudioConfig,
    id: &str,
    transport: &str,
) -> pl_protocol::Result<()> {
    let Some(id) = mcp_server_id(id) else {
        return Ok(());
    };
    if crate::config::mcp::is_builtin_mcp_server_id(&id) {
        return Ok(());
    }
    let transport = match transport.trim() {
        "stdio" => pl_tool::mcp::config::McpServerTransport::Stdio,
        "streamableHttp" => pl_tool::mcp::config::McpServerTransport::StreamableHttp,
        _ => {
            return Err(pl_protocol::PureError::ConfigError(
                "Unsupported MCP transport".to_string(),
            ));
        }
    };
    let server = config.mcp.servers.entry(id).or_default();
    let endpoint = match server.transport {
        pl_tool::mcp::config::McpServerTransport::Stdio => server.command.take(),
        pl_tool::mcp::config::McpServerTransport::StreamableHttp => server.url.take(),
    };
    server.transport = transport;
    match transport {
        pl_tool::mcp::config::McpServerTransport::Stdio => {
            server.command = endpoint;
            server.url = None;
        }
        pl_tool::mcp::config::McpServerTransport::StreamableHttp => {
            server.url = endpoint;
            server.command = None;
        }
    }
    Ok(())
}

fn apply_mcp_server_endpoint(
    config: &mut crate::StudioConfig,
    id: &str,
    endpoint: &str,
) -> pl_protocol::Result<()> {
    let Some(id) = mcp_server_id(id) else {
        return Ok(());
    };
    if crate::config::mcp::is_builtin_mcp_server_id(&id) {
        return Ok(());
    }
    let server = config.mcp.servers.entry(id).or_default();
    let endpoint = endpoint.trim();
    match server.transport {
        pl_tool::mcp::config::McpServerTransport::Stdio => {
            server.command = (!endpoint.is_empty()).then(|| endpoint.to_string());
            server.url = None;
        }
        pl_tool::mcp::config::McpServerTransport::StreamableHttp => {
            server.url = (!endpoint.is_empty()).then(|| endpoint.to_string());
            server.command = None;
        }
    }
    Ok(())
}

pub(super) fn validated_route(
    config: &crate::StudioConfig,
    subject: &str,
    account_id: &str,
    model_id: &str,
    effort: Option<&str>,
) -> Result<ModelRouteConfig> {
    let account_id = account_id.trim();
    let model_id = model_id.trim();
    let account_key = AccountId::new(account_id)?;
    let account = config
        .models
        .accounts
        .get(&account_key)
        .with_context(|| format!("{subject} references missing account: {account_id}"))?;
    let models = account.effective_models(None)?;
    let model = models
        .iter()
        .find(|model| model.model_id == model_id)
        .with_context(|| format!("{subject} references missing model: {account_id}.{model_id}"))?;
    let resolved_effort = match effort.map(str::trim).filter(|value| !value.is_empty()) {
        Some(value) => {
            if !model
                .supported_efforts()
                .iter()
                .any(|candidate| candidate == value)
            {
                bail!(
                    "{subject} uses unsupported effort '{value}' for model {account_id}.{model_id}"
                );
            }
            Some(value.to_string())
        }
        None => model.default_effort(),
    };
    Ok(ModelRouteConfig {
        account_id: account_key,
        model_id: model_id.to_string(),
        effort: resolved_effort.map(ReasoningEffort::new),
    })
}
