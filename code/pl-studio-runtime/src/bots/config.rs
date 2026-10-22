use super::protocol::error::{FeishuError, FeishuErrorKind};
use crate::config::BotCredentialRef;
use crate::studio::unix_seconds;
use pl_protocol::studio::BotPlatform;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::path::Path;

pub const BOT_CONFIG_SCHEMA_VERSION: u32 = 2;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BotConfigFile {
    pub schema_version: u32,
    pub id: String,
    pub name: String,
    pub project_id: String,
    pub app_id: String,
    pub platform: BotPlatform,
    pub enabled: bool,
    pub tools_enabled: bool,
    pub trusted_open_ids: BTreeSet<String>,
    pub trusted_chat_ids: BTreeSet<String>,
    pub config_revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected_ref: Option<BotCredentialRef>,
    pub created_at: i64,
    pub updated_at: i64,
}

impl BotConfigFile {
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
            app_id,
            platform: BotPlatform::FeishuChina,
            enabled: true,
            tools_enabled: false,
            trusted_open_ids: BTreeSet::new(),
            trusted_chat_ids: BTreeSet::new(),
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
    validate_app_id(&config.app_id)?;
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
