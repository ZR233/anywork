use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use pl_protocol::{AgentProfileSnapshot, AgentWorkspaceMode};
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
    pub system_instructions: String,
    pub account_id: AccountId,
    pub model_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<ReasoningEffort>,
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
    pub profiles: Vec<AgentProfileSnapshot>,
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
                        1,
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
                        Some(1),
                        1,
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
                        Some(1),
                        1,
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
        if mode == pl_protocol::DelegationMode::Profile {
            catalog
                .profiles
                .retain(|profile| !self.unavailable_profiles.contains(&profile.profile_id));
        }
        Ok(catalog)
    }

    fn push_profile(&mut self, profile: AgentProfileSnapshot, config: &StudioConfig) {
        if let Err(error) = crate::studio::delegation::resolve_child_route(config, &profile) {
            self.unavailable_profiles.insert(profile.profile_id.clone());
            self.diagnostics.push(AgentProfileDiagnostic {
                path: PathBuf::from(&profile.source),
                message: format!(
                    "Agent Profile `{}` is unavailable: {error}",
                    profile.profile_id
                ),
            });
        }
        self.profiles.push(profile);
    }

    pub fn discover(paths: &ConfigPaths, config: &StudioConfig) -> Self {
        Self::discover_with_disabled(paths, config, false)
    }

    /// 设置页保留被禁用的系统与用户 Profile；执行目录仍只返回启用项。
    pub fn discover_for_settings(paths: &ConfigPaths, config: &StudioConfig) -> Self {
        Self::discover_with_disabled(paths, config, true)
    }

    fn discover_with_disabled(
        paths: &ConfigPaths,
        config: &StudioConfig,
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
                Ok(Some(profile)) => catalog.push_profile(profile, config),
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

/// Resolves a frozen Profile against one configuration snapshot without changing stored routes.
///
/// # Errors
/// Returns missing account/model bindings or invalid route parameters.
pub fn resolve_profile_route(
    config: &crate::config::StudioConfig,
    profile: &pl_protocol::AgentProfileSnapshot,
) -> Result<pl_model::config::ResolvedModelRoute> {
    let role = pl_model::config::AgentRoleId::new(profile.profile_id.clone())?;
    let mut models = config.models.clone();
    models.routes.insert(
        role.clone(),
        pl_model::config::ModelRouteConfig {
            account_id: pl_model::config::AccountId::new(profile.account_id.clone())?,
            model_id: profile.model_id.clone(),
            effort: profile
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
) -> Result<bool> {
    validate_user_agent_profile_id(profile_id)?;
    validate_user_profile(profile_id, profile, config)?;
    let content = super::document_migration::ProfileV1::from_current(profile)
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
            Ok(profile) => catalog.push_profile(profile, config),
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
) -> Result<AgentProfileSnapshot> {
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
    Ok(with_content_hash(snapshot))
}

pub(crate) fn system_agent_profile(
    config: &StudioConfig,
    profile_id: &str,
) -> Result<AgentProfileSnapshot> {
    let definition = crate::agent::catalog::definition(profile_id)?
        .ok_or_else(|| PureError::ConfigError(format!("unknown bundled Agent `{profile_id}`")))?;
    if definition.identity.scope != crate::agent::definition::AgentDefinitionScope::Child {
        return Err(PureError::ConfigError(format!(
            "root Agent `{profile_id}` is not a configurable child Profile"
        )));
    }
    system_profile(definition, config)
}

pub(crate) fn system_agent_profiles(config: &StudioConfig) -> Result<Vec<AgentProfileSnapshot>> {
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

fn load_user_profile(path: &Path, include_disabled: bool) -> Result<Option<AgentProfileSnapshot>> {
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
    let snapshot = AgentProfileSnapshot {
        profile_id: profile_id.to_string(),
        display_name: profile.display_name,
        description: profile.description,
        when_to_use: profile.when_to_use,
        system_instructions: profile.system_instructions,
        account_id: profile.account_id.as_str().to_string(),
        model_id: profile.model_id,
        effort: profile.effort.map(|effort| effort.as_str().to_string()),
        source: path.to_string_lossy().into_owned(),
        // Revision describes the business Profile, independent of its TOML schema header.
        revision,
        content_hash: String::new(),
        system: false,
        enabled: profile.enabled,
        workspace_mode: profile.workspace_mode,
    };
    Ok(Some(with_content_hash(snapshot)))
}

fn parse_profile_content(profile_id: &str, content: &str) -> Result<UserAgentProfile> {
    validate_user_agent_profile_id(profile_id)?;
    let profile = super::document_migration::load_current_profile(Path::new(profile_id), content)
        .and_then(|document| document.into_profile())
        .map_err(|_| PureError::ConfigError(format!("invalid Agent Profile TOML: {profile_id}")))?;
    validate_user_profile_fields(profile_id, &profile)?;
    Ok(profile)
}

fn validate_user_profile(
    profile_id: &str,
    profile: &UserAgentProfile,
    config: &StudioConfig,
) -> Result<()> {
    validate_user_profile_fields(profile_id, profile)?;
    config
        .models
        .resolve_route(
            pl_model::config::AgentRoleId::new(profile_id)?,
            &ModelRouteConfig {
                account_id: profile.account_id.clone(),
                model_id: profile.model_id.clone(),
                effort: profile.effort.clone(),
            },
        )
        .map(|_| ())
}

pub(super) fn validate_user_profile_fields(
    profile_id: &str,
    profile: &UserAgentProfile,
) -> Result<()> {
    for (field, value) in [
        ("display_name", profile.display_name.as_str()),
        ("description", profile.description.as_str()),
        ("when_to_use", profile.when_to_use.as_str()),
        ("system_instructions", profile.system_instructions.as_str()),
        ("model", profile.model_id.as_str()),
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
