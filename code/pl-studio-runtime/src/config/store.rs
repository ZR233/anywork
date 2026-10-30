use std::env;
use std::fs::{self, OpenOptions};
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::{PureError, Result};

use super::credential::{CredentialStore, MemoryCredentialStore, SystemCredentialStore};
use super::{STUDIO_CONFIG_DIR_NAME, STUDIO_CONFIG_FILE_NAME, StudioConfig};
#[cfg(test)]
use pl_protocol::ThreadModeId;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfigPaths {
    config_dir: PathBuf,
    config_file: PathBuf,
}

#[derive(Clone)]
pub struct ConfigStore {
    paths: ConfigPaths,
    pub(super) credentials: Arc<dyn CredentialStore>,
    observed: Arc<std::sync::Mutex<Option<super::credential_commit::Baseline>>>,
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

    pub(super) fn with_credential_store(
        paths: ConfigPaths,
        credentials: Arc<dyn CredentialStore>,
    ) -> Self {
        Self {
            paths,
            credentials,
            observed: Arc::new(std::sync::Mutex::new(None)),
        }
    }

    /// 测试专用：用调用方持有的内存凭据库构造 store。
    ///
    /// 迁移专项测试需要观察"接续路径是否复制了旧 `provider:<id>` 关联"，因此必须与 fixture 共享
    /// 同一个凭据库；这不是生产构造入口，也不改变任何运行时行为。
    #[cfg(test)]
    pub(super) fn with_shared_credentials(
        paths: ConfigPaths,
        credentials: Arc<super::credential::MemoryCredentialStore>,
    ) -> Self {
        Self {
            paths,
            credentials,
            observed: Arc::new(std::sync::Mutex::new(None)),
        }
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

    pub(crate) fn bot_credentials(&self) -> crate::config::BotCredentialCapability {
        crate::config::BotCredentialCapability::new(self.credentials.clone())
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
        self.recover_credentials()?;
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
    /// 也不替换为默认配置；已知旧版本走数据保全式迁移路径。
    pub(crate) fn load_for_startup(
        &self,
    ) -> std::result::Result<StudioConfig, super::ConfigRuntimeError> {
        self.recover_credentials()?;
        // 中断的迁移必须先接续同一操作，不能先按当前结构解析后发布新旧混合状态。
        super::schema_migration::resume_for_startup(&self.paths, self.credentials.as_ref())
            .map_err(super::ConfigRuntimeError::Migration)?;
        let content = if self.config_absent()? {
            None
        } else {
            Some(fs::read(self.paths.config_file()).map_err(PureError::from)?)
        };
        let mut config = super::schema_migration::prepare_for_startup(
            &self.paths,
            self.credentials.as_ref(),
            content.as_deref(),
            &|path, bytes| {
                pl_tool::workspace::write_file_atomically(path, bytes).map_err(Into::into)
            },
        )
        .map_err(super::ConfigRuntimeError::Migration)?;
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

    #[cfg(test)]
    fn migrate_legacy_config_for_startup_with(
        &self,
        original: &[u8],
        source_version: u32,
        replace: impl Fn(&Path, &[u8]) -> Result<()>,
    ) -> Result<StudioConfig> {
        let text = std::str::from_utf8(original)
            .map_err(|error| PureError::ConfigError(error.to_string()))?;
        let loaded = super::document_migration::load_main(self.paths.config_file(), text)
            .map_err(|error| PureError::ConfigError(error.to_string()))?;
        assert_eq!(loaded.source_version, source_version);
        let mut config = super::schema_migration::prepare_for_startup(
            &self.paths,
            self.credentials.as_ref(),
            Some(original),
            &replace,
        )
        .map_err(|error| match error.downcast::<PureError>() {
            Ok(error) => error,
            Err(error) => PureError::ConfigError(error.to_string()),
        })?;
        self.hydrate_credentials(&mut config)?;
        Ok(config)
    }

    pub fn load(&self) -> Result<StudioConfig> {
        self.recover_credentials()?;
        let content = fs::read_to_string(self.paths.config_file())
            .map_err(|error| self.config_path_error(error.into()))?;
        let mut config =
            parse_current_config(&content).map_err(|error| self.config_path_error(error))?;
        self.hydrate_credentials(&mut config)?;
        Ok(config)
    }

    /// Saves against the binding last observed by this store. Existing unobserved files
    /// require a load first; the current system value is never adopted as an expected binding.
    pub fn save(&self, config: &StudioConfig) -> Result<()> {
        self.save_with(config, |path, bytes| {
            pl_tool::workspace::write_file_atomically(path, bytes).map_err(Into::into)
        })
    }

    fn save_with(
        &self,
        config: &StudioConfig,
        replace: impl Fn(&Path, &[u8]) -> Result<()>,
    ) -> Result<()> {
        let baseline = self
            .observed
            .lock()
            .map_err(|_| super::credential_commit::recovery_required())?
            .clone();
        let baseline = match baseline {
            Some(value) => value,
            None if self.config_absent()? => super::credential_commit::Baseline::default(),
            None => {
                return Err(PureError::ConfigError(
                    "load configuration before saving its credential bindings".into(),
                ));
            }
        };
        self.commit_credentials(
            &baseline,
            config,
            &super::credential_commit::CredentialIntents::default(),
            &replace,
        )?;
        self.remember_bindings(config)
    }

    pub(super) fn commit_config(
        &self,
        baseline: &StudioConfig,
        candidate: &StudioConfig,
        intents: &super::credential_commit::CredentialIntents,
    ) -> Result<()> {
        self.commit_config_with(baseline, candidate, intents, &|path, bytes| {
            pl_tool::workspace::write_file_atomically(path, bytes).map_err(Into::into)
        })
    }

    pub(crate) fn commit_config_with(
        &self,
        baseline: &StudioConfig,
        candidate: &StudioConfig,
        intents: &super::credential_commit::CredentialIntents,
        replace: &impl Fn(&Path, &[u8]) -> Result<()>,
    ) -> Result<()> {
        let baseline = super::credential_commit::Baseline::from_config(baseline)?;
        self.commit_credentials(&baseline, candidate, intents, replace)?;
        self.remember_bindings(candidate)
    }

    fn remember_bindings(&self, config: &StudioConfig) -> Result<()> {
        *self
            .observed
            .lock()
            .map_err(|_| super::credential_commit::recovery_required())? =
            Some(super::credential_commit::Baseline::from_config(config)?);
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
        let _locks = self.lock_accounts(config.models.accounts.keys().map(ToString::to_string))?;
        for (account_id, account) in &mut config.models.accounts {
            self.ensure_credential_available(account_id.as_str())?;
            if account.authentication == pl_protocol::studio::AccountAuthenticationMethod::ChatGpt {
                account.bearer_token = None;
                let payload = self
                    .credentials
                    .load_strict(account_id.as_str())?
                    .ok_or_else(|| {
                        PureError::ConfigError("ChatGPT credential is missing".into())
                    })?;
                let record: pl_model::protocol::chatgpt::ChatGptCredentialRecord =
                    serde_json::from_str(&payload).map_err(|_| {
                        PureError::ConfigError("ChatGPT credential is invalid".into())
                    })?;
                record
                    .validate()
                    .map_err(|error| PureError::ConfigError(error.to_string()))?;
                if account.chatgpt_account.as_ref() != Some(&record.account) {
                    return Err(PureError::ConfigError(
                        "ChatGPT credential identity conflicts with account".into(),
                    ));
                }
                account.chatgpt_session = Some(self.chatgpt_session(account_id.as_str(), &record)?);
                account.chatgpt_credentials = Some(record);
            } else {
                let secret = self.credentials.load(account_id.as_str())?;
                if secret.as_deref().is_some_and(|payload| {
                    serde_json::from_str::<pl_model::protocol::chatgpt::ChatGptCredentialRecord>(
                        payload,
                    )
                    .is_ok()
                }) {
                    // A crash or external inconsistency between config and keyring must fail
                    // closed, never reinterpret an OAuth record as an API Authorization value.
                    return Err(PureError::ConfigError(
                        "protected credential authentication does not match the account".into(),
                    ));
                }
                account.bearer_token = secret;
            }
        }
        self.remember_bindings(config)
    }
}

pub(super) fn parse_current_config(content: &str) -> Result<StudioConfig> {
    parse_config(content)
}

fn parse_config(content: &str) -> Result<StudioConfig> {
    let document =
        super::document_migration::load_current_main(Path::new(STUDIO_CONFIG_FILE_NAME), content)
            .map_err(|error| PureError::ConfigError(error.to_string()))?;
    document
        .into_config()
        .map_err(|error| PureError::ConfigError(error.to_string()))
}

#[cfg(test)]
pub(super) fn parse_migrated_config(content: &[u8]) -> Result<StudioConfig> {
    let text =
        std::str::from_utf8(content).map_err(|error| PureError::ConfigError(error.to_string()))?;
    parse_current_config(text)
}

pub(super) fn write_config_backup(
    config_path: &Path,
    content: &[u8],
    kind: &str,
) -> Result<PathBuf> {
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

pub(super) fn serialize_persisted_config(config: &StudioConfig) -> Result<String> {
    let mut persisted = config.clone();
    clear_inline_credentials(&mut persisted);
    super::document_migration::MainV28::from_config(&persisted)
        .and_then(|document| document.encode())
        .map_err(|error| {
            PureError::ConfigError(format!("failed to serialize Studio config: {error}"))
        })
}

fn clear_inline_credentials(config: &mut StudioConfig) {
    for account in config.models.accounts.values_mut() {
        account.bearer_token = None;
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
    use pl_model::config::{AccountCapabilitySelection, AccountId};
    use pl_model::protocol::StandaloneWebSearchDialect;
    use pl_protocol::search::WebSearchMode;

    #[test]
    fn chatgpt_schema_27_startup_preserves_api_credentials_routes_headers_and_overrides() {
        let (_directory, store) = isolated_store();
        let mut expected = StudioConfig::default_config().unwrap();
        let (id, account) = expected.models.accounts.iter_mut().next().unwrap();
        let id = id.to_string();
        let model_id = account.effective_catalog(None).unwrap()[0]
            .model
            .model_id
            .clone();
        account.set_model_enabled(&model_id, false).unwrap();
        account
            .set_model_auto_compact_override(&model_id, Some(32_000))
            .unwrap();
        match &mut account.catalog {
            pl_model::config::AccountModelCatalogConfig::Bundled {
                connection_overrides,
                ..
            }
            | pl_model::config::AccountModelCatalogConfig::Explicit {
                connection_overrides,
                ..
            } => {
                connection_overrides.insert(model_id, pl_model::protocol::ConnectionMode::Http);
            }
        }
        account.bearer_token = Some("migration-api-secret".into());
        account.http_headers = Some(
            [("x-fixture".into(), "preserved".into())]
                .into_iter()
                .collect(),
        );
        account.billing_kind = Some(pl_protocol::BillingKind::NoCharge);
        store.save(&expected).unwrap();
        let mut historical: toml::Value =
            toml::from_str(&std::fs::read_to_string(store.paths.config_file()).unwrap()).unwrap();
        historical["schema_version"] = 27.into();
        for (_, account) in historical["models"]["accounts"]
            .as_table_mut()
            .unwrap()
            .iter_mut()
        {
            account.as_table_mut().unwrap().remove("authentication");
        }
        let original = toml::to_string(&historical).unwrap();
        std::fs::write(store.paths.config_file(), &original).unwrap();
        let migrated = store.load_for_startup().unwrap();
        assert_eq!(migrated, expected);
        assert_eq!(
            migrated.models.accounts[&pl_model::config::AccountId::new(&id).unwrap()]
                .authentication,
            pl_protocol::studio::AccountAuthenticationMethod::ApiKey
        );
        assert_eq!(
            store.credentials.load_strict(&id).unwrap().as_deref(),
            Some("migration-api-secret")
        );
        let saved = std::fs::read_to_string(store.paths.config_file()).unwrap();
        assert!(saved.contains("schema_version = 28"));
        assert!(!saved.contains("migration-api-secret"));
        assert_eq!(store.load_for_startup().unwrap(), expected);
        assert!(
            std::fs::read_dir(store.paths.config_dir())
                .unwrap()
                .filter_map(|entry| entry.ok())
                .filter(|entry| entry.file_name().to_string_lossy().ends_with(".bak"))
                .any(|entry| std::fs::read_to_string(entry.path()).unwrap() == original)
        );
    }

    #[test]
    fn chatgpt_save_rolls_back_original_credentials_and_preserves_refresh_markers() {
        use pl_model::protocol::chatgpt::ChatGptCredentialRecord;
        use pl_protocol::studio::{AccountAuthenticationMethod, ChatGptAccountInfo};
        let (_directory, store) = isolated_store();
        let mut initial = StudioConfig::default_config().unwrap();
        let id = pl_model::config::AccountId::new("transaction-fixture").unwrap();
        let mut api = pl_model::config::builtin_account_catalog()
            .unwrap()
            .templates
            .into_iter()
            .find(|template| template.id.as_str() == "openai")
            .unwrap()
            .account;
        api.bearer_token = Some("original-api-key".into());
        api.bearer_token_env = None;
        initial.models.accounts.insert(id.clone(), api);
        store.save(&initial).unwrap();
        let original_bytes = fs::read(store.paths.config_file()).unwrap();
        let record = ChatGptCredentialRecord {
            schema_version: 1,
            registration_id: "transaction-registration".into(),
            account: ChatGptAccountInfo {
                issuer: "https://auth.openai.com".into(),
                subject: "fixture-subject".into(),
                client_id: "fixture-client".into(),
                email: None,
                plan_usage_enabled: true,
            },
            ext_agent_host_id: "urn:uuid:00000000-0000-4000-8000-000000000001".into(),
            access_token: "transaction-access".into(),
            refresh_token: "transaction-refresh".into(),
            id_token: "transaction-verified-id".into(),
            scopes: vec!["chatgpt.tokens.use.direct".into()],
            expires_at: crate::studio::unix_seconds() + 3600,
            earliest_refresh_at: None,
            refresh_in_flight: false,
        };
        let mut candidate = initial.clone();
        let account = candidate.models.accounts.get_mut(&id).unwrap();
        account.authentication = AccountAuthenticationMethod::ChatGpt;
        account.chatgpt_account = Some(record.account.clone());
        account.chatgpt_credentials = Some(record.clone());
        account.chatgpt_session = Some(store.chatgpt_session(id.as_str(), &record).unwrap());
        account.bearer_token = None;
        let intents = super::super::credential_commit::CredentialIntents::for_account(
            id.as_str(),
            &pl_protocol::studio::AccountAuthenticationIntent::ChatGpt {
                login_id: "fixture-login".into(),
                editor_id: "fixture-editor".into(),
            },
        );
        let calls = std::cell::Cell::new(0);
        let error = store
            .commit_config_with(&initial, &candidate, &intents, &|path, bytes| {
                pl_tool::workspace::write_file_atomically(path, bytes)?;
                calls.set(calls.get() + 1);
                if calls.get() > 1 {
                    return Ok(());
                }
                let protected = store.credentials.load_strict(id.as_str())?.unwrap();
                let written: ChatGptCredentialRecord = serde_json::from_str(&protected).unwrap();
                assert_eq!(written, record);
                Err(PureError::ConfigError(
                    "injected configuration commit failure".into(),
                ))
            })
            .unwrap_err();
        assert!(
            error
                .to_string()
                .contains("injected configuration commit failure")
        );
        assert_eq!(
            store
                .credentials
                .load_strict(id.as_str())
                .unwrap()
                .as_deref(),
            Some("original-api-key")
        );
        assert_eq!(fs::read(store.paths.config_file()).unwrap(), original_bytes);
        assert_eq!(store.load().unwrap(), initial);
        store
            .credentials
            .save_strict(id.as_str(), &serde_json::to_string(&record).unwrap())
            .unwrap();
        assert!(
            store.load().is_err(),
            "an OAuth record is never hydrated as an API key"
        );
        store
            .credentials
            .save_strict(id.as_str(), "original-api-key")
            .unwrap();
        store.commit_config(&initial, &candidate, &intents).unwrap();
        let mut in_flight = record.clone();
        in_flight.refresh_in_flight = true;
        store
            .credentials
            .save_strict(id.as_str(), &serde_json::to_string(&in_flight).unwrap())
            .unwrap();
        // An unrelated settings save carries a cached original record. It must not resurrect
        // a consumed refresh token or erase another process's pending-operation marker.
        store.save(&candidate).unwrap();
        let protected: ChatGptCredentialRecord =
            serde_json::from_str(&store.credentials.load_strict(id.as_str()).unwrap().unwrap())
                .unwrap();
        assert!(protected.refresh_in_flight);
        let encoded = fs::read_to_string(store.paths.config_file()).unwrap();
        assert!(!encoded.contains("transaction-access"));
        assert!(!encoded.contains("transaction-refresh"));
        let hydrated = store.load().unwrap();
        assert_eq!(
            hydrated.models.accounts[&id].chatgpt_credentials.as_ref(),
            Some(&in_flight)
        );
    }

    fn isolated_store() -> (tempfile::TempDir, ConfigStore) {
        let directory = tempfile::tempdir().expect("isolated config directory");
        let store = ConfigStore::new(ConfigPaths::from_config_dir(directory.path()));
        (directory, store)
    }

    #[test]
    fn ui_language_defaults_for_existing_config_and_rejects_unknown_values() {
        let (_directory, store) = isolated_store();
        let mut config = StudioConfig::default_config().unwrap();
        config.ui.compact_timeline = true;
        store.save(&config).unwrap();
        let path = store.paths.config_file();
        let mut table = read_table(path);
        table["ui"].as_table_mut().unwrap().remove("language");
        fs::write(path, toml::to_string(&table).unwrap()).unwrap();
        assert_eq!(store.load().unwrap(), config);

        table["ui"]
            .as_table_mut()
            .unwrap()
            .insert("language".into(), "unsupported".into());
        let invalid = toml::to_string(&table).unwrap();
        fs::write(path, &invalid).unwrap();
        assert!(store.load().is_err());
        assert_eq!(fs::read_to_string(path).unwrap(), invalid);
    }

    /// 把当前 canonical 文档改写成 HEAD 的 22/21 真实结构（providers/preset/adapter/路由 provider,model）。
    fn downgrade_to_legacy_document(table: &mut toml::Table, schema_version: i64, slug: bool) {
        table.insert(
            "schema_version".into(),
            toml::Value::Integer(schema_version),
        );
        let route_legacy = |route: &mut toml::Value| {
            if let Some(route) = route.as_table_mut() {
                if let Some(account) = route.remove("account_id") {
                    route.insert("provider".into(), account);
                }
                if let Some(model) = route.remove("model_id") {
                    route.insert("model".into(), model);
                }
            }
        };
        if let Some(modes) = table
            .get_mut("mode_model_routes")
            .and_then(toml::Value::as_table_mut)
        {
            for (_, route) in modes.iter_mut() {
                route_legacy(route);
            }
        }
        let models = table
            .get_mut("models")
            .and_then(toml::Value::as_table_mut)
            .expect("models table");
        if let Some(accounts) = models.remove("accounts") {
            models.insert("providers".into(), accounts);
        }
        if let Some(routes) = models.get_mut("routes").and_then(toml::Value::as_table_mut) {
            for (_, route) in routes.iter_mut() {
                route_legacy(route);
            }
        }
        let providers = models
            .get_mut("providers")
            .and_then(toml::Value::as_table_mut)
            .expect("providers table");
        for (_, account) in providers.iter_mut() {
            let Some(account) = account.as_table_mut() else {
                continue;
            };
            account.remove("authentication");
            if let Some(template) = account.remove("template") {
                account.insert("preset".into(), template);
            }
            if let Some(protocol) = account.remove("protocol") {
                let adapter = match protocol.as_str().unwrap_or_default() {
                    "open_ai" => "openAi",
                    "deep_seek" => "deepSeek",
                    "zhipu" => "zhipu",
                    "mi_mo" => "miMo",
                    "xai" => "xai",
                    _ => "openAiCompatible",
                };
                account.insert("adapter".into(), toml::Value::String(adapter.into()));
            }
            if let Some(capabilities) = account
                .get_mut("capabilities")
                .and_then(toml::Value::as_table_mut)
                && capabilities.get("source").and_then(toml::Value::as_str)
                    == Some("template_defaults")
            {
                capabilities.insert("source".into(), "preset_defaults".into());
            }
            if slug
                && let Some(catalog) = account
                    .get_mut("catalog")
                    .and_then(toml::Value::as_table_mut)
            {
                for key in ["models", "additional_models"] {
                    if let Some(models) = catalog.get_mut(key).and_then(toml::Value::as_array_mut) {
                        for model in models {
                            if let Some(model) = model.as_table_mut()
                                && let Some(identifier) = model.remove("model_id")
                            {
                                model.insert("slug".into(), identifier);
                            }
                        }
                    }
                }
            }
        }
    }

    fn write_table(path: &Path, table: &toml::Table) {
        fs::write(path, toml::to_string(table).expect("serialize test config"))
            .expect("write test config");
    }

    #[test]
    fn schema_21_model_ids_migrate_without_losing_routes_overrides_or_credentials() {
        use pl_model::{
            config::AccountModelCatalogConfig, model::ModelInfo, protocol::ConnectionMode,
        };
        let (_directory, store) = isolated_store();
        let mut config = StudioConfig::default_config().unwrap();
        let id = AccountId::new("deepseek").unwrap();
        let account = config.models.accounts.get_mut(&id).unwrap();
        account.bearer_token = Some("synthetic-migration-secret".into());
        if let AccountModelCatalogConfig::Bundled {
            additional_models,
            connection_overrides,
            auto_compact_overrides,
            ..
        } = &mut account.catalog
        {
            additional_models.push(ModelInfo::compatible("exact-Unchanged-ID"));
            connection_overrides.insert("exact-Unchanged-ID".into(), ConnectionMode::Http);
            auto_compact_overrides.insert("exact-Unchanged-ID".into(), 1234);
        }
        store.save(&config).unwrap();
        let path = store.paths.config_file();
        let mut table = read_table(path);
        table["schema_version"] = 21.into();
        for (_, account) in table["models"]["accounts"]
            .as_table_mut()
            .unwrap()
            .iter_mut()
        {
            account.as_table_mut().unwrap().remove("authentication");
        }
        let model = table
            .get_mut("models")
            .unwrap()
            .get_mut("accounts")
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
    fn schema_23_upgrade_preserves_choices_and_credentials_after_commit_failure() {
        let (_directory, store) = isolated_store();
        let mut config = StudioConfig::default_config().unwrap();
        config.instructions.user = "保留用户约定".into();
        config
            .models
            .accounts
            .get_mut(&AccountId::new("deepseek").unwrap())
            .unwrap()
            .bearer_token = Some("schema-23-account-secret".into());
        store.save(&config).unwrap();
        // HEAD 767771084f6c's persisted schema 23 differs here only by the absent
        // delegation/enablement/billing fields; account IDs/routes already use current casing.
        let path = store.paths.config_file();
        let mut table = read_table(path);
        table["schema_version"] = 23.into();
        table.remove("delegation");
        let accounts = table["models"]["accounts"].as_table_mut().unwrap();
        for (_, account) in accounts.iter_mut() {
            let account = account.as_table_mut().unwrap();
            account.remove("disabled_models");
            account.remove("billing_kind");
            account.remove("authentication");
        }
        write_table(path, &table);
        let original = fs::read(path).unwrap();
        let failure = store
            .migrate_legacy_config_for_startup_with(&original, 23, |_, _| {
                Err(PureError::Io(std::io::Error::other(
                    "injected config replacement failure",
                )))
            })
            .unwrap_err();
        assert!(
            failure
                .to_string()
                .contains("injected config replacement failure")
        );
        assert_eq!(fs::read(path).unwrap(), original);
        let loaded = store.load_for_startup().unwrap();
        assert_eq!(loaded, config);
        assert_eq!(
            loaded.delegation,
            pl_protocol::DelegationSettings::default()
        );
        assert!(
            loaded
                .models
                .accounts
                .values()
                .all(|account| account.model_enabled_overrides().is_empty()
                    && account.billing_kind.is_none())
        );
        assert_eq!(
            store.credentials.load("deepseek").unwrap().as_deref(),
            Some("schema-23-account-secret")
        );
        assert_eq!(
            fs::read(migrated_backups(path).pop().unwrap()).unwrap(),
            original
        );
        assert_eq!(
            store.load_for_startup().unwrap(),
            config,
            "reopen is current and idempotent"
        );
    }

    /// 使用真实凭据存储边界（私有构造）验证 22→当前 schema 的启动路径。
    fn store_with_credentials(
        directory: &tempfile::TempDir,
        credentials: super::super::credential::MemoryCredentialStore,
    ) -> ConfigStore {
        ConfigStore::with_credential_store(
            ConfigPaths::from_config_dir(directory.path()),
            std::sync::Arc::new(credentials),
        )
    }

    #[test]
    fn schema_22_startup_migrates_accounts_capabilities_and_credentials() {
        let directory = tempfile::tempdir().expect("isolated config directory");
        let credentials = crate::config::credential::MemoryCredentialStore::default();
        credentials.seed_legacy_provider("deepseek", "legacy-secret");
        let mut config = StudioConfig::default_config().unwrap();
        let reviewer = crate::config::AgentRoleId::new("reviewer").unwrap();
        config.models.routes.insert(
            reviewer.clone(),
            config.mode_model_routes[&ThreadModeId::simple()].clone(),
        );
        let second_id = AccountId::new("second").unwrap();
        let mut second = config.models.accounts[&AccountId::new("deepseek").unwrap()].clone();
        second.name = "Second".into();
        second.bearer_token_env = Some("SECOND_API_KEY".into());
        config.models.accounts.insert(second_id.clone(), second);
        let mut route = config.models.routes[&reviewer].clone();
        route.account_id = second_id.clone();
        config.models.routes.insert(reviewer.clone(), route);
        let store = store_with_credentials(&directory, credentials);
        store.save(&config).unwrap();
        // 原始配置文档：真实 22 结构（providers/preset/adapter/路由 provider,model）。
        let path = store.paths.config_file();
        let original = fs::read_to_string(path).unwrap();
        let mut table: toml::Table = toml::from_str(&original).unwrap();
        downgrade_to_legacy_document(&mut table, 22, false);
        // 历史内联凭据：只在迁移边界转录到凭据库。
        table["models"]["providers"]["second"]
            .as_table_mut()
            .unwrap()
            .insert(
                "bearer_token".into(),
                toml::Value::String("inline-secret".into()),
            );
        write_table(path, &table);
        let original_bytes = fs::read(path).unwrap();

        let loaded = store
            .load_for_startup()
            .expect("schema 22 migrates at startup");
        assert_eq!(loaded.schema_version, crate::STUDIO_CONFIG_SCHEMA_VERSION);
        let deepseek = &loaded.models.accounts[&AccountId::new("deepseek").unwrap()];
        assert_eq!(
            deepseek.protocol,
            pl_model::protocol::ProtocolKind::DeepSeek
        );
        assert_eq!(
            deepseek.template.as_ref().map(|value| value.as_str()),
            Some("deepseek")
        );
        assert_eq!(
            deepseek.capabilities,
            pl_model::config::AccountCapabilitySelection::TemplateDefaults
        );
        assert_eq!(loaded.models.routes[&reviewer].account_id, second_id);
        // 旧凭据项保留；内联值与旧项均已转写到 `account:` 命名空间。
        assert_eq!(
            store.credentials.load("deepseek").unwrap().as_deref(),
            Some("legacy-secret")
        );
        assert_eq!(
            store.credentials.load("second").unwrap().as_deref(),
            Some("inline-secret")
        );
        assert_eq!(
            store.credentials.load("second").ok().flatten(),
            Some("inline-secret".to_string())
        );
        // 持久化文档是当前结构：无 providers/preset/adapter/preset_defaults。
        let persisted = fs::read_to_string(path).unwrap();
        assert!(persisted.contains(&format!(
            "schema_version = {}",
            crate::STUDIO_CONFIG_SCHEMA_VERSION
        )));
        assert!(persisted.contains("template_defaults"));
        assert!(!persisted.contains("models.providers"));
        assert!(!persisted.contains("preset_defaults"));
        assert!(!persisted.contains("inline-secret"));
        let backups = migrated_backups(path);
        assert_eq!(backups.len(), 1);
        assert_eq!(fs::read(&backups[0]).unwrap(), original_bytes);
        // 二次启动幂等。
        assert_eq!(store.load_for_startup().unwrap(), loaded);
    }

    #[test]
    fn schema_21_startup_migrates_legacy_identifiers_and_continues_to_current_schema() {
        let directory = tempfile::tempdir().expect("isolated config directory");
        let credentials = crate::config::credential::MemoryCredentialStore::default();
        credentials.seed_legacy_provider("deepseek", "legacy-secret");
        let mut config = StudioConfig::default_config().unwrap();
        if let pl_model::config::AccountModelCatalogConfig::Bundled {
            additional_models, ..
        } = &mut config
            .models
            .accounts
            .get_mut(&AccountId::new("deepseek").unwrap())
            .unwrap()
            .catalog
        {
            additional_models.push(pl_model::model::ModelInfo::compatible("legacy-slug"));
        }
        let store = store_with_credentials(&directory, credentials);
        store.save(&config).unwrap();
        let path = store.paths.config_file();
        let mut table = read_table(path);
        downgrade_to_legacy_document(&mut table, 21, true);
        write_table(path, &table);

        let loaded = store
            .load_for_startup()
            .expect("schema 21 continues through the account migration to the current schema");
        // 迁移后 canonical 配置由凭据存储注入 token，期望值同样注入。
        let mut expected = config.clone();
        expected
            .models
            .accounts
            .get_mut(&AccountId::new("deepseek").unwrap())
            .unwrap()
            .bearer_token = Some("legacy-secret".into());
        assert_eq!(loaded, expected);
        assert_eq!(
            store.credentials.load("deepseek").unwrap().as_deref(),
            Some("legacy-secret")
        );
        let persisted = fs::read_to_string(path).unwrap();
        assert!(persisted.contains(&format!(
            "schema_version = {}",
            crate::STUDIO_CONFIG_SCHEMA_VERSION
        )));
        assert!(!persisted.contains("models.providers"));
        assert_eq!(store.load_for_startup().unwrap(), expected);
        assert_eq!(migrated_backups(path).len(), 1);
    }

    #[test]
    fn current_schema_rejects_retired_capability_source_token() {
        let (_directory, store) = isolated_store();
        let config = StudioConfig::default_config().unwrap();
        store.save(&config).unwrap();
        let path = store.paths.config_file();
        let mut table = read_table(path);
        table["models"]["accounts"]["deepseek"]
            .as_table_mut()
            .unwrap()
            .insert(
                "capabilities".into(),
                toml::Value::Table(toml::Table::from_iter([(
                    "source".to_string(),
                    toml::Value::String("preset_defaults".into()),
                )])),
            );
        write_table(path, &table);
        let original = fs::read(path).unwrap();
        let error = store
            .load_for_startup()
            .expect_err("retired capability token must not parse in the current schema");
        assert!(
            matches!(
                error,
                super::super::ConfigRuntimeError::Migration(_)
                    | super::super::ConfigRuntimeError::Core(_)
            ),
            "current-schema rejection is a config error: {error}"
        );
        assert_eq!(fs::read(path).unwrap(), original);
        assert!(migrated_backups(path).is_empty());
    }

    #[test]
    fn conflicting_legacy_model_identifiers_leave_original_file_untouched() {
        let (_directory, store) = isolated_store();
        let mut config = StudioConfig::default_config().unwrap();
        if let pl_model::config::AccountModelCatalogConfig::Bundled {
            additional_models, ..
        } = &mut config
            .models
            .accounts
            .get_mut(&AccountId::new("deepseek").unwrap())
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
            .get_mut("accounts")
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
        downgrade_to_legacy_document(&mut table, 20, true);
        let accounts = table
            .get_mut("models")
            .and_then(toml::Value::as_table_mut)
            .and_then(|models| models.get_mut("providers"))
            .and_then(toml::Value::as_table_mut)
            .expect("accounts table");
        let deepseek = accounts
            .get_mut("deepseek")
            .and_then(toml::Value::as_table_mut)
            .expect("deepseek account");
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
        let account_id = AccountId::new("deepseek").expect("account id");
        let account = loaded
            .models
            .accounts
            .get(&account_id)
            .expect("deepseek account");
        let AccountCapabilitySelection::Explicit(capabilities) = &account.capabilities else {
            panic!("migrated account must keep explicit capabilities");
        };

        assert_eq!(
            loaded.schema_version,
            super::super::STUDIO_CONFIG_SCHEMA_VERSION
        );
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
        assert_eq!(account.name, config.models.accounts[&account_id].name);
        assert_eq!(
            account.base_url,
            config.models.accounts[&account_id].base_url
        );
        assert_eq!(
            account.template,
            config.models.accounts[&account_id].template
        );

        let persisted = fs::read_to_string(path).expect("read migrated config");
        let persisted_table: toml::Table =
            toml::from_str(&persisted).expect("parse migrated config");
        assert_eq!(
            persisted_table["schema_version"].as_integer(),
            Some(i64::from(super::super::STUDIO_CONFIG_SCHEMA_VERSION))
        );
        assert_eq!(
            persisted_table["models"]["accounts"]["deepseek"]["capabilities"]["web_search"]
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
                .and_then(|models| models.get("accounts"))
                .and_then(|accounts| accounts.get("deepseek"))
                .and_then(|account| account.get("service_capabilities"))
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
        let mut config = StudioConfig::default_config().expect("bundled defaults");
        let explorer = crate::config::AgentRoleId::new("explorer").unwrap();
        config.models.routes.insert(
            explorer,
            config.mode_model_routes[&ThreadModeId::simple()].clone(),
        );
        store.save(&config).expect("save current schema");
        let path = store.paths.config_file();
        let mut table = read_table(path);
        downgrade_to_legacy_document(&mut table, 20, true);
        write_table(path, &table);

        let loaded = store
            .load_for_startup()
            .expect("schema 20 without dialect token migrates");
        assert_eq!(
            loaded.schema_version,
            super::super::STUDIO_CONFIG_SCHEMA_VERSION
        );
        assert_eq!(loaded.mode_model_routes, config.mode_model_routes);
        assert_eq!(loaded.models.routes, config.models.routes);
        assert!(
            loaded
                .models
                .routes
                .contains_key(&crate::config::AgentRoleId::new("explorer").unwrap())
        );
        assert_eq!(loaded.models.accounts, config.models.accounts);
        assert_eq!(loaded.web_search, config.web_search);
        assert_eq!(loaded.deepseek_web_search, config.deepseek_web_search);
        assert!(loaded.deepseek_web_search.fetch_enabled);
    }

    /// 23→当前 schema：前进版本并补出空 ACP 集合，Native 账号、路由、搜索设置与用户 Profile 原样保留。
    #[test]
    fn schema_23_gains_empty_acp_and_preserves_native_config_and_profiles() {
        let (_directory, store) = isolated_store();
        let config = StudioConfig::default_config().expect("bundled defaults");
        store.save(&config).expect("save current schema");
        let path = store.paths.config_file();
        let mut table = read_table(path);
        table.insert("schema_version".into(), toml::Value::Integer(23));
        for (_, account) in table["models"]["accounts"]
            .as_table_mut()
            .unwrap()
            .iter_mut()
        {
            account.as_table_mut().unwrap().remove("authentication");
        }
        let _ = table.remove("acp");
        write_table(path, &table);
        let original = fs::read(path).expect("original schema 23 bytes");
        let agents = store.paths.agents_dir();
        fs::create_dir_all(&agents).expect("agents directory");
        let profile = concat!(
            "schema_version = 1\n",
            "display_name = \"Verify\"\n",
            "description = \"Checks conversions\"\n",
            "when_to_use = \"after a migration\"\n",
            "system_instructions = \"verify\"\n",
            "account_id = \"deepseek\"\n",
            "model_id = \"deepseek-flash\"\n",
            "effort = \"high\"\n",
        );
        fs::write(agents.join("verify.toml"), profile).expect("write user profile");

        let loaded = store.load_for_startup().expect("schema 23 migrates");
        assert_eq!(
            loaded.schema_version,
            super::super::STUDIO_CONFIG_SCHEMA_VERSION
        );
        assert!(
            loaded.acp.accounts.is_empty(),
            "schema 23 carries no ACP accounts"
        );
        assert_eq!(loaded.models.accounts, config.models.accounts);
        assert_eq!(loaded.models.routes, config.models.routes);
        assert_eq!(loaded.mode_model_routes, config.mode_model_routes);
        assert_eq!(loaded.web_search, config.web_search);
        assert_eq!(loaded.deepseek_web_search, config.deepseek_web_search);
        assert_eq!(loaded.skills, config.skills);
        assert_eq!(
            fs::read(agents.join("verify.toml")).expect("reread profile"),
            profile.as_bytes(),
            "user Agent Profile is preserved across the schema upgrade"
        );
        assert_eq!(
            fs::read(migrated_backups(path).pop().expect("migration backup")).expect("read backup"),
            original
        );
    }

    #[test]
    fn unknown_future_schema_fails_closed_without_rewrite() {
        let (_directory, store) = isolated_store();
        let config = StudioConfig::default_config().expect("bundled defaults");
        store.save(&config).expect("save current schema");
        let path = store.paths.config_file();
        let mut table = read_table(path);
        // 真正的"未来版本"：始终比当前 schema 高一级，不随版本提升失效。
        table.insert(
            "schema_version".into(),
            toml::Value::Integer(i64::from(crate::STUDIO_CONFIG_SCHEMA_VERSION) + 1),
        );
        write_table(path, &table);
        let original = fs::read(path).expect("original future-schema bytes");

        let error = store
            .load_for_startup()
            .expect_err("future schema must fail closed");
        assert!(
            matches!(error, super::super::ConfigRuntimeError::Migration(_)),
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
        let mut config = StudioConfig::default_config().expect("bundled defaults");
        let explorer = crate::config::AgentRoleId::new("explorer").unwrap();
        config.models.routes.insert(
            explorer,
            config.mode_model_routes[&ThreadModeId::simple()].clone(),
        );
        store.save(&config).expect("save current schema");
        let path = store.paths.config_file();
        let mut table = read_table(path);
        downgrade_to_legacy_document(&mut table, 20, true);
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
            toml::Value::String("missing-account".into()),
        );
        write_table(path, &table);
        let original = fs::read(path).expect("original invalid schema 20 bytes");

        let error = store
            .load_for_startup()
            .expect_err("invalid schema 20 must not migrate");
        assert!(
            matches!(error, super::super::ConfigRuntimeError::Migration(_)),
            "migration failure is a config error: {error}"
        );
        assert_eq!(fs::read(path).expect("reread config"), original);
        assert!(
            migrated_backups(path).is_empty(),
            "backup is written only after validation succeeds"
        );
    }
}
