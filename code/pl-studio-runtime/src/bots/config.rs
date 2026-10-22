use super::protocol::error::{FeishuError, FeishuErrorKind};
use crate::config::BotCredentialRef;
use crate::studio::unix_seconds;
use pl_protocol::studio::BotPlatform;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::path::Path;

pub const BOT_CONFIG_SCHEMA_VERSION: u32 = 3;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(try_from = "StoredBotConfig")]
pub struct BotConfigFile {
    pub schema_version: u32,
    pub id: String,
    pub name: String,
    pub project_id: String,
    #[serde(flatten)]
    pub platform: BotPlatformConfig,
    pub enabled: bool,
    pub tools_enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_route: Option<pl_protocol::studio::BotModelRoute>,

    pub config_revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected_ref: Option<BotCredentialRef>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "platform",
    content = "platform_config",
    rename_all = "camelCase"
)]
pub enum BotPlatformConfig {
    FeishuChina(FeishuBotConfig),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FeishuBotConfig {
    pub app_id: String,
    pub trusted_open_ids: BTreeSet<String>,
    pub trusted_chat_ids: BTreeSet<String>,
}

// This is the only legacy decoding boundary, including credential journals that
// embed a config. The running product consumes BotPlatformConfig exclusively.
#[derive(Deserialize)]
struct StoredBotConfig {
    schema_version: u32,
    id: String,
    name: String,
    project_id: String,
    platform: BotPlatform,
    enabled: bool,
    tools_enabled: bool,
    model_route: Option<pl_protocol::studio::BotModelRoute>,
    platform_config: Option<FeishuBotConfig>,
    app_id: Option<String>,
    trusted_open_ids: Option<BTreeSet<String>>,
    trusted_chat_ids: Option<BTreeSet<String>>,
    config_revision: u64,
    selected_ref: Option<BotCredentialRef>,
    created_at: i64,
    updated_at: i64,
}

impl TryFrom<StoredBotConfig> for BotConfigFile {
    type Error = &'static str;
    fn try_from(value: StoredBotConfig) -> Result<Self, Self::Error> {
        let details = if value.schema_version < 3 && value.platform_config.is_none() {
            FeishuBotConfig {
                app_id: value.app_id.ok_or("missing legacy app id")?,
                trusted_open_ids: value
                    .trusted_open_ids
                    .ok_or("missing legacy trusted users")?,
                trusted_chat_ids: value
                    .trusted_chat_ids
                    .ok_or("missing legacy trusted chats")?,
            }
        } else {
            if value.app_id.is_some()
                || value.trusted_open_ids.is_some()
                || value.trusted_chat_ids.is_some()
            {
                return Err("current config contains legacy platform fields");
            }
            value
                .platform_config
                .ok_or("missing platform configuration")?
        };
        let platform = match value.platform {
            BotPlatform::FeishuChina => BotPlatformConfig::FeishuChina(details),
        };
        Ok(Self {
            schema_version: value.schema_version,
            id: value.id,
            name: value.name,
            project_id: value.project_id,
            platform,
            enabled: value.enabled,
            tools_enabled: value.tools_enabled,
            model_route: value.model_route,
            config_revision: value.config_revision,
            selected_ref: value.selected_ref,
            created_at: value.created_at,
            updated_at: value.updated_at,
        })
    }
}

impl BotConfigFile {
    pub fn feishu(&self) -> &FeishuBotConfig {
        match &self.platform {
            BotPlatformConfig::FeishuChina(config) => config,
        }
    }
    pub fn feishu_mut(&mut self) -> &mut FeishuBotConfig {
        match &mut self.platform {
            BotPlatformConfig::FeishuChina(config) => config,
        }
    }

    pub fn new(
        id: String,
        name: String,
        project_id: String,
        app_id: String,
    ) -> Result<Self, FeishuError> {
        validate_bot_id(&id)?;
        validate_app_id(&app_id)?;
        if name.trim().is_empty() || project_id.trim().is_empty() {
            return Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "bot name and projectId are required",
                false,
                None,
            ));
        }
        let now = unix_seconds();
        Ok(Self {
            schema_version: BOT_CONFIG_SCHEMA_VERSION,
            id,
            name,
            project_id,
            platform: BotPlatformConfig::FeishuChina(FeishuBotConfig {
                app_id,
                trusted_open_ids: BTreeSet::new(),
                trusted_chat_ids: BTreeSet::new(),
            }),
            enabled: true,
            tools_enabled: false,
            model_route: None,

            config_revision: 1,
            selected_ref: None,
            created_at: now,
            updated_at: now,
        })
    }

    pub fn bump(&mut self) {
        self.config_revision = self.config_revision.saturating_add(1);
        self.updated_at = unix_seconds();
    }
}

pub fn validate_bot_id(bot_id: &str) -> Result<(), FeishuError> {
    if bot_id.len() < 8
        || bot_id.len() > 80
        || !bot_id
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_')
    {
        return Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "invalid bot id",
            false,
            None,
        ));
    }
    Ok(())
}

pub fn validate_app_id(app_id: &str) -> Result<(), FeishuError> {
    if app_id.trim().is_empty() || app_id.len() > 128 {
        return Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "invalid app id",
            false,
            None,
        ));
    }
    Ok(())
}

pub fn try_load_config(path: &Path) -> Result<Option<BotConfigFile>, FeishuError> {
    match std::fs::read_to_string(path) {
        Ok(text) => parse_config(&text).map(Some),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(FeishuError::new(
            FeishuErrorKind::Unavailable,
            format!("failed to read bot config: {error}"),
            true,
            None,
        )),
    }
}

pub fn load_config(path: &Path) -> Result<BotConfigFile, FeishuError> {
    let text = std::fs::read_to_string(path).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Unavailable,
            format!("failed to read bot config: {error}"),
            true,
            None,
        )
    })?;
    parse_config(&text)
}

fn parse_config(text: &str) -> Result<BotConfigFile, FeishuError> {
    let config: BotConfigFile = toml::from_str(text).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            format!("invalid bot config: {error}"),
            false,
            None,
        )
    })?;
    if !(1..=BOT_CONFIG_SCHEMA_VERSION).contains(&config.schema_version) {
        return Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            format!("unsupported bot config schema {}", config.schema_version),
            false,
            None,
        ));
    }
    validate_bot_id(&config.id)?;
    validate_app_id(&config.feishu().app_id)?;
    Ok(config)
}

pub fn save_config(path: &Path, config: &BotConfigFile) -> Result<(), FeishuError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|error| {
            FeishuError::new(
                FeishuErrorKind::Unavailable,
                format!("failed to create bot directory: {error}"),
                true,
                None,
            )
        })?;
    }
    let contents = toml::to_string_pretty(config).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            format!("failed to serialize bot config: {error}"),
            false,
            None,
        )
    })?;
    pl_tool::workspace::write_file_atomically(path, contents.as_bytes()).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Unavailable,
            format!("failed to write bot config: {error}"),
            true,
            None,
        )
    })
}

#[cfg(test)]
mod migration_tests {
    use super::*;

    #[test]
    fn legacy_platform_config_round_trips_with_identity_and_authorization_intact() {
        let legacy = r#"
schema_version = 2
id = "bot-migrate-1"
name = "原机器人"
project_id = "business-project"
app_id = "cli_original"
platform = "feishuChina"
enabled = true
tools_enabled = false
trusted_open_ids = ["ou_original"]
trusted_chat_ids = ["oc_original"]
config_revision = 9
created_at = 100
updated_at = 200
"#;
        let mut migrated = parse_config(legacy).unwrap();
        assert_eq!(migrated.feishu().app_id, "cli_original");
        assert!(migrated.feishu().trusted_open_ids.contains("ou_original"));
        assert!(migrated.feishu().trusted_chat_ids.contains("oc_original"));
        // A recovered credential journal may serialize its normalized old-version snapshot
        // before the configuration owner commits the schema/model upgrade.
        assert_eq!(
            parse_config(&toml::to_string(&migrated).unwrap()).unwrap(),
            migrated
        );
        migrated.schema_version = BOT_CONFIG_SCHEMA_VERSION;
        migrated.model_route = Some(pl_protocol::studio::BotModelRoute {
            account_id: "account-original".into(),
            model_id: "model-original".into(),
            effort: Some("high".into()),
        });
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("config.toml");
        save_config(&path, &migrated).unwrap();
        assert_eq!(load_config(&path).unwrap(), migrated);
        assert_eq!(migrated.id, "bot-migrate-1");
        assert_eq!(migrated.project_id, "business-project");
        assert_eq!(migrated.config_revision, 9);
    }
}
