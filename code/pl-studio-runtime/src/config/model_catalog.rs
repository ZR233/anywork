//! Instance-scoped successful model observations; independent of persisted settings.
use std::{
    collections::BTreeMap,
    fs,
    io::Read,
    path::{Path, PathBuf},
};

use pl_model::{
    config::{AccountConfig, AccountId},
    model::ModelInfo,
    protocol::discovery::{ModelCatalogQuery, ModelCatalogQueryCache, ModelCatalogQueryError},
};
use pl_protocol::studio::{
    StudioModelCatalogCacheWarning as CacheWarning, StudioModelCatalogError as CatalogError,
    StudioModelCatalogSource as Source, StudioModelCatalogStatus as Status,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

use super::{ConfigPaths, StudioConfig};
use crate::Result;

const CACHE_BYTES_LIMIT: usize = 8 * 1024 * 1024;
const NORMALIZATION_REVISION: u32 = 3;
/// On-disk schema of `model.json`. Schema 3 also records whether the snapshot was verified by a
/// complete response of the recorded query identity or adopted from the retired query identity.
const CACHE_SCHEMA: u32 = 3;
/// A legacy import claim is a few hundred bytes; bound the read like every other cache document.
const CLAIM_BYTES_LIMIT: usize = 4096;
const CLAIM_FILE: &str = "legacy-import-claim.json";
const CLAIM_VERSION: u32 = 1;

/// Keep acquisition order across removals and restarts. Persisting the watermark
/// before a cache may leave a harmless gap; it can never make an old field newer.
pub(super) fn next_observation_order(paths: &ConfigPaths, minimum: u64) -> Result<u64> {
    let directory = paths.config_dir().join("v2/model-catalogs");
    fs::create_dir_all(&directory)?;
    let path = directory.canonicalize()?.join("sequence.json");
    let previous = match fs::read(&path) {
        Ok(bytes) => serde_json::from_slice::<u64>(&bytes).map_err(|_| {
            pl_protocol::PureError::ConfigError("invalid model observation sequence".into())
        })?,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => 0,
        Err(error) => return Err(error.into()),
    };
    let order = previous.max(minimum).checked_add(1).ok_or_else(|| {
        pl_protocol::PureError::ConfigError("model observation sequence exhausted".into())
    })?;
    pl_tool::workspace::write_file_atomically(&path, order.to_string().as_bytes())?;
    Ok(order)
}

#[derive(Clone)]
pub(super) struct Observation {
    pub identity: Option<String>,
    pub generation: u64,
    pub cancellation: CancellationToken,
    pub cache: Option<SuccessCache>,
    pub status: Status,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct SuccessCache {
    schema: u32,
    #[serde(default)]
    normalization_revision: u32,
    /// 快照是否由记录的查询身份完整响应验证过。
    verification: CacheVerification,
    identity: String,
    pub success_at: i64,
    pub checked_at: i64,
    pub etag: Option<String>,
    pub models: Vec<ModelInfo>,
}

/// 成功快照的来源。旧查询身份（v1）的 `model.json` 从未记录厂商协议，因此这类快照只能作为
/// 展示与失败回退的历史事实，不能冒充当前协议的新观察。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum CacheVerification {
    /// 由该文件记录身份的完整响应解码并验证。
    Verified,
    /// 从退役查询身份认领的快照；在完整响应重新验证前不得参与解码继承或条件请求。
    LegacyMigrated,
}

pub(crate) struct CatalogProbe {
    pub account: AccountId,
    pub generation: u64,
    pub query: ModelCatalogQuery,
    pub previous: Option<ModelCatalogQueryCache>,
    pub cancellation: CancellationToken,
}

impl SuccessCache {
    pub fn new(
        account: &AccountId,
        identity: &str,
        etag: Option<String>,
        models: Vec<ModelInfo>,
        success_at: i64,
    ) -> Self {
        Self {
            schema: CACHE_SCHEMA,
            normalization_revision: NORMALIZATION_REVISION,
            verification: CacheVerification::Verified,
            identity: full_identity(account, identity),
            success_at,
            checked_at: crate::studio::unix_seconds(),
            etag,
            models,
        }
    }
    /// 只有当前查询身份完整验证过的快照可以作为解码器的前次声明或条件请求来源。
    pub(super) fn is_verified(&self) -> bool {
        self.verification == CacheVerification::Verified
    }
    pub fn query_etag(&self) -> Option<&str> {
        // A previous normalization cannot be upgraded from a bodyless 304. Keep
        // its snapshot for failures but fetch the body under the current rules.
        (self.is_verified() && self.normalization_revision == NORMALIZATION_REVISION)
            .then_some(self.etag.as_deref())
            .flatten()
    }
    pub fn not_modified(&self, etag: Option<String>) -> Self {
        Self {
            checked_at: crate::studio::unix_seconds(),
            etag,
            ..self.clone()
        }
    }
    pub fn persist(&self, paths: &ConfigPaths, account: &AccountId, identity: &str) -> Result<()> {
        let path = cache_path(paths, account, identity);
        let bytes = serde_json::to_vec(self).map_err(|_| {
            pl_protocol::PureError::ConfigError("could not encode model observation".into())
        })?;
        if bytes.len() > CACHE_BYTES_LIMIT {
            return Err(pl_protocol::PureError::ConfigError(
                "model observation exceeds cache size limit".into(),
            ));
        }
        write_bytes_atomically(&path, &bytes)
    }
}

/// Single-file atomic replacement for cache documents outside the canonical config payload.
fn write_bytes_atomically(path: &Path, bytes: &[u8]) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| std::io::Error::other("model cache path has no parent"))?;
    fs::create_dir_all(parent)?;
    // On Windows canonicalization supplies the verbatim path prefix needed
    // by the atomic writer's native move, including its longer temporary name.
    let path = parent.canonicalize()?.join(
        path.file_name()
            .ok_or_else(|| std::io::Error::other("model cache path has no filename"))?,
    );
    pl_tool::workspace::write_file_atomically(&path, bytes)?;
    Ok(())
}

/// 结合已有观察与磁盘缓存重算每个账号的目录观察。
///
/// 调用方持有 Settings 命令的串行锁，或在发布任何 canonical 状态之前调用，因此同一账号的旧缓存
/// 认领与快照写入不会并发；缓存故障只记录在该账号的观察上，不中断其它账号。
pub(super) fn reconcile(
    paths: &ConfigPaths,
    desired: &StudioConfig,
    old: &BTreeMap<AccountId, Observation>,
) -> Result<BTreeMap<AccountId, Observation>> {
    let mut next = BTreeMap::new();
    for (id, account) in &desired.models.accounts {
        let supported = account.discovery_profile()?.is_some();
        let query = if supported {
            match ModelCatalogQuery::for_account(account) {
                Ok(query) => Some(query),
                Err(ModelCatalogQueryError::Definition(error)) => return Err(error.into()),
                Err(_) => None,
            }
        } else {
            None
        };
        let identity = query.as_ref().map(|query| query.identity().to_owned());
        if let Some(previous) = old.get(id)
            && previous.identity == identity
            && previous.status.supported == supported
        {
            next.insert(id.clone(), previous.clone());
            continue;
        }
        let mut observation = Observation {
            identity: identity.clone(),
            generation: old
                .get(id)
                .map_or(1, |previous| previous.generation.saturating_add(1)),
            cancellation: CancellationToken::new(),
            cache: None,
            status: Status {
                supported,
                source: Source::Default,
                probing: false,
                last_success_at: None,
                checked_at: None,
                error: None,
                cache_warning: None,
            },
        };
        if let Some(query) = &query {
            // 当前查询身份已有成功文件时先验证并使用它，不再回看退役身份的旧快照。
            let cached = match read_cache(paths, id, query.identity(), account) {
                Ok(Some(cache)) => Ok(Some(cache)),
                Ok(None) => import_legacy_cache(paths, id, query, account),
                Err(warning) => Err(warning),
            };
            match cached {
                Ok(Some(cache)) => adopt_cached(&mut observation, cache),
                Ok(None) => {}
                Err(warning) => observation.status.cache_warning = Some(warning),
            }
        }
        next.insert(id.clone(), observation);
    }
    Ok(next)
}

fn adopt_cached(observation: &mut Observation, cache: SuccessCache) {
    observation.status.source = Source::Cached;
    observation.status.last_success_at = Some(cache.success_at);
    observation.status.checked_at = Some(cache.checked_at);
    observation.cache = Some(cache);
}

pub(super) fn effective(
    desired: &StudioConfig,
    observations: &BTreeMap<AccountId, Observation>,
) -> Result<StudioConfig> {
    let mut config = desired.clone();
    for (id, account) in &mut config.models.accounts {
        account.clear_model_catalog_overlay();
        if let Some(cache) = observations
            .get(id)
            .and_then(|observation| observation.cache.as_ref())
        {
            account.set_model_catalog_overlay(cache.models.clone())?;
        }
    }
    config.models.reconcile_model_catalog()?;
    Ok(config)
}

/// 当前查询身份的成功文件；旧 schema 只在这里升级为 3，成员与时间保真。
fn read_cache(
    paths: &ConfigPaths,
    account_id: &AccountId,
    identity: &str,
    account: &AccountConfig,
) -> std::result::Result<Option<SuccessCache>, CacheWarning> {
    let path = cache_path(paths, account_id, identity);
    let Some(file) = read_cache_file(&path, &full_identity(account_id, identity), account)? else {
        return Ok(None);
    };
    if file.converted {
        file.cache
            .persist(paths, account_id, identity)
            .map_err(|_| CacheWarning::Read)?;
    }
    Ok(Some(file.cache))
}

/// 一个 `model.json`：按文件所在身份目录声明的语义解码，并保留原始字节摘要。
struct CachedFile {
    cache: SuccessCache,
    /// 原始文件字节，用于在认领时证明来源未被外部改写。
    bytes: Vec<u8>,
    /// 文件使用了较早的 schema，仅在内存中规范化为当前结构。
    converted: bool,
}

impl CachedFile {
    fn source_hash(&self) -> String {
        hex::encode(Sha256::digest(&self.bytes))
    }
}

/// 同一旧查询身份只认领一个当前查询身份。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyImportClaim {
    version: u32,
    source_identity: String,
    source_hash: String,
    target_identity: String,
    phase: LegacyImportPhase,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum LegacyImportPhase {
    /// 认领已记录、快照尚未提交；同目标重启可续接。
    Prepared,
    /// 快照已提交到目标身份。
    Complete,
}

/// 读取并校验一个缓存文件。缺少验证字段的旧 schema 按当前身份语义规范化；旧查询身份的快照由
/// [`import_legacy_cache`] 覆盖成显式的历史快照，那里是唯一的判断点。
fn read_cache_file(
    path: &Path,
    expected_identity: &str,
    account: &AccountConfig,
) -> std::result::Result<Option<CachedFile>, CacheWarning> {
    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err(CacheWarning::Read),
    };
    let mut bytes = Vec::new();
    file.take(CACHE_BYTES_LIMIT as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| CacheWarning::Read)?;
    if bytes.len() > CACHE_BYTES_LIMIT {
        return Err(CacheWarning::Schema);
    }
    let mut value: serde_json::Value =
        serde_json::from_slice(&bytes).map_err(|_| CacheWarning::Schema)?;
    let schema = value
        .get("schema")
        .and_then(serde_json::Value::as_u64)
        .ok_or(CacheWarning::Schema)?;
    if schema == 1 {
        let models = value
            .get_mut("models")
            .and_then(serde_json::Value::as_array_mut)
            .ok_or(CacheWarning::Schema)?;
        for model in models {
            let object = model.as_object_mut().ok_or(CacheWarning::Schema)?;
            if let Some(legacy) = object.remove("slug") {
                if object
                    .get("model_id")
                    .is_some_and(|current| current != &legacy)
                {
                    return Err(CacheWarning::Declaration);
                }
                object.insert("model_id".into(), legacy);
            }
            // Legacy normalized values survive, but cannot claim field presence or recency.
            object.remove("observation");
        }
        value["normalizationRevision"] = 1.into();
    }
    if schema > u64::from(CACHE_SCHEMA) {
        return Err(CacheWarning::Schema);
    }
    if schema < u64::from(CACHE_SCHEMA) {
        value["verification"] =
            serde_json::to_value(CacheVerification::Verified).map_err(|_| CacheWarning::Schema)?;
    }
    value["schema"] = CACHE_SCHEMA.into();
    let cache: SuccessCache = serde_json::from_value(value).map_err(|_| CacheWarning::Schema)?;
    if cache.normalization_revision > NORMALIZATION_REVISION
        || cache.success_at <= 0
        || cache.checked_at < cache.success_at
    {
        return Err(CacheWarning::Schema);
    }
    if cache.identity != expected_identity {
        return Err(CacheWarning::Identity);
    }
    if cache
        .etag
        .as_ref()
        .is_some_and(|etag| etag.len() > 1024 || etag.bytes().any(|byte| byte < 32 || byte == 127))
    {
        return Err(CacheWarning::Declaration);
    }
    let mut checked = account.clone();
    checked
        .set_model_catalog_overlay(cache.models.clone())
        .map_err(|_| CacheWarning::Declaration)?;
    Ok(Some(CachedFile {
        cache,
        bytes,
        converted: schema != u64::from(CACHE_SCHEMA),
    }))
}

/// 在明确的缓存升级边界为当前查询身份认领退役身份（v1 指纹）的快照。
///
/// 顺序是认领 → 快照 → 完成：认领先落盘，因此中断后同目标可续接，而切换厂商协议后的另一
/// 查询身份不会再导入同一份无厂商来源的旧快照。原始 `model.json` 只读，永不改写或删除。
fn import_legacy_cache(
    paths: &ConfigPaths,
    account_id: &AccountId,
    query: &ModelCatalogQuery,
    account: &AccountConfig,
) -> std::result::Result<Option<SuccessCache>, CacheWarning> {
    let legacy_path = cache_path(paths, account_id, query.legacy_v1_identity_for_migration());
    let source_identity = full_identity(account_id, query.legacy_v1_identity_for_migration());
    let Some(source) = read_cache_file(&legacy_path, &source_identity, account)? else {
        return Ok(None);
    };
    let target_identity = query.identity();
    let claim_path = legacy_path.with_file_name(CLAIM_FILE);
    let source_hash = source.source_hash();
    let claim = match read_claim(&claim_path)? {
        Some(claim) => {
            if claim.source_identity != source_identity || claim.source_hash != source_hash {
                // 认领之后旧文件被外部改写：不覆盖已记录目标，也不静默改用新内容。
                return Err(CacheWarning::Identity);
            }
            if claim.target_identity != target_identity {
                return Ok(None);
            }
            claim
        }
        None => {
            let claim = LegacyImportClaim {
                version: CLAIM_VERSION,
                source_identity,
                source_hash,
                target_identity: target_identity.to_owned(),
                phase: LegacyImportPhase::Prepared,
            };
            write_claim(&claim_path, &claim)?;
            claim
        }
    };
    let migrated = SuccessCache {
        // 快照在新的查询身份目录下保存，因此身份字段随之改写到当前身份。
        identity: full_identity(account_id, target_identity),
        verification: CacheVerification::LegacyMigrated,
        ..source.cache
    };
    migrated
        .persist(paths, account_id, target_identity)
        .map_err(|_| CacheWarning::Read)?;
    if claim.phase == LegacyImportPhase::Prepared {
        write_claim(
            &claim_path,
            &LegacyImportClaim {
                phase: LegacyImportPhase::Complete,
                ..claim
            },
        )?;
    }
    Ok(Some(migrated))
}

fn read_claim(path: &Path) -> std::result::Result<Option<LegacyImportClaim>, CacheWarning> {
    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err(CacheWarning::Read),
    };
    let mut bytes = Vec::new();
    file.take(CLAIM_BYTES_LIMIT as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| CacheWarning::Read)?;
    if bytes.len() > CLAIM_BYTES_LIMIT {
        return Err(CacheWarning::Schema);
    }
    let claim: LegacyImportClaim =
        serde_json::from_slice(&bytes).map_err(|_| CacheWarning::Schema)?;
    if claim.version != CLAIM_VERSION {
        return Err(CacheWarning::Schema);
    }
    Ok(Some(claim))
}

fn write_claim(path: &Path, claim: &LegacyImportClaim) -> std::result::Result<(), CacheWarning> {
    let bytes = serde_json::to_vec(claim).map_err(|_| CacheWarning::Schema)?;
    write_bytes_atomically(path, &bytes).map_err(|_| CacheWarning::Read)
}

fn full_identity(account: &AccountId, query: &str) -> String {
    let mut digest = Sha256::new();
    for part in [
        b"studio-model-catalog-v1".as_slice(),
        account.as_str().as_bytes(),
        query.as_bytes(),
    ] {
        digest.update((part.len() as u64).to_be_bytes());
        digest.update(part);
    }
    hex::encode(digest.finalize())
}
fn cache_path(paths: &ConfigPaths, account: &AccountId, query: &str) -> PathBuf {
    paths
        .config_dir()
        .join("v2/model-catalogs")
        .join(hex::encode(Sha256::digest(account.as_str().as_bytes())))
        .join(full_identity(account, query))
        .join("model.json")
}

pub(crate) fn query_error(error: ModelCatalogQueryError) -> Result<CatalogError> {
    Ok(match error {
        ModelCatalogQueryError::Definition(error) => return Err(error.into()),
        ModelCatalogQueryError::Unsupported => CatalogError::Unsupported,
        ModelCatalogQueryError::Configuration => CatalogError::Configuration,
        ModelCatalogQueryError::Timeout => CatalogError::Timeout,
        ModelCatalogQueryError::Transport { http_status, .. } => {
            CatalogError::Transport { http_status }
        }
        ModelCatalogQueryError::Http { status } => CatalogError::Http { status },
        ModelCatalogQueryError::TooLarge => CatalogError::TooLarge,
        ModelCatalogQueryError::Protocol => CatalogError::Protocol,
        ModelCatalogQueryError::CacheIdentity => CatalogError::CacheIdentity,
        ModelCatalogQueryError::UnexpectedNotModified => CatalogError::UnexpectedNotModified,
    })
}

#[cfg(test)]
mod migration_tests {
    use super::*;
    use crate::config::{ConfigRuntime, ConfigStore};
    use pl_model::{
        config::ModelCatalogId,
        model::{ModelMetadataField, ModelObservation, ModelTransportProfile},
        protocol::{ProtocolEndpoint, ProtocolKind, discovery::ModelCatalogQueryResult},
    };

    fn bundled_account() -> AccountConfig {
        AccountConfig::from_bundled_catalog(
            ProtocolEndpoint::openai(None),
            ModelCatalogId::new("openai").unwrap(),
            vec![],
        )
    }

    fn observed_model() -> ModelInfo {
        let mut model = ModelInfo::compatible("exact-observed-id");
        model.display_name = "Observed display name".into();
        model.description = Some("catalog description".into());
        model.context_window = Some(200_000);
        model.max_context_window = Some(200_000);
        model
            .binding
            .set_transport(ModelTransportProfile::responses_websocket());
        let mut observation = ModelObservation::default();
        observation.declare(ModelMetadataField::ContextWindow);
        observation.commit(7);
        model.observation = Some(observation);
        model
    }

    /// 复现版本 70b0137b 写出的旧文件：v1 查询身份目录、无厂商协议与验证来源字段。
    fn write_legacy_v1_snapshot(
        paths: &ConfigPaths,
        id: &AccountId,
        account: &AccountConfig,
        schema: u64,
        checked_at: i64,
    ) -> (ModelCatalogQuery, Vec<u8>) {
        let query = ModelCatalogQuery::for_account(account).unwrap();
        let cache = SuccessCache::new(
            id,
            query.legacy_v1_identity_for_migration(),
            Some("\"legacy-etag\"".into()),
            vec![observed_model()],
            123,
        );
        let mut value = serde_json::to_value(cache).unwrap();
        value.as_object_mut().unwrap().remove("verification");
        value["checkedAt"] = checked_at.into();
        value["schema"] = schema.into();
        if schema == 1 {
            let object = value["models"][0].as_object_mut().unwrap();
            let model_id = object.remove("model_id").unwrap();
            object.insert("slug".into(), model_id);
            object.remove("observation");
            value["normalizationRevision"] = 1.into();
        }
        let bytes = serde_json::to_vec(&value).unwrap();
        let path = cache_path(paths, id, query.legacy_v1_identity_for_migration());
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, &bytes).unwrap();
        (query, bytes)
    }

    fn legacy_source_path(
        paths: &ConfigPaths,
        id: &AccountId,
        query: &ModelCatalogQuery,
    ) -> PathBuf {
        cache_path(paths, id, query.legacy_v1_identity_for_migration())
    }

    fn claim_value(
        paths: &ConfigPaths,
        id: &AccountId,
        query: &ModelCatalogQuery,
    ) -> serde_json::Value {
        serde_json::from_slice(
            &fs::read(legacy_source_path(paths, id, query).with_file_name(CLAIM_FILE)).unwrap(),
        )
        .unwrap()
    }

    fn legacy_cache(
        paths: &ConfigPaths,
        conflict: bool,
    ) -> (AccountId, AccountConfig, String, Vec<u8>) {
        let id = AccountId::new("migration-instance").unwrap();
        let account = AccountConfig::from_bundled_catalog(
            ProtocolEndpoint::openai(None),
            ModelCatalogId::new("openai").unwrap(),
            vec![],
        );
        let identity = ModelCatalogQuery::for_account(&account)
            .unwrap()
            .identity()
            .to_owned();
        let mut model = ModelInfo::compatible("exact-Unchanged-ID");
        model
            .binding
            .set_transport(ModelTransportProfile::responses_websocket());
        let cache = SuccessCache::new(&id, &identity, Some("\"legacy\"".into()), vec![model], 123);
        let mut value = serde_json::to_value(cache).unwrap();
        value["schema"] = 1.into();
        value["normalizationRevision"] = 1.into();
        let object = value["models"][0].as_object_mut().unwrap();
        let model_id = object.remove("model_id").unwrap();
        object.insert("slug".into(), model_id);
        if conflict {
            object.insert("model_id".into(), "different-id".into());
        }
        let bytes = serde_json::to_vec(&value).unwrap();
        let path = cache_path(paths, &id, &identity);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, &bytes).unwrap();
        (id, account, identity, bytes)
    }

    #[test]
    fn old_cache_migrates_atomically_keeps_snapshot_and_forces_a_body_once() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let (id, mut account, identity, _) = legacy_cache(&paths, false);
        let cache = read_cache(&paths, &id, &identity, &account)
            .unwrap()
            .unwrap();
        assert_eq!(cache.models[0].model_id, "exact-Unchanged-ID");
        assert!(cache.models[0].observation.is_none());
        assert_eq!(cache.query_etag(), None);
        assert_eq!(cache.success_at, 123);
        account
            .set_model_catalog_overlay(cache.models.clone())
            .unwrap();
        assert_eq!(account.effective_models(None).unwrap()[0], cache.models[0]);
        let persisted = fs::read(cache_path(&paths, &id, &identity)).unwrap();
        let again = read_cache(&paths, &id, &identity, &account)
            .unwrap()
            .unwrap();
        assert_eq!(again.models, cache.models);
        assert_eq!(
            fs::read(cache_path(&paths, &id, &identity)).unwrap(),
            persisted
        );
        assert_eq!(again.query_etag(), None);
        let mut previous_normalization = cache.clone();
        previous_normalization.normalization_revision = NORMALIZATION_REVISION - 1;
        previous_normalization
            .persist(&paths, &id, &identity)
            .unwrap();
        let previous = read_cache(&paths, &id, &identity, &account)
            .unwrap()
            .unwrap();
        assert_eq!(previous.models, cache.models);
        assert_eq!(previous.query_etag(), None);
        let current = SuccessCache::new(
            &id,
            &identity,
            Some("\"current\"".into()),
            previous.models,
            124,
        );
        current.persist(&paths, &id, &identity).unwrap();
        let reloaded = read_cache(&paths, &id, &identity, &account)
            .unwrap()
            .unwrap();
        assert_eq!(reloaded.query_etag(), Some("\"current\""));
    }

    #[test]
    fn conflicting_cached_ids_keep_original_bytes() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let (id, account, identity, original) = legacy_cache(&paths, true);
        assert!(matches!(
            read_cache(&paths, &id, &identity, &account),
            Err(CacheWarning::Declaration)
        ));
        assert_eq!(
            fs::read(cache_path(&paths, &id, &identity)).unwrap(),
            original
        );
    }

    #[test]
    fn migrated_sequence_never_reuses_order_after_sources_disappear() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        assert_eq!(next_observation_order(&paths, 17).unwrap(), 18);
        assert_eq!(next_observation_order(&paths, 0).unwrap(), 19);
        let path = paths.config_dir().join("v2/model-catalogs/sequence.json");
        fs::write(&path, b"broken").unwrap();
        assert!(next_observation_order(&paths, 0).is_err());
        assert_eq!(fs::read(path).unwrap(), b"broken");
    }

    #[test]
    fn legacy_v1_snapshot_is_adopted_once_without_touching_source_bytes() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let id = AccountId::new("legacy-instance").unwrap();
        let account = bundled_account();
        let (query, original) = write_legacy_v1_snapshot(&paths, &id, &account, 2, 456);

        let cache = import_legacy_cache(&paths, &id, &query, &account)
            .unwrap()
            .unwrap();
        assert_eq!(cache.verification, CacheVerification::LegacyMigrated);
        assert!(!cache.is_verified());
        assert_eq!(cache.models, vec![observed_model()], "成员与元数据保真");
        assert_eq!((cache.success_at, cache.checked_at), (123, 456));
        assert_eq!(cache.query_etag(), None, "旧快照的 ETag 不能用于条件请求");
        assert_eq!(
            fs::read(legacy_source_path(&paths, &id, &query)).unwrap(),
            original,
            "原文件字节保持"
        );

        let target_path = cache_path(&paths, &id, query.identity());
        let persisted: serde_json::Value =
            serde_json::from_slice(&fs::read(&target_path).unwrap()).unwrap();
        assert_eq!(persisted["schema"], 3);
        assert_eq!(persisted["verification"], "legacyMigrated");
        assert_eq!(persisted["successAt"], 123);
        assert_eq!(persisted["checkedAt"], 456);

        let claim = claim_value(&paths, &id, &query);
        assert_eq!(claim["version"], CLAIM_VERSION);
        assert_eq!(claim["targetIdentity"], query.identity());
        assert_eq!(claim["phase"], "complete");
        assert_eq!(
            claim["sourceIdentity"],
            full_identity(&id, query.legacy_v1_identity_for_migration())
        );

        // 当前身份已有成功文件：正常读取只消费它，不再回看 v1。
        let read = read_cache(&paths, &id, query.identity(), &account)
            .unwrap()
            .unwrap();
        assert_eq!(read.models, cache.models);
        assert!(!read.is_verified());
        assert_eq!(read.success_at, 123);
    }

    #[test]
    fn protocol_switch_changes_generation_without_reimporting_the_claimed_snapshot() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let id = AccountId::new("kind-switch").unwrap();
        let account = bundled_account();
        let (query, _) = write_legacy_v1_snapshot(&paths, &id, &account, 2, 456);
        let mut config = StudioConfig::default_config().unwrap();
        config.models.accounts.insert(id.clone(), account.clone());

        let first = reconcile(&paths, &config, &BTreeMap::new()).unwrap();
        let observation = first.get(&id).unwrap();
        assert_eq!(observation.status.source, Source::Cached);
        assert_eq!(observation.status.last_success_at, Some(123));
        assert!(!observation.cache.as_ref().unwrap().is_verified());

        let mut switched = config.clone();
        switched.models.accounts.get_mut(&id).unwrap().protocol = ProtocolKind::DeepSeek;
        let second = reconcile(&paths, &switched, &first).unwrap();
        let observation = second.get(&id).unwrap();
        assert_eq!(observation.generation, 2);
        assert!(
            observation.cache.is_none(),
            "旧快照只归一个当前查询身份，切换厂商协议后不再导入"
        );
        assert_eq!(observation.status.source, Source::Default);
        assert_eq!(
            observation.status.cache_warning, None,
            "另一目标不是缓存故障"
        );

        // 切回原协议时当前身份的成功文件仍在，可继续作为展示与失败回退。
        let back = reconcile(&paths, &config, &second).unwrap();
        let observation = back.get(&id).unwrap();
        assert_eq!(observation.generation, 3);
        assert_eq!(observation.status.source, Source::Cached);
        assert!(!observation.cache.as_ref().unwrap().is_verified());
        assert_eq!(
            claim_value(&paths, &id, &query)["targetIdentity"],
            query.identity(),
            "第一次认领的目标保持不变"
        );
    }

    #[test]
    fn interrupted_legacy_import_resumes_for_its_target_only() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let id = AccountId::new("interrupted-instance").unwrap();
        let account = bundled_account();
        let (query, original) = write_legacy_v1_snapshot(&paths, &id, &account, 2, 456);
        // 目标身份目录的位置被普通文件占用：快照写入在准备阶段之后失败。
        let target_directory = cache_path(&paths, &id, query.identity())
            .parent()
            .unwrap()
            .to_path_buf();
        fs::create_dir_all(target_directory.parent().unwrap()).unwrap();
        fs::write(&target_directory, b"blocked").unwrap();

        assert_eq!(
            import_legacy_cache(&paths, &id, &query, &account).unwrap_err(),
            CacheWarning::Read
        );
        assert_eq!(claim_value(&paths, &id, &query)["phase"], "prepared");
        assert!(!cache_path(&paths, &id, query.identity()).exists());
        assert_eq!(
            fs::read(legacy_source_path(&paths, &id, &query)).unwrap(),
            original
        );

        // 认领先落盘：中断后另一协议身份不会把同一份旧快照导入自己的目录。
        let mut switched = account.clone();
        switched.protocol = ProtocolKind::DeepSeek;
        let other = ModelCatalogQuery::for_account(&switched).unwrap();
        assert!(
            import_legacy_cache(&paths, &id, &other, &switched)
                .unwrap()
                .is_none()
        );
        assert!(!cache_path(&paths, &id, other.identity()).exists());

        // 解除故障后同目标续接完成，并且只写它自己的缓存文件。
        fs::remove_file(&target_directory).unwrap();
        let cache = import_legacy_cache(&paths, &id, &query, &account)
            .unwrap()
            .unwrap();
        assert_eq!(cache.verification, CacheVerification::LegacyMigrated);
        assert_eq!(claim_value(&paths, &id, &query)["phase"], "complete");
        assert!(cache_path(&paths, &id, query.identity()).exists());
        assert!(!cache_path(&paths, &id, other.identity()).exists());
        assert_eq!(
            fs::read(legacy_source_path(&paths, &id, &query)).unwrap(),
            original
        );
    }

    #[test]
    fn claim_write_failure_keeps_retryable_state_without_writing_a_snapshot() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let id = AccountId::new("claim-failure-instance").unwrap();
        let account = bundled_account();
        let (query, original) = write_legacy_v1_snapshot(&paths, &id, &account, 2, 456);
        // 认领文件的位置被普通目录占用：准备阶段写入失败。
        let claim_path = legacy_source_path(&paths, &id, &query).with_file_name(CLAIM_FILE);
        fs::create_dir_all(&claim_path).unwrap();

        assert_eq!(
            import_legacy_cache(&paths, &id, &query, &account).unwrap_err(),
            CacheWarning::Read
        );
        assert!(
            !cache_path(&paths, &id, query.identity()).exists(),
            "认领失败不写快照"
        );
        assert_eq!(
            fs::read(legacy_source_path(&paths, &id, &query)).unwrap(),
            original
        );

        fs::remove_dir(&claim_path).unwrap();
        let cache = import_legacy_cache(&paths, &id, &query, &account)
            .unwrap()
            .unwrap();
        assert_eq!(cache.verification, CacheVerification::LegacyMigrated);
        assert_eq!(claim_value(&paths, &id, &query)["phase"], "complete");
    }

    #[test]
    fn legacy_source_change_after_claim_is_reported_without_overwrite() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let id = AccountId::new("changed-instance").unwrap();
        let account = bundled_account();
        let (query, _) = write_legacy_v1_snapshot(&paths, &id, &account, 2, 456);
        import_legacy_cache(&paths, &id, &query, &account)
            .unwrap()
            .unwrap();
        let target_path = cache_path(&paths, &id, query.identity());
        let target_bytes = fs::read(&target_path).unwrap();

        // 认领之后旧文件被外部改写：内容变化不能静默改判已提交快照。
        let (_, rewritten) = write_legacy_v1_snapshot(&paths, &id, &account, 2, 999);
        assert_eq!(
            import_legacy_cache(&paths, &id, &query, &account).unwrap_err(),
            CacheWarning::Identity
        );
        assert_eq!(fs::read(&target_path).unwrap(), target_bytes);
        assert_eq!(
            fs::read(legacy_source_path(&paths, &id, &query)).unwrap(),
            rewritten
        );
        assert_eq!(claim_value(&paths, &id, &query)["phase"], "complete");
    }

    #[test]
    fn schema_one_legacy_snapshot_keeps_last_success_without_unprovable_fields() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let id = AccountId::new("schema-one-instance").unwrap();
        let account = bundled_account();
        let (query, _) = write_legacy_v1_snapshot(&paths, &id, &account, 1, 456);

        let cache = import_legacy_cache(&paths, &id, &query, &account)
            .unwrap()
            .unwrap();
        assert_eq!(cache.models[0].model_id, "exact-observed-id");
        assert!(
            cache.models[0].observation.is_none(),
            "旧规范化值不能声称字段存在"
        );
        assert_eq!(cache.normalization_revision, 1);
        assert_eq!((cache.success_at, cache.checked_at), (123, 456));
        assert_eq!(cache.query_etag(), None);
        assert_eq!(cache.verification, CacheVerification::LegacyMigrated);
    }

    #[test]
    fn current_identity_schema_two_snapshot_is_upgraded_as_verified() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let id = AccountId::new("current-instance").unwrap();
        let account = bundled_account();
        let query = ModelCatalogQuery::for_account(&account).unwrap();
        let cache = SuccessCache::new(
            &id,
            query.identity(),
            Some("\"current-etag\"".into()),
            vec![observed_model()],
            123,
        );
        let mut value = serde_json::to_value(&cache).unwrap();
        value.as_object_mut().unwrap().remove("verification");
        value["schema"] = 2.into();
        let path = cache_path(&paths, &id, query.identity());
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, serde_json::to_vec(&value).unwrap()).unwrap();

        let read = read_cache(&paths, &id, query.identity(), &account)
            .unwrap()
            .unwrap();
        assert!(read.is_verified(), "当前身份写出的文件是该查询的验证观察");
        assert_eq!(read.query_etag(), Some("\"current-etag\""));
        let persisted: serde_json::Value =
            serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(persisted["schema"], 3);
        assert_eq!(persisted["verification"], "verified");
    }

    #[test]
    fn runtime_probe_never_inherits_a_migrated_snapshot_and_recovers_on_success() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let id = AccountId::new("runtime-instance").unwrap();
        let account = bundled_account();
        let (query, _) = write_legacy_v1_snapshot(&paths, &id, &account, 2, 456);
        let mut config = StudioConfig::default_config().unwrap();
        config.models.accounts.insert(id.clone(), account);
        ConfigStore::new(paths.clone()).save(&config).unwrap();

        let runtime = ConfigRuntime::initialize(ConfigStore::new(paths.clone())).unwrap();
        let status = runtime
            .read_catalog()
            .unwrap()
            .catalogs
            .remove(&id)
            .unwrap();
        assert_eq!(status.source, Source::Cached);
        assert_eq!(status.last_success_at, Some(123));
        assert_eq!(status.error, None);

        let probe = runtime
            .begin_model_catalog_probe(id.clone())
            .unwrap()
            .expect("bundled account probes discovery");
        assert!(probe.previous.is_none(), "迁移快照不能作为解码器前次声明");
        let identity = probe.query.identity().to_owned();
        assert_eq!(identity, query.identity(), "探测使用当前查询身份");
        runtime
            .finish_model_catalog_probe(
                probe,
                Err(pl_model::protocol::discovery::ModelCatalogQueryError::Timeout),
            )
            .unwrap();
        let status = runtime
            .read_catalog()
            .unwrap()
            .catalogs
            .remove(&id)
            .unwrap();
        assert_eq!(status.source, Source::Cached, "首次刷新失败保留迁移快照");
        assert_eq!(status.error, Some(CatalogError::Timeout));
        assert_eq!(status.last_success_at, Some(123));
        assert!(
            cache_path(&paths, &id, &identity).exists(),
            "迁移快照仍在当前身份文件中"
        );

        let probe = runtime
            .begin_model_catalog_probe(id.clone())
            .unwrap()
            .unwrap();
        assert!(probe.previous.is_none(), "完整响应前不继承旧声明");
        runtime
            .finish_model_catalog_probe(
                probe,
                Ok(ModelCatalogQueryResult::Updated {
                    identity: identity.clone(),
                    etag: Some("\"fresh\"".into()),
                    models: vec![observed_model()],
                }),
            )
            .unwrap();
        let status = runtime
            .read_catalog()
            .unwrap()
            .catalogs
            .remove(&id)
            .unwrap();
        assert_eq!(status.source, Source::Online);
        assert_eq!(status.error, None);

        let probe = runtime
            .begin_model_catalog_probe(id.clone())
            .unwrap()
            .unwrap();
        let previous = probe
            .previous
            .clone()
            .expect("验证过的快照可作为前次声明与条件请求来源");
        assert_eq!(previous.identity, identity);
        assert_eq!(previous.etag.as_deref(), Some("\"fresh\""));
        runtime
            .finish_model_catalog_probe(
                probe,
                Err(pl_model::protocol::discovery::ModelCatalogQueryError::Timeout),
            )
            .unwrap();
        assert_eq!(
            runtime.read_catalog().unwrap().catalogs[&id].source,
            Source::Online
        );
    }
}
