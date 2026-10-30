use super::protocol::error::{FeishuError, FeishuErrorKind};
use crate::config::BotCredentialRef;
use crate::studio::unix_seconds;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::path::Path;

mod schema;

use schema::{BotConfigV1, BotConfigV2, BotConfigV3};

pub const BOT_CONFIG_SCHEMA_VERSION: u32 = 3;
pub(super) const BOT_CONFIG_ENTITY: &str = "bot_config";
pub(super) const BOT_CONFIG_VERSION_KEY: &str = "schema_version";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BotConfigFile {
    /// Disk / snapshot source schema, not the in-memory platform shape.
    pub schema_version: u32,
    pub id: String,
    pub name: String,
    pub workspace_id: String,
    pub platform: BotPlatformConfig,
    pub enabled: bool,
    pub tools_enabled: bool,
    pub model_route: Option<pl_protocol::studio::BotModelRoute>,
    pub config_revision: u64,
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

fn map_schema_error(error: impl Into<anyhow::Error>) -> FeishuError {
    let error = error.into();
    FeishuError::new(
        FeishuErrorKind::Protocol,
        format!("invalid bot config: {error}"),
        false,
        None,
    )
    .with_source(error)
}

fn insert_integer_schema_version(
    mut value: serde_json::Value,
    version: u32,
) -> Result<serde_json::Value, FeishuError> {
    let Some(table) = value.as_object_mut() else {
        return Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "document must be a JSON object",
            false,
            None,
        ));
    };
    if table.contains_key(BOT_CONFIG_VERSION_KEY) {
        return Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "document DTO must not contain its root schema header",
            false,
            None,
        ));
    }
    table.insert(
        BOT_CONFIG_VERSION_KEY.into(),
        serde_json::Value::from(version),
    );
    Ok(value)
}

fn encode_historical_toml<T: Serialize>(dto: &T, version: u32) -> Result<String, FeishuError> {
    let mut value = toml::Value::try_from(dto).map_err(map_schema_error)?;
    let Some(table) = value.as_table_mut() else {
        return Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "document must be a TOML table",
            false,
            None,
        ));
    };
    if table.contains_key(BOT_CONFIG_VERSION_KEY) {
        return Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "document DTO must not contain its root schema header",
            false,
            None,
        ));
    }
    table.insert(
        BOT_CONFIG_VERSION_KEY.into(),
        toml::Value::Integer(i64::from(version)),
    );
    toml::to_string_pretty(&value).map_err(map_schema_error)
}

fn persist_config_bytes(path: &Path, contents: &str) -> Result<(), FeishuError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|error| {
            FeishuError::new(
                FeishuErrorKind::Unavailable,
                format!("failed to create bot directory: {error}"),
                true,
                None,
            )
            .with_source(error)
        })?;
    }
    pl_tool::workspace::write_file_atomically(path, contents.as_bytes()).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Unavailable,
            format!("failed to write bot config: {error}"),
            true,
            None,
        )
        .with_source(error)
    })
}

fn finish_loaded(
    path: &Path,
    source_version: u32,
    document: BotConfigV3,
) -> Result<BotConfigFile, FeishuError> {
    let target = schema::current_version().map_err(map_schema_error)?;
    let mut config = BotConfigFile::try_from(document).map_err(|error| {
        map_schema_error(crate::toml_schema::migration_error(
            path,
            BOT_CONFIG_ENTITY,
            Some(source_version),
            target,
            "construct",
            error,
        ))
    })?;
    config.schema_version = source_version;
    validate_loaded(&config).map_err(|error| {
        map_schema_error(crate::toml_schema::migration_error(
            path,
            BOT_CONFIG_ENTITY,
            Some(source_version),
            target,
            "validate",
            error,
        ))
    })?;
    Ok(config)
}

fn validate_loaded(config: &BotConfigFile) -> anyhow::Result<()> {
    validate_bot_id(&config.id)?;
    validate_app_id(&config.feishu().app_id)?;
    Ok(())
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
        workspace_id: String,
        app_id: String,
    ) -> Result<Self, FeishuError> {
        validate_bot_id(&id)?;
        validate_app_id(&app_id)?;
        if name.trim().is_empty() || workspace_id.trim().is_empty() {
            return Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "bot name and workspaceId are required",
                false,
                None,
            ));
        }
        let now = unix_seconds();
        Ok(Self {
            schema_version: BOT_CONFIG_SCHEMA_VERSION,
            id,
            name,
            workspace_id,
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

pub(super) fn parse_config_at(path: &Path, text: &str) -> Result<BotConfigFile, FeishuError> {
    let loaded = schema::load_document(path, text).map_err(map_schema_error)?;
    finish_loaded(path, loaded.source_version, loaded.document)
}

fn encode_current_config(config: &BotConfigFile) -> Result<String, FeishuError> {
    crate::toml_schema::encode(&BotConfigV3::from(config), BOT_CONFIG_VERSION_KEY)
        .map_err(map_schema_error)
}

fn encode_historical_config(config: &BotConfigFile) -> Result<String, FeishuError> {
    match config.schema_version {
        1 => encode_historical_toml(
            &BotConfigV1::from_file(config).map_err(map_schema_error)?,
            1,
        ),
        2 => encode_historical_toml(&BotConfigV2::from_file(config), 2),
        BOT_CONFIG_SCHEMA_VERSION => encode_current_config(config),
        version => Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            format!("unsupported bot config schema {version}"),
            false,
            None,
        )),
    }
}

pub(super) fn encode_config_snapshot(
    config: &BotConfigFile,
) -> Result<serde_json::Value, FeishuError> {
    let value = match config.schema_version {
        1 => serde_json::to_value(BotConfigV1::from_file(config).map_err(map_schema_error)?)
            .map_err(map_schema_error)?,
        2 => serde_json::to_value(BotConfigV2::from_file(config)).map_err(map_schema_error)?,
        BOT_CONFIG_SCHEMA_VERSION => {
            serde_json::to_value(BotConfigV3::from(config)).map_err(map_schema_error)?
        }
        version => {
            return Err(FeishuError::new(
                FeishuErrorKind::Protocol,
                format!("unsupported bot config schema {version}"),
                false,
                None,
            ));
        }
    };
    insert_integer_schema_version(value, config.schema_version)
}

pub(super) fn decode_config_snapshot_at(
    path: &Path,
    value: serde_json::Value,
) -> Result<BotConfigFile, FeishuError> {
    let loaded = schema::load_snapshot(path, value).map_err(map_schema_error)?;
    finish_loaded(path, loaded.source_version, loaded.document)
}

#[cfg(test)]
fn decode_config_snapshot(value: serde_json::Value) -> Result<BotConfigFile, FeishuError> {
    decode_config_snapshot_at(Path::new("credential-journal.json"), value)
}

pub fn try_load_config(path: &Path) -> Result<Option<BotConfigFile>, FeishuError> {
    match std::fs::read_to_string(path) {
        Ok(text) => parse_config_at(path, &text).map(Some),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(FeishuError::new(
            FeishuErrorKind::Unavailable,
            format!("failed to read bot config: {error}"),
            true,
            None,
        )
        .with_source(error)),
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
        .with_source(error)
    })?;
    parse_config_at(path, &text)
}

/// Normal file save: current V3 only. Historical schema is not rewritten here.
pub fn save_config(path: &Path, config: &BotConfigFile) -> Result<(), FeishuError> {
    persist_config_bytes(path, &encode_current_config(config)?)
}

/// Recovery / journal confirmation writer. Historical candidates keep their
/// original schema; they are not re-encoded as the current document.
pub(super) fn save_recognized_config(
    path: &Path,
    config: &BotConfigFile,
) -> Result<(), FeishuError> {
    persist_config_bytes(path, &encode_historical_config(config)?)
}

#[cfg(test)]
pub(super) fn assert_current_v3_document(persisted: &str, app_id: &str) {
    let table: toml::Table = toml::from_str(persisted).expect("current bot config TOML");
    assert_eq!(table[BOT_CONFIG_VERSION_KEY].as_integer(), Some(3));
    assert!(table.get("app_id").is_none());
    assert!(table.get("trusted_open_ids").is_none());
    assert!(table.get("trusted_chat_ids").is_none());
    let platform_config = table
        .get("platform_config")
        .and_then(toml::Value::as_table)
        .expect("current document nests platform_config");
    assert_eq!(platform_config["app_id"].as_str(), Some(app_id));
    assert!(platform_config.get("trusted_open_ids").is_some());
    assert!(platform_config.get("trusted_chat_ids").is_some());
}

#[cfg(test)]
mod migration_tests {
    use super::schema::FrozenBotPlatformConfig;
    use super::*;
    use crate::toml_schema::DocumentMigrationFailed;

    const V1_FIXTURE: &str = r#"
schema_version = 1
id = "bot-migrate-1"
name = "原机器人"
workspace_id = "business-project"
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

    const V2_FIXTURE: &str = r#"
schema_version = 2
id = "bot-migrate-1"
name = "原机器人"
workspace_id = "business-project"
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

    fn parse_config(text: &str) -> Result<BotConfigFile, FeishuError> {
        parse_config_at(Path::new("config.toml"), text)
    }

    #[test]
    fn loaded_validation_keeps_the_typed_rejection_in_file_and_snapshot_sources() {
        for (from, to, message) in [
            (
                "id = \"bot-migrate-1\"",
                "id = \"bad/private/id\"",
                "invalid bot id",
            ),
            (
                "app_id = \"cli_original\"",
                "app_id = \"\"",
                "invalid app id",
            ),
        ] {
            let text = V1_FIXTURE.replace(from, to);
            let snapshot: toml::Table = toml::from_str(&text).unwrap();
            for error in [
                parse_config(&text).unwrap_err(),
                decode_config_snapshot(serde_json::to_value(snapshot).unwrap()).unwrap_err(),
            ] {
                assert_eq!(error.kind(), FeishuErrorKind::Protocol);
                assert!(!error.retryable());
                assert!(!error.diagnostic().message.contains("bad/private/id"));
                let error = anyhow::Error::new(error);
                assert!(
                    error
                        .chain()
                        .any(|cause| cause.is::<DocumentMigrationFailed>())
                );
                let rejection = error
                    .chain()
                    .filter_map(|cause| cause.downcast_ref::<FeishuError>())
                    .find(|cause| cause.kind() == FeishuErrorKind::Rejected)
                    .expect("validator rejection remains a typed leaf cause");
                assert_eq!(rejection.diagnostic().message, message);
            }
        }
    }

    #[test]
    fn file_io_keeps_retryability_and_typed_cause_while_schema_errors_do_not_retry() {
        let directory = tempfile::tempdir().unwrap();
        let error = load_config(directory.path()).unwrap_err();
        assert_eq!(error.kind(), FeishuErrorKind::Unavailable);
        assert!(error.retryable());
        let source = anyhow::Error::new(error);
        assert!(source.chain().any(|cause| cause.is::<std::io::Error>()));

        let blocked_parent = directory.path().join("ordinary-file");
        std::fs::write(&blocked_parent, b"not a directory").unwrap();
        let config = BotConfigFile::new(
            "botA1234".into(),
            "Bot".into(),
            "project".into(),
            "cli_io".into(),
        )
        .unwrap();
        let error = save_config(&blocked_parent.join("config.toml"), &config).unwrap_err();
        assert!(error.diagnostic().retryable);
        assert!(
            anyhow::Error::new(error)
                .chain()
                .any(|cause| cause.is::<std::io::Error>())
        );

        let error = parse_config("schema_version = 999\n").unwrap_err();
        assert_eq!(error.kind(), FeishuErrorKind::Protocol);
        assert!(!error.retryable());
        assert!(
            anyhow::Error::new(error)
                .chain()
                .any(|cause| cause.is::<crate::toml_schema::DocumentMigrationFailed>())
        );
    }

    fn assert_identity(config: &BotConfigFile) {
        assert_eq!(config.feishu().app_id, "cli_original");
        assert!(config.feishu().trusted_open_ids.contains("ou_original"));
        assert!(config.feishu().trusted_chat_ids.contains("oc_original"));
        assert_eq!(config.id, "bot-migrate-1");
        assert_eq!(config.workspace_id, "business-project");
        assert_eq!(config.config_revision, 9);
        assert!(config.selected_ref.is_none());
    }

    fn assert_current_v3_toml(persisted: &str, app_id: &str) {
        let table: toml::Table = toml::from_str(persisted).unwrap();
        assert_eq!(table[BOT_CONFIG_VERSION_KEY].as_integer(), Some(3));
        assert!(table.get("app_id").is_none());
        assert!(table.get("trusted_open_ids").is_none());
        assert!(table.get("trusted_chat_ids").is_none());
        let platform_config = table
            .get("platform_config")
            .and_then(toml::Value::as_table)
            .expect("current document nests platform_config");
        assert_eq!(platform_config["app_id"].as_str(), Some(app_id));
        let open_ids: Vec<&str> = platform_config["trusted_open_ids"]
            .as_array()
            .expect("trusted_open_ids")
            .iter()
            .map(|value| value.as_str().unwrap())
            .collect();
        let chat_ids: Vec<&str> = platform_config["trusted_chat_ids"]
            .as_array()
            .expect("trusted_chat_ids")
            .iter()
            .map(|value| value.as_str().unwrap())
            .collect();
        assert_eq!(open_ids, vec!["ou_original"]);
        assert_eq!(chat_ids, vec!["oc_original"]);
    }

    fn dto_toml_round_trip<T>(dto: &T) -> T
    where
        T: Serialize + serde::de::DeserializeOwned + PartialEq + std::fmt::Debug,
    {
        let encoded = toml::to_string_pretty(dto).unwrap();
        toml::from_str(&encoded).unwrap()
    }

    const V1_DTO: &str = r#"
id = "bot-migrate-1"
name = "原机器人"
workspace_id = "business-project"
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

    #[test]
    fn v1_wire_dto_round_trips_without_selected_ref() {
        let dto: BotConfigV1 = toml::from_str(V1_DTO).unwrap();
        assert_eq!(dto.app_id, "cli_original");
        assert_eq!(dto_toml_round_trip(&dto), dto);
        let json = serde_json::to_value(&dto).unwrap();
        assert!(json.get("selected_ref").is_none());
        assert_eq!(serde_json::from_value::<BotConfigV1>(json).unwrap(), dto);
    }

    #[test]
    fn v2_wire_dto_round_trips_selected_ref() {
        let mut dto: BotConfigV2 = toml::from_str(V1_DTO).unwrap();
        dto.selected_ref = Some(crate::config::BotCredentialRef::system("original-version").into());
        assert_eq!(dto_toml_round_trip(&dto), dto);
        let json = serde_json::to_value(&dto).unwrap();
        assert_eq!(serde_json::from_value::<BotConfigV2>(json).unwrap(), dto);
    }

    #[test]
    fn v3_wire_dto_round_trips_nested_platform() {
        let current = BotConfigV3::from(&parse_config(V2_FIXTURE).unwrap());
        match &current.platform {
            FrozenBotPlatformConfig::FeishuChina(config) => {
                assert_eq!(config.app_id, "cli_original");
            }
        }
        let encoded = crate::toml_schema::encode(&current, BOT_CONFIG_VERSION_KEY).unwrap();
        let table: toml::Table = toml::from_str(&encoded).unwrap();
        assert_eq!(table[BOT_CONFIG_VERSION_KEY].as_integer(), Some(3));
        assert!(table.get("app_id").is_none());
        let json = serde_json::to_value(&current).unwrap();
        assert_eq!(
            serde_json::from_value::<BotConfigV3>(json).unwrap(),
            current
        );
        assert_eq!(dto_toml_round_trip(&current), current);
    }

    #[test]
    fn v1_file_keeps_source_schema_and_does_not_invent_selected_ref() {
        let loaded = parse_config(V1_FIXTURE).unwrap();
        assert_eq!(loaded.schema_version, 1);
        assert_identity(&loaded);
        let snapshot = encode_config_snapshot(&loaded).unwrap();
        assert_eq!(snapshot[BOT_CONFIG_VERSION_KEY], 1);
        assert!(snapshot.get("platform_config").is_none());
        assert_eq!(decode_config_snapshot(snapshot).unwrap(), loaded);
    }

    #[test]
    fn legacy_platform_config_round_trips_with_identity_and_authorization_intact() {
        let loaded = crate::toml_schema::load::<BotConfigV1, BotConfigV3>(
            Path::new("config.toml"),
            V2_FIXTURE,
            schema::migrator().unwrap(),
            BOT_CONFIG_ENTITY,
            BOT_CONFIG_VERSION_KEY,
        )
        .unwrap();
        assert!(loaded.migrated);
        assert_eq!(loaded.source_version, 2);
        let migrated = finish_loaded(
            Path::new("config.toml"),
            loaded.source_version,
            loaded.document,
        )
        .unwrap();
        assert_eq!(migrated.schema_version, 2);
        assert_identity(&migrated);
        let snapshot = encode_config_snapshot(&migrated).unwrap();
        assert_eq!(snapshot[BOT_CONFIG_VERSION_KEY], 2);
        assert_eq!(decode_config_snapshot(snapshot.clone()).unwrap(), migrated);
        let nested = serde_json::json!({
            "schema_version": 2,
            "id": "bot-migrate-1",
            "name": "原机器人",
            "workspace_id": "business-project",
            "platform": "feishuChina",
            "platform_config": {
                "app_id": "cli_original",
                "trusted_open_ids": ["ou_original"],
                "trusted_chat_ids": ["oc_original"]
            },
            "enabled": true,
            "tools_enabled": false,
            "config_revision": 9,
            "created_at": 100,
            "updated_at": 200
        });
        assert_eq!(decode_config_snapshot(nested).unwrap(), migrated);
        let mut current = migrated.clone();
        current.schema_version = BOT_CONFIG_SCHEMA_VERSION;
        current.model_route = Some(pl_protocol::studio::BotModelRoute {
            account_id: "account-original".into(),
            model_id: "model-original".into(),
            effort: Some("high".into()),
        });
        assert_eq!(current.config_revision, 9);
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("config.toml");
        save_config(&path, &current).unwrap();
        let persisted = std::fs::read_to_string(&path).unwrap();
        assert!(persisted.contains("schema_version = 3"));
        assert_current_v3_toml(&persisted, "cli_original");
        let reloaded = crate::toml_schema::load::<BotConfigV1, BotConfigV3>(
            &path,
            &persisted,
            schema::migrator().unwrap(),
            BOT_CONFIG_ENTITY,
            BOT_CONFIG_VERSION_KEY,
        )
        .unwrap();
        assert!(!reloaded.migrated);
        assert_eq!(reloaded.source_version, 3);
        assert_eq!(load_config(&path).unwrap(), current);
        assert_eq!(current.id, "bot-migrate-1");
        assert_eq!(current.workspace_id, "business-project");
        assert_eq!(current.config_revision, 9);
    }

    #[test]
    fn current_schema_is_a_no_op_and_does_not_rewrite_on_read() {
        let mut config = parse_config(V2_FIXTURE).unwrap();
        config.schema_version = BOT_CONFIG_SCHEMA_VERSION;
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("config.toml");
        save_config(&path, &config).unwrap();
        let before = std::fs::read(&path).unwrap();
        let loaded = load_config(&path).unwrap();
        assert_eq!(loaded.schema_version, 3);
        assert_eq!(loaded, config);
        assert_eq!(std::fs::read(&path).unwrap(), before);
    }

    #[test]
    fn rejects_unknown_integer_and_current_shaped_future_schema() {
        let current = parse_config(V2_FIXTURE).unwrap();
        let mut encoded = encode_current_config(&{
            let mut config = current.clone();
            config.schema_version = BOT_CONFIG_SCHEMA_VERSION;
            config
        })
        .unwrap();
        encoded = encoded.replace("schema_version = 3", "schema_version = 4");
        let error = parse_config(&encoded).unwrap_err();
        assert_eq!(error.kind(), FeishuErrorKind::Protocol);
        let wrapped = crate::toml_schema::load::<BotConfigV1, BotConfigV3>(
            Path::new("config.toml"),
            &encoded,
            schema::migrator().unwrap(),
            BOT_CONFIG_ENTITY,
            BOT_CONFIG_VERSION_KEY,
        )
        .err()
        .expect("future file version must be rejected");
        assert!(wrapped.is::<DocumentMigrationFailed>());
        for header in [
            "",
            "schema_version = 0\n",
            "schema_version = -1\n",
            "schema_version = \"3\"\n",
            "schema_version = 3.0\n",
        ] {
            let raw = format!("{header}id='bot-migrate-1'\nname='n'\nworkspace_id='p'\n");
            assert!(parse_config(&raw).is_err(), "{header:?}");
        }
    }

    #[test]
    fn conflicting_platform_fields_are_rejected_before_migrate() {
        let raw = r#"
schema_version = 2
id = "bot-migrate-1"
name = "原机器人"
workspace_id = "business-project"
app_id = "cli_flat"
platform = "feishuChina"
platform_config = { app_id = "cli_nested", trusted_open_ids = [], trusted_chat_ids = [] }
enabled = true
tools_enabled = false
trusted_open_ids = ["ou_original"]
trusted_chat_ids = ["oc_original"]
config_revision = 9
created_at = 100
updated_at = 200
"#;
        assert!(parse_config(raw).is_err());
        let nested = serde_json::json!({
            "schema_version": 3,
            "id": "bot-migrate-1",
            "name": "原机器人",
            "workspace_id": "business-project",
            "platform": "feishuChina",
            "platform_config": {
                "app_id": "cli_nested",
                "trusted_open_ids": [],
                "trusted_chat_ids": []
            },
            "app_id": "cli_flat",
            "enabled": true,
            "tools_enabled": false,
            "config_revision": 9,
            "created_at": 100,
            "updated_at": 200
        });
        assert!(decode_config_snapshot(nested).is_err());
    }
}
