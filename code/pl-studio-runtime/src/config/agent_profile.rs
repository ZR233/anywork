use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use pl_protocol::{AgentProfileSnapshot, AgentWorkspaceMode};
use serde::{Deserialize, Serialize};

use crate::{PureError, Result};

use super::{AccountId, ConfigPaths, ModelRouteConfig, ReasoningEffort, StudioConfig, StudioRole};

const SYSTEM_PROFILE_REVISION: &str = "studio-system-agent-v2";
const SYSTEM_PROFILE_IDS: [&str; 4] = ["explorer", "executor", "worktree_executor", "reviewer"];

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
    pub(crate) fn validate_for_startup(paths: &ConfigPaths) -> Result<()> {
        let entries = match fs::read_dir(paths.agents_dir()) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(error) => return Err(error.into()),
        };
        for entry in entries {
            let path = entry?.path();
            if path.extension().and_then(|value| value.to_str()) == Some("toml") {
                load_user_profile(&path, true)?;
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
    validate_profile_id(profile_id)?;
    if StudioRole::from_key(profile_id).is_some() {
        return Err(PureError::ConfigError(format!(
            "system Agent Profile `{profile_id}` is immutable"
        )));
    }
    validate_user_profile(profile_id, profile, config)?;
    let content = toml::to_string_pretty(profile).map_err(|error| {
        PureError::ConfigError(format!(
            "failed to serialize Agent Profile `{profile_id}`: {error}"
        ))
    })?;
    let directory = paths.agents_dir();
    fs::create_dir_all(&directory)?;
    let path = directory.join(format!("{profile_id}.toml"));
    let changed = match fs::read_to_string(&path) {
        Ok(existing) => toml::from_str::<UserAgentProfile>(&existing)
            .map(|existing| existing != *profile)
            .unwrap_or(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => true,
        Err(error) => return Err(error.into()),
    };
    pl_tool::workspace::write_file_atomically(&path, content.as_bytes())?;
    Ok(changed)
}

pub fn is_system_profile_id(profile_id: &str) -> bool {
    SYSTEM_PROFILE_IDS.contains(&profile_id)
}

fn system_profiles(config: &StudioConfig, include_disabled: bool) -> AgentProfileCatalog {
    let mut catalog = AgentProfileCatalog::default();
    for role in StudioRole::all()
        .into_iter()
        .filter(|role| is_system_profile_id(role.key()))
        .filter(|role| include_disabled || !config.disabled_system_agents.contains(role.key()))
    {
        match system_profile(role, config) {
            Ok(profile) => catalog.push_profile(profile, config),
            Err(error) => {
                tracing::warn!(profile_id = role.key(), %error, "system Agent Profile is unavailable");
                catalog.diagnostics.push(AgentProfileDiagnostic {
                    path: PathBuf::from(format!("studio-builtin:{}", role.key())),
                    message: format!("Agent Profile `{}` is unavailable: {error}", role.key()),
                });
            }
        }
    }
    catalog
}

fn system_profile(role: StudioRole, config: &StudioConfig) -> Result<AgentProfileSnapshot> {
    let (description, when_to_use, instructions) = match role {
        StudioRole::Explorer => (
            "只读探索代码、文档和现场事实。",
            "需要快速定位边界、依赖、实现入口或验证事实时。",
            include_str!("../prompts/explorer.md"),
        ),
        StudioRole::Planner => {
            return Err(PureError::ConfigError(
                "planner is the main agent route, not a child Profile".into(),
            ));
        }
        StudioRole::Executor => (
            "实施明确、边界清楚的工程任务。",
            "已有目标和范围，需要修改与验证代码时。",
            include_str!("../prompts/executor.md"),
        ),
        StudioRole::WorktreeExecutor => (
            "在独立 Git worktree 中实施明确任务。",
            "需要物理隔离修改，并由主代理审查、整合和清理时。",
            include_str!("../prompts/worktree_executor.md"),
        ),
        StudioRole::Reviewer => (
            "检查实现、测试、错误路径和需求一致性。",
            "需要独立复核已完成工作并报告具体问题时。",
            include_str!("../prompts/reviewer.md"),
        ),
    };
    let route = config
        .models
        .routes
        .get(&role.id())
        .ok_or_else(|| PureError::ConfigError("system Profile route is missing".into()))?;
    let snapshot = AgentProfileSnapshot {
        profile_id: role.key().to_string(),
        display_name: role.display_name().to_string(),
        description: description.to_string(),
        when_to_use: when_to_use.to_string(),
        system_instructions: instructions.to_string(),
        account_id: route.account_id.as_str().to_string(),
        model_id: route.model_id.clone(),
        effort: route
            .effort
            .as_ref()
            .map(|effort| effort.as_str().to_string()),
        source: "studio-builtin".to_string(),
        revision: SYSTEM_PROFILE_REVISION.to_string(),
        content_hash: String::new(),
        system: true,
        enabled: !config.disabled_system_agents.contains(role.key()),
        workspace_mode: match role {
            StudioRole::Explorer | StudioRole::Planner => AgentWorkspaceMode::Unrestricted,
            StudioRole::Reviewer => AgentWorkspaceMode::Review,
            StudioRole::Executor => AgentWorkspaceMode::Directory,
            StudioRole::WorktreeExecutor => AgentWorkspaceMode::Worktree,
        },
    };
    Ok(with_content_hash(snapshot))
}

fn load_user_profile(path: &Path, include_disabled: bool) -> Result<Option<AgentProfileSnapshot>> {
    let profile_id = path
        .file_stem()
        .and_then(|value| value.to_str())
        .ok_or_else(|| PureError::ConfigError("Agent Profile filename is not UTF-8".to_string()))?;
    validate_profile_id(profile_id)?;
    if StudioRole::from_key(profile_id).is_some() {
        return Err(PureError::ConfigError(format!(
            "user Agent Profile cannot replace immutable system profile `{profile_id}`"
        )));
    }
    let content = fs::read_to_string(path)?;
    // Existing, structurally valid files remain editable even if their account/model was removed.
    // The canonical scan records route failures separately when it builds the executable view.
    let profile = parse_profile_content(profile_id, &content)?;
    if !profile.enabled && !include_disabled {
        return Ok(None);
    }
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
        revision: pl_core::context::content_hash(content.as_bytes()),
        content_hash: String::new(),
        system: false,
        enabled: profile.enabled,
        workspace_mode: profile.workspace_mode,
    };
    Ok(Some(with_content_hash(snapshot)))
}

/// Validates a migration candidate's fields and references before publishing any new bytes.
pub(super) fn validate_profile_content(
    profile_id: &str,
    content: &str,
    config: &StudioConfig,
) -> Result<UserAgentProfile> {
    let profile = parse_profile_content(profile_id, content)?;
    config.models.route_availability(&ModelRouteConfig {
        account_id: profile.account_id.clone(),
        model_id: profile.model_id.clone(),
        effort: profile.effort.clone(),
    })?;
    Ok(profile)
}

fn parse_profile_content(profile_id: &str, content: &str) -> Result<UserAgentProfile> {
    validate_profile_id(profile_id)?;
    if StudioRole::from_key(profile_id).is_some() {
        return Err(PureError::ConfigError(format!(
            "user Agent Profile cannot replace immutable system profile `{profile_id}`"
        )));
    }
    let profile: UserAgentProfile = toml::from_str(content)
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

fn validate_user_profile_fields(profile_id: &str, profile: &UserAgentProfile) -> Result<()> {
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

fn validate_profile_id(profile_id: &str) -> Result<()> {
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

/// 返回内置 Profile 的稳定集合，供配置校验和 UI 使用。
pub fn system_profile_ids() -> BTreeSet<String> {
    SYSTEM_PROFILE_IDS.into_iter().map(str::to_string).collect()
}
