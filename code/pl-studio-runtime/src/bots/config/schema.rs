//! Frozen bot config wire types and the V1→V2→V3→V4 typed chain.
//!
//! Nested platform, model-route and credential-ref shapes stay local to this
//! module. Pure `MigratesTo` steps only move frozen types; mapping into the
//! current domain is explicit `From` / `TryFrom` after the library chain.

use std::collections::BTreeSet;
use std::path::Path;
use std::sync::OnceLock;

use anyhow::{Context, Result, ensure};
use pl_protocol::studio::BotModelRoute;
use serde::{Deserialize, Serialize};
use version_migrate::{IntoDomain, MigratesTo, Migrator, Versioned};

use super::{
    BOT_CONFIG_ENTITY, BOT_CONFIG_SCHEMA_VERSION, BOT_CONFIG_VERSION_KEY, BotConfigFile,
    BotPlatformConfig, FeishuBotConfig,
};
use crate::config::{BotCredentialRef, BotCredentialRefKind};
use crate::toml_schema;

pub(super) fn current_version() -> Result<u32> {
    toml_schema::integer_version(BotConfigV4::VERSION)
        .map_err(|error| toml_schema::chain_error(BOT_CONFIG_ENTITY, error))
}

pub(super) fn migrator() -> Result<&'static Migrator> {
    static MIGRATOR: OnceLock<Migrator> = OnceLock::new();
    if let Some(migrator) = MIGRATOR.get() {
        return Ok(migrator);
    }
    let mut migrator = Migrator::new();
    migrator
        .register(
            Migrator::define(BOT_CONFIG_ENTITY)
                .with_keys(BOT_CONFIG_VERSION_KEY, "data")
                .from::<BotConfigV1>()
                .step::<BotConfigV2>()
                .step::<BotConfigV3>()
                .step::<BotConfigV4>()
                .into::<BotConfigV4>(),
        )
        .map_err(|error| toml_schema::chain_error(BOT_CONFIG_ENTITY, error))?;
    Ok(MIGRATOR.get_or_init(|| migrator))
}

fn has_legacy_platform_fields(table: &serde_json::Map<String, serde_json::Value>) -> bool {
    table.contains_key("app_id")
        || table.contains_key("trusted_open_ids")
        || table.contains_key("trusted_chat_ids")
}

/// Historical confirm/write may keep schema 1/2 with either the original flat
/// layout or a nested `platform_config`. Layout is classified first; the chosen
/// DTO then enters the registered V1→V2→V3 library chain.
pub(super) fn load_document(
    path: &Path,
    content: &str,
) -> Result<toml_schema::LoadedDocument<BotConfigV4>> {
    let target = current_version()?;
    let table = toml_schema::parse(path, content, BOT_CONFIG_ENTITY, target)?;
    let value = serde_json::to_value(table).map_err(|error| {
        toml_schema::migration_error(path, BOT_CONFIG_ENTITY, None, target, "adapt", error)
    })?;
    load_snapshot(path, value)
}

pub(super) fn load_snapshot(
    path: &Path,
    mut value: serde_json::Value,
) -> Result<toml_schema::LoadedDocument<BotConfigV4>> {
    let target = current_version()?;
    let source = value
        .get(BOT_CONFIG_VERSION_KEY)
        .and_then(serde_json::Value::as_u64)
        .and_then(|version| u32::try_from(version).ok())
        .filter(|version| *version > 0);
    let prepared = (|| -> Result<serde_json::Value> {
        let source = source.context("missing or invalid integer document schema")?;
        let table = value
            .as_object_mut()
            .context("bot config must be an object")?;
        let legacy = has_legacy_platform_fields(table);
        let nested = table.contains_key("platform_config");
        if matches!(source, 1 | 2) {
            ensure!(
                legacy != nested,
                "historical bot config needs exactly one proven platform layout"
            );
            if nested {
                table.remove(BOT_CONFIG_VERSION_KEY);
                value = if source == 1 {
                    let nested: BotConfigV1Nested = serde_json::from_value(value)?;
                    serde_json::to_value(BotConfigV1::from(nested))?
                } else {
                    let nested: BotConfigV2Nested = serde_json::from_value(value)?;
                    serde_json::to_value(BotConfigV2::from(nested))?
                };
                value
                    .as_object_mut()
                    .context("frozen config must serialize as an object")?
                    .insert(BOT_CONFIG_VERSION_KEY.into(), source.into());
            }
        } else if source == target {
            ensure!(!legacy, "current config contains legacy platform fields");
        }
        Ok(value)
    })()
    .map_err(|error| {
        toml_schema::migration_error(path, BOT_CONFIG_ENTITY, source, target, "prepare", error)
    })?;
    toml_schema::load_json::<BotConfigV1, BotConfigV4>(
        path,
        prepared,
        migrator()?,
        BOT_CONFIG_ENTITY,
        BOT_CONFIG_VERSION_KEY,
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum FrozenBotPlatform {
    FeishuChina,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct FrozenBotModelRoute {
    account_id: String,
    model_id: String,
    effort: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum FrozenBotCredentialRefKind {
    System,
    Session,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct FrozenBotCredentialRef {
    kind: FrozenBotCredentialRefKind,
    version: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(super) struct FrozenFeishuBotConfig {
    pub(super) app_id: String,
    trusted_open_ids: BTreeSet<String>,
    trusted_chat_ids: BTreeSet<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "platform",
    content = "platform_config",
    rename_all = "camelCase"
)]
pub(super) enum FrozenBotPlatformConfig {
    FeishuChina(FrozenFeishuBotConfig),
}

/// Proven nested layout written by historical confirm/write with a V1 header.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct BotConfigV1Nested {
    id: String,
    name: String,
    project_id: String,
    #[serde(flatten)]
    platform: FrozenBotPlatformConfig,
    enabled: bool,
    tools_enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    model_route: Option<FrozenBotModelRoute>,
    config_revision: u64,
    created_at: i64,
    updated_at: i64,
}

/// Proven nested layout written by historical confirm/write with a V2 header.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct BotConfigV2Nested {
    id: String,
    name: String,
    project_id: String,
    #[serde(flatten)]
    platform: FrozenBotPlatformConfig,
    enabled: bool,
    tools_enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    model_route: Option<FrozenBotModelRoute>,
    config_revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    selected_ref: Option<FrozenBotCredentialRef>,
    created_at: i64,
    updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "1.0.0")]
#[serde(deny_unknown_fields)]
pub(super) struct BotConfigV1 {
    pub(super) id: String,
    name: String,
    project_id: String,
    platform: FrozenBotPlatform,
    enabled: bool,
    tools_enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    model_route: Option<FrozenBotModelRoute>,
    pub(super) app_id: String,
    trusted_open_ids: BTreeSet<String>,
    trusted_chat_ids: BTreeSet<String>,
    config_revision: u64,
    created_at: i64,
    updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "2.0.0")]
#[serde(deny_unknown_fields)]
pub(super) struct BotConfigV2 {
    pub(super) id: String,
    name: String,
    project_id: String,
    platform: FrozenBotPlatform,
    enabled: bool,
    tools_enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    model_route: Option<FrozenBotModelRoute>,
    pub(super) app_id: String,
    trusted_open_ids: BTreeSet<String>,
    trusted_chat_ids: BTreeSet<String>,
    config_revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) selected_ref: Option<FrozenBotCredentialRef>,
    created_at: i64,
    updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "3.0.0")]
#[serde(deny_unknown_fields)]
pub(super) struct BotConfigV3 {
    id: String,
    name: String,
    project_id: String,
    #[serde(flatten)]
    pub(super) platform: FrozenBotPlatformConfig,
    enabled: bool,
    tools_enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    model_route: Option<FrozenBotModelRoute>,
    config_revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    selected_ref: Option<FrozenBotCredentialRef>,
    created_at: i64,
    updated_at: i64,
}

/// Current ownership vocabulary. Historical DTOs above keep their published keys.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "4.0.0")]
#[serde(deny_unknown_fields)]
pub(super) struct BotConfigV4 {
    id: String,
    name: String,
    workspace_id: String,
    #[serde(flatten)]
    platform: FrozenBotPlatformConfig,
    enabled: bool,
    tools_enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    model_route: Option<FrozenBotModelRoute>,
    config_revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    selected_ref: Option<FrozenBotCredentialRef>,
    created_at: i64,
    updated_at: i64,
}

impl MigratesTo<BotConfigV2> for BotConfigV1 {
    fn migrate(self) -> BotConfigV2 {
        BotConfigV2 {
            id: self.id,
            name: self.name,
            project_id: self.project_id,
            platform: self.platform,
            enabled: self.enabled,
            tools_enabled: self.tools_enabled,
            model_route: self.model_route,
            app_id: self.app_id,
            trusted_open_ids: self.trusted_open_ids,
            trusted_chat_ids: self.trusted_chat_ids,
            config_revision: self.config_revision,
            selected_ref: None,
            created_at: self.created_at,
            updated_at: self.updated_at,
        }
    }
}

impl MigratesTo<BotConfigV3> for BotConfigV2 {
    fn migrate(self) -> BotConfigV3 {
        BotConfigV3 {
            id: self.id,
            name: self.name,
            project_id: self.project_id,
            platform: FrozenBotPlatformConfig::FeishuChina(FrozenFeishuBotConfig {
                app_id: self.app_id,
                trusted_open_ids: self.trusted_open_ids,
                trusted_chat_ids: self.trusted_chat_ids,
            }),
            enabled: self.enabled,
            tools_enabled: self.tools_enabled,
            model_route: self.model_route,
            config_revision: self.config_revision,
            selected_ref: self.selected_ref,
            created_at: self.created_at,
            updated_at: self.updated_at,
        }
    }
}

impl MigratesTo<BotConfigV4> for BotConfigV3 {
    fn migrate(self) -> BotConfigV4 {
        BotConfigV4 {
            id: self.id,
            name: self.name,
            workspace_id: self.project_id,
            platform: self.platform,
            enabled: self.enabled,
            tools_enabled: self.tools_enabled,
            model_route: self.model_route,
            config_revision: self.config_revision,
            selected_ref: self.selected_ref,
            created_at: self.created_at,
            updated_at: self.updated_at,
        }
    }
}

impl IntoDomain<BotConfigV4> for BotConfigV4 {
    fn into_domain(self) -> BotConfigV4 {
        self
    }
}

impl From<BotConfigV1Nested> for BotConfigV1 {
    fn from(value: BotConfigV1Nested) -> Self {
        let FrozenBotPlatformConfig::FeishuChina(feishu) = value.platform;
        Self {
            id: value.id,
            name: value.name,
            project_id: value.project_id,
            platform: FrozenBotPlatform::FeishuChina,
            enabled: value.enabled,
            tools_enabled: value.tools_enabled,
            model_route: value.model_route,
            app_id: feishu.app_id,
            trusted_open_ids: feishu.trusted_open_ids,
            trusted_chat_ids: feishu.trusted_chat_ids,
            config_revision: value.config_revision,
            created_at: value.created_at,
            updated_at: value.updated_at,
        }
    }
}

impl From<BotConfigV2Nested> for BotConfigV2 {
    fn from(value: BotConfigV2Nested) -> Self {
        let FrozenBotPlatformConfig::FeishuChina(feishu) = value.platform;
        Self {
            id: value.id,
            name: value.name,
            project_id: value.project_id,
            platform: FrozenBotPlatform::FeishuChina,
            enabled: value.enabled,
            tools_enabled: value.tools_enabled,
            model_route: value.model_route,
            app_id: feishu.app_id,
            trusted_open_ids: feishu.trusted_open_ids,
            trusted_chat_ids: feishu.trusted_chat_ids,
            config_revision: value.config_revision,
            selected_ref: value.selected_ref,
            created_at: value.created_at,
            updated_at: value.updated_at,
        }
    }
}

impl From<FrozenBotModelRoute> for BotModelRoute {
    fn from(value: FrozenBotModelRoute) -> Self {
        Self {
            account_id: value.account_id,
            model_id: value.model_id,
            effort: value.effort,
        }
    }
}

impl From<BotModelRoute> for FrozenBotModelRoute {
    fn from(value: BotModelRoute) -> Self {
        Self {
            account_id: value.account_id,
            model_id: value.model_id,
            effort: value.effort,
        }
    }
}

impl From<FrozenBotCredentialRef> for BotCredentialRef {
    fn from(value: FrozenBotCredentialRef) -> Self {
        Self {
            kind: match value.kind {
                FrozenBotCredentialRefKind::System => BotCredentialRefKind::System,
                FrozenBotCredentialRefKind::Session => BotCredentialRefKind::Session,
            },
            version: value.version,
        }
    }
}

impl From<BotCredentialRef> for FrozenBotCredentialRef {
    fn from(value: BotCredentialRef) -> Self {
        Self {
            kind: match value.kind {
                BotCredentialRefKind::System => FrozenBotCredentialRefKind::System,
                BotCredentialRefKind::Session => FrozenBotCredentialRefKind::Session,
            },
            version: value.version,
        }
    }
}

impl From<FrozenFeishuBotConfig> for FeishuBotConfig {
    fn from(value: FrozenFeishuBotConfig) -> Self {
        Self {
            app_id: value.app_id,
            trusted_open_ids: value.trusted_open_ids,
            trusted_chat_ids: value.trusted_chat_ids,
        }
    }
}

impl From<&FeishuBotConfig> for FrozenFeishuBotConfig {
    fn from(value: &FeishuBotConfig) -> Self {
        Self {
            app_id: value.app_id.clone(),
            trusted_open_ids: value.trusted_open_ids.clone(),
            trusted_chat_ids: value.trusted_chat_ids.clone(),
        }
    }
}

impl From<FrozenBotPlatformConfig> for BotPlatformConfig {
    fn from(value: FrozenBotPlatformConfig) -> Self {
        match value {
            FrozenBotPlatformConfig::FeishuChina(config) => Self::FeishuChina(config.into()),
        }
    }
}

impl From<&BotPlatformConfig> for FrozenBotPlatformConfig {
    fn from(value: &BotPlatformConfig) -> Self {
        match value {
            BotPlatformConfig::FeishuChina(config) => Self::FeishuChina(config.into()),
        }
    }
}

impl TryFrom<BotConfigV4> for BotConfigFile {
    type Error = anyhow::Error;

    fn try_from(document: BotConfigV4) -> Result<Self> {
        Ok(Self {
            schema_version: BOT_CONFIG_SCHEMA_VERSION,
            id: document.id,
            name: document.name,
            workspace_id: document.workspace_id,
            platform: document.platform.into(),
            enabled: document.enabled,
            tools_enabled: document.tools_enabled,
            model_route: document.model_route.map(Into::into),
            config_revision: document.config_revision,
            selected_ref: document.selected_ref.map(Into::into),
            created_at: document.created_at,
            updated_at: document.updated_at,
        })
    }
}

impl From<&BotConfigFile> for BotConfigV3 {
    fn from(config: &BotConfigFile) -> Self {
        Self {
            id: config.id.clone(),
            name: config.name.clone(),
            project_id: config.workspace_id.clone(),
            platform: FrozenBotPlatformConfig::from(&config.platform),
            enabled: config.enabled,
            tools_enabled: config.tools_enabled,
            model_route: config.model_route.clone().map(Into::into),
            config_revision: config.config_revision,
            selected_ref: config.selected_ref.clone().map(Into::into),
            created_at: config.created_at,
            updated_at: config.updated_at,
        }
    }
}

impl From<&BotConfigFile> for BotConfigV4 {
    fn from(config: &BotConfigFile) -> Self {
        Self {
            id: config.id.clone(),
            name: config.name.clone(),
            workspace_id: config.workspace_id.clone(),
            platform: FrozenBotPlatformConfig::from(&config.platform),
            enabled: config.enabled,
            tools_enabled: config.tools_enabled,
            model_route: config.model_route.clone().map(Into::into),
            config_revision: config.config_revision,
            selected_ref: config.selected_ref.clone().map(Into::into),
            created_at: config.created_at,
            updated_at: config.updated_at,
        }
    }
}

impl BotConfigV1 {
    pub(super) fn from_file(config: &BotConfigFile) -> Result<Self, anyhow::Error> {
        anyhow::ensure!(
            config.selected_ref.is_none(),
            "v1 bot config cannot carry a credential ref"
        );
        let feishu = config.feishu();
        Ok(Self {
            id: config.id.clone(),
            name: config.name.clone(),
            project_id: config.workspace_id.clone(),
            platform: FrozenBotPlatform::FeishuChina,
            enabled: config.enabled,
            tools_enabled: config.tools_enabled,
            model_route: config.model_route.clone().map(Into::into),
            app_id: feishu.app_id.clone(),
            trusted_open_ids: feishu.trusted_open_ids.clone(),
            trusted_chat_ids: feishu.trusted_chat_ids.clone(),
            config_revision: config.config_revision,
            created_at: config.created_at,
            updated_at: config.updated_at,
        })
    }
}

impl BotConfigV2 {
    pub(super) fn from_file(config: &BotConfigFile) -> Self {
        let feishu = config.feishu();
        Self {
            id: config.id.clone(),
            name: config.name.clone(),
            project_id: config.workspace_id.clone(),
            platform: FrozenBotPlatform::FeishuChina,
            enabled: config.enabled,
            tools_enabled: config.tools_enabled,
            model_route: config.model_route.clone().map(Into::into),
            app_id: feishu.app_id.clone(),
            trusted_open_ids: feishu.trusted_open_ids.clone(),
            trusted_chat_ids: feishu.trusted_chat_ids.clone(),
            config_revision: config.config_revision,
            selected_ref: config.selected_ref.clone().map(Into::into),
            created_at: config.created_at,
            updated_at: config.updated_at,
        }
    }
}
