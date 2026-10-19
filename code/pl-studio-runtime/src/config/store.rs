use std::collections::BTreeSet;
use std::env;
use std::fs::{self, OpenOptions};
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::{PureError, Result};

use super::credential::{CredentialStore, MemoryCredentialStore, SystemCredentialStore};
use super::{STUDIO_CONFIG_DIR_NAME, STUDIO_CONFIG_FILE_NAME, StudioConfig, StudioRole};
use pl_protocol::ThreadModeId;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfigPaths {
    config_dir: PathBuf,
    config_file: PathBuf,
}

#[derive(Clone)]
pub struct ConfigStore {
    paths: ConfigPaths,
    credentials: Arc<dyn CredentialStore>,
}

impl std::fmt::Debug for ConfigStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ConfigStore")
            .field("paths", &self.paths)
            .finish_non_exhaustive()
    }
}

impl ConfigPaths {
    pub fn for_current_user() -> Result<Self> {
        Ok(Self::from_home(user_home_dir()?))
    }

    pub fn from_home(home: impl Into<PathBuf>) -> Self {
        let config_dir = home.into().join(STUDIO_CONFIG_DIR_NAME);
        Self::from_config_dir(config_dir)
    }

    pub fn from_config_dir(config_dir: impl Into<PathBuf>) -> Self {
        let config_dir = config_dir.into();
        let config_file = config_dir.join(STUDIO_CONFIG_FILE_NAME);
        Self {
            config_dir,
            config_file,
        }
    }

    pub fn config_dir(&self) -> &Path {
        &self.config_dir
    }

    pub fn config_file(&self) -> &Path {
        &self.config_file
    }

    /// 用户 Agent Profile 的独立 TOML 目录。
    pub fn agents_dir(&self) -> PathBuf {
        self.config_dir.join("agents")
    }

    /// 用户工作模式的独立 JSON 目录；每个文件保存一份完整编辑文档。
    pub fn modes_dir(&self) -> PathBuf {
        self.config_dir.join("modes")
    }
}

impl ConfigStore {
    pub fn default_app() -> Result<Self> {
        Ok(Self::with_credential_store(
            ConfigPaths::for_current_user()?,
            Arc::new(SystemCredentialStore::default()),
        ))
    }

    pub fn for_studio_home(studio_home: impl Into<PathBuf>) -> Self {
        Self::with_credential_store(
            ConfigPaths::from_config_dir(studio_home),
            Arc::new(SystemCredentialStore::default()),
        )
    }

    /// 创建使用进程内凭据存储的隔离配置实例。
    ///
    /// 生产桌面应用必须使用 [`Self::default_app`]，避免测试、fixture 或 driver 修改用户的系统凭据库。
    pub fn new(paths: ConfigPaths) -> Self {
        Self::with_credential_store(paths, Arc::new(MemoryCredentialStore::default()))
    }

    fn with_credential_store(paths: ConfigPaths, credentials: Arc<dyn CredentialStore>) -> Self {
        Self { paths, credentials }
    }

    pub fn paths(&self) -> &ConfigPaths {
        &self.paths
    }

    pub fn load_ssh_password(&self, alias: &str) -> Result<Option<String>> {
        self.credentials
            .load_ssh(alias)
            .map(|secret| secret.filter(|value| !value.trim().is_empty()))
    }

    pub fn save_ssh_password(&self, alias: &str, secret: &str) -> Result<()> {
        self.credentials.save_ssh(alias, secret)
    }

    pub fn delete_ssh_password(&self, alias: &str) -> Result<()> {
        self.credentials.delete_ssh(alias)
    }

    /// 判断 `config.toml` 是否真实缺失。
    ///
    /// 只认路径条目本身不存在（`NotFound`）为缺失；权限、元数据或符号链接异常一律返回
    /// `Err`，避免把“存在但不可访问/已损坏”的配置误判为缺失，从而静默落入默认配置或
    /// 在保存路径上覆盖未知文件。
    fn config_absent(&self) -> Result<bool> {
        match fs::symlink_metadata(self.paths.config_file()) {
            Ok(_) => Ok(false),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(true),
            Err(error) => Err(self.config_path_error(error.into())),
        }
    }

    pub fn load_or_default(&self) -> Result<StudioConfig> {
        if self.config_absent()? {
            let mut config = StudioConfig::default_config()?;
            self.hydrate_credentials(&mut config)?;
            return Ok(config);
        }
        let content = fs::read_to_string(self.paths.config_file())
            .map_err(|error| self.config_path_error(error.into()))?;
        let mut config =
            parse_current_config(&content).map_err(|error| self.config_path_error(error))?;
        self.hydrate_credentials(&mut config)?;
        Ok(config)
    }

    /// 启动期读取并校验配置。
    ///
    /// 只有 `config.toml` 缺失时才采用内存默认配置。其余任何未知/未来版本、不可解析、
    /// 当前 schema 校验失败或含内联凭据的输入都保留原字节并返回错误，不重写文件、
    /// 也不替换为默认配置；已知 18/19/20/21 版本走数据保全式迁移路径。
    pub(crate) fn load_for_startup(
        &self,
    ) -> std::result::Result<StudioConfig, super::ConfigRuntimeError> {
        if self.config_absent()? {
            let mut config = StudioConfig::default_config()?;
            self.hydrate_credentials(&mut config)?;
            return Ok(config);
        }
        let content = fs::read(self.paths.config_file())
            .map_err(|error| self.config_path_error(error.into()))?;
        // Version dispatch precedes the strict parse so the supported 18/19/20/21 configs reach
        // their data-preserving migration instead of failing current-schema validation.
        #[derive(serde::Deserialize)]
        struct Version {
            schema_version: u32,
        }
        if let Some(version) = std::str::from_utf8(&content)
            .ok()
            .and_then(|text| toml::from_str::<Version>(text).ok())
            .map(|version| version.schema_version)
            .filter(|version| matches!(version, 18..=21))
        {
            return self
                .migrate_legacy_config_for_startup(&content, version)
                .map_err(|error| {
                    super::ConfigRuntimeError::Migration(self.config_path_error(error))
                });
        }
        // Unknown/future versions, malformed TOML and current-schema validation failures
        // all fail closed here: the original bytes stay on disk untouched.
        let mut config =
            parse_startup_config(&content).map_err(|error| self.config_path_error(error))?;
        self.hydrate_credentials(&mut config)?;
        Ok(config)
    }

    /// 为配置文件错误附上 `config.toml` 路径以便定位。保持 `Io` 类别不变，只消化
    /// `PureError` 文本，不引入任何配置内容、token 或凭据。
    fn config_path_error(&self, error: PureError) -> PureError {
        match error {
            PureError::Io(error) => PureError::Io(std::io::Error::new(
                error.kind(),
                format!(
                    "failed to access Studio config {}: {error}",
                    self.paths.config_file().display()
                ),
            )),
            PureError::ConfigError(message) => PureError::ConfigError(format!(
                "failed to load Studio config {}: {message}",
                self.paths.config_file().display()
            )),
            other => other,
        }
    }

    fn migrate_legacy_config_for_startup(
        &self,
        original: &[u8],
        source_version: u32,
    ) -> Result<StudioConfig> {
        self.migrate_legacy_config_for_startup_with(original, source_version, |path, content| {
            pl_tool::workspace::write_file_atomically(path, content).map_err(Into::into)
        })
    }

    fn migrate_legacy_config_for_startup_with(
        &self,
        original: &[u8],
        source_version: u32,
        replace: impl FnOnce(&Path, &[u8]) -> Result<()>,
    ) -> Result<StudioConfig> {
        let text = std::str::from_utf8(original).map_err(|error| {
            PureError::ConfigError(format!("invalid schema {source_version} UTF-8: {error}"))
        })?;
        let rewritten = rewrite_legacy_deepseek_standalone_dialect(text)?;
        let rewritten = migrate_model_identifiers(&rewritten)?;
        let mut config = parse_typed_config(&rewritten)?;
        reject_inline_credentials(&config)?;
        match source_version {
            18 => {
                config.disabled_system_agents.remove("planner");
                migrate_legacy_planner_route(&mut config, source_version)?;
            }
            19 => migrate_legacy_planner_route(&mut config, source_version)?,
            20 | 21 => {}
            other => {
                return Err(PureError::ConfigError(format!(
                    "unsupported Studio config schema version: {other}"
                )));
            }
        }
        config.schema_version = super::STUDIO_CONFIG_SCHEMA_VERSION;
        config.validate_declarations()?;
        let persisted = serialize_persisted_config(&config)?;
        // Provider identities do not change. Read credentials before committing; never rewrite them.
        self.hydrate_credentials(&mut config)?;
        let backup = write_config_backup(self.paths.config_file(), original, "migrated")?;
        replace(self.paths.config_file(), persisted.as_bytes())?;
        tracing::info!(
            backup_path = %backup.display(),
            source_version,
            target_version = super::STUDIO_CONFIG_SCHEMA_VERSION,
            "migrated Studio config"
        );
        Ok(config)
    }

    pub fn load(&self) -> Result<StudioConfig> {
        let content = fs::read_to_string(self.paths.config_file())
            .map_err(|error| self.config_path_error(error.into()))?;
        let mut config =
            parse_current_config(&content).map_err(|error| self.config_path_error(error))?;
        self.hydrate_credentials(&mut config)?;
        Ok(config)
    }

    pub fn save(&self, config: &StudioConfig) -> Result<()> {
        config.validate_declarations()?;
        let persisted_provider_ids = self.persisted_provider_ids()?;
        let content = serialize_persisted_config(config)?;
        fs::create_dir_all(self.paths.config_dir())?;
        let previous = self.apply_credentials(config, persisted_provider_ids)?;
        if let Err(error) =
            pl_tool::workspace::write_file_atomically(self.paths.config_file(), content.as_bytes())
        {
            self.restore_credentials(&previous);
            return Err(error.into());
        }
        Ok(())
    }

    pub fn init_default(&self) -> Result<StudioConfig> {
        if !self.config_absent()? {
            return Err(PureError::ConfigError(format!(
                "config already exists: {}",
                self.paths.config_file().display()
            )));
        }
        let config = StudioConfig::default_config()?;
        self.save(&config)?;
        Ok(config)
    }

    fn hydrate_credentials(&self, config: &mut StudioConfig) -> Result<()> {
        for (provider_id, provider) in &mut config.models.providers {
            provider.bearer_token = self.credentials.load(provider_id.as_str())?;
        }
        Ok(())
    }

    fn persisted_provider_ids(&self) -> Result<BTreeSet<String>> {
        if self.config_absent()? {
            return Ok(BTreeSet::new());
        }
        let content = fs::read_to_string(self.paths.config_file())
            .map_err(|error| self.config_path_error(error.into()))?;
        let persisted =
            parse_current_config(&content).map_err(|error| self.config_path_error(error))?;
        Ok(persisted
            .models
            .providers
            .keys()
            .map(|provider_id| provider_id.as_str().to_string())
            .collect())
    }

    fn apply_credentials(
        &self,
        config: &StudioConfig,
        mut provider_ids: BTreeSet<String>,
    ) -> Result<Vec<(String, Option<String>)>> {
        let mut previous = Vec::new();
        provider_ids.extend(
            config
                .models
                .providers
                .keys()
                .map(|provider_id| provider_id.as_str().to_string()),
        );
        for provider_id in provider_ids {
            let desired = config
                .models
                .providers
                .iter()
                .find(|(candidate, _)| candidate.as_str() == provider_id)
                .and_then(|(_, provider)| provider.bearer_token.as_deref())
                .filter(|secret| !secret.trim().is_empty());
            let old = self.credentials.load(&provider_id)?;
            previous.push((provider_id.clone(), old));
            let result = match desired {
                Some(secret) => self.credentials.save(&provider_id, secret),
                None => self.credentials.delete(&provider_id),
            }
            .and_then(|()| {
                let actual = self.credentials.load(&provider_id)?;
                if actual.as_deref() == desired {
                    Ok(())
                } else {
                    Err(PureError::ConfigError(format!(
                        "system credential verification failed for provider {provider_id}"
                    )))
                }
            });
            if let Err(error) = result {
                self.restore_credentials(&previous);
                return Err(error);
            }
        }
        Ok(previous)
    }

    fn restore_credentials(&self, previous: &[(String, Option<String>)]) {
        for (provider_id, secret) in previous.iter().rev() {
            let result = match secret {
                Some(secret) => self.credentials.save(provider_id, secret),
                None => self.credentials.delete(provider_id),
            };
            if let Err(error) = result {
                tracing::error!(%error, provider_id, "回滚系统凭据失败");
            }
        }
    }
}

fn rewrite_legacy_deepseek_standalone_dialect(text: &str) -> Result<String> {
    let mut table: toml::Table = toml::from_str(text).map_err(|error| {
        PureError::ConfigError(format!(
            "invalid Studio config TOML{}",
            toml_error_location(text, &error)
        ))
    })?;
    rewrite_legacy_deepseek_standalone_in_providers(&mut table);
    toml::to_string(&table).map_err(|error| {
        PureError::ConfigError(format!(
            "failed to rewrite Studio config dialect token: {error}"
        ))
    })
}

fn rewrite_legacy_deepseek_standalone_in_providers(table: &mut toml::Table) {
    let Some(toml::Value::Table(models)) = table.get_mut("models") else {
        return;
    };
    let Some(toml::Value::Table(providers)) = models.get_mut("providers") else {
        return;
    };
    let provider_ids: Vec<String> = providers.keys().cloned().collect();
    for provider_id in provider_ids {
        let Some(toml::Value::Table(provider)) = providers.get_mut(&provider_id) else {
            continue;
        };
        // Design/token path is `service_capabilities`; persisted ProviderConfig uses `capabilities`.
        for field in ["service_capabilities", "capabilities"] {
            rewrite_legacy_web_search_standalone_token(provider.get_mut(field));
        }
    }
}

fn rewrite_legacy_web_search_standalone_token(capabilities: Option<&mut toml::Value>) {
    let Some(toml::Value::Table(capabilities)) = capabilities else {
        return;
    };
    let Some(toml::Value::Table(web_search)) = capabilities.get_mut("web_search") else {
        return;
    };
    let Some(toml::Value::String(standalone)) = web_search.get_mut("standalone") else {
        return;
    };
    if standalone == "deep_seek_anthropic_messages" {
        *standalone = "deep_seek_tools_api".to_string();
    }
}

fn migrate_legacy_planner_route(config: &mut StudioConfig, source_version: u32) -> Result<()> {
    let planner_route = config
        .models
        .routes
        .remove(&StudioRole::Planner.id())
        .ok_or_else(|| {
            PureError::ConfigError(format!(
                "schema {source_version} config is missing planner model route"
            ))
        })?;
    config.mode_model_routes = std::collections::BTreeMap::from([
        (ThreadModeId::simple(), planner_route.clone()),
        (ThreadModeId::task(), planner_route),
    ]);
    Ok(())
}

fn parse_current_config(content: &str) -> Result<StudioConfig> {
    parse_config(content)
}

fn parse_startup_config(content: &[u8]) -> Result<StudioConfig> {
    let content = std::str::from_utf8(content).map_err(|error| {
        PureError::ConfigError(format!("failed to parse Studio config as UTF-8: {error}"))
    })?;
    parse_config(content)
}

fn parse_config(content: &str) -> Result<StudioConfig> {
    let config = parse_typed_config(content)?;
    reject_inline_credentials(&config)?;
    config.validate_declarations()?;
    Ok(config)
}

fn parse_typed_config(content: &str) -> Result<StudioConfig> {
    // 第一遍只做 TOML 语法解析；语法诊断由解析器生成，不含文档内容。
    if let Err(error) = toml::from_str::<toml::Table>(content) {
        return Err(PureError::ConfigError(format!(
            "invalid Studio config TOML{}",
            toml_error_location(content, &error)
        )));
    }
    // 第二遍做结构/类型解码；serde 诊断可能回显字段值，因此只保留类别与行/列位置。
    toml::from_str(content).map_err(|error| {
        PureError::ConfigError(format!(
            "Studio config TOML does not match the current schema{}",
            toml_error_location(content, &error)
        ))
    })
}

/// 仅按错误的字节 span 计算 1-based 行/列用于定位；刻意不回显任何原文或字段值。
fn toml_error_location(content: &str, error: &toml::de::Error) -> String {
    let Some(span) = error.span() else {
        return String::new();
    };
    let Some(prefix) = content.get(..span.start) else {
        return String::new();
    };
    let line = prefix.bytes().filter(|byte| *byte == b'\n').count() + 1;
    let column = prefix
        .rfind('\n')
        .map_or(prefix.len(), |newline| prefix.len() - newline - 1)
        + 1;
    format!(" at line {line}, column {column}")
}

fn reject_inline_credentials(config: &StudioConfig) -> Result<()> {
    if config
        .models
        .providers
        .values()
        .any(|provider| provider.bearer_token.is_some())
    {
        return Err(PureError::ConfigError(
            "current schema forbids inline provider bearer_token; use the Studio credential store"
                .to_string(),
        ));
    }
    Ok(())
}

/// Decode legacy identifiers only at the migration boundary. Never rewrite arbitrary vendor bodies.
fn migrate_model_identifiers(text: &str) -> Result<String> {
    let mut value: toml::Value =
        toml::from_str(text).map_err(|_| PureError::ConfigError("invalid legacy config".into()))?;
    if let Some(providers) = value
        .get_mut("models")
        .and_then(|v| v.get_mut("providers"))
        .and_then(toml::Value::as_table_mut)
    {
        for (_, provider) in providers.iter_mut() {
            if let Some(catalog) = provider.get_mut("catalog") {
                for key in ["models", "additional_models"] {
                    if let Some(models) = catalog.get_mut(key).and_then(toml::Value::as_array_mut) {
                        for model in models {
                            let table = model.as_table_mut().ok_or_else(|| {
                                PureError::ConfigError("invalid legacy model declaration".into())
                            })?;
                            if let Some(legacy) = table.remove("slug") {
                                if table
                                    .get("model_id")
                                    .is_some_and(|current| current != &legacy)
                                {
                                    return Err(PureError::ConfigError(
                                        "conflicting model identifiers in legacy config".into(),
                                    ));
                                }
                                table.insert("model_id".into(), legacy);
                            }
                        }
                    }
                }
            }
        }
    }
    toml::to_string(&value)
        .map_err(|_| PureError::ConfigError("could not encode migrated config".into()))
}

fn write_config_backup(config_path: &Path, content: &[u8], kind: &str) -> Result<PathBuf> {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    write_config_backup_at(config_path, content, kind, stamp)
}

fn write_config_backup_at(
    config_path: &Path,
    content: &[u8],
    kind: &str,
    stamp: u128,
) -> Result<PathBuf> {
    for collision in 0..u32::MAX {
        let backup_path = config_backup_path(config_path, kind, stamp, collision);
        let mut backup = match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&backup_path)
        {
            Ok(backup) => backup,
            Err(error) if error.kind() == ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error.into()),
        };
        let result = backup.write_all(content).and_then(|()| backup.sync_all());
        if let Err(error) = result {
            drop(backup);
            let _ = fs::remove_file(&backup_path);
            return Err(error.into());
        }
        return Ok(backup_path);
    }
    Err(PureError::ConfigError(
        "could not allocate a unique Studio config backup path".to_string(),
    ))
}

fn config_backup_path(config_path: &Path, kind: &str, stamp: u128, collision: u32) -> PathBuf {
    let file_name = config_path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(super::STUDIO_CONFIG_FILE_NAME);
    let suffix = if collision == 0 {
        format!("{kind}.{stamp}.bak")
    } else {
        format!("{kind}.{stamp}.{collision}.bak")
    };
    config_path.with_file_name(format!("{file_name}.{suffix}"))
}

fn serialize_persisted_config(config: &StudioConfig) -> Result<String> {
    let mut persisted = config.clone();
    clear_inline_credentials(&mut persisted);
    toml::to_string_pretty(&persisted).map_err(|error| {
        PureError::ConfigError(format!("failed to serialize Studio config: {error}"))
    })
}

fn clear_inline_credentials(config: &mut StudioConfig) {
    for provider in config.models.providers.values_mut() {
        provider.bearer_token = None;
    }
}

fn user_home_dir() -> Result<PathBuf> {
    const HOME_VARS: &[&str] = &["HOME", "USERPROFILE"];

    HOME_VARS
        .iter()
        .filter_map(env::var_os)
        .map(PathBuf::from)
        .find(|path| !path.as_os_str().is_empty())
        .ok_or_else(|| PureError::ConfigError("could not resolve user home directory".to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_model::config::{ProviderCapabilitySelection, ProviderId};
    use pl_model::provider::StandaloneWebSearchDialect;
    use pl_protocol::search::WebSearchMode;

    fn isolated_store() -> (tempfile::TempDir, ConfigStore) {
        let directory = tempfile::tempdir().expect("isolated config directory");
        let store = ConfigStore::new(ConfigPaths::from_config_dir(directory.path()));
        (directory, store)
    }

    fn write_table(path: &Path, table: &toml::Table) {
        fs::write(path, toml::to_string(table).expect("serialize test config"))
            .expect("write test config");
    }

    #[test]
    fn schema_21_model_ids_migrate_without_losing_routes_overrides_or_credentials() {
        use pl_model::{
            config::ProviderModelCatalogConfig, model::ModelInfo, provider::ProviderConnectionMode,
        };
        let (_directory, store) = isolated_store();
        let mut config = StudioConfig::default_config().unwrap();
        let id = ProviderId::new("deepseek").unwrap();
        let provider = config.models.providers.get_mut(&id).unwrap();
        provider.bearer_token = Some("synthetic-migration-secret".into());
        if let ProviderModelCatalogConfig::Bundled {
            additional_models,
            connection_overrides,
            auto_compact_overrides,
            ..
        } = &mut provider.catalog
        {
            additional_models.push(ModelInfo::compatible("exact-Unchanged-ID"));
            connection_overrides.insert("exact-Unchanged-ID".into(), ProviderConnectionMode::Http);
            auto_compact_overrides.insert("exact-Unchanged-ID".into(), 1234);
        }
        store.save(&config).unwrap();
        let path = store.paths.config_file();
        let mut table = read_table(path);
        table["schema_version"] = 21.into();
        let model = table
            .get_mut("models")
            .unwrap()
            .get_mut("providers")
            .unwrap()
            .get_mut("deepseek")
            .unwrap()
            .get_mut("catalog")
            .unwrap()
            .get_mut("additional_models")
            .unwrap()
            .as_array_mut()
            .unwrap()[0]
            .as_table_mut()
            .unwrap();
        let identifier = model.remove("model_id").unwrap();
        model.insert("slug".into(), identifier);
        write_table(path, &table);
        let original = fs::read(path).unwrap();
        let loaded = store.load_for_startup().unwrap();
        assert_eq!(loaded, config);
        assert_eq!(
            fs::read(migrated_backups(path).pop().unwrap()).unwrap(),
            original
        );
        let persisted = fs::read(path).unwrap();
        assert_eq!(store.load_for_startup().unwrap(), config);
        assert_eq!(fs::read(path).unwrap(), persisted);
        assert_eq!(migrated_backups(path).len(), 1);
    }

    #[test]
    fn conflicting_legacy_model_identifiers_leave_original_file_untouched() {
        let (_directory, store) = isolated_store();
        let mut config = StudioConfig::default_config().unwrap();
        if let pl_model::config::ProviderModelCatalogConfig::Bundled {
            additional_models, ..
        } = &mut config
            .models
            .providers
            .get_mut(&ProviderId::new("deepseek").unwrap())
            .unwrap()
            .catalog
        {
            additional_models.push(pl_model::model::ModelInfo::compatible("current-id"));
        }
        store.save(&config).unwrap();
        let path = store.paths.config_file();
        let mut table = read_table(path);
        table["schema_version"] = 21.into();
        let model = table
            .get_mut("models")
            .unwrap()
            .get_mut("providers")
            .unwrap()
            .get_mut("deepseek")
            .unwrap()
            .get_mut("catalog")
            .unwrap()
            .get_mut("additional_models")
            .unwrap()
            .as_array_mut()
            .unwrap()[0]
            .as_table_mut()
            .unwrap();
        model.insert("slug".into(), "different-id".into());
        write_table(path, &table);
        let original = fs::read(path).unwrap();
        assert!(store.load_for_startup().is_err());
        assert_eq!(fs::read(path).unwrap(), original);
        assert!(migrated_backups(path).is_empty());
    }

    fn read_table(path: &Path) -> toml::Table {
        toml::from_str(&fs::read_to_string(path).expect("read test config"))
            .expect("parse test config")
    }

    fn migrated_backups(config_file: &Path) -> Vec<PathBuf> {
        let Some(directory) = config_file.parent() else {
            return Vec::new();
        };
        let prefix = format!(
            "{}.migrated.",
            config_file
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or(super::super::STUDIO_CONFIG_FILE_NAME)
        );
        fs::read_dir(directory)
            .expect("read config directory")
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name.starts_with(&prefix) && name.ends_with(".bak"))
            })
            .collect()
    }

    fn legacy_web_search_table() -> toml::Table {
        let mut web_search = toml::Table::new();
        web_search.insert("hosted_responses".into(), toml::Value::Boolean(false));
        web_search.insert(
            "hosted_dialect".into(),
            toml::Value::String("open_ai_responses".into()),
        );
        web_search.insert(
            "standalone".into(),
            toml::Value::String("deep_seek_anthropic_messages".into()),
        );
        web_search
    }

    fn explicit_legacy_deepseek_capabilities() -> toml::Table {
        let mut prompt_cache = toml::Table::new();
        prompt_cache.insert(
            "dialect".into(),
            toml::Value::String("implicit_prefix".into()),
        );
        let mut responses_tools = toml::Table::new();
        responses_tools.insert(
            "programmatic_tool_calling".into(),
            toml::Value::Boolean(false),
        );
        let mut capabilities = toml::Table::new();
        capabilities.insert("source".into(), toml::Value::String("explicit".into()));
        capabilities.insert("files".into(), toml::Value::String("deepSeek".into()));
        capabilities.insert("remote_compaction".into(), toml::Value::Boolean(false));
        capabilities.insert(
            "web_search".into(),
            toml::Value::Table(legacy_web_search_table()),
        );
        capabilities.insert("prompt_cache".into(), toml::Value::Table(prompt_cache));
        capabilities.insert(
            "responses_tools".into(),
            toml::Value::Table(responses_tools),
        );
        capabilities.insert(
            "historyInstructionRole".into(),
            toml::Value::String("developer".into()),
        );
        capabilities
    }

    fn declared_service_capabilities() -> toml::Table {
        let mut capabilities = toml::Table::new();
        capabilities.insert("files".into(), toml::Value::String("deepSeek".into()));
        capabilities.insert("remote_compaction".into(), toml::Value::Boolean(false));
        capabilities.insert(
            "web_search".into(),
            toml::Value::Table(legacy_web_search_table()),
        );
        capabilities
    }

    #[test]
    fn schema_20_rewrites_legacy_deepseek_standalone_token_and_preserves_fields() {
        let (_directory, store) = isolated_store();
        let mut config = StudioConfig::default_config().expect("bundled defaults");
        config.deepseek_web_search.enabled = false;
        config.web_search.mode = WebSearchMode::Live;
        config.instructions.user = "keep deep_seek_anthropic_messages in user text".into();
        store.save(&config).expect("save current schema");

        let path = store.paths.config_file();
        let mut table = read_table(path);
        table.insert("schema_version".into(), toml::Value::Integer(20));
        let providers = table
            .get_mut("models")
            .and_then(toml::Value::as_table_mut)
            .and_then(|models| models.get_mut("providers"))
            .and_then(toml::Value::as_table_mut)
            .expect("providers table");
        let deepseek = providers
            .get_mut("deepseek")
            .and_then(toml::Value::as_table_mut)
            .expect("deepseek provider");
        deepseek.insert(
            "capabilities".into(),
            toml::Value::Table(explicit_legacy_deepseek_capabilities()),
        );
        deepseek.insert(
            "service_capabilities".into(),
            toml::Value::Table(declared_service_capabilities()),
        );
        table
            .get_mut("deepseek_web_search")
            .and_then(toml::Value::as_table_mut)
            .expect("deepseek_web_search")
            .remove("fetch_enabled");
        write_table(path, &table);
        let original = fs::read(path).expect("original schema 20 bytes");

        let loaded = store.load_for_startup().expect("schema 20 migrates");
        let provider_id = ProviderId::new("deepseek").expect("provider id");
        let provider = loaded
            .models
            .providers
            .get(&provider_id)
            .expect("deepseek provider");
        let ProviderCapabilitySelection::Explicit(capabilities) = &provider.capabilities else {
            panic!("migrated provider must keep explicit capabilities");
        };

        assert_eq!(
            loaded.schema_version,
            super::super::STUDIO_CONFIG_SCHEMA_VERSION
        );
        assert_eq!(loaded.schema_version, 22);
        assert_eq!(
            capabilities.web_search.standalone,
            Some(StandaloneWebSearchDialect::DeepSeekToolsApi)
        );
        assert!(!capabilities.web_search.hosted_responses);
        assert_eq!(loaded.mode_model_routes, config.mode_model_routes);
        assert_eq!(loaded.models.routes, config.models.routes);
        assert_eq!(loaded.web_search, config.web_search);
        assert!(!loaded.deepseek_web_search.enabled);
        assert!(loaded.deepseek_web_search.fetch_enabled);
        assert_eq!(loaded.instructions.user, config.instructions.user);
        assert_eq!(provider.name, config.models.providers[&provider_id].name);
        assert_eq!(
            provider.base_url,
            config.models.providers[&provider_id].base_url
        );
        assert_eq!(
            provider.preset,
            config.models.providers[&provider_id].preset
        );

        let persisted = fs::read_to_string(path).expect("read migrated config");
        let persisted_table: toml::Table =
            toml::from_str(&persisted).expect("parse migrated config");
        assert_eq!(persisted_table["schema_version"].as_integer(), Some(22));
        assert_eq!(
            persisted_table["models"]["providers"]["deepseek"]["capabilities"]["web_search"]
                ["standalone"]
                .as_str(),
            Some("deep_seek_tools_api")
        );
        assert_eq!(
            loaded.instructions.user,
            "keep deep_seek_anthropic_messages in user text"
        );
        assert!(
            persisted_table
                .get("models")
                .and_then(|models| models.get("providers"))
                .and_then(|providers| providers.get("deepseek"))
                .and_then(|provider| provider.get("service_capabilities"))
                .is_none(),
            "canonical persist drops the untyped service_capabilities table"
        );

        let backups = migrated_backups(path);
        assert_eq!(backups.len(), 1, "one migration backup");
        assert_eq!(fs::read(&backups[0]).expect("read backup"), original);
    }

    #[test]
    fn schema_20_without_legacy_token_preserves_routes() {
        let (_directory, store) = isolated_store();
        let config = StudioConfig::default_config().expect("bundled defaults");
        store.save(&config).expect("save current schema");
        let path = store.paths.config_file();
        let mut table = read_table(path);
        table.insert("schema_version".into(), toml::Value::Integer(20));
        write_table(path, &table);

        let loaded = store
            .load_for_startup()
            .expect("schema 20 without dialect token migrates");
        assert_eq!(loaded.schema_version, 22);
        assert_eq!(loaded.mode_model_routes, config.mode_model_routes);
        assert_eq!(loaded.models.routes, config.models.routes);
        assert_eq!(
            loaded.models.routes.len(),
            4,
            "four child-agent routes remain"
        );
        assert_eq!(loaded.models.providers, config.models.providers);
        assert_eq!(loaded.web_search, config.web_search);
        assert_eq!(loaded.deepseek_web_search, config.deepseek_web_search);
        assert!(loaded.deepseek_web_search.fetch_enabled);
    }

    #[test]
    fn unknown_future_schema_fails_closed_without_rewrite() {
        let (_directory, store) = isolated_store();
        let config = StudioConfig::default_config().expect("bundled defaults");
        store.save(&config).expect("save current schema");
        let path = store.paths.config_file();
        let mut table = read_table(path);
        table.insert("schema_version".into(), toml::Value::Integer(23));
        write_table(path, &table);
        let original = fs::read(path).expect("original future-schema bytes");

        let error = store
            .load_for_startup()
            .expect_err("future schema must fail closed");
        assert!(
            matches!(
                error,
                super::super::ConfigRuntimeError::Core(PureError::ConfigError(_))
            ),
            "future schema is a config error: {error}"
        );
        assert_eq!(fs::read(path).expect("reread config"), original);
        assert!(
            migrated_backups(path).is_empty(),
            "no backup for fail-closed load"
        );
    }

    #[test]
    fn schema_20_migration_failure_does_not_persist() {
        let (_directory, store) = isolated_store();
        let config = StudioConfig::default_config().expect("bundled defaults");
        store.save(&config).expect("save current schema");
        let path = store.paths.config_file();
        let mut table = read_table(path);
        table.insert("schema_version".into(), toml::Value::Integer(20));
        let routes = table
            .get_mut("models")
            .and_then(toml::Value::as_table_mut)
            .and_then(|models| models.get_mut("routes"))
            .and_then(toml::Value::as_table_mut)
            .expect("role routes");
        let explorer = routes
            .get_mut("explorer")
            .and_then(toml::Value::as_table_mut)
            .expect("explorer route");
        explorer.insert(
            "provider".into(),
            toml::Value::String("missing-provider".into()),
        );
        write_table(path, &table);
        let original = fs::read(path).expect("original invalid schema 20 bytes");

        let error = store
            .load_for_startup()
            .expect_err("invalid schema 20 must not migrate");
        assert!(
            matches!(
                error,
                super::super::ConfigRuntimeError::Migration(PureError::ConfigError(_))
            ),
            "migration failure is a config error: {error}"
        );
        assert_eq!(fs::read(path).expect("reread config"), original);
        assert!(
            migrated_backups(path).is_empty(),
            "backup is written only after validation succeeds"
        );
    }
}
