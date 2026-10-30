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
use super::{
    ConfigPaths, STUDIO_CONFIG_SCHEMA_VERSION, StudioConfig, validate_user_agent_profile_id,
};
use crate::{PureError, Result};

mod resources;

/// New resource journals and frozen v1 journals share the same operation directory and writers.
pub(super) fn resume_for_startup(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
) -> anyhow::Result<()> {
    let journal_path = operation_dir(paths).join(JOURNAL_FILE_NAME);
    let bytes = match fs::read(&journal_path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    #[derive(serde::Deserialize)]
    struct Header {
        version: u32,
    }
    let header: Header = serde_json::from_slice(&bytes)?;
    match header.version {
        JOURNAL_VERSION => {
            // Complete the immutable old operation before preparing any current candidate.
            if let Some(resumed) = resume_legacy(paths, credentials)? {
                tracing::debug!(
                    target_version = resumed.target_version,
                    current = resumed.config.is_some(),
                    "completed recorded legacy config migration"
                );
            }
        }
        resources::VERSION => {
            resources::resume(paths, credentials, &bytes)?;
        }
        _ => anyhow::bail!("unsupported configuration migration journal version"),
    }
    Ok(())
}

pub(super) fn prepare_for_startup(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
    original: Option<&[u8]>,
    write: ResourceWriter<'_>,
) -> anyhow::Result<StudioConfig> {
    resources::prepare(paths, credentials, original, write)
}

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

/// 一个已接续完成的迁移操作。
///
/// 旧版本的待续操作可能以更早的 schema（23–26）为目标：这类操作必须先按它自己的候选、摘要与
/// 提交步骤完成，再由调用方从该**已提交版本**继续升级到当前 schema，不能改写旧目标或伪造摘要。
#[derive(Debug)]
pub(super) struct ResumedOperation {
    /// 该操作日志记录的目标版本（已完成）。
    pub(super) target_version: u32,
    /// 目标就是当前 schema 时解析出的配置；旧目标为 `None`，由调用方继续升级。
    pub(super) config: Option<StudioConfig>,
}

/// 启动时先接续未完成操作；没有待续操作时返回 `None`。
fn resume_legacy(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
) -> anyhow::Result<Option<ResumedOperation>> {
    let directory = operation_dir(paths);
    let journal_path = directory.join(JOURNAL_FILE_NAME);
    let bytes = match fs::read(&journal_path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    let mut journal: MigrationJournal = serde_json::from_slice(&bytes)?;
    if journal.version != JOURNAL_VERSION {
        return Err(PureError::ConfigError(format!(
            "unsupported Studio config migration journal version: {}",
            journal.version
        ))
        .into());
    }
    if !(23..=STUDIO_CONFIG_SCHEMA_VERSION).contains(&journal.target_version) {
        return Err(PureError::ConfigError(format!(
            "Studio config migration target {} does not match the current schema",
            journal.target_version
        ))
        .into());
    }
    tracing::warn!(
        operation_id = %journal.operation_id,
        source_version = journal.source_version,
        phase = ?journal.phase,
        "resuming interrupted Studio config migration"
    );
    let target_version = journal.target_version;
    let config = commit_legacy(paths, credentials, &mut journal, &atomic_write)?;
    Ok(Some(ResumedOperation {
        target_version,
        config,
    }))
}

#[cfg(test)]
fn resume(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
) -> Result<Option<ResumedOperation>> {
    let bytes = match fs::read(operation_dir(paths).join(JOURNAL_FILE_NAME)) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    if serde_json::from_slice::<serde_json::Value>(&bytes)
        .ok()
        .and_then(|value| value.get("version").and_then(serde_json::Value::as_u64))
        == Some(u64::from(resources::VERSION))
    {
        return resources::resume(paths, credentials, &bytes)
            .map(|config| {
                Some(ResumedOperation {
                    target_version: STUDIO_CONFIG_SCHEMA_VERSION,
                    config: Some(config),
                })
            })
            .map_err(test_migration_error);
    }
    resume_legacy(paths, credentials).map_err(test_migration_error)
}

/// 一次迁移的源侧输入。
///
/// 这些字段描述同一个源版本与同一份候选改写，必须一起传递：拆成散装参数容易把版本、
/// 原文与候选配对错。是否需要重排 Profile 不单独传入，由 [`migrate`] 从源版本推导。
#[cfg(test)]
pub(super) struct MigrationSource<'a> {
    /// 主配置在磁盘上的原始字节；迁移期间不允许被外部改写。
    pub original: &'a [u8],
    /// 迁移前的 schema 版本。
    pub source_version: u32,
    /// 已按目标版本重写、尚未落盘的候选内容。
    pub candidate: Vec<u8>,
    /// 需要搬进 keyring 的旧版内联凭据。
    pub inline_tokens: BTreeMap<String, String>,
}

/// 为主配置与用户 Profile 准备并提交一次迁移。
///
/// 是否需要重排 Profile 只由源版本决定：只有确实改变了 Profile 键（`provider`/`model` →
/// `account_id`/`model_id`）的旧版本才重写。仅前进版本（如 23→24）时 Profile 原字节保留，
/// 不重新序列化、不丢注释，也不产生多余资源计划。
#[cfg(test)]
pub(super) fn migrate(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
    source: MigrationSource<'_>,
    write: ResourceWriter<'_>,
) -> Result<StudioConfig> {
    let MigrationSource {
        original,
        source_version,
        candidate,
        inline_tokens,
    } = source;
    // 源/目标元数据先于任何写入校验：只判范围无法识别"原件其实是 22、日志却记成 source 23"，
    // 那会静默跳过旧 `provider:<id>` 凭据复制。
    validate_operation_metadata(source_version, STUDIO_CONFIG_SCHEMA_VERSION, original)?;
    super::store::parse_migrated_config(&candidate)?;
    if inline_tokens != inline_tokens_from_verified_original(original) {
        return Err(PureError::ConfigError(
            "credential intent differs from preserved original".into(),
        ));
    }
    resources::prepare(paths, credentials, Some(original), write).map_err(test_migration_error)
}

#[cfg(test)]
fn test_migration_error(error: anyhow::Error) -> PureError {
    match error.downcast::<PureError>() {
        Ok(error) => error,
        Err(error) => PureError::ConfigError(format!("{error:#}")),
    }
}

#[cfg(test)]
fn commit(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
    journal: &mut MigrationJournal,
    write: ResourceWriter<'_>,
) -> Result<Option<StudioConfig>> {
    commit_legacy(paths, credentials, journal, write).map_err(test_migration_error)
}

fn commit_legacy(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
    journal: &mut MigrationJournal,
    write: ResourceWriter<'_>,
) -> anyhow::Result<Option<StudioConfig>> {
    let directory = operation_dir(paths);
    // 1) 集合身份：journal 是外部可变的输入，不能假定 migrate 构造的不变量——空集合、首项不是
    //    主配置或主配置重复都必须在这里拒绝，绝不索引越界、不默认补配置、不重排旧日志。
    validate_journal_resources(journal)?;
    // 2) 一次性核验本次 journal 的**全部**资源：受保护原件与候选字节都必须匹配各自记录的摘要，
    //    磁盘状态只能是原件或已提交候选。返回的快照是本提交后续唯一消费的字节来源，绝不再从
    //    路径二次读取原件/候选——否则校验之后被替换的字节可能被解析、写盘或用于凭据复制。
    let verified = verify_pending_resources(paths, &directory, journal)?;
    let Some(config_resource) = verified.first() else {
        // 集合身份已校验，这里只是 panic-free 的防御，不补造资源。
        return Err(PureError::ConfigError(
            "Studio config migration has no verified resources; existing files preserved"
                .to_string(),
        )
        .into());
    };
    // A v1 operation keeps its producer's original admission rules. Only its recorded header
    // and verified bytes establish source identity; do not re-admit the original with new DTOs.
    #[derive(serde::Deserialize)]
    struct OriginalHeader {
        schema_version: u32,
    }
    let original_text = std::str::from_utf8(&config_resource.original).map_err(|error| {
        crate::toml_schema::migration_error(
            paths.config_file(),
            "studio-config",
            None,
            journal.target_version,
            "journal original UTF-8",
            error,
        )
    })?;
    let original: OriginalHeader = toml::from_str(original_text).map_err(|error| {
        crate::toml_schema::migration_error(
            paths.config_file(),
            "studio-config",
            None,
            journal.target_version,
            "journal original header",
            error,
        )
    })?;
    anyhow::ensure!(
        original.schema_version == journal.source_version,
        "journal source {} contradicts preserved original schema {}",
        journal.source_version,
        original.schema_version,
    );
    // 3) 元数据：source/target 必须受支持、且记录的 source 与已核验原件实际 schema 一致。
    validate_operation_metadata(
        journal.source_version,
        journal.target_version,
        &config_resource.original,
    )?;
    // 4) 内联 token 只来自已核验原件；恢复路径不再从路径读未验证的新值。
    let inline_tokens = inline_tokens_from_verified_original(&config_resource.original);
    let candidate = &config_resource.candidate;
    // 盘上写入的始终是日志记录的原始候选字节；这里只解码一份**只读**的当前形状视图，供候选
    // 校验与凭据复制使用。旧目标（23–26）候选可能带当前 schema 已退役的字段（ACP 的
    // `program`/`args`、账号 `pricing_mode` 或 `disabled_models`），视图先转换它们，不改变原候选写入内容。
    let target_is_current = journal.target_version == STUDIO_CONFIG_SCHEMA_VERSION;
    let (candidate_config, candidate_version, _) =
        resources::main_document(paths.config_file(), candidate)?;
    anyhow::ensure!(
        candidate_version == journal.target_version,
        "candidate schema contradicts recorded target"
    );
    // The historical producer already admitted its Profile candidates. Finish those exact bytes
    // first; independent Profile schema admission belongs to the next operation.
    if journal.phase == MigrationPhase::Prepared {
        // The 23→24 change preserves the already canonical credential association.
        // Re-reading the retired provider namespace here could reject valid newer credentials.
        if journal.source_version <= LEGACY_ACCOUNT_SCHEMA {
            copy_credentials(credentials, &candidate_config, &inline_tokens)?;
        }
        journal.phase = MigrationPhase::Credentials;
        write_journal(&directory, journal)?;
    }
    if journal.phase == MigrationPhase::Credentials {
        let resources = journal.resources.clone();
        for (index, resource) in resources.iter().enumerate() {
            // 只写已核验快照里的候选字节：即使底层 candidate 在校验后被替换，也绝不写入新变体。
            let verified_candidate = &verified[index].candidate;
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
                )).into());
            }
            write(&path, verified_candidate)?;
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
            ))
            .into());
        }
    }
    // 提交确认后才清理操作目录；普通迁移备份已经另行保留。
    if let Err(error) = fs::remove_dir_all(&directory)
        && error.kind() != std::io::ErrorKind::NotFound
    {
        tracing::warn!(error = %error, "config migration operation directory cleanup failed");
    }
    Ok(target_is_current.then_some(candidate_config))
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

/// journal 资源集合的身份校验。
///
/// 磁盘上的 journal 是外部可变输入：`resources` 为空、首项不是主配置、主配置缺失或重复，都会让
/// 后续"第 0 项就是主配置"的假设失效（越界 panic 或把 Profile 当主配置）。这里在读取任何资源、
/// 复制凭据与写入之前直接拒绝，保持 journal 与全部文件原样，也不补造/重排资源。
fn validate_journal_resources(journal: &MigrationJournal) -> Result<()> {
    let Some(first) = journal.resources.first() else {
        return Err(PureError::ConfigError(
            "Studio config migration journal has no resources; existing files preserved"
                .to_string(),
        ));
    };
    if first.relative_path != super::STUDIO_CONFIG_FILE_NAME {
        return Err(PureError::ConfigError(format!(
            "Studio config migration journal must start with {}; existing files preserved",
            super::STUDIO_CONFIG_FILE_NAME
        )));
    }
    let mut seen: std::collections::BTreeSet<&str> = std::collections::BTreeSet::new();
    for resource in &journal.resources {
        if !seen.insert(resource.relative_path.as_str()) {
            return Err(PureError::ConfigError(format!(
                "Studio config migration journal repeats resource {}; existing files preserved",
                resource.relative_path
            )));
        }
    }
    // 23 及以上的历史 producer 只为规范化 Profile 保留原字节，从不生成 Profile 计划：除主配置外的
    // 任何资源都属于损坏/矛盾日志，按非法拓扑直接拒绝——不为不存在的 producer 增加兼容接受分支，
    // 也不重排或默认抹掉该资源。
    if journal.source_version > LEGACY_ACCOUNT_SCHEMA && journal.resources.len() != 1 {
        return Err(PureError::ConfigError(format!(
            "Studio config migration source {} has unexpected additional resources; existing files preserved",
            journal.source_version
        )));
    }
    // 18..22 的附加资源只有用户 Profile：历史 producer 只产生 `agents/<profile_id>.toml`。路径身份
    // 按原字符串校验（不 trim、不归一化、不重排），防止自洽的 journal 把任意文件写到配置目录其它
    // 位置；profile id 复用现有配置校验规则。
    if journal.source_version <= LEGACY_ACCOUNT_SCHEMA {
        for resource in journal.resources.iter().skip(1) {
            validate_profile_resource_path(&resource.relative_path)?;
        }
    }
    Ok(())
}

/// 迁移 journal 中用户 Profile 资源的唯一合法形状：`agents/<profile_id>.toml`。
fn validate_profile_resource_path(relative_path: &str) -> Result<()> {
    let rejected = || {
        PureError::ConfigError(format!(
            "Studio config migration resource `{relative_path}` is not a user Agent Profile; existing files preserved"
        ))
    };
    let Some(rest) = relative_path.strip_prefix("agents/") else {
        return Err(rejected());
    };
    let Some(profile_id) = rest.strip_suffix(".toml") else {
        return Err(rejected());
    };
    // 只允许单一组件：绝对路径、嵌套目录、`.`/`..` 段与额外分隔符都在这里被拒。
    if profile_id.is_empty() || profile_id.contains('/') || profile_id.contains('\\') {
        return Err(rejected());
    }
    // Reserved identities and builtin child declarations are rejected before any resource IO.
    validate_user_agent_profile_id(profile_id).map_err(|_| rejected())?;
    Ok(())
}

/// 迁移操作的源/目标元数据校验；任何矛盾都在凭据复制或资源写入之前 fail closed。
///
/// 支持范围是 `18 <= source < target <= 当前 schema`。只判范围不足以识别"原件其实是 schema 22、
/// 日志却记成 source 23/target 24"这类矛盾：那会静默跳过旧 `provider:<id>` 凭据复制。
fn validate_operation_metadata(
    source_version: u32,
    target_version: u32,
    original: &[u8],
) -> Result<()> {
    if !(23..=STUDIO_CONFIG_SCHEMA_VERSION).contains(&target_version) {
        return Err(PureError::ConfigError(format!(
            "Studio config migration target {target_version} is not supported; existing files preserved"
        )));
    }
    if !(OLDEST_SUPPORTED_SCHEMA..target_version).contains(&source_version) {
        return Err(PureError::ConfigError(format!(
            "Studio config migration source {source_version} is not supported for target {target_version}; existing files preserved"
        )));
    }
    let actual = document_schema_version(original)?;
    if actual != source_version {
        return Err(PureError::ConfigError(format!(
            "Studio config migration records source {source_version} but the preserved original is schema {actual}; existing files preserved"
        )));
    }
    Ok(())
}

/// 只读取文档的 `schema_version`，不做完整解码（原件可能是已退役形状）。
fn document_schema_version(content: &[u8]) -> Result<u32> {
    #[derive(serde::Deserialize)]
    struct Version {
        schema_version: u32,
    }
    let text = std::str::from_utf8(content).map_err(|error| {
        PureError::ConfigError(format!(
            "preserved Studio config original is not UTF-8: {error}; existing files preserved"
        ))
    })?;
    toml::from_str::<Version>(text)
        .map(|version| version.schema_version)
        .map_err(|_| {
            PureError::ConfigError(
                "preserved Studio config original has no readable schema version; existing files preserved"
                    .to_string(),
            )
        })
}

/// 提交前对**本次 journal 的全部资源**做摘要与磁盘状态核对，并返回唯一消费的快照。
///
/// 受保护原件与候选字节都必须匹配各自记录的摘要：原件被改成"仍合法但内容不同"时（例如内联
/// `bearer_token` 换成另一个字符串）必须在这里失败，绝不能把未验证的值导入凭据。候选被改成另一份
/// 仍可解析的 TOML 同样在这里失败。返回的 [`ResourcePlan`] 按 journal 顺序给出已核验字节，后续
/// 解析、token 提取、引用校验与落盘都只消费这份快照，不再二次读取原件/候选。
fn verify_pending_resources(
    paths: &ConfigPaths,
    directory: &Path,
    journal: &MigrationJournal,
) -> Result<Vec<ResourcePlan>> {
    let mut verified = Vec::with_capacity(journal.resources.len());
    for resource in &journal.resources {
        // 保留真实 IO 类别与 source：缺失、权限或坏链接不能被统一说成 "missing"。
        let original = fs::read(
            directory
                .join(ORIGINAL_DIR_NAME)
                .join(&resource.relative_path),
        )?;
        if digest(&original) != resource.original_hash {
            return Err(PureError::ConfigError(format!(
                "Studio config resource {} preserved original no longer matches its recorded digest; existing files preserved",
                resource.relative_path
            )));
        }
        let candidate = read_candidate(directory, &resource.relative_path)?;
        if digest(&candidate) != resource.candidate_hash {
            return Err(PureError::ConfigError(format!(
                "Studio config resource {} candidate no longer matches its recorded digest; existing files preserved",
                resource.relative_path
            )));
        }
        let disk = fs::read(config_resource_path(paths, &resource.relative_path))?;
        let disk_hash = digest(&disk);
        if disk_hash != resource.original_hash && disk_hash != resource.candidate_hash {
            return Err(PureError::ConfigError(format!(
                "Studio config resource {} changed outside the pending migration; existing files preserved",
                resource.relative_path
            )));
        }
        verified.push(ResourcePlan {
            relative_path: resource.relative_path.clone(),
            original,
            candidate,
        });
    }
    Ok(verified)
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

/// 把一份用户 Profile 的 `provider`/`model` 转为 `account_id`/`model_id`。
///
/// 只改写这两个已知键；其它键与用户文本原样保留。旧新键同时存在但不一致时明确报冲突，
/// 不以覆盖丢弃用户选择。
#[cfg(test)]
pub(super) fn rewrite_profile_document(text: &str) -> Result<String> {
    let mut table: toml::Table = toml::from_str(text)
        .map_err(|error| PureError::ConfigError(format!("invalid Agent Profile TOML: {error}")))?;
    move_key(&mut table, "provider", "account_id")?;
    move_key(&mut table, "model", "model_id")?;
    toml::to_string(&table)
        .map_err(|error| PureError::ConfigError(format!("could not encode Agent Profile: {error}")))
}

/// 主配置迁移边界的账号接入改写：22→23 的 Provider/Preset → Account/Template 改写，以及
/// 24→25 退役旧 ACP 接入的执行字段。
#[cfg(test)]
pub(super) fn rewrite_account_document(
    text: &str,
    inline_tokens: &mut BTreeMap<String, String>,
) -> Result<String> {
    let loaded = super::document_migration::load_main(Path::new("config.toml"), text)
        .map_err(test_migration_error)?;
    *inline_tokens = inline_tokens_from_verified_original(text.as_bytes());
    loaded.document.encode().map_err(test_migration_error)
}

#[cfg(test)]
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

/// 从受保护原件重新提取内联凭据，供中断后接续使用；不写入操作记录。
/// 从**已核验**的受保护原件字节中提取内联凭据；不接受路径，避免读取校验之后的新值。
fn inline_tokens_from_verified_original(original: &[u8]) -> BTreeMap<String, String> {
    let mut tokens = BTreeMap::new();
    let Ok(text) = std::str::from_utf8(original) else {
        return tokens;
    };
    let Ok(value) = toml::from_str::<toml::Value>(text) else {
        return tokens;
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
    tokens
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

    /// 与启动路径一致的候选准备：先做迁移边界的文档改写，再走可恢复提交。
    fn migrate_fixture_from(
        fixture: &Fixture,
        source_version: u32,
        write: ResourceWriter<'_>,
    ) -> Result<StudioConfig> {
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
            MigrationSource {
                original: &original,
                source_version,
                candidate: candidate.into_bytes(),
                inline_tokens,
            },
            write,
        )
    }

    fn migrate_fixture(fixture: &Fixture, write: ResourceWriter<'_>) -> Result<StudioConfig> {
        migrate_fixture_from(fixture, LEGACY_ACCOUNT_SCHEMA, write)
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
        assert!(persisted.contains(&format!("schema_version = {STUDIO_CONFIG_SCHEMA_VERSION}")));
        assert!(!persisted.contains("models.providers"));
    }

    /// schema 24 的 ACP 账号带旧 `program`/`args`（旧版本原样写进配置）；25 只保留 ID、名称与 provider。
    const LEGACY_ACP_BLOCK: &str = "\n[acp.accounts.antigravity-1]\n\
         name = \"Antigravity 主账号\"\n\
         provider = \"antigravity\"\n\
         program = \"/opt/legacy/agy_acp_server.par\"\n\
         args = [\"--uid=\"]\n";

    /// 24→25 的公共基线：真实 22→25 迁移结果回标成 schema 24（两个版本只差 ACP 执行字段），
    /// 复用既有 fixture/迁移工具，不另造框架。
    struct Schema24Bases {
        /// 保存临时目录，避免基线文件被提前删除。
        _legacy: Fixture,
        baseline: StudioConfig,
        document: String,
        profile: String,
    }

    fn schema_24_bases() -> Schema24Bases {
        let legacy = make_fixture(LEGACY_CONFIG, Some(LEGACY_PROFILE));
        let baseline = migrate_fixture(&legacy, &atomic_write).expect("schema 22 migrates");
        let profile = fs::read(legacy.paths.agents_dir().join("verify.toml")).unwrap();
        let persisted = fs::read_to_string(legacy.paths.config_file()).unwrap();
        let current = format!("schema_version = {STUDIO_CONFIG_SCHEMA_VERSION}");
        assert!(
            persisted.contains(&current),
            "migrated config carries the current schema version"
        );
        Schema24Bases {
            _legacy: legacy,
            baseline,
            document: persisted
                .replace(&current, "schema_version = 24")
                .replace("authentication = \"apiKey\"\n", ""),
            profile: String::from_utf8(profile).expect("profile stays UTF-8"),
        }
    }

    #[test]
    fn schema_24_retires_acp_execution_fields_and_preserves_native_config() {
        let bases = schema_24_bases();
        // 同字节输入，只有是否带旧 ACP 执行字段的差别。
        let plain = make_fixture(&bases.document, Some(bases.profile.as_str()));
        let migrated_plain =
            migrate_fixture_from(&plain, 24, &atomic_write).expect("schema 24 migrates");
        let with_acp = make_fixture(
            &format!("{}{LEGACY_ACP_BLOCK}", bases.document),
            Some(bases.profile.as_str()),
        );
        with_acp
            .credentials
            .seed_legacy_provider("deepseek", "native-secret");
        let migrated_acp =
            migrate_fixture_from(&with_acp, 24, &atomic_write).expect("schema 24 migrates");

        // ACP 接入保留稳定 ID、名称与 provider；执行字段退出当前结构。
        assert_eq!(migrated_acp.acp.accounts.len(), 1);
        let account = migrated_acp
            .acp
            .accounts
            .get("antigravity-1")
            .expect("ACP account keeps its id");
        assert_eq!(account.name, "Antigravity 主账号");
        assert_eq!(account.provider, crate::config::AcpProvider::Antigravity);
        assert!(migrated_plain.acp.accounts.is_empty());

        // 全部其它事实逐项相同：Native 账号（含 endpoint/模板/覆盖）、全部路由、模式路由、MCP/LSP/
        // Skills/UI 等设置；退役 ACP 执行字段不改变其中任何一项。
        let mut without_acp = migrated_acp.clone();
        without_acp.acp = Default::default();
        assert_eq!(without_acp, migrated_plain);
        assert_eq!(migrated_acp.models, bases.baseline.models);
        assert_eq!(
            migrated_acp.mode_model_routes,
            bases.baseline.mode_model_routes
        );
        assert_eq!(migrated_acp.skills, bases.baseline.skills);
        assert_eq!(migrated_acp.mcp, bases.baseline.mcp);
        assert_eq!(migrated_acp.lsp, bases.baseline.lsp);
        assert_eq!(migrated_acp.ui, bases.baseline.ui);

        // 显式列出账号/路由/模式路由集合，避免只靠整体相等掩盖"某类整体消失"。
        let accounts: Vec<&str> = migrated_acp
            .models
            .accounts
            .keys()
            .map(pl_model::config::AccountId::as_str)
            .collect();
        assert_eq!(accounts, vec!["deepseek", "second"]);
        let routes: Vec<&str> = migrated_acp
            .models
            .routes
            .keys()
            .map(pl_model::config::AgentRoleId::as_str)
            .collect();
        assert_eq!(
            routes,
            vec!["executor", "explorer", "reviewer", "worktree_executor"]
        );
        assert!(
            migrated_acp
                .mode_model_routes
                .contains_key(&pl_protocol::ThreadModeId::simple())
        );
        assert!(
            migrated_acp
                .mode_model_routes
                .contains_key(&pl_protocol::ThreadModeId::task())
        );

        // 23 及以上不再访问旧 `provider:<id>` 命名空间：迁移只处理结构，不复制旧凭据，
        // 也不删除或改写既有旧项（正常凭据关联早已在 22→23 边界完成）。
        assert_eq!(with_acp.credentials.load("deepseek").unwrap(), None);
        assert_eq!(
            with_acp.credentials.legacy_provider_secret("deepseek"),
            Some("native-secret".to_string())
        );

        // Profile 在 24→25 不重排：字节完全保留。
        assert_eq!(
            fs::read(with_acp.paths.agents_dir().join("verify.toml")).unwrap(),
            bases.profile.as_bytes()
        );

        let persisted = fs::read_to_string(with_acp.paths.config_file()).unwrap();
        assert!(persisted.contains(&format!("schema_version = {STUDIO_CONFIG_SCHEMA_VERSION}")));
        assert!(persisted.contains("[acp.accounts.antigravity-1]"));
        assert!(!persisted.contains("program ="));
        assert!(!persisted.contains("--uid="));
        assert!(!operation_dir(&with_acp.paths).exists());
    }

    #[test]
    fn schema_24_startup_migration_keeps_original_backup_and_profile_bytes() {
        let bases = schema_24_bases();
        let original = format!("{}{LEGACY_ACP_BLOCK}", bases.document);
        let fixture = make_fixture(&original, Some(bases.profile.as_str()));
        // 真实启动路径：版本分派 → 数据保全迁移 → 原件备份 → 候选校验 → 逐个原子提交。
        let migrated = crate::config::ConfigStore::new(fixture.paths.clone())
            .load_for_startup()
            .expect("schema 24 startup migration succeeds");

        assert_eq!(migrated.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        // 全部 Native 账号/路由/模式路由保持。
        assert_eq!(migrated.models, bases.baseline.models);
        assert_eq!(migrated.mode_model_routes, bases.baseline.mode_model_routes);
        // ACP 接入保留 ID/名称/provider，执行字段退役。
        let account = migrated
            .acp
            .accounts
            .get("antigravity-1")
            .expect("ACP account keeps its id");
        assert_eq!(account.name, "Antigravity 主账号");
        assert_eq!(account.provider, crate::config::AcpProvider::Antigravity);
        // Profile 原字节保留。
        assert_eq!(
            fs::read(fixture.paths.agents_dir().join("verify.toml")).unwrap(),
            bases.profile.as_bytes()
        );
        // 备份保存的是**迁移前原件**，其中仍含已退役的 program/args。
        let mut backups: Vec<std::path::PathBuf> = fs::read_dir(fixture.paths.config_dir())
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .filter(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| {
                        name.starts_with("config.toml.migrated.") && name.ends_with(".bak")
                    })
            })
            .collect();
        backups.sort();
        assert_eq!(backups.len(), 1, "exactly one migration backup");
        assert_eq!(fs::read(&backups[0]).unwrap(), original.as_bytes());
        // 现役配置不再含旧执行字段。
        let persisted = fs::read_to_string(fixture.paths.config_file()).unwrap();
        assert!(persisted.contains(&format!("schema_version = {STUDIO_CONFIG_SCHEMA_VERSION}")));
        assert!(!persisted.contains("program ="));
        assert!(!persisted.contains("--uid="));
        assert!(!operation_dir(&fixture.paths).exists());
    }

    #[test]
    fn current_schema_rejects_retired_acp_execution_fields() {
        let bases = schema_24_bases();
        let document = format!(
            "{}{LEGACY_ACP_BLOCK}",
            crate::config::store::serialize_persisted_config(&bases.baseline).unwrap()
        );
        assert!(
            crate::config::store::parse_migrated_config(document.as_bytes()).is_err(),
            "current schema must not silently accept program/args"
        );
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
        assert_eq!(resumed.target_version, STUDIO_CONFIG_SCHEMA_VERSION);
        let resumed_config = resumed
            .config
            .expect("a current-target operation yields the canonical config");
        assert_eq!(resumed_config.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
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
        fn read_transaction(&self, alias: &str) -> Result<Option<String>> {
            self.inner.read_transaction(alias)
        }
        fn write_transaction(&self, alias: &str, payload: &str) -> Result<()> {
            self.inner.write_transaction(alias, payload)
        }
        fn delete_transaction(&self, alias: &str) -> Result<()> {
            self.inner.delete_transaction(alias)
        }
        fn account_lock_directory(
            &self,
            isolated_root: &std::path::Path,
        ) -> Result<std::path::PathBuf> {
            self.inner.account_lock_directory(isolated_root)
        }
        fn load_strict(&self, account_id: &str) -> Result<Option<String>> {
            self.inner.load_strict(account_id)
        }
        fn save_strict(&self, account_id: &str, secret: &str) -> Result<()> {
            self.inner.save_strict(account_id, secret)
        }
        fn delete_strict(&self, account_id: &str) -> Result<()> {
            self.inner.delete_strict(account_id)
        }
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
        fn read_bot_system(
            &self,
            bot_id: &str,
        ) -> std::result::Result<
            super::super::credential::BotProtectedRead,
            super::super::credential::BotCredentialIoError,
        > {
            self.inner.read_bot_system(bot_id)
        }
        fn read_bot_lease(
            &self,
            bot_id: &str,
        ) -> std::result::Result<Option<String>, super::super::credential::BotCredentialIoError>
        {
            self.inner.read_bot_lease(bot_id)
        }
        fn persist_bot_protected(
            &self,
            bot_id: &str,
            payload: &str,
        ) -> std::result::Result<
            super::super::credential::BotProtectedPersist,
            super::super::credential::BotCredentialIoError,
        > {
            self.inner.persist_bot_protected(bot_id, payload)
        }
        fn lease_bot_protected(
            &self,
            bot_id: &str,
            payload: &str,
        ) -> std::result::Result<(), super::super::credential::BotCredentialIoError> {
            self.inner.lease_bot_protected(bot_id, payload)
        }
        fn recycle_bot_system(
            &self,
            bot_id: &str,
        ) -> std::result::Result<(), super::super::credential::BotCredentialIoError> {
            self.inner.recycle_bot_system(bot_id)
        }
        fn recycle_bot_lease(
            &self,
            bot_id: &str,
        ) -> std::result::Result<(), super::super::credential::BotCredentialIoError> {
            self.inner.recycle_bot_lease(bot_id)
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
            MigrationSource {
                original: &original,
                source_version: LEGACY_ACCOUNT_SCHEMA,
                candidate: candidate.into_bytes(),
                inline_tokens,
            },
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
            fn read_transaction(&self, alias: &str) -> Result<Option<String>> {
                self.0.read_transaction(alias)
            }
            fn write_transaction(&self, alias: &str, payload: &str) -> Result<()> {
                self.0.write_transaction(alias, payload)
            }
            fn delete_transaction(&self, alias: &str) -> Result<()> {
                self.0.delete_transaction(alias)
            }
            fn account_lock_directory(
                &self,
                isolated_root: &std::path::Path,
            ) -> Result<std::path::PathBuf> {
                self.0.account_lock_directory(isolated_root)
            }
            fn load_strict(&self, _account_id: &str) -> Result<Option<String>> {
                Err(PureError::ConfigError(
                    "credential service unavailable".into(),
                ))
            }
            fn save_strict(&self, _account_id: &str, _secret: &str) -> Result<()> {
                Err(PureError::ConfigError(
                    "credential service unavailable".into(),
                ))
            }
            fn delete_strict(&self, _account_id: &str) -> Result<()> {
                Err(PureError::ConfigError(
                    "credential service unavailable".into(),
                ))
            }
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
            fn read_bot_system(
                &self,
                _bot_id: &str,
            ) -> std::result::Result<
                super::super::credential::BotProtectedRead,
                super::super::credential::BotCredentialIoError,
            > {
                Err(super::super::credential::BotCredentialIoError {
                    kind: super::super::credential::BotCredentialIoKind::Unavailable,
                })
            }
            fn read_bot_lease(
                &self,
                _bot_id: &str,
            ) -> std::result::Result<Option<String>, super::super::credential::BotCredentialIoError>
            {
                Ok(None)
            }
            fn persist_bot_protected(
                &self,
                _bot_id: &str,
                _payload: &str,
            ) -> std::result::Result<
                super::super::credential::BotProtectedPersist,
                super::super::credential::BotCredentialIoError,
            > {
                Err(super::super::credential::BotCredentialIoError {
                    kind: super::super::credential::BotCredentialIoKind::Unavailable,
                })
            }
            fn lease_bot_protected(
                &self,
                _bot_id: &str,
                _payload: &str,
            ) -> std::result::Result<(), super::super::credential::BotCredentialIoError>
            {
                Err(super::super::credential::BotCredentialIoError {
                    kind: super::super::credential::BotCredentialIoKind::Unavailable,
                })
            }
            fn recycle_bot_system(
                &self,
                _bot_id: &str,
            ) -> std::result::Result<(), super::super::credential::BotCredentialIoError>
            {
                Err(super::super::credential::BotCredentialIoError {
                    kind: super::super::credential::BotCredentialIoKind::Unavailable,
                })
            }
            fn recycle_bot_lease(
                &self,
                _bot_id: &str,
            ) -> std::result::Result<(), super::super::credential::BotCredentialIoError>
            {
                Ok(())
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
                MigrationSource {
                    original: &original,
                    source_version: LEGACY_ACCOUNT_SCHEMA,
                    candidate: candidate.into_bytes(),
                    inline_tokens,
                },
                &atomic_write,
            )
            .is_err()
        );
        assert_eq!(fs::read(fixture.paths.config_file()).unwrap(), original);
    }

    /// 迁移备份文件（`config.toml.migrated.*.bak`），按路径排序。
    fn config_backups(paths: &ConfigPaths) -> Vec<std::path::PathBuf> {
        let prefix = format!("{}.migrated.", super::super::STUDIO_CONFIG_FILE_NAME);
        let mut backups: Vec<std::path::PathBuf> = fs::read_dir(paths.config_dir())
            .expect("read config directory")
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name.starts_with(&prefix) && name.ends_with(".bak"))
            })
            .collect();
        backups.sort();
        backups
    }

    /// schema 24 的 main 风格文档：显式分发设置、模型禁用与计费覆盖。
    fn schema_24_main_document(with_legacy_acp: bool) -> String {
        let config = StudioConfig::default_config().expect("default config");
        let base = crate::config::store::serialize_persisted_config(&config)
            .expect("encode default config");
        let current = format!("schema_version = {STUDIO_CONFIG_SCHEMA_VERSION}");
        assert!(
            base.contains(&current),
            "default config carries its version"
        );
        let mut document: toml::Value = toml::from_str(&base).expect("parse default config");
        let table = document.as_table_mut().expect("document table");
        table.insert("schema_version".into(), toml::Value::Integer(24));
        let mut delegation = toml::Table::new();
        delegation.insert("mode".into(), toml::Value::String("automatic".into()));
        delegation.insert("preference".into(), toml::Value::String("fast".into()));
        table.insert("delegation".into(), toml::Value::Table(delegation));
        let account = table["models"]["accounts"]["deepseek"]
            .as_table_mut()
            .expect("deepseek account table");
        account.remove("authentication");
        account.insert(
            "disabled_models".into(),
            toml::Value::Array(vec![toml::Value::String("deepseek-flash".into())]),
        );
        account.insert(
            "billing_kind".into(),
            toml::Value::String("subscription".into()),
        );
        if with_legacy_acp {
            let mut acp = toml::Table::new();
            let mut legacy = toml::Table::new();
            legacy.insert(
                "name".into(),
                toml::Value::String("Antigravity 主账号".into()),
            );
            legacy.insert("provider".into(), toml::Value::String("antigravity".into()));
            legacy.insert(
                "program".into(),
                toml::Value::String("/opt/legacy/agy_acp_server.par".into()),
            );
            legacy.insert(
                "args".into(),
                toml::Value::Array(vec![toml::Value::String("--uid=".into())]),
            );
            let mut accounts = toml::Table::new();
            accounts.insert("antigravity-1".into(), toml::Value::Table(legacy));
            acp.insert("accounts".into(), toml::Value::Table(accounts));
            table.insert("acp".into(), toml::Value::Table(acp));
        }
        toml::to_string(&document).expect("encode schema 24 fixture")
    }

    fn assert_main_fields_preserved(config: &StudioConfig) {
        assert_eq!(
            config.delegation.mode,
            pl_protocol::DelegationMode::Automatic
        );
        assert_eq!(
            config.delegation.preference,
            pl_protocol::DelegationPreference::Fast
        );
        let account =
            &config.models.accounts[&pl_model::config::AccountId::new("deepseek").unwrap()];
        assert_eq!(
            account
                .model_enabled_overrides()
                .get("deepseek-flash")
                .copied(),
            Some(false)
        );
        assert_eq!(
            account.billing_kind,
            Some(pl_protocol::BillingKind::Subscription)
        );
    }

    fn schema_25_with_disabled_estimation() -> String {
        let mut document: toml::Value = toml::from_str(&schema_24_main_document(false)).unwrap();
        document["schema_version"] = 25.into();
        let accounts = document["models"]["accounts"].as_table_mut().unwrap();
        accounts["deepseek"]
            .as_table_mut()
            .unwrap()
            .insert("pricing_mode".into(), "disabled".into());
        let mut custom = accounts["deepseek"].as_table().unwrap().clone();
        custom.remove("template");
        custom.remove("billing_kind");
        custom.insert("base_url".into(), "https://example.test/v1".into());
        accounts.insert("legacy-disabled".into(), toml::Value::Table(custom));
        toml::to_string(&document).unwrap()
    }

    #[test]
    fn schema_25_retires_estimation_without_inventing_no_charge() {
        let original = schema_25_with_disabled_estimation();
        let profile = canonical_profile_on_disk();
        let fixture = make_fixture(&original, Some(&profile));
        let credentials = std::sync::Arc::new(MemoryCredentialStore::default());
        credentials
            .save("deepseek", "current-account-secret")
            .unwrap();
        let store = crate::config::ConfigStore::with_shared_credentials(
            fixture.paths.clone(),
            std::sync::Arc::clone(&credentials),
        );
        let migrated = store.load_for_startup().expect("schema 25 migrates");
        assert_main_fields_preserved(&migrated);
        let custom = &migrated.models.accounts
            [&pl_model::config::AccountId::new("legacy-disabled").unwrap()];
        assert_eq!(custom.billing_kind, None);
        assert_eq!(
            custom.billing_kind().unwrap(),
            pl_protocol::BillingKind::Unknown
        );
        assert_eq!(
            pl_protocol::PricingMode::from(custom.billing_kind().unwrap()),
            pl_protocol::PricingMode::Catalog
        );
        assert_eq!(
            credentials.load("deepseek").unwrap().as_deref(),
            Some("current-account-secret")
        );
        let persisted = fs::read_to_string(fixture.paths.config_file()).unwrap();
        assert!(!persisted.contains("pricing_mode"));
        let mut expected: toml::Value = toml::from_str(&original).unwrap();
        expected["schema_version"] = i64::from(STUDIO_CONFIG_SCHEMA_VERSION).into();
        for (_, account) in expected["models"]["accounts"]
            .as_table_mut()
            .unwrap()
            .iter_mut()
        {
            account.as_table_mut().unwrap().remove("pricing_mode");
            account
                .as_table_mut()
                .unwrap()
                .insert("authentication".into(), "apiKey".into());
            account.as_table_mut().unwrap().remove("disabled_models");
            account.as_table_mut().unwrap().insert(
                "model_enabled_overrides".into(),
                toml::Value::Table(
                    [("deepseek-flash".into(), false.into())]
                        .into_iter()
                        .collect(),
                ),
            );
        }
        assert_eq!(toml::from_str::<toml::Value>(&persisted).unwrap(), expected);
        assert_eq!(
            fs::read_to_string(fixture.paths.agents_dir().join("verify.toml")).unwrap(),
            profile
        );
        assert_eq!(
            fs::read(config_backups(&fixture.paths).pop().unwrap()).unwrap(),
            original.as_bytes()
        );
        assert!(!operation_dir(&fixture.paths).exists());
        store.load_for_startup().expect("upgraded config reloads");
        assert_eq!(config_backups(&fixture.paths).len(), 1);
    }

    #[test]
    fn schema_26_enablement_migrates_through_startup_preserving_other_configuration() {
        let mut original: toml::Value = toml::from_str(&schema_24_main_document(true)).unwrap();
        original["schema_version"] = 26.into();
        let acp = original["acp"]["accounts"]["antigravity-1"]
            .as_table_mut()
            .unwrap();
        acp.remove("program");
        acp.remove("args");
        let catalog = original["models"]["accounts"]["deepseek"]["catalog"]
            .as_table_mut()
            .unwrap();
        let manual = pl_model::model::ModelInfo::compatible("manual-preserved");
        catalog.insert(
            "additional_models".into(),
            toml::Value::Array(vec![toml::Value::try_from(manual).unwrap()]),
        );
        catalog.insert(
            "connection_overrides".into(),
            toml::Value::Table(
                [("manual-preserved".into(), "http".into())]
                    .into_iter()
                    .collect(),
            ),
        );
        catalog.insert(
            "auto_compact_overrides".into(),
            toml::Value::Table(
                [("manual-preserved".into(), 10_000.into())]
                    .into_iter()
                    .collect(),
            ),
        );
        let original = toml::to_string(&original).unwrap();
        assert!(original.contains("disabled_models"));
        assert!(!original.contains("model_enabled_overrides"));
        let profile = canonical_profile_on_disk();
        let fixture = make_fixture(&original, Some(&profile));
        let credentials = std::sync::Arc::new(MemoryCredentialStore::default());
        credentials
            .save("deepseek", "linked-account-secret")
            .unwrap();
        let store = crate::config::ConfigStore::with_shared_credentials(
            fixture.paths.clone(),
            std::sync::Arc::clone(&credentials),
        );
        let loaded = store
            .load_for_startup()
            .expect("schema 26 startup migration");
        assert_main_fields_preserved(&loaded);
        assert_eq!(loaded.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        let mut expected: toml::Value = toml::from_str(&original).unwrap();
        expected["schema_version"] = STUDIO_CONFIG_SCHEMA_VERSION.into();
        let account = expected["models"]["accounts"]["deepseek"]
            .as_table_mut()
            .unwrap();
        account.remove("disabled_models");
        account.insert("authentication".into(), "apiKey".into());
        account.insert(
            "model_enabled_overrides".into(),
            toml::Value::Table(
                [("deepseek-flash".into(), false.into())]
                    .into_iter()
                    .collect(),
            ),
        );
        let persisted = fs::read_to_string(fixture.paths.config_file()).unwrap();
        assert!(!persisted.contains("disabled_models"));
        assert_eq!(toml::from_str::<toml::Value>(&persisted).unwrap(), expected);
        assert_eq!(
            credentials.load("deepseek").unwrap().as_deref(),
            Some("linked-account-secret")
        );
        assert_eq!(
            fs::read_to_string(fixture.paths.agents_dir().join("verify.toml")).unwrap(),
            profile
        );
        assert_eq!(
            fs::read(config_backups(&fixture.paths).pop().unwrap()).unwrap(),
            original.as_bytes()
        );
        assert!(!operation_dir(&fixture.paths).exists());
        assert_main_fields_preserved(&store.load_for_startup().unwrap());
        assert_eq!(config_backups(&fixture.paths).len(), 1);

        // 当前 schema 不把旧字段静默忽略或当成运行时兼容入口。
        expected["models"]["accounts"]["deepseek"]
            .as_table_mut()
            .unwrap()
            .insert(
                "disabled_models".into(),
                toml::Value::Array(vec!["deepseek-flash".into()]),
            );
        let retired = toml::to_string(&expected).unwrap();
        fs::write(fixture.paths.config_file(), &retired).unwrap();
        assert!(store.load_for_startup().is_err());
        assert_eq!(
            fs::read_to_string(fixture.paths.config_file()).unwrap(),
            retired
        );
        assert_eq!(config_backups(&fixture.paths).len(), 1);
    }

    #[test]
    fn pending_schema_25_commits_original_candidate_before_retiring_estimation() {
        let original = schema_24_main_document(false);
        let candidate = schema_25_with_disabled_estimation();
        let profile = canonical_profile_on_disk();
        let fixture = make_fixture(&original, Some(&profile));
        write_pending_operation(
            &fixture.paths,
            24,
            25,
            &[PendingResource {
                relative_path: super::super::STUDIO_CONFIG_FILE_NAME.into(),
                original: original.into_bytes(),
                candidate: candidate.as_bytes().to_vec(),
            }],
        );
        let resumed = resume(&fixture.paths, &fixture.credentials)
            .unwrap()
            .unwrap();
        assert_eq!(resumed.target_version, 25);
        assert!(resumed.config.is_none());
        // The old journal's bytes/digests, not a current-shape reserialization, were committed.
        assert_eq!(
            fs::read(fixture.paths.config_file()).unwrap(),
            candidate.as_bytes()
        );
        let credentials = std::sync::Arc::new(MemoryCredentialStore::default());
        let migrated =
            crate::config::ConfigStore::with_shared_credentials(fixture.paths.clone(), credentials)
                .load_for_startup()
                .unwrap();
        assert_eq!(migrated.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        assert_main_fields_preserved(&migrated);
        let persisted = fs::read_to_string(fixture.paths.config_file()).unwrap();
        assert!(!persisted.contains("pricing_mode"));
        assert_eq!(
            fs::read(config_backups(&fixture.paths).pop().unwrap()).unwrap(),
            candidate.as_bytes()
        );
        assert_eq!(
            fs::read_to_string(fixture.paths.agents_dir().join("verify.toml")).unwrap(),
            profile
        );
        assert!(!operation_dir(&fixture.paths).exists());
    }

    #[test]
    fn schema_24_main_fields_survive_the_upgrade_to_current() {
        let fixture = make_fixture(&schema_24_main_document(false), None);
        let migrated =
            migrate_fixture_from(&fixture, 24, &atomic_write).expect("schema 24 migrates");
        assert_eq!(migrated.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        // 分发设置、模型禁用与计费覆盖都是显式意图：不能被字段级缺省覆盖回默认。
        assert_main_fields_preserved(&migrated);
        assert!(migrated.acp.accounts.is_empty());
        let persisted = fs::read_to_string(fixture.paths.config_file()).unwrap();
        assert!(persisted.contains("[delegation]"));
        assert!(persisted.contains("mode = \"automatic\""));
        assert!(persisted.contains("preference = \"fast\""));
        assert!(persisted.contains("billing_kind = \"subscription\""));
    }

    #[test]
    fn schema_24_mixed_config_retires_acp_fields_and_keeps_main_fields() {
        let fixture = make_fixture(&schema_24_main_document(true), None);
        let migrated =
            migrate_fixture_from(&fixture, 24, &atomic_write).expect("mixed schema 24 migrates");
        // ACP：保留 ID/名称/provider，执行字段退役。
        let account = migrated
            .acp
            .accounts
            .get("antigravity-1")
            .expect("ACP account keeps its id");
        assert_eq!(account.name, "Antigravity 主账号");
        assert_eq!(account.provider, crate::config::AcpProvider::Antigravity);
        // 同一份文档里的 main 显式字段同样保留（两组字段互不覆盖）。
        assert_main_fields_preserved(&migrated);
        let persisted = fs::read_to_string(fixture.paths.config_file()).unwrap();
        assert!(persisted.contains("[acp.accounts.antigravity-1]"));
        assert!(!persisted.contains("program ="));
        assert!(!persisted.contains("--uid="));
        assert!(persisted.contains("mode = \"automatic\""));
    }

    #[test]
    fn current_schema_without_new_optional_fields_loads_without_migration() {
        let config = StudioConfig::default_config().expect("default config");
        let base = crate::config::store::serialize_persisted_config(&config).expect("encode");
        let mut document: toml::Value = toml::from_str(&base).expect("parse");
        let table = document.as_table_mut().expect("document table");
        // 显式移除新增可选字段：当前 schema 必须按同一缺省语义有效读取。
        table.remove("delegation");
        for (_, account) in table["models"]["accounts"]
            .as_table_mut()
            .expect("accounts")
            .iter_mut()
        {
            let account = account.as_table_mut().expect("account table");
            account.remove("disabled_models");
            account.remove("billing_kind");
        }
        let document = toml::to_string(&document).expect("encode");
        let fixture = make_fixture(&document, None);
        let loaded = crate::config::ConfigStore::new(fixture.paths.clone())
            .load_for_startup()
            .expect("current schema with missing optional fields loads");
        assert_eq!(loaded.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
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
        // 不降级、不重写：文件字节不变，也没有迁移备份或操作目录。
        assert_eq!(
            fs::read_to_string(fixture.paths.config_file()).unwrap(),
            document
        );
        assert!(config_backups(&fixture.paths).is_empty());
        assert!(!operation_dir(&fixture.paths).exists());
    }

    /// 一条待续操作资源：相对路径 + 受保护原件 + 候选字节。
    struct PendingResource {
        relative_path: String,
        original: Vec<u8>,
        candidate: Vec<u8>,
    }

    /// 直接按旧版本格式写入一个待续操作（original/candidate/journal），模拟旧目标的日志。
    fn write_pending_operation(
        paths: &ConfigPaths,
        source_version: u32,
        target_version: u32,
        resources: &[PendingResource],
    ) {
        let directory = operation_dir(paths);
        let _ = fs::remove_dir_all(&directory);
        fs::create_dir_all(directory.join(ORIGINAL_DIR_NAME)).unwrap();
        fs::create_dir_all(directory.join(CANDIDATE_DIR_NAME)).unwrap();
        for resource in resources {
            for kind in [ORIGINAL_DIR_NAME, CANDIDATE_DIR_NAME] {
                let path = directory.join(kind).join(&resource.relative_path);
                if let Some(parent) = path.parent() {
                    fs::create_dir_all(parent).unwrap();
                }
                let content = if kind == ORIGINAL_DIR_NAME {
                    &resource.original
                } else {
                    &resource.candidate
                };
                fs::write(path, content).unwrap();
            }
        }
        let journal = MigrationJournal {
            version: JOURNAL_VERSION,
            operation_id: format!("schema-{source_version}-to-{target_version}"),
            source_version,
            target_version,
            phase: MigrationPhase::Prepared,
            resources: resources
                .iter()
                .map(|resource| JournalResource {
                    relative_path: resource.relative_path.clone(),
                    original_hash: digest(&resource.original),
                    candidate_hash: digest(&resource.candidate),
                    replaced: false,
                })
                .collect(),
        };
        write_journal(&directory, &journal).unwrap();
    }

    /// 指定版本形状的规范化文档：去掉当前可选集合，作为候选或更高版本的"原件"。
    fn converted_document(version: u32) -> Vec<u8> {
        let config = StudioConfig::default_config().expect("default config");
        let base = crate::config::store::serialize_persisted_config(&config).expect("encode");
        let mut value: toml::Value = toml::from_str(&base).expect("parse");
        let table = value.as_table_mut().expect("document table");
        table.insert(
            "schema_version".into(),
            toml::Value::Integer(i64::from(version)),
        );
        table.remove("delegation");
        table.remove("acp");
        if version < 28 {
            for (_, account) in table["models"]["accounts"]
                .as_table_mut()
                .unwrap()
                .iter_mut()
            {
                account.as_table_mut().unwrap().remove("authentication");
            }
        }
        toml::to_string(&value)
            .expect("encode document")
            .into_bytes()
    }

    /// 旧版本真实形态的源文档：18..22 用旧 dialect/键，23+ 用已规范化文档。
    fn source_document(source_version: u32) -> Vec<u8> {
        if source_version <= LEGACY_ACCOUNT_SCHEMA {
            LEGACY_CONFIG.as_bytes().to_vec()
        } else {
            converted_document(source_version)
        }
    }

    /// 一个真实的旧 source=22→23 / 23→24 待续操作现场；store 与现场共享同一内存凭据库，
    /// 因此可以观察接续路径是否真的复制（或未复制）旧 `provider:<id>` 关联。
    struct PendingLegacy {
        _directory: tempfile::TempDir,
        paths: ConfigPaths,
        credentials: std::sync::Arc<crate::config::credential::MemoryCredentialStore>,
        store: crate::config::ConfigStore,
    }

    impl PendingLegacy {
        fn load(&self) -> Result<StudioConfig> {
            self.store.load_for_startup().map_err(|error| match error {
                super::super::ConfigRuntimeError::Migration(inner) => test_migration_error(inner),
                other => PureError::ConfigError(other.to_string()),
            })
        }
    }

    fn build_pending_operation(
        source_version: u32,
        target_version: u32,
        original: Vec<u8>,
        candidate_version: u32,
        profile: Option<&str>,
    ) -> PendingLegacy {
        let original_text = std::str::from_utf8(&original).expect("UTF-8 source document");
        let directory = tempfile::tempdir().expect("isolated config directory");
        let paths = ConfigPaths::from_config_dir(directory.path());
        fs::create_dir_all(paths.config_dir()).unwrap();
        fs::write(paths.config_file(), original_text).unwrap();
        if let Some(profile) = profile {
            fs::create_dir_all(paths.agents_dir()).unwrap();
            fs::write(paths.agents_dir().join("verify.toml"), profile).unwrap();
        }
        let credentials =
            std::sync::Arc::new(crate::config::credential::MemoryCredentialStore::default());
        let store = crate::config::ConfigStore::with_shared_credentials(
            paths.clone(),
            std::sync::Arc::clone(&credentials),
        );
        let mut resources = vec![PendingResource {
            relative_path: super::super::STUDIO_CONFIG_FILE_NAME.to_string(),
            original,
            candidate: converted_document(candidate_version),
        }];
        if let Some(profile) = profile {
            resources.push(PendingResource {
                relative_path: "agents/verify.toml".to_string(),
                original: profile.as_bytes().to_vec(),
                candidate: rewrite_profile_document(profile).unwrap().into_bytes(),
            });
        }
        write_pending_operation(&paths, source_version, target_version, &resources);
        PendingLegacy {
            _directory: directory,
            paths,
            credentials,
            store,
        }
    }

    /// 用显式资源集合构造待续操作现场（供资源集合身份负例使用）。
    fn build_pending_with_resources(
        source_version: u32,
        target_version: u32,
        live_config: Option<&[u8]>,
        live_profile: Option<&[u8]>,
        resources: &[PendingResource],
    ) -> PendingLegacy {
        let directory = tempfile::tempdir().expect("isolated config directory");
        let paths = ConfigPaths::from_config_dir(directory.path());
        fs::create_dir_all(paths.config_dir()).unwrap();
        if let Some(live) = live_config {
            fs::write(paths.config_file(), live).unwrap();
        }
        if let Some(profile) = live_profile {
            fs::create_dir_all(paths.agents_dir()).unwrap();
            fs::write(paths.agents_dir().join("verify.toml"), profile).unwrap();
        }
        let credentials =
            std::sync::Arc::new(crate::config::credential::MemoryCredentialStore::default());
        let store = crate::config::ConfigStore::with_shared_credentials(
            paths.clone(),
            std::sync::Arc::clone(&credentials),
        );
        write_pending_operation(&paths, source_version, target_version, resources);
        PendingLegacy {
            _directory: directory,
            paths,
            credentials,
            store,
        }
    }

    /// 自定义元数据的待续操作（供元数据矛盾负例使用）。
    fn pending_operation_with(
        source_version: u32,
        target_version: u32,
        original: Vec<u8>,
        candidate_version: u32,
    ) -> PendingLegacy {
        build_pending_operation(
            source_version,
            target_version,
            original,
            candidate_version,
            None,
        )
    }

    /// 磁盘上的规范化 Profile（带注释与空白，用于证明 23+ 原字节保留）。
    fn canonical_profile_on_disk() -> String {
        let imported = super::super::document_migration::load_profile(
            Path::new("verify.toml"),
            LEGACY_PROFILE,
        )
        .unwrap();
        format!(
            "# 用户 Profile 原字节必须保留\n\n{}",
            imported.document.encode().unwrap()
        )
    }

    fn legacy_canonical_profile_on_disk() -> String {
        format!(
            "# 用户 Profile 原字节必须保留\n\n{}",
            rewrite_profile_document(LEGACY_PROFILE).unwrap()
        )
    }

    /// 真实的旧 source=22→23 / 23→24 待续操作现场。
    ///
    /// 18..22 的 Profile 是 journal 资源（历史 producer 会改键）；23+ 的历史 producer 只生成主配置
    /// 计划，Profile 若是既有文件只做原字节保留——因此不进 journal。
    fn pending_legacy_fixture(
        source_version: u32,
        target_version: u32,
        with_profile: bool,
    ) -> PendingLegacy {
        let original = source_document(source_version);
        let mut resources = vec![PendingResource {
            relative_path: super::super::STUDIO_CONFIG_FILE_NAME.to_string(),
            original: original.clone(),
            candidate: converted_document(target_version),
        }];
        let (live_profile, include_profile_resource) = match with_profile {
            false => (None, false),
            true => (Some(()), source_version <= LEGACY_ACCOUNT_SCHEMA),
        };
        if include_profile_resource {
            resources.push(PendingResource {
                relative_path: "agents/verify.toml".to_string(),
                original: LEGACY_PROFILE.as_bytes().to_vec(),
                candidate: rewrite_profile_document(LEGACY_PROFILE)
                    .unwrap()
                    .into_bytes(),
            });
        }
        let live_profile_bytes = live_profile.map(|()| {
            if include_profile_resource {
                LEGACY_PROFILE.as_bytes().to_vec()
            } else {
                legacy_canonical_profile_on_disk().into_bytes()
            }
        });
        build_pending_with_resources(
            source_version,
            target_version,
            Some(&original),
            live_profile_bytes.as_deref(),
            &resources,
        )
    }

    fn candidate_config_bytes(paths: &ConfigPaths) -> Vec<u8> {
        fs::read(
            operation_dir(paths)
                .join(CANDIDATE_DIR_NAME)
                .join(super::super::STUDIO_CONFIG_FILE_NAME),
        )
        .unwrap()
    }

    fn journal_bytes(paths: &ConfigPaths) -> Vec<u8> {
        fs::read(operation_dir(paths).join(JOURNAL_FILE_NAME)).unwrap()
    }

    /// target 23/24 共用的成功恢复断言：先完成旧操作，再从已提交版本续升当前 schema。
    fn legacy_journal_round_trip(source_version: u32, target_version: u32) {
        for with_profile in [false, true] {
            let fixture = pending_legacy_fixture(source_version, target_version, with_profile);
            fixture
                .credentials
                .seed_legacy_provider("deepseek", "legacy-secret");
            let candidate = candidate_config_bytes(&fixture.paths);

            // 1) 提交故障：受管资源出现未证明的第三种状态 → 在凭据复制与任何写入之前 fail closed。
            let live_before = fs::read(fixture.paths.config_file()).unwrap();
            let journal_before = journal_bytes(&fixture.paths);
            fs::write(fixture.paths.config_file(), b"# external edit\n").unwrap();
            let error = fixture
                .load()
                .expect_err("unproven resource state fails closed");
            assert!(matches!(error, PureError::ConfigError(_)), "{error}");
            assert_eq!(
                fs::read(fixture.paths.config_file()).unwrap(),
                b"# external edit\n".to_vec()
            );
            // fail closed 早于凭据复制：旧项保持、当前账号仍无凭据。
            assert_eq!(fixture.credentials.load("deepseek").unwrap(), None);
            assert_eq!(
                fixture.credentials.legacy_provider_secret("deepseek"),
                Some("legacy-secret".to_string())
            );
            // 原件、候选与 journal 原字节保持不变。
            assert_eq!(journal_bytes(&fixture.paths), journal_before);
            assert_eq!(candidate_config_bytes(&fixture.paths), candidate);
            fs::write(fixture.paths.config_file(), &live_before).unwrap();

            // 2) 重开即恢复：完成旧目标后从已提交版本续升当前 schema。
            let loaded = fixture
                .load()
                .expect("legacy journal completes and continues to the current schema");
            assert_eq!(loaded.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
            // 旧 provider 命名空间只在 source<=22 的那一步复制；23+ 不访问。
            let expected = if source_version <= LEGACY_ACCOUNT_SCHEMA {
                Some("legacy-secret")
            } else {
                None
            };
            assert_eq!(
                fixture.credentials.load("deepseek").unwrap().as_deref(),
                expected
            );
            assert_eq!(
                fixture.credentials.legacy_provider_secret("deepseek"),
                Some("legacy-secret".to_string())
            );
            // 续升备份正是刚提交的旧目标候选字节（候选/摘要未被伪改）。
            let backups = config_backups(&fixture.paths);
            assert_eq!(backups.len(), 1);
            assert_eq!(fs::read(&backups[0]).unwrap(), candidate);
            assert!(!operation_dir(&fixture.paths).exists());
            let persisted = fs::read_to_string(fixture.paths.config_file()).unwrap();
            assert!(
                persisted.contains(&format!("schema_version = {STUDIO_CONFIG_SCHEMA_VERSION}"))
            );
            assert!(!persisted.contains("models.providers"));
            if with_profile {
                let profile = fs::read(fixture.paths.agents_dir().join("verify.toml")).unwrap();
                if source_version <= LEGACY_ACCOUNT_SCHEMA {
                    // 18..22 的 Profile 是 journal 资源：按原候选/步骤改键。
                    let profile = String::from_utf8(profile).unwrap();
                    assert!(profile.contains("account_id = \"deepseek\""));
                    assert!(profile.contains("model_id = \"deepseek-flash\""));
                    assert!(!profile.contains("provider ="));
                }
                let profile =
                    fs::read_to_string(fixture.paths.agents_dir().join("verify.toml")).unwrap();
                let loaded = super::super::document_migration::load_profile(
                    Path::new("verify.toml"),
                    &profile,
                )
                .unwrap();
                assert!(
                    !loaded.migrated,
                    "Profile independently reaches its own schema after the old operation"
                );
            }
        }
    }

    #[test]
    fn legacy_journal_targeting_23_recovers_then_upgrades_to_current() {
        legacy_journal_round_trip(LEGACY_ACCOUNT_SCHEMA, 23);
    }

    #[test]
    fn legacy_journal_targeting_24_recovers_then_upgrades_to_current() {
        legacy_journal_round_trip(23, 24);
    }

    #[test]
    fn legacy_journal_keeps_original_admission_rules_until_its_candidate_is_committed() {
        // The v1 producer ignored unknown main fields when it prepared its canonical candidate.
        // A resumed operation must not reinterpret that verified original with today's DTOs.
        let original = format!("{LEGACY_CONFIG}\n[old_unowned_section]\nnote='kept in original'\n");
        let fixture = pending_operation_with(22, 23, original.into_bytes(), 23);
        fixture
            .credentials
            .seed_legacy_provider("deepseek", "legacy-secret");
        let candidate = candidate_config_bytes(&fixture.paths);
        fixture
            .load()
            .expect("recorded operation completes before independent upgrade");
        assert_eq!(
            fixture.credentials.load("deepseek").unwrap().as_deref(),
            Some("legacy-secret")
        );
        assert_eq!(
            fs::read(config_backups(&fixture.paths).pop().unwrap()).unwrap(),
            candidate
        );
        assert!(!operation_dir(&fixture.paths).exists());
    }

    /// 源/目标元数据矛盾必须在任何凭据或资源写入之前 fail closed。
    #[test]
    fn invalid_journal_metadata_fails_closed_before_any_write() {
        // (日志 source, 日志 target, 原件实际 schema, 候选 schema)
        let cases = [
            (17_u32, 23_u32, 17_u32, 23_u32), // 源低于支持下界
            (23, 23, 23, 23),                 // 源等于目标
            (24, 23, 24, 23),                 // 源高于目标
            (23, 25, 22, 25),                 // 记录的 source 与受保护原件实际 schema 不符
        ];
        for (source_version, target_version, original_version, candidate_version) in cases {
            let fixture = pending_operation_with(
                source_version,
                target_version,
                converted_document(original_version),
                candidate_version,
            );
            fixture
                .credentials
                .seed_legacy_provider("deepseek", "legacy-secret");
            let journal_before = journal_bytes(&fixture.paths);
            let candidate_before = candidate_config_bytes(&fixture.paths);
            let live_before = fs::read(fixture.paths.config_file()).unwrap();

            let error = fixture
                .load()
                .expect_err("contradictory migration metadata fails closed");
            assert!(
                matches!(error, PureError::ConfigError(_)),
                "source {source_version} target {target_version} original {original_version}: {error}"
            );
            // 无副作用：live、原件、候选、journal 与凭据全部保持。
            assert_eq!(fs::read(fixture.paths.config_file()).unwrap(), live_before);
            assert_eq!(
                fs::read(
                    operation_dir(&fixture.paths)
                        .join(ORIGINAL_DIR_NAME)
                        .join(super::super::STUDIO_CONFIG_FILE_NAME)
                )
                .unwrap(),
                live_before
            );
            assert_eq!(candidate_config_bytes(&fixture.paths), candidate_before);
            assert_eq!(journal_bytes(&fixture.paths), journal_before);
            assert_eq!(fixture.credentials.load("deepseek").unwrap(), None);
        }
    }

    /// 候选字节被改成"仍可解析"的其他 TOML 时，必须在任何写入之前按记录的摘要拒绝。
    #[test]
    fn changed_candidate_bytes_fail_closed_before_any_write() {
        let fixture = pending_legacy_fixture(LEGACY_ACCOUNT_SCHEMA, 23, true);
        fixture
            .credentials
            .seed_legacy_provider("deepseek", "legacy-secret");
        let live_before = fs::read(fixture.paths.config_file()).unwrap();
        let journal_before = journal_bytes(&fixture.paths);
        let candidate_before = candidate_config_bytes(&fixture.paths);
        // Profile 候选被换成另一份可解析的 Profile（journal 记录 hash 不变）。
        let tampered = rewrite_profile_document(LEGACY_PROFILE)
            .unwrap()
            .replace("account_id = \"deepseek\"", "account_id = \"second\"");
        let tampered_path = operation_dir(&fixture.paths)
            .join(CANDIDATE_DIR_NAME)
            .join("agents/verify.toml");
        fs::write(&tampered_path, tampered.as_bytes()).unwrap();

        let error = fixture
            .load()
            .expect_err("candidate that no longer matches its hash fails closed");
        assert!(matches!(error, PureError::ConfigError(_)), "{error}");
        // live 配置绝不能被"先写后报错"覆盖；凭据也不得在此之前被复制。
        assert_eq!(fs::read(fixture.paths.config_file()).unwrap(), live_before);
        assert_eq!(fixture.credentials.load("deepseek").unwrap(), None);
        assert_eq!(candidate_config_bytes(&fixture.paths), candidate_before);
        assert_eq!(journal_bytes(&fixture.paths), journal_before);
        // 恢复候选原字节后可正常完成（失败没有破坏现场）。
        fs::write(
            &tampered_path,
            rewrite_profile_document(LEGACY_PROFILE).unwrap().as_bytes(),
        )
        .unwrap();
        let loaded = fixture
            .load()
            .expect("restored candidate completes the pending operation");
        assert_eq!(loaded.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
    }

    /// 受保护原件的内联凭据在 schema 不变的情况下被改写时必须 fail closed：绝不能把未验证的值
    /// 导入凭据，也不清除原件/候选/journal。
    #[test]
    fn changed_original_inline_token_fails_closed_before_credential_copy() {
        let original = LEGACY_CONFIG.replace(
            "bearer_token_env = \"DEEPSEEK_API_KEY\"",
            "bearer_token_env = \"DEEPSEEK_API_KEY\"\nbearer_token = \"secret-a\"",
        );
        assert!(original.contains("bearer_token = \"secret-a\""));
        let fixture = pending_operation_with(LEGACY_ACCOUNT_SCHEMA, 23, original.into_bytes(), 23);
        let live_before = fs::read(fixture.paths.config_file()).unwrap();
        let journal_before = journal_bytes(&fixture.paths);
        let candidate_before = candidate_config_bytes(&fixture.paths);
        // 只改受保护原件里的内联 token；schema 仍是 22，文件仍可解析。
        let tampered = String::from_utf8(live_before.clone())
            .unwrap()
            .replace("\"secret-a\"", "\"secret-b\"");
        let original_path = operation_dir(&fixture.paths)
            .join(ORIGINAL_DIR_NAME)
            .join(super::super::STUDIO_CONFIG_FILE_NAME);
        fs::write(&original_path, tampered.as_bytes()).unwrap();

        let error = fixture
            .load()
            .expect_err("changed preserved original fails closed");
        assert!(matches!(error, PureError::ConfigError(_)), "{error}");
        // 未验证的值绝不能被导入凭据；现场（原件/候选/journal/live）原样保留且未清理。
        assert_eq!(fixture.credentials.load("deepseek").unwrap(), None);
        assert_eq!(fs::read(&original_path).unwrap(), tampered.as_bytes());
        assert_eq!(fs::read(fixture.paths.config_file()).unwrap(), live_before);
        assert_eq!(journal_bytes(&fixture.paths), journal_before);
        assert_eq!(candidate_config_bytes(&fixture.paths), candidate_before);
        assert!(
            operation_dir(&fixture.paths).exists(),
            "migration materials are preserved for recovery"
        );
    }

    /// 预检之后底层候选被替换时，提交必须仍写入**已核验冻结**的原候选字节（按原 hash 成功），
    /// 绝不消费新变体。
    #[test]
    fn commit_writes_the_verified_candidate_snapshot() {
        let fixture = pending_legacy_fixture(LEGACY_ACCOUNT_SCHEMA, 23, true);
        fixture
            .credentials
            .seed_legacy_provider("deepseek", "legacy-secret");
        let verified_profile = rewrite_profile_document(LEGACY_PROFILE)
            .unwrap()
            .into_bytes();
        let variant = String::from_utf8(verified_profile.clone())
            .unwrap()
            .replace("account_id = \"deepseek\"", "account_id = \"second\"")
            .into_bytes();
        assert_ne!(verified_profile, variant);
        let profile_candidate_path = operation_dir(&fixture.paths)
            .join(CANDIDATE_DIR_NAME)
            .join("agents/verify.toml");
        let mut journal: MigrationJournal =
            serde_json::from_slice(&journal_bytes(&fixture.paths)).unwrap();
        // 既有 ResourceWriter 故障注入：第一次写入口把后一个候选文件换成另一种可解析内容。
        let writes = std::sync::atomic::AtomicUsize::new(0);
        let write = |path: &Path, content: &[u8]| -> Result<()> {
            if writes.fetch_add(1, std::sync::atomic::Ordering::SeqCst) == 0 {
                fs::write(&profile_candidate_path, &variant).unwrap();
            }
            pl_tool::workspace::write_file_atomically(path, content).map_err(Into::into)
        };
        let committed = commit(
            &fixture.paths,
            fixture.credentials.as_ref(),
            &mut journal,
            &write,
        )
        .expect("commit consumes the verified candidate snapshot");
        assert!(
            committed.is_none(),
            "legacy target yields no current config"
        );
        assert_eq!(
            fixture.credentials.load("deepseek").unwrap().as_deref(),
            Some("legacy-secret")
        );
        // 写入的是已核验原候选，不是注入的变体。
        let profile = fs::read(fixture.paths.agents_dir().join("verify.toml")).unwrap();
        assert_eq!(profile, verified_profile);
        assert_ne!(profile, variant);
        assert_eq!(
            fs::read(fixture.paths.config_file()).unwrap(),
            converted_document(23)
        );
        assert!(!operation_dir(&fixture.paths).exists());
    }

    /// journal 资源集合身份不合法（空集合、首项不是主配置、主配置缺失、主配置重复）时，
    /// 必须在任何索引/凭据/写入之前 fail closed，且绝不 panic 或清理现场。
    #[test]
    fn invalid_journal_resource_set_fails_closed_before_any_write() {
        let config_name = super::super::STUDIO_CONFIG_FILE_NAME.to_string();
        let config_resource_for = |source_version: u32, target_version: u32| PendingResource {
            relative_path: config_name.clone(),
            original: source_document(source_version),
            candidate: converted_document(target_version),
        };
        let profile_resource = || PendingResource {
            relative_path: "agents/verify.toml".to_string(),
            original: LEGACY_PROFILE.as_bytes().to_vec(),
            candidate: rewrite_profile_document(LEGACY_PROFILE)
                .unwrap()
                .into_bytes(),
        };
        /// 一个非法资源集合用例：日志 source/target、资源集合与磁盘上的 Profile。
        struct InvalidResourceCase {
            case: &'static str,
            source_version: u32,
            target_version: u32,
            resources: Vec<PendingResource>,
            live_profile: Option<Vec<u8>>,
        }
        let config_22_23 = || config_resource_for(22, 23);
        let cases = vec![
            InvalidResourceCase {
                case: "empty",
                source_version: 22,
                target_version: 23,
                resources: Vec::new(),
                live_profile: None,
            },
            InvalidResourceCase {
                case: "firstNotConfig",
                source_version: 22,
                target_version: 23,
                resources: vec![profile_resource(), config_22_23()],
                live_profile: Some(LEGACY_PROFILE.as_bytes().to_vec()),
            },
            InvalidResourceCase {
                case: "mainMissing",
                source_version: 22,
                target_version: 23,
                resources: vec![profile_resource()],
                live_profile: Some(LEGACY_PROFILE.as_bytes().to_vec()),
            },
            InvalidResourceCase {
                case: "duplicateMain",
                source_version: 22,
                target_version: 23,
                resources: vec![config_22_23(), config_22_23()],
                live_profile: None,
            },
            // 18..22 的附加资源必须是 agents/<profile_id>.toml：其它位置/后缀/非法 ID 一律拒绝。
            InvalidResourceCase {
                case: "unrelatedTopLevel",
                source_version: 22,
                target_version: 23,
                resources: vec![
                    config_22_23(),
                    PendingResource {
                        relative_path: "unrelated.toml".to_string(),
                        original: b"placeholder = 1\n".to_vec(),
                        candidate: b"placeholder = 2\n".to_vec(),
                    },
                ],
                live_profile: None,
            },
            InvalidResourceCase {
                case: "profileWrongSuffix",
                source_version: 22,
                target_version: 23,
                resources: vec![
                    config_22_23(),
                    PendingResource {
                        relative_path: "agents/unrelated.txt".to_string(),
                        original: b"placeholder = 1\n".to_vec(),
                        candidate: b"placeholder = 2\n".to_vec(),
                    },
                ],
                live_profile: None,
            },
            InvalidResourceCase {
                case: "profileInvalidId",
                source_version: 22,
                target_version: 23,
                resources: vec![
                    config_22_23(),
                    PendingResource {
                        relative_path: "agents/Nope.toml".to_string(),
                        original: b"placeholder = 1\n".to_vec(),
                        candidate: b"placeholder = 2\n".to_vec(),
                    },
                ],
                live_profile: None,
            },
            // 保留角色（planner/explorer/...）不是用户 Profile：现场即使自洽，也必须在任何读取、
            // 凭据复制、写入与清理之前拒绝，不能指望 Profile 加载路径事后再报错。
            InvalidResourceCase {
                case: "profileReservedRole",
                source_version: 22,
                target_version: 23,
                resources: vec![
                    config_22_23(),
                    PendingResource {
                        relative_path: "agents/planner.toml".to_string(),
                        original: LEGACY_PROFILE.as_bytes().to_vec(),
                        candidate: rewrite_profile_document(LEGACY_PROFILE)
                            .unwrap()
                            .into_bytes(),
                    },
                ],
                live_profile: None,
            },
            // 23+ 的历史 producer 只生成主配置计划：附加 Profile 资源即非法拓扑（即使现场自洽）。
            InvalidResourceCase {
                case: "source23WithProfileResource",
                source_version: 23,
                target_version: 24,
                resources: vec![config_resource_for(23, 24), profile_resource()],
                live_profile: Some(
                    rewrite_profile_document(LEGACY_PROFILE)
                        .unwrap()
                        .into_bytes(),
                ),
            },
        ];
        for InvalidResourceCase {
            case,
            source_version,
            target_version,
            resources,
            live_profile,
        } in cases
        {
            let live_config = source_document(source_version);
            let fixture = build_pending_with_resources(
                source_version,
                target_version,
                Some(&live_config),
                live_profile.as_deref(),
                &resources,
            );
            // 让附加资源在 live 上与其候选自洽：否则它们会因别的校验失败，掩盖路径身份缺陷。
            for resource in resources.iter().skip(1) {
                let live_path = fixture.paths.config_dir().join(&resource.relative_path);
                if let Some(parent) = live_path.parent() {
                    fs::create_dir_all(parent).unwrap();
                }
                fs::write(&live_path, &resource.candidate).unwrap();
            }
            fixture
                .credentials
                .seed_legacy_provider("deepseek", "legacy-secret");
            let live_before = fs::read(fixture.paths.config_file()).unwrap();
            let extras_before: Vec<(std::path::PathBuf, Vec<u8>)> = resources
                .iter()
                .skip(1)
                .map(|resource| {
                    let path = fixture.paths.config_dir().join(&resource.relative_path);
                    let bytes = fs::read(&path).unwrap();
                    (path, bytes)
                })
                .collect();
            let journal_before = journal_bytes(&fixture.paths);
            let originals_before: Vec<Option<Vec<u8>>> = resources
                .iter()
                .map(|resource| {
                    fs::read(
                        operation_dir(&fixture.paths)
                            .join(ORIGINAL_DIR_NAME)
                            .join(&resource.relative_path),
                    )
                    .ok()
                })
                .collect();

            // 真实启动/恢复入口：必须返回错误而不是 panic。
            let error = fixture
                .load()
                .expect_err("invalid journal resource set fails closed");
            assert!(
                matches!(error, PureError::ConfigError(_)),
                "{case}: unexpected error {error}"
            );
            // 无副作用：凭据、live、journal、原件全部保持，恢复材料不被清理。
            assert_eq!(
                fixture.credentials.load("deepseek").unwrap(),
                None,
                "{case}"
            );
            assert_eq!(
                fs::read(fixture.paths.config_file()).unwrap(),
                live_before,
                "{case}"
            );
            assert_eq!(journal_bytes(&fixture.paths), journal_before, "{case}");
            let originals_after: Vec<Option<Vec<u8>>> = resources
                .iter()
                .map(|resource| {
                    fs::read(
                        operation_dir(&fixture.paths)
                            .join(ORIGINAL_DIR_NAME)
                            .join(&resource.relative_path),
                    )
                    .ok()
                })
                .collect();
            assert_eq!(originals_after, originals_before, "{case}");
            for (path, bytes) in &extras_before {
                assert_eq!(
                    fs::read(path).unwrap(),
                    *bytes,
                    "{case}: {} must stay unchanged",
                    path.display()
                );
            }
            assert!(operation_dir(&fixture.paths).exists(), "{case}");
        }
    }
}
