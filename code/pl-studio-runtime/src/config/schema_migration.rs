//! 配置 schema 迁移的可恢复操作。
//!
//! 迁移把主配置与用户 Agent Profile 当作同一个操作：先把原始字节和已验证候选写入操作目录，
//! 校验候选内容与全部引用，再把系统凭据从 `provider:<id>` 复制到 `account:<id>` 并回读确认，
//! 最后按资源逐个原子替换。操作记录只保存身份、版本、步骤与内容摘要，不保存任何密钥。
//!
//! 中断后必须先接续同一操作：磁盘文件既不是原件也不是候选说明被外部改写，此时明确报错而
//! 不覆盖；只要仍是原件就继续替换，已是候选则跳过。全部资源确认到达候选后才清理操作目录。
//! 迁移失败保留原件、原件副本和操作记录，重新启动可继续，不通过重置或默认值绕过。

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;
use sha2::{Digest, Sha256};

use super::credential::{CredentialStore, LegacyCredentialCopy};
use super::{ConfigPaths, STUDIO_CONFIG_SCHEMA_VERSION, StudioConfig};
use crate::{PureError, Result};

/// 迁移前最后一个使用 Provider/Preset 模型接入语义的配置版本。
pub(super) const LEGACY_ACCOUNT_SCHEMA: u32 = 22;
/// 仍受支持的迁移源版本下界。
pub(super) const OLDEST_SUPPORTED_SCHEMA: u32 = 18;
/// 操作记录格式版本；与配置 schema 版本相互独立。
const JOURNAL_VERSION: u32 = 1;
const JOURNAL_DIR_NAME: &str = "schema-migration";
const JOURNAL_FILE_NAME: &str = "journal.json";
const ORIGINAL_DIR_NAME: &str = "original";
const CANDIDATE_DIR_NAME: &str = "candidate";

/// 一个待迁移资源的原始字节与已验证候选。
struct ResourcePlan {
    relative_path: String,
    original: Vec<u8>,
    candidate: Vec<u8>,
}

impl ResourcePlan {
    fn original_hash(&self) -> String {
        digest(&self.original)
    }

    fn candidate_hash(&self) -> String {
        digest(&self.candidate)
    }
}

/// 操作阶段；只前进不回退，用于中断后判断还需要做哪些步骤。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
enum MigrationPhase {
    /// 原件与候选已落盘，等待凭据复制。
    Prepared,
    /// 凭据已复制并回读，等待逐资源提交。
    Credentials,
    /// 所有资源已替换，等待最终校验。
    Committing,
}

#[derive(Debug, Clone, Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct JournalResource {
    relative_path: String,
    original_hash: String,
    candidate_hash: String,
    replaced: bool,
}

/// 不含密钥的操作记录。
#[derive(Debug, Clone, Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct MigrationJournal {
    version: u32,
    operation_id: String,
    source_version: u32,
    target_version: u32,
    phase: MigrationPhase,
    resources: Vec<JournalResource>,
}

impl MigrationJournal {
    fn resource_mut(&mut self, relative_path: &str) -> Option<&mut JournalResource> {
        self.resources
            .iter_mut()
            .find(|resource| resource.relative_path == relative_path)
    }
}

/// 资源替换的唯一写入点；测试可注入失败写入器验证中断恢复。
type ResourceWriter<'a> = &'a dyn Fn(&Path, &[u8]) -> Result<()>;

fn atomic_write(path: &Path, content: &[u8]) -> Result<()> {
    pl_tool::workspace::write_file_atomically(path, content).map_err(Into::into)
}

/// 启动时先接续未完成操作；没有待续操作时返回 `None`。
pub(super) fn resume(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
) -> Result<Option<StudioConfig>> {
    let directory = operation_dir(paths);
    let journal_path = directory.join(JOURNAL_FILE_NAME);
    let bytes = match fs::read(&journal_path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    let mut journal: MigrationJournal = serde_json::from_slice(&bytes).map_err(|_| {
        PureError::ConfigError(
            "unreadable Studio config migration journal; existing files preserved".to_string(),
        )
    })?;
    if journal.version != JOURNAL_VERSION {
        return Err(PureError::ConfigError(format!(
            "unsupported Studio config migration journal version: {}",
            journal.version
        )));
    }
    if journal.target_version != STUDIO_CONFIG_SCHEMA_VERSION {
        return Err(PureError::ConfigError(format!(
            "Studio config migration target {} does not match the current schema",
            journal.target_version
        )));
    }
    tracing::warn!(
        operation_id = %journal.operation_id,
        source_version = journal.source_version,
        phase = ?journal.phase,
        "resuming interrupted Studio config migration"
    );
    let config = commit(paths, credentials, &mut journal, &atomic_write)?;
    Ok(Some(config))
}

/// 为主配置与用户 Profile 准备并提交一次迁移。
pub(super) fn migrate(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
    original: &[u8],
    source_version: u32,
    config_candidate: Vec<u8>,
    inline_tokens: BTreeMap<String, String>,
    write: ResourceWriter<'_>,
) -> Result<StudioConfig> {
    let mut plans = vec![ResourcePlan {
        relative_path: super::STUDIO_CONFIG_FILE_NAME.to_string(),
        original: original.to_vec(),
        candidate: config_candidate,
    }];
    plans.extend(profile_plans(paths)?);
    for plan in &plans {
        // 迁移失败时不允许覆盖中途被外部改写的原件。
        let disk = fs::read(config_resource_path(paths, &plan.relative_path))?;
        if disk != plan.original {
            return Err(PureError::ConfigError(format!(
                "Studio config resource {} changed during migration; existing files preserved",
                plan.relative_path
            )));
        }
    }
    // 任何资源落盘前先完成候选校验与全部引用校验。
    let candidate_config = super::store::parse_migrated_config(&plans[0].candidate)?;
    for plan in plans.iter().skip(1) {
        let name = plan
            .relative_path
            .strip_prefix("agents/")
            .unwrap_or(&plan.relative_path);
        let profile_id = name.strip_suffix(".toml").unwrap_or(name);
        let text = std::str::from_utf8(&plan.candidate).map_err(|error| {
            PureError::ConfigError(format!("invalid migrated Agent Profile UTF-8: {error}"))
        })?;
        super::agent_profile::validate_profile_content(profile_id, text, &candidate_config)?;
    }
    let directory = operation_dir(paths);
    if let Err(error) = fs::remove_dir_all(&directory)
        && error.kind() != std::io::ErrorKind::NotFound
    {
        return Err(error.into());
    }
    for plan in &plans {
        write_protected(&directory, ORIGINAL_DIR_NAME, plan, &plan.original)?;
        write_protected(&directory, CANDIDATE_DIR_NAME, plan, &plan.candidate)?;
    }
    let mut journal = MigrationJournal {
        version: JOURNAL_VERSION,
        operation_id: format!("schema-{source_version}-to-{STUDIO_CONFIG_SCHEMA_VERSION}"),
        source_version,
        target_version: STUDIO_CONFIG_SCHEMA_VERSION,
        phase: MigrationPhase::Prepared,
        resources: plans
            .iter()
            .map(|plan| JournalResource {
                relative_path: plan.relative_path.clone(),
                original_hash: plan.original_hash(),
                candidate_hash: plan.candidate_hash(),
                replaced: false,
            })
            .collect(),
    };
    write_journal(&directory, &journal)?;
    commit_with_tokens(paths, credentials, &mut journal, &inline_tokens, write)
}

fn commit(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
    journal: &mut MigrationJournal,
    write: ResourceWriter<'_>,
) -> Result<StudioConfig> {
    let tokens = inline_tokens_from_original(paths)?;
    commit_with_tokens(paths, credentials, journal, &tokens, write)
}

fn commit_with_tokens(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
    journal: &mut MigrationJournal,
    inline_tokens: &BTreeMap<String, String>,
    write: ResourceWriter<'_>,
) -> Result<StudioConfig> {
    let directory = operation_dir(paths);
    let candidate = read_candidate(&directory, super::STUDIO_CONFIG_FILE_NAME)?;
    let candidate_config = super::store::parse_migrated_config(&candidate)?;
    if journal.phase == MigrationPhase::Prepared {
        copy_credentials(credentials, &candidate_config, inline_tokens)?;
        journal.phase = MigrationPhase::Credentials;
        write_journal(&directory, journal)?;
    }
    if journal.phase == MigrationPhase::Credentials {
        for resource in journal.resources.clone() {
            let path = config_resource_path(paths, &resource.relative_path);
            let disk = fs::read(&path)?;
            let disk_hash = digest(&disk);
            if disk_hash == resource.candidate_hash {
                if !resource.replaced
                    && let Some(entry) = journal.resource_mut(&resource.relative_path)
                {
                    entry.replaced = true;
                }
                continue;
            }
            if disk_hash != resource.original_hash {
                return Err(PureError::ConfigError(format!(
                    "Studio config resource {} changed outside the pending migration; existing files preserved",
                    resource.relative_path
                )));
            }
            let next = read_candidate(&directory, &resource.relative_path)?;
            write(&path, &next)?;
            if let Some(entry) = journal.resource_mut(&resource.relative_path) {
                entry.replaced = true;
            }
            write_journal(&directory, journal)?;
        }
        journal.phase = MigrationPhase::Committing;
        write_journal(&directory, journal)?;
    }
    for resource in &journal.resources {
        let path = config_resource_path(paths, &resource.relative_path);
        let bytes = fs::read(&path)?;
        if digest(&bytes) != resource.candidate_hash {
            return Err(PureError::ConfigError(format!(
                "Studio config resource {} did not reach its verified candidate",
                resource.relative_path
            )));
        }
    }
    // 提交确认后才清理操作目录；普通迁移备份已经另行保留。
    if let Err(error) = fs::remove_dir_all(&directory)
        && error.kind() != std::io::ErrorKind::NotFound
    {
        tracing::warn!(error = %error, "config migration operation directory cleanup failed");
    }
    Ok(candidate_config)
}

/// 复制旧 `provider:<id>` 关联并回读确认；内联历史凭据只在此边界转入系统凭据库。
fn copy_credentials(
    credentials: &dyn CredentialStore,
    config: &StudioConfig,
    inline_tokens: &BTreeMap<String, String>,
) -> Result<()> {
    for account_id in config.models.accounts.keys() {
        let id = account_id.as_str();
        if let Some(secret) = inline_tokens.get(id) {
            // 内联凭据来自原文；走与旧命名空间复制相同的**持久**写入+回读边界，
            // 不用普通 runtime 读写（后者在服务不可访问时可能回退到进程内 lease）。
            match credentials.import_inline_secret(id, secret)? {
                LegacyCredentialCopy::Copied | LegacyCredentialCopy::AlreadyIdentical => {}
                LegacyCredentialCopy::Absent => {
                    return Err(PureError::ConfigError(format!(
                        "inline credential import reported no persisted credential for account {id}"
                    )));
                }
            }
        }
        match credentials.copy_legacy_account(id)? {
            LegacyCredentialCopy::Copied
            | LegacyCredentialCopy::AlreadyIdentical
            | LegacyCredentialCopy::Absent => {}
        }
    }
    Ok(())
}

fn read_candidate(directory: &Path, relative_path: &str) -> Result<Vec<u8>> {
    Ok(fs::read(
        directory.join(CANDIDATE_DIR_NAME).join(relative_path),
    )?)
}

fn write_protected(
    directory: &Path,
    kind: &str,
    plan: &ResourcePlan,
    content: &[u8],
) -> Result<()> {
    let path = directory.join(kind).join(&plan.relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, content)?;
    Ok(())
}

fn write_journal(directory: &Path, journal: &MigrationJournal) -> Result<()> {
    fs::create_dir_all(directory)?;
    let content = serde_json::to_vec_pretty(journal).map_err(|error| {
        PureError::ConfigError(format!("could not encode migration journal: {error}"))
    })?;
    pl_tool::workspace::write_file_atomically(&directory.join(JOURNAL_FILE_NAME), &content)?;
    Ok(())
}

fn operation_dir(paths: &ConfigPaths) -> PathBuf {
    paths.config_dir().join(JOURNAL_DIR_NAME)
}

fn config_resource_path(paths: &ConfigPaths, relative_path: &str) -> PathBuf {
    if relative_path == super::STUDIO_CONFIG_FILE_NAME {
        return paths.config_file().to_path_buf();
    }
    paths.config_dir().join(relative_path)
}

/// 用户 Profile 的候选计划；没有 Profile 目录时为空集合。
fn profile_plans(paths: &ConfigPaths) -> Result<Vec<ResourcePlan>> {
    let directory = paths.agents_dir();
    let mut names = Vec::new();
    let entries = match fs::read_dir(&directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error.into()),
    };
    for entry in entries {
        let path = entry?.path();
        if path.extension().and_then(|value| value.to_str()) == Some("toml") {
            names.push(path);
        }
    }
    names.sort();
    let mut plans = Vec::new();
    for path in names {
        let name = path
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or_else(|| {
                PureError::ConfigError("Agent Profile filename is not UTF-8".to_string())
            })?;
        let original = fs::read(&path)?;
        let text = std::str::from_utf8(&original).map_err(|error| {
            PureError::ConfigError(format!("invalid Agent Profile UTF-8: {error}"))
        })?;
        let candidate = rewrite_profile_document(text)?;
        plans.push(ResourcePlan {
            relative_path: format!("agents/{name}"),
            original,
            candidate: candidate.into_bytes(),
        });
    }
    Ok(plans)
}

/// 把一份用户 Profile 的 `provider`/`model` 转为 `account_id`/`model_id`。
///
/// 只改写这两个已知键；其它键与用户文本原样保留。旧新键同时存在但不一致时明确报冲突，
/// 不以覆盖丢弃用户选择。
pub(super) fn rewrite_profile_document(text: &str) -> Result<String> {
    let mut table: toml::Table = toml::from_str(text)
        .map_err(|error| PureError::ConfigError(format!("invalid Agent Profile TOML: {error}")))?;
    move_key(&mut table, "provider", "account_id")?;
    move_key(&mut table, "model", "model_id")?;
    toml::to_string(&table)
        .map_err(|error| PureError::ConfigError(format!("could not encode Agent Profile: {error}")))
}

/// 主配置 22→23 的账号接入改写。
pub(super) fn rewrite_account_document(
    text: &str,
    inline_tokens: &mut BTreeMap<String, String>,
) -> Result<String> {
    let mut value: toml::Value = toml::from_str(text)
        .map_err(|error| PureError::ConfigError(format!("invalid legacy config TOML: {error}")))?;
    // 候选文档本身就是目标结构：版本与账号接入键在同一次改写内前进。
    let table = value.as_table_mut().ok_or_else(|| {
        PureError::ConfigError("legacy Studio config is not a TOML document".to_string())
    })?;
    table.insert(
        "schema_version".into(),
        toml::Value::Integer(i64::from(STUDIO_CONFIG_SCHEMA_VERSION)),
    );
    let Some(models) = value.get_mut("models").and_then(toml::Value::as_table_mut) else {
        return Err(PureError::ConfigError(
            "legacy Studio config has no models table".to_string(),
        ));
    };
    move_table(models, "providers", "accounts")?;
    if let Some(routes) = models.get_mut("routes").and_then(toml::Value::as_table_mut) {
        rewrite_route_table(routes)?;
    }
    if let Some(accounts) = models
        .get_mut("accounts")
        .and_then(toml::Value::as_table_mut)
    {
        let ids: Vec<String> = accounts.keys().cloned().collect();
        for id in ids {
            let Some(account) = accounts.get_mut(&id).and_then(toml::Value::as_table_mut) else {
                continue;
            };
            move_key(account, "preset", "template")?;
            if let Some(adapter) = account.remove("adapter") {
                let protocol = protocol_from_adapter(adapter)?;
                if let Some(existing) = account.get("protocol")
                    && existing.as_str() != Some(protocol.as_str())
                {
                    return Err(PureError::ConfigError(format!(
                        "conflicting account protocol for {id}; existing files preserved"
                    )));
                }
                account.insert("protocol".into(), toml::Value::String(protocol));
            }
            // 能力来源 token：旧 `preset_defaults` 只在迁移边界改写为当前 `template_defaults`。
            if let Some(capabilities) = account
                .get_mut("capabilities")
                .and_then(toml::Value::as_table_mut)
            {
                match capabilities.get("source").and_then(toml::Value::as_str) {
                    Some("preset_defaults") => {
                        capabilities.insert(
                            "source".into(),
                            toml::Value::String("template_defaults".into()),
                        );
                    }
                    Some("template_defaults") | Some("explicit") | None => {}
                    Some(other) => {
                        return Err(PureError::ConfigError(format!(
                            "unsupported account capability source: {other}"
                        )));
                    }
                }
            }
            // 历史内联凭据只在迁移边界转入系统凭据库，不进入当前配置正文。
            if let Some(toml::Value::String(token)) = account.remove("bearer_token")
                && !token.trim().is_empty()
            {
                inline_tokens.insert(id.clone(), token);
            }
        }
    }
    if let Some(mode_routes) = value
        .get_mut("mode_model_routes")
        .and_then(toml::Value::as_table_mut)
    {
        rewrite_route_table(mode_routes)?;
    }
    toml::to_string(&value).map_err(|error| {
        PureError::ConfigError(format!("could not encode migrated config: {error}"))
    })
}

fn rewrite_route_table(routes: &mut toml::Table) -> Result<()> {
    for (_, route) in routes.iter_mut() {
        let Some(route) = route.as_table_mut() else {
            continue;
        };
        move_key(route, "provider", "account_id")?;
        move_key(route, "model", "model_id")?;
    }
    Ok(())
}

fn move_table(table: &mut toml::Table, old: &str, new: &str) -> Result<()> {
    let Some(legacy) = table.remove(old) else {
        return Ok(());
    };
    if let Some(existing) = table.get(new) {
        if existing != &legacy {
            return Err(PureError::ConfigError(format!(
                "conflicting `{new}` and legacy `{old}` tables; existing files preserved"
            )));
        }
        return Ok(());
    }
    table.insert(new.to_string(), legacy);
    Ok(())
}

fn move_key(table: &mut toml::Table, old: &str, new: &str) -> Result<()> {
    let Some(legacy) = table.remove(old) else {
        return Ok(());
    };
    if let Some(existing) = table.get(new) {
        if existing != &legacy {
            return Err(PureError::ConfigError(format!(
                "conflicting `{new}` and legacy `{old}` values; existing files preserved"
            )));
        }
        return Ok(());
    }
    table.insert(new.to_string(), legacy);
    Ok(())
}

/// 旧 adapter 值只在这里转换为 protocol wire 值；正常运行不做别名解析。
fn protocol_from_adapter(adapter: toml::Value) -> Result<String> {
    let Some(value) = adapter.as_str() else {
        return Err(PureError::ConfigError(
            "legacy account adapter is not a string".to_string(),
        ));
    };
    let protocol = match value {
        "openAi" | "open_ai" => "open_ai",
        "deepSeek" | "deep_seek" => "deep_seek",
        "zhipu" => "zhipu",
        "miMo" | "mi_mo" => "mi_mo",
        "xai" => "xai",
        "openAiCompatible" | "open_ai_compatible" => "open_ai_compatible",
        other => {
            return Err(PureError::ConfigError(format!(
                "unsupported legacy account adapter: {other}"
            )));
        }
    };
    Ok(protocol.to_string())
}

/// 从受保护原件重新提取内联凭据，供中断后接续使用；不写入操作记录。
fn inline_tokens_from_original(paths: &ConfigPaths) -> Result<BTreeMap<String, String>> {
    let directory = operation_dir(paths);
    let original = fs::read(
        directory
            .join(ORIGINAL_DIR_NAME)
            .join(super::STUDIO_CONFIG_FILE_NAME),
    )?;
    let text = std::str::from_utf8(&original).map_err(|error| {
        PureError::ConfigError(format!("invalid preserved config UTF-8: {error}"))
    })?;
    let mut tokens = BTreeMap::new();
    let Ok(value) = toml::from_str::<toml::Value>(text) else {
        return Ok(tokens);
    };
    let accounts = value
        .get("models")
        .and_then(|models| models.get("providers").or_else(|| models.get("accounts")))
        .and_then(toml::Value::as_table);
    if let Some(accounts) = accounts {
        for (id, account) in accounts {
            if let Some(token) = account.get("bearer_token").and_then(toml::Value::as_str)
                && !token.trim().is_empty()
            {
                tokens.insert(id.clone(), token.to_string());
            }
        }
    }
    Ok(tokens)
}

fn digest(content: &[u8]) -> String {
    hex::encode(Sha256::digest(content))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::credential::{CredentialStore, MemoryCredentialStore};

    const LEGACY_CONFIG: &str = r#"
schema_version = 22

[models.routes.explorer]
provider = "deepseek"
model = "deepseek-flash"
effort = "high"

[models.routes.executor]
provider = "deepseek"
model = "deepseek-flash"
effort = "high"

[models.routes.worktree_executor]
provider = "deepseek"
model = "deepseek-flash"
effort = "high"

[models.routes.reviewer]
provider = "second"
model = "deepseek-reasoner"
effort = "high"

[mode_model_routes."mode.simple"]
provider = "deepseek"
model = "deepseek-flash"
effort = "high"

[mode_model_routes."mode.task"]
provider = "second"
model = "deepseek-reasoner"
effort = "high"

[models.providers.deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com"
tool_wire_policy = "function_fallback"
preset = "deepseek"
adapter = "deepSeek"
bearer_token_env = "DEEPSEEK_API_KEY"

[models.providers.deepseek.catalog]
source = "bundled"
catalog = "deepseek"

[models.providers.deepseek.catalog.connection_overrides]
deepseek-flash = "http"

[models.providers.deepseek.catalog.auto_compact_overrides]
deepseek-flash = 500000

[models.providers.second]
name = "Second"
base_url = "https://example.invalid"
tool_wire_policy = "function_fallback"
preset = "deepseek"
adapter = "deepSeek"
bearer_token_env = "SECOND_API_KEY"

[models.providers.second.catalog]
source = "bundled"
catalog = "deepseek"
"#;

    const LEGACY_PROFILE: &str = r#"
display_name = "Verify"
description = "Checks conversions"
when_to_use = "after a migration"
system_instructions = "verify"
provider = "deepseek"
model = "deepseek-flash"
effort = "high"
"#;

    struct Fixture {
        _directory: tempfile::TempDir,
        paths: ConfigPaths,
        credentials: MemoryCredentialStore,
    }

    fn make_fixture(config: &str, profile: Option<&str>) -> Fixture {
        let directory = tempfile::tempdir().expect("isolated config directory");
        let paths = ConfigPaths::from_config_dir(directory.path());
        fs::create_dir_all(paths.config_dir()).unwrap();
        fs::write(paths.config_file(), config).unwrap();
        if let Some(profile) = profile {
            fs::create_dir_all(paths.agents_dir()).unwrap();
            fs::write(paths.agents_dir().join("verify.toml"), profile).unwrap();
        }
        Fixture {
            _directory: directory,
            paths,
            credentials: MemoryCredentialStore::default(),
        }
    }

    /// 与启动路径一致的候选准备：22→23 的账号接入改写。
    fn migrate_fixture(fixture: &Fixture, write: ResourceWriter<'_>) -> Result<StudioConfig> {
        let original = fs::read(fixture.paths.config_file())?;
        let text = std::str::from_utf8(&original).unwrap();
        let mut inline_tokens = BTreeMap::new();
        let rewritten = rewrite_account_document(text, &mut inline_tokens)?;
        let mut config = crate::config::store::parse_migrated_config(rewritten.as_bytes())?;
        config.schema_version = STUDIO_CONFIG_SCHEMA_VERSION;
        let candidate = crate::config::store::serialize_persisted_config(&config)?;
        migrate(
            &fixture.paths,
            &fixture.credentials,
            &original,
            LEGACY_ACCOUNT_SCHEMA,
            candidate.into_bytes(),
            inline_tokens,
            write,
        )
    }

    #[test]
    fn schema_22_accounts_migrate_preserving_identity_endpoint_and_overrides() {
        let fixture = make_fixture(LEGACY_CONFIG, Some(LEGACY_PROFILE));
        fixture
            .credentials
            .seed_legacy_provider("deepseek", "legacy-secret");
        let migrated = migrate_fixture(&fixture, &atomic_write).expect("schema 22 migrates");

        let deepseek = migrated
            .models
            .accounts
            .get(&pl_model::config::AccountId::new("deepseek").unwrap())
            .expect("account keeps its id");
        assert_eq!(
            deepseek.protocol,
            pl_model::protocol::ProtocolKind::DeepSeek
        );
        assert_eq!(
            deepseek.template.as_ref().map(|value| value.as_str()),
            Some("deepseek")
        );
        assert_eq!(deepseek.base_url, "https://api.deepseek.com");
        assert_eq!(
            deepseek.bearer_token_env.as_deref(),
            Some("DEEPSEEK_API_KEY")
        );
        assert_eq!(
            deepseek.connection_overrides().get("deepseek-flash"),
            Some(&pl_model::protocol::ConnectionMode::Http)
        );
        assert_eq!(
            deepseek.auto_compact_overrides().get("deepseek-flash"),
            Some(&500_000)
        );
        let explorer =
            &migrated.models.routes[&pl_model::config::AgentRoleId::new("explorer").unwrap()];
        assert_eq!(explorer.account_id.as_str(), "deepseek");
        assert_eq!(explorer.model_id, "deepseek-flash");
        let reviewer =
            &migrated.models.routes[&pl_model::config::AgentRoleId::new("reviewer").unwrap()];
        assert_eq!(reviewer.account_id.as_str(), "second");
        assert_eq!(reviewer.model_id, "deepseek-reasoner");
        assert_eq!(
            migrated.mode_model_routes[&pl_protocol::ThreadModeId::task()]
                .account_id
                .as_str(),
            "second"
        );

        // 旧凭据关联保留，新命名空间已复制可读。
        assert_eq!(
            fixture.credentials.legacy_provider_secret("deepseek"),
            Some("legacy-secret".to_string())
        );
        assert_eq!(
            fixture.credentials.load("deepseek").unwrap().as_deref(),
            Some("legacy-secret")
        );

        // Profile 文件转换为当前键，其它字段与用户文本保持。
        let profile = fs::read_to_string(fixture.paths.agents_dir().join("verify.toml")).unwrap();
        assert!(profile.contains("account_id = \"deepseek\""));
        assert!(profile.contains("model_id = \"deepseek-flash\""));
        assert!(!profile.contains("provider ="));
        assert!(profile.contains("description = \"Checks conversions\""));

        // 操作目录在确认完成后清理；迁移备份与原字节仍在。
        assert!(!operation_dir(&fixture.paths).exists());
        let persisted = fs::read_to_string(fixture.paths.config_file()).unwrap();
        assert!(persisted.contains("schema_version = 23"));
        assert!(!persisted.contains("models.providers"));
    }

    #[test]
    fn conflicting_legacy_and_current_keys_fail_closed_without_writing() {
        let config = LEGACY_CONFIG.replace(
            "preset = \"deepseek\"",
            "preset = \"deepseek\"\ntemplate = \"other\"",
        );
        let fixture = make_fixture(&config, None);
        let original = fs::read(fixture.paths.config_file()).unwrap();
        let error = migrate_fixture(&fixture, &atomic_write).expect_err("conflict must fail");
        assert!(matches!(error, PureError::ConfigError(_)), "{error}");
        assert_eq!(fs::read(fixture.paths.config_file()).unwrap(), original);
        assert!(!operation_dir(&fixture.paths).exists());
    }

    #[test]
    fn interrupted_commit_resumes_from_the_recorded_operation() {
        let fixture = make_fixture(LEGACY_CONFIG, Some(LEGACY_PROFILE));
        fixture
            .credentials
            .seed_legacy_provider("deepseek", "legacy-secret");
        // 第一次提交在 Profile 资源上失败：主配置已替换，Profile 仍是原件。
        let failing = |path: &Path, content: &[u8]| -> Result<()> {
            if path.ends_with("verify.toml") {
                return Err(PureError::ConfigError("injected write failure".into()));
            }
            atomic_write(path, content)
        };
        assert!(migrate_fixture(&fixture, &failing).is_err());
        assert!(
            operation_dir(&fixture.paths)
                .join(JOURNAL_FILE_NAME)
                .exists()
        );
        assert!(
            fs::read(fixture.paths.agents_dir().join("verify.toml"))
                .unwrap()
                .starts_with(LEGACY_PROFILE.as_bytes())
        );

        // 重新启动接续同一操作：幂等凭据复制、剩余资源提交、Profile 转换完成。
        let resumed = resume(&fixture.paths, &fixture.credentials)
            .expect("resume succeeds")
            .expect("pending operation is resumed");
        assert_eq!(resumed.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        let profile = fs::read_to_string(fixture.paths.agents_dir().join("verify.toml")).unwrap();
        assert!(profile.contains("account_id = \"deepseek\""));
        assert!(!operation_dir(&fixture.paths).exists());
        assert_eq!(
            fixture.credentials.load("deepseek").unwrap().as_deref(),
            Some("legacy-secret")
        );
        // 操作确认后受保护原件与候选一起清理，不留下可误用的中间状态。
        assert!(
            !operation_dir(&fixture.paths)
                .join(ORIGINAL_DIR_NAME)
                .exists()
        );
    }

    #[test]
    fn external_edit_during_pending_migration_is_not_overwritten() {
        let fixture = make_fixture(LEGACY_CONFIG, Some(LEGACY_PROFILE));
        let failing = |path: &Path, content: &[u8]| -> Result<()> {
            if path.ends_with("verify.toml") {
                return Err(PureError::ConfigError("injected write failure".into()));
            }
            atomic_write(path, content)
        };
        assert!(migrate_fixture(&fixture, &failing).is_err());
        let edited = b"# user edit outside the migration\n";
        fs::write(fixture.paths.agents_dir().join("verify.toml"), edited).unwrap();
        let error =
            resume(&fixture.paths, &fixture.credentials).expect_err("external edit conflicts");
        assert!(matches!(error, PureError::ConfigError(_)), "{error}");
        assert_eq!(
            fs::read(fixture.paths.agents_dir().join("verify.toml")).unwrap(),
            edited
        );
    }

    /// 迁移专用故障注入：inline 导入在各阶段失败，验证严格持久义务。
    #[derive(Clone, Copy, PartialEq, Eq)]
    enum InlineFault {
        None,
        Unavailable,
        WriteFails,
        ReadBackDiffers,
    }

    struct FaultyStore {
        inner: MemoryCredentialStore,
        inline_fault: InlineFault,
        /// 证明迁移不走普通 runtime 写入（后者可能在服务不可访问时落入进程内 lease）。
        forbid_normal_save: bool,
        import_calls: std::sync::atomic::AtomicUsize,
    }

    impl CredentialStore for FaultyStore {
        fn load(&self, account_id: &str) -> Result<Option<String>> {
            self.inner.load(account_id)
        }
        fn save(&self, account_id: &str, secret: &str) -> Result<()> {
            if self.forbid_normal_save {
                return Err(PureError::ConfigError(
                    "migration must not use the ordinary credential write path".into(),
                ));
            }
            self.inner.save(account_id, secret)
        }
        fn delete(&self, account_id: &str) -> Result<()> {
            self.inner.delete(account_id)
        }
        fn load_ssh(&self, alias: &str) -> Result<Option<String>> {
            self.inner.load_ssh(alias)
        }
        fn save_ssh(&self, alias: &str, secret: &str) -> Result<()> {
            self.inner.save_ssh(alias, secret)
        }
        fn delete_ssh(&self, alias: &str) -> Result<()> {
            self.inner.delete_ssh(alias)
        }
        fn copy_legacy_account(&self, account_id: &str) -> Result<LegacyCredentialCopy> {
            self.inner.copy_legacy_account(account_id)
        }
        fn import_inline_secret(
            &self,
            account_id: &str,
            secret: &str,
        ) -> Result<LegacyCredentialCopy> {
            self.import_calls
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            match self.inline_fault {
                InlineFault::None => self.inner.import_inline_secret(account_id, secret),
                InlineFault::Unavailable => Err(PureError::Io(std::io::Error::other(
                    "platform failure: no storage access",
                ))),
                InlineFault::WriteFails => Err(PureError::Io(std::io::Error::other(
                    "credential write failed",
                ))),
                InlineFault::ReadBackDiffers => {
                    // 写入被接受但回读不同：不得当作持久成功。
                    self.inner.save(account_id, "different-secret")?;
                    Err(PureError::ConfigError(
                        "system credential verification failed".into(),
                    ))
                }
            }
        }
    }

    const LEGACY_INLINE_CONFIG: &str = r#"
schema_version = 22

[models.routes.explorer]
provider = "deepseek"
model = "deepseek-flash"
effort = "high"

[models.routes.executor]
provider = "deepseek"
model = "deepseek-flash"
effort = "high"

[models.routes.worktree_executor]
provider = "deepseek"
model = "deepseek-flash"
effort = "high"

[models.routes.reviewer]
provider = "envonly"
model = "deepseek-flash"
effort = "high"

[mode_model_routes."mode.simple"]
provider = "deepseek"
model = "deepseek-flash"
effort = "high"

[mode_model_routes."mode.task"]
provider = "deepseek"
model = "deepseek-flash"
effort = "high"

[models.providers.deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com"
tool_wire_policy = "function_fallback"
preset = "deepseek"
adapter = "deepSeek"
bearer_token = "inline-history-secret"

[models.providers.deepseek.catalog]
source = "bundled"
catalog = "deepseek"

[models.providers.envonly]
name = "EnvOnly"
base_url = "https://example.invalid"
tool_wire_policy = "function_fallback"
preset = "deepseek"
adapter = "deepSeek"
bearer_token_env = "ENVONLY_API_KEY"

[models.providers.envonly.catalog]
source = "bundled"
catalog = "deepseek"
"#;

    fn migrate_with_store(store: &FaultyStore, paths: &ConfigPaths) -> Result<StudioConfig> {
        let original = fs::read(paths.config_file())?;
        let text = std::str::from_utf8(&original).unwrap();
        let mut inline_tokens = BTreeMap::new();
        let rewritten = rewrite_account_document(text, &mut inline_tokens)?;
        assert!(
            inline_tokens.contains_key("deepseek"),
            "legacy inline token is discovered at the migration boundary"
        );
        let mut config = crate::config::store::parse_migrated_config(rewritten.as_bytes())?;
        config.schema_version = STUDIO_CONFIG_SCHEMA_VERSION;
        let candidate = crate::config::store::serialize_persisted_config(&config)?;
        migrate(
            paths,
            store,
            &original,
            LEGACY_ACCOUNT_SCHEMA,
            candidate.into_bytes(),
            inline_tokens,
            &atomic_write,
        )
    }

    fn inline_fixture() -> (Fixture, FaultyStore) {
        let fixture = make_fixture(LEGACY_INLINE_CONFIG, None);
        let store = FaultyStore {
            inner: MemoryCredentialStore::default(),
            inline_fault: InlineFault::None,
            forbid_normal_save: false,
            import_calls: std::sync::atomic::AtomicUsize::new(0),
        };
        (fixture, store)
    }

    #[test]
    fn inline_credentials_are_imported_through_the_strict_persistent_path() {
        let (fixture, mut store) = inline_fixture();
        // 普通 runtime 写入在迁移中不可用：内联转录必须走持久导入边界。
        store.forbid_normal_save = true;
        let migrated = migrate_with_store(&store, &fixture.paths).expect("inline import succeeds");
        assert!(
            store
                .import_calls
                .load(std::sync::atomic::Ordering::Relaxed)
                > 0,
            "inline credentials must go through the strict persistent import boundary"
        );
        assert_eq!(migrated.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        assert_eq!(
            store.load("deepseek").unwrap().as_deref(),
            Some("inline-history-secret")
        );
        // env-only 账号不制造空凭据项。
        assert!(store.load("envonly").unwrap().is_none());
        assert_eq!(
            migrated.models.accounts[&pl_model::config::AccountId::new("envonly").unwrap()]
                .bearer_token_env
                .as_deref(),
            Some("ENVONLY_API_KEY")
        );
        // secret 不进入配置或操作记录。
        let persisted = fs::read_to_string(fixture.paths.config_file()).unwrap();
        assert!(!persisted.contains("inline-history-secret"));
        assert!(!operation_dir(&fixture.paths).exists());
    }

    #[test]
    fn inline_import_failures_preserve_originals_journal_and_old_items() {
        for fault in [
            InlineFault::Unavailable,
            InlineFault::WriteFails,
            InlineFault::ReadBackDiffers,
        ] {
            let (fixture, mut store) = inline_fixture();
            store
                .inner
                .seed_legacy_provider("envonly", "legacy-envonly-secret");
            store.inline_fault = fault;
            let original = fs::read(fixture.paths.config_file()).unwrap();
            let error = migrate_with_store(&store, &fixture.paths)
                .expect_err("strict inline import must fail closed");
            assert!(matches!(
                error,
                PureError::Io(_) | PureError::ConfigError(_)
            ));
            // 原件、操作记录、旧 provider 项都保留；配置文件未被替换成候选。
            assert_eq!(fs::read(fixture.paths.config_file()).unwrap(), original);
            assert!(
                operation_dir(&fixture.paths)
                    .join(JOURNAL_FILE_NAME)
                    .exists()
            );
            assert_eq!(
                store.inner.legacy_provider_secret("envonly").as_deref(),
                Some("legacy-envonly-secret")
            );
            // 操作记录只保存身份/版本/摘要，不含密钥。
            let journal =
                fs::read_to_string(operation_dir(&fixture.paths).join(JOURNAL_FILE_NAME)).unwrap();
            assert!(!journal.contains("inline-history-secret"));
            assert!(!journal.contains("legacy-envonly-secret"));
        }
    }

    #[test]
    fn credential_conflict_and_unavailable_store_fail_closed() {
        let fixture = make_fixture(LEGACY_CONFIG, None);
        fixture
            .credentials
            .seed_legacy_provider("deepseek", "legacy-secret");
        fixture
            .credentials
            .save("deepseek", "different-secret")
            .unwrap();
        let original = fs::read(fixture.paths.config_file()).unwrap();
        let error = migrate_fixture(&fixture, &atomic_write).expect_err("conflict must fail");
        assert!(matches!(error, PureError::ConfigError(_)), "{error}");
        assert_eq!(fs::read(fixture.paths.config_file()).unwrap(), original);
        assert_eq!(
            fixture.credentials.load("deepseek").unwrap().as_deref(),
            Some("different-secret")
        );

        struct Unavailable(MemoryCredentialStore);
        impl CredentialStore for Unavailable {
            fn load(&self, account_id: &str) -> Result<Option<String>> {
                self.0.load(account_id)
            }
            fn save(&self, account_id: &str, secret: &str) -> Result<()> {
                self.0.save(account_id, secret)
            }
            fn delete(&self, account_id: &str) -> Result<()> {
                self.0.delete(account_id)
            }
            fn load_ssh(&self, alias: &str) -> Result<Option<String>> {
                self.0.load_ssh(alias)
            }
            fn save_ssh(&self, alias: &str, secret: &str) -> Result<()> {
                self.0.save_ssh(alias, secret)
            }
            fn delete_ssh(&self, alias: &str) -> Result<()> {
                self.0.delete_ssh(alias)
            }
            fn copy_legacy_account(&self, _account_id: &str) -> Result<LegacyCredentialCopy> {
                // 服务不可访问不是"原项不存在"，必须显式失败。
                Err(PureError::Io(std::io::Error::other(
                    "credential service unavailable",
                )))
            }
            fn import_inline_secret(
                &self,
                _account_id: &str,
                _secret: &str,
            ) -> Result<LegacyCredentialCopy> {
                Err(PureError::Io(std::io::Error::other(
                    "credential service unavailable",
                )))
            }
        }
        let fixture = make_fixture(LEGACY_CONFIG, None);
        let unavailable = Unavailable(MemoryCredentialStore::default());
        let original = fs::read(fixture.paths.config_file()).unwrap();
        let text = std::str::from_utf8(&original).unwrap();
        let mut inline_tokens = BTreeMap::new();
        let rewritten = rewrite_account_document(text, &mut inline_tokens).unwrap();
        let mut config = crate::config::store::parse_migrated_config(rewritten.as_bytes()).unwrap();
        config.schema_version = STUDIO_CONFIG_SCHEMA_VERSION;
        let candidate = crate::config::store::serialize_persisted_config(&config).unwrap();
        assert!(
            migrate(
                &fixture.paths,
                &unavailable,
                &original,
                LEGACY_ACCOUNT_SCHEMA,
                candidate.into_bytes(),
                inline_tokens,
                &atomic_write,
            )
            .is_err()
        );
        assert_eq!(fs::read(fixture.paths.config_file()).unwrap(), original);
    }
}
