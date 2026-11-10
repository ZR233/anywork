use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use pl_protocol::{
    AgentBinding, AgentDefinitionSnapshot, AgentProfile, AgentProfileSnapshot, AgentWorkspaceMode,
};
use serde::{Deserialize, Serialize};

use crate::{PureError, Result};

use super::{AccountId, AgentRoleId, ConfigPaths, ModelRouteConfig, ReasoningEffort, StudioConfig};

/// 单个用户 Agent TOML 的 canonical 格式。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserAgentProfile {
    #[serde(default = "default_true")]
    pub enabled: bool,
    pub display_name: String,
    pub description: String,
    pub when_to_use: String,
    pub binding: AgentBinding,
    #[serde(default)]
    pub workspace_mode: AgentWorkspaceMode,
}

/// 单文件诊断只排除对应 Profile，不阻断其余系统或用户 Profile。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentProfileDiagnostic {
    pub path: PathBuf,
    pub message: String,
}

/// 一次已发布扫描的 Profile 配置与诊断；派发视图还需排除禁用和不可执行项。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AgentProfileCatalog {
    pub profiles: Vec<AgentProfile>,
    pub diagnostics: Vec<AgentProfileDiagnostic>,
    unavailable_profiles: BTreeSet<String>,
    directory_error: Option<String>,
}

impl AgentProfileCatalog {
    /// Startup validates every owned profile before publishing a mixed configuration.
    pub(crate) fn validate_for_startup(
        paths: &ConfigPaths,
    ) -> std::result::Result<(), super::ConfigRuntimeError> {
        let entries = match fs::read_dir(paths.agents_dir()) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(error) => return Err(PureError::from(error).into()),
        };
        for entry in entries {
            let path = entry.map_err(PureError::from)?.path();
            if path.extension().and_then(|value| value.to_str()) == Some("toml") {
                let bytes = fs::read(&path).map_err(PureError::from)?;
                let content = std::str::from_utf8(&bytes).map_err(|error| {
                    super::ConfigRuntimeError::Migration(crate::toml_schema::migration_error(
                        &path,
                        "agent-profile",
                        None,
                        3,
                        "UTF-8",
                        error,
                    ))
                })?;
                let document = super::document_migration::load_current_profile(&path, content)
                    .map_err(super::ConfigRuntimeError::Migration)?;
                let profile = document.into_profile().map_err(|error| {
                    super::ConfigRuntimeError::Migration(crate::toml_schema::migration_error(
                        &path,
                        "agent-profile",
                        Some(3),
                        3,
                        "validate",
                        error,
                    ))
                })?;
                let fields = (|| {
                    let profile_id =
                        path.file_stem()
                            .and_then(|name| name.to_str())
                            .ok_or_else(|| {
                                PureError::ConfigError("Agent Profile filename is not UTF-8".into())
                            })?;
                    validate_user_agent_profile_id(profile_id)?;
                    validate_user_profile_fields(profile_id, &profile)
                })();
                fields.map_err(|error| {
                    super::ConfigRuntimeError::Migration(crate::toml_schema::migration_error(
                        &path,
                        "agent-profile",
                        Some(3),
                        3,
                        "validate",
                        error,
                    ))
                })?;
            }
        }
        Ok(())
    }

    /// 只保留启用 Profile 的执行视图；诊断保持原样。
    pub fn enabled_only(mut self) -> Self {
        self.profiles.retain(|profile| profile.enabled);
        self
    }

    /// Enabled role declarations for host admission; model qualification is checked separately.
    pub(crate) fn enabled_for_dispatch(&self) -> Result<Self> {
        if let Some(error) = &self.directory_error {
            return Err(PureError::ConfigError(error.clone()));
        }
        Ok(self.clone().enabled_only())
    }

    /// Derives the model-visible view from this scan, never a newer configuration read.
    /// Automatic mode needs enabled roles, not the availability of their fixed model routes.
    pub(crate) fn executable(&self, mode: pl_protocol::DelegationMode) -> Result<Self> {
        let mut catalog = self.enabled_for_dispatch()?;
        // Automatic selection may replace a Native route, not turn an unsupported backend into
        // Native. ACP configurations remain visible in Settings but are never dispatch entries.
        catalog
            .profiles
            .retain(|profile| matches!(profile.binding, AgentBinding::Native(_)));
        if mode == pl_protocol::DelegationMode::Profile {
            catalog.profiles.retain(|profile| {
                !self
                    .unavailable_profiles
                    .contains(&profile.definition.definition_id)
            });
        }
        Ok(catalog)
    }

    fn push_profile(
        &mut self,
        profile: AgentProfile,
        config: &StudioConfig,
        acp_definitions: &super::AcpDefinitionsSnapshot,
    ) {
        let availability = match &profile.binding {
            AgentBinding::Acp(acp) => acp_definitions
                .definitions
                .get(&acp.account_id)
                .ok_or_else(|| {
                    PureError::ConfigError(format!("unknown ACP account `{}`", acp.account_id))
                })
                .and_then(|entry| {
                    if entry.definition.enabled {
                        Ok(())
                    } else {
                        Err(PureError::ConfigError("ACP definition is disabled".into()))
                    }
                })
                .and_then(|_| {
                    crate::studio::delegation::resolve_current_child_route(config, &profile)
                        .map(|_| ())
                }),
            AgentBinding::Native(_) => {
                crate::studio::delegation::resolve_current_child_route(config, &profile).map(|_| ())
            }
        };
        if let Err(error) = availability {
            self.unavailable_profiles
                .insert(profile.definition.definition_id.clone());
            self.diagnostics.push(AgentProfileDiagnostic {
                path: PathBuf::from(&profile.definition.source),
                message: format!(
                    "Agent Profile `{}` is unavailable: {error}",
                    profile.definition.definition_id
                ),
            });
        }
        self.profiles.push(profile);
    }

    pub fn discover(
        paths: &ConfigPaths,
        config: &StudioConfig,
        acp: &super::AcpDefinitionsSnapshot,
    ) -> Self {
        Self::discover_with_disabled(paths, config, acp, false)
    }

    /// 设置页保留被禁用的系统与用户 Profile；执行目录仍只返回启用项。
    pub fn discover_for_settings(
        paths: &ConfigPaths,
        config: &StudioConfig,
        acp: &super::AcpDefinitionsSnapshot,
    ) -> Self {
        Self::discover_with_disabled(paths, config, acp, true)
    }

    fn discover_with_disabled(
        paths: &ConfigPaths,
        config: &StudioConfig,
        acp: &super::AcpDefinitionsSnapshot,
        include_disabled: bool,
    ) -> Self {
        let mut catalog = system_profiles(config, include_disabled);
        let agents_dir = paths.agents_dir();
        let entries = match fs::read_dir(&agents_dir) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return catalog,
            Err(error) => {
                let message = format!("failed to read Agent Profile directory: {error}");
                catalog.directory_error = Some(message.clone());
                catalog.diagnostics.push(AgentProfileDiagnostic {
                    path: agents_dir,
                    message,
                });
                return catalog;
            }
        };
        let mut paths = Vec::new();
        for entry in entries {
            match entry {
                Ok(entry) => {
                    let path = entry.path();
                    if path.extension().and_then(|value| value.to_str()) == Some("toml") {
                        paths.push(path);
                    }
                }
                Err(error) => {
                    let message = format!("failed to enumerate Agent Profile directory: {error}");
                    catalog.directory_error = Some(message.clone());
                    catalog.diagnostics.push(AgentProfileDiagnostic {
                        path: agents_dir.clone(),
                        message,
                    });
                }
            }
        }
        paths.sort();
        for path in paths {
            match load_user_profile(&path, include_disabled) {
                Ok(Some(profile)) => catalog.push_profile(profile, config, acp),
                Ok(None) => {}
                Err(error) => catalog.diagnostics.push(AgentProfileDiagnostic {
                    path,
                    message: error.to_string(),
                }),
            }
        }
        catalog
    }
}

/// Resolves a current Native Profile against one configuration snapshot.
///
/// # Errors
/// Returns missing account/model bindings or invalid route parameters.
pub fn resolve_profile_route(
    config: &crate::config::StudioConfig,
    profile: &AgentProfile,
) -> Result<pl_model::config::ResolvedModelRoute> {
    let AgentBinding::Native(native) = &profile.binding else {
        return Err(PureError::ConfigError(
            "ACP execution is not supported before S4".into(),
        ));
    };
    let route = native
        .route
        .as_ref()
        .ok_or_else(|| PureError::ConfigError("child Native Profile has no model route".into()))?;
    let role = pl_model::config::AgentRoleId::new(profile.definition.definition_id.clone())?;
    let mut models = config.models.clone();
    models.routes.insert(
        role.clone(),
        pl_model::config::ModelRouteConfig {
            account_id: pl_model::config::AccountId::new(route.account_id.clone())?,
            model_id: route.model_id.clone(),
            effort: route
                .effort
                .as_ref()
                .map(|effort| pl_model::config::ReasoningEffort::new(effort.clone())),
        },
    );
    models.resolve(&role)
}

/// 原子创建或保存单个用户 Agent 文件；系统 Profile ID 永远不可写。
pub fn save_user_agent_profile(
    paths: &ConfigPaths,
    profile_id: &str,
    profile: &UserAgentProfile,
    config: &StudioConfig,
    acp: &super::AcpDefinitionsSnapshot,
) -> Result<bool> {
    validate_user_agent_profile_id(profile_id)?;
    validate_user_profile(profile_id, profile, config, acp)?;
    let content = super::document_migration::ProfileV3::from_current(profile)
        .and_then(|document| document.encode())
        .map_err(|error| {
            PureError::ConfigError(format!(
                "failed to serialize Agent Profile `{profile_id}`: {error}"
            ))
        })?;
    let directory = paths.agents_dir();
    fs::create_dir_all(&directory)?;
    let path = directory.join(format!("{profile_id}.toml"));
    let changed = match fs::read_to_string(&path) {
        Ok(existing) => super::document_migration::load_current_profile(&path, &existing)
            .and_then(|document| document.into_profile())
            .map(|existing| existing != *profile)
            .unwrap_or(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => true,
        Err(error) => return Err(error.into()),
    };
    pl_tool::workspace::write_file_atomically(&path, content.as_bytes())?;
    Ok(changed)
}

pub fn is_system_profile_id(profile_id: &str) -> Result<bool> {
    Ok(system_profile_ids()?.contains(profile_id))
}

fn system_profiles(config: &StudioConfig, include_disabled: bool) -> AgentProfileCatalog {
    let mut catalog = AgentProfileCatalog::default();
    let definitions = match crate::agent::catalog::definitions() {
        Ok(definitions) => definitions,
        Err(error) => {
            let message = format!("bundled Agent catalog is unavailable: {error}");
            catalog.directory_error = Some(message.clone());
            catalog.diagnostics.push(AgentProfileDiagnostic {
                path: PathBuf::from("studio-builtin"),
                message,
            });
            return catalog;
        }
    };
    for definition in definitions
        .iter()
        .filter(|definition| {
            definition.identity.scope == crate::agent::definition::AgentDefinitionScope::Child
        })
        .filter(|definition| {
            include_disabled
                || !config
                    .disabled_system_agents
                    .contains(&definition.identity.id)
        })
    {
        match system_profile(definition, config) {
            Ok(profile) => {
                catalog.push_profile(profile, config, &super::AcpDefinitionsSnapshot::default())
            }
            Err(error) => {
                tracing::warn!(profile_id = %definition.identity.id, %error, "system Agent Profile is unavailable");
                catalog.diagnostics.push(AgentProfileDiagnostic {
                    path: PathBuf::from(format!("studio-builtin:{}", definition.identity.id)),
                    message: format!(
                        "Agent Profile `{}` is unavailable: {error}",
                        definition.identity.id
                    ),
                });
            }
        }
    }
    catalog
}

fn system_profile(
    definition: &crate::agent::catalog::BuiltinAgentDefinition,
    config: &StudioConfig,
) -> Result<AgentProfile> {
    let route = effective_system_profile_route(config, &definition.identity.id)?;
    let agent = crate::agent::definition::ResolvedAgentDefinition::from_builtin(definition);
    let snapshot = AgentProfileSnapshot {
        profile_id: agent.identity().id.clone(),
        display_name: agent.display_name().to_owned(),
        description: agent.description().to_owned(),
        when_to_use: agent.when_to_use().to_owned(),
        system_instructions: agent.instructions().to_owned(),
        account_id: route.account_id.as_str().to_string(),
        model_id: route.model_id.clone(),
        effort: route
            .effort
            .as_ref()
            .map(|effort| effort.as_str().to_string()),
        source: "studio-builtin".to_string(),
        revision: agent.identity().revision.clone(),
        content_hash: String::new(),
        system: true,
        enabled: !config.disabled_system_agents.contains(&agent.identity().id),
        workspace_mode: agent.workspace_mode().ok_or_else(|| {
            PureError::ConfigError(format!(
                "child Agent `{}` has no workspace mode",
                definition.identity.id
            ))
        })?,
    };
    Ok(with_content_hash(snapshot).into())
}

pub(crate) fn system_agent_profile(
    config: &StudioConfig,
    profile_id: &str,
) -> Result<AgentProfile> {
    let definition = crate::agent::catalog::definition(profile_id)?
        .ok_or_else(|| PureError::ConfigError(format!("unknown bundled Agent `{profile_id}`")))?;
    if definition.identity.scope != crate::agent::definition::AgentDefinitionScope::Child {
        return Err(PureError::ConfigError(format!(
            "root Agent `{profile_id}` is not a configurable child Profile"
        )));
    }
    system_profile(definition, config)
}

pub(crate) fn system_agent_profiles(config: &StudioConfig) -> Result<Vec<AgentProfile>> {
    crate::agent::catalog::definitions()?
        .iter()
        .filter(|definition| {
            definition.identity.scope == crate::agent::definition::AgentDefinitionScope::Child
        })
        .map(|definition| system_profile(definition, config))
        .collect()
}

/// Resolves a builtin child selector without persisting an inherited value. An explicit invalid
/// selector remains authoritative; only an absent key inherits the current simple Mode route.
pub(crate) fn effective_system_profile_route(
    config: &StudioConfig,
    profile_id: &str,
) -> Result<ModelRouteConfig> {
    let definition = crate::agent::catalog::definition(profile_id)?
        .ok_or_else(|| PureError::ConfigError(format!("unknown bundled Agent `{profile_id}`")))?;
    if definition.identity.scope != crate::agent::definition::AgentDefinitionScope::Child {
        return Err(PureError::ConfigError(format!(
            "root Agent `{profile_id}` has no child model route"
        )));
    }
    let role = AgentRoleId::new(profile_id.to_owned())?;
    Ok(config.models.routes.get(&role).cloned().unwrap_or(
        config
            .mode_model_route(&pl_protocol::ThreadModeId::simple())?
            .clone(),
    ))
}

fn load_user_profile(path: &Path, include_disabled: bool) -> Result<Option<AgentProfile>> {
    let profile_id = path
        .file_stem()
        .and_then(|value| value.to_str())
        .ok_or_else(|| PureError::ConfigError("Agent Profile filename is not UTF-8".to_string()))?;
    validate_user_agent_profile_id(profile_id)?;
    let content = fs::read_to_string(path)?;
    // Existing, structurally valid files remain editable even if their account/model was removed.
    // The canonical scan records route failures separately when it builds the executable view.
    let profile = parse_profile_content(profile_id, &content)?;
    if !profile.enabled && !include_disabled {
        return Ok(None);
    }
    let revision = pl_core::context::content_hash(
        toml::to_string(&profile)
            .map_err(|error| {
                PureError::ConfigError(format!("failed to serialize Profile revision: {error}"))
            })?
            .as_bytes(),
    );
    let mut current = AgentProfile {
        definition: AgentDefinitionSnapshot {
            definition_id: profile_id.to_string(),
            display_name: profile.display_name,
            description: profile.description,
            when_to_use: profile.when_to_use,
            source: path.to_string_lossy().into_owned(),
            revision,
            content_hash: String::new(),
        },
        binding: profile.binding,
        system: false,
        enabled: profile.enabled,
        workspace_mode: profile.workspace_mode,
    };
    current.definition.content_hash = match &current.binding {
        AgentBinding::Native(_) => with_content_hash(current.freeze_native()?).content_hash,
        AgentBinding::Acp(_) => pl_core::context::content_hash(
            &serde_json::to_vec(&current).expect("Agent Profile must serialize"),
        ),
    };
    Ok(Some(current))
}

fn parse_profile_content(profile_id: &str, content: &str) -> Result<UserAgentProfile> {
    validate_user_agent_profile_id(profile_id)?;
    let profile = super::document_migration::load_current_profile(Path::new(profile_id), content)
        .and_then(|document| document.into_profile())
        .map_err(|_| PureError::ConfigError(format!("invalid Agent Profile TOML: {profile_id}")))?;
    validate_user_profile_fields(profile_id, &profile)?;
    Ok(profile)
}

pub(super) fn validate_user_profile(
    profile_id: &str,
    profile: &UserAgentProfile,
    config: &StudioConfig,
    definitions: &super::AcpDefinitionsSnapshot,
) -> Result<()> {
    validate_user_profile_fields(profile_id, profile)?;
    match &profile.binding {
        AgentBinding::Native(native) => {
            let route = native.route.as_ref().ok_or_else(|| {
                PureError::ConfigError("child Native Profile has no model route".into())
            })?;
            config
                .models
                .resolve_route(
                    AgentRoleId::new(profile_id)?,
                    &ModelRouteConfig {
                        account_id: AccountId::new(route.account_id.clone())?,
                        model_id: route.model_id.clone(),
                        effort: route.effort.clone().map(ReasoningEffort::new),
                    },
                )
                .map(|_| ())
        }
        AgentBinding::Acp(acp) => {
            let entry = definitions
                .definitions
                .get(&acp.account_id)
                .ok_or_else(|| {
                    PureError::ConfigError(format!("unknown ACP account `{}`", acp.account_id))
                })?;
            entry.definition.validate()
        }
    }
}

pub(super) fn validate_user_profile_fields(
    profile_id: &str,
    profile: &UserAgentProfile,
) -> Result<()> {
    validate_user_profile_metadata(profile_id, profile)?;
    match &profile.binding {
        AgentBinding::Native(native) => {
            let route = native.route.as_ref().ok_or_else(|| {
                PureError::ConfigError("child Native Profile has no model route".into())
            })?;
            AccountId::new(route.account_id.clone())?;
            if route.model_id.trim().is_empty()
                || native
                    .system_instructions
                    .as_deref()
                    .is_none_or(|value| value.trim().is_empty())
            {
                return Err(PureError::ConfigError(format!(
                    "Agent Profile `{profile_id}` requires Native model and instructions"
                )));
            }
        }
        AgentBinding::Acp(acp) => super::acp::validate_acp_account_id(&acp.account_id)?,
    }
    Ok(())
}

pub(super) fn validate_user_profile_metadata(
    profile_id: &str,
    profile: &UserAgentProfile,
) -> Result<()> {
    for (field, value) in [
        ("display_name", profile.display_name.as_str()),
        ("description", profile.description.as_str()),
        ("when_to_use", profile.when_to_use.as_str()),
    ] {
        if value.trim().is_empty() {
            return Err(PureError::ConfigError(format!(
                "Agent Profile `{profile_id}` has empty {field}"
            )));
        }
    }
    Ok(())
}

/// 校验 Agent Profile 稳定 ID：1..=64 个小写 ASCII 字母/数字/`-`/`_`。
///
/// 该函数由配置校验与配置迁移共用同一规则；不复制第二套命名约束，也不放宽到其它字符。
pub(super) fn validate_profile_id(profile_id: &str) -> Result<()> {
    let valid = !profile_id.is_empty()
        && profile_id.len() <= 64
        && profile_id.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'-' | b'_')
        });
    if valid {
        Ok(())
    } else {
        Err(PureError::ConfigError(format!(
            "invalid Agent Profile id `{profile_id}`; use 1-64 lowercase ASCII letters, digits, '-' or '_'"
        )))
    }
}

fn with_content_hash(mut snapshot: AgentProfileSnapshot) -> AgentProfileSnapshot {
    let mut hashable = snapshot.clone();
    hashable.content_hash.clear();
    snapshot.content_hash = pl_core::context::content_hash(
        &serde_json::to_vec(&hashable).expect("Agent Profile snapshot must serialize"),
    );
    snapshot
}

const fn default_true() -> bool {
    true
}

/// Returns the child-only view of the validated builtin declaration catalog.
pub fn system_profile_ids() -> Result<BTreeSet<String>> {
    crate::agent::catalog::child_ids()
}

pub(crate) fn validate_user_agent_profile_id(profile_id: &str) -> Result<()> {
    validate_profile_id(profile_id)?;
    if profile_id == super::ROOT_AGENT_ROUTE_KEY
        || crate::agent::definition::is_root_definition_id(profile_id)
        || is_system_profile_id(profile_id)?
    {
        return Err(PureError::ConfigError(format!(
            "Agent Profile id `{profile_id}` is reserved"
        )));
    }
    Ok(())
}
