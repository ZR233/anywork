//! Instance-scoped successful model observations; independent of persisted settings.
use std::{collections::BTreeMap, fs, io::Read, path::PathBuf};

use pl_model::{
    config::{ProviderConfig, ProviderId},
    model::ModelInfo,
    provider::discovery::{ModelCatalogQuery, ModelCatalogQueryCache, ModelCatalogQueryError},
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
    identity: String,
    pub success_at: i64,
    pub checked_at: i64,
    pub etag: Option<String>,
    pub models: Vec<ModelInfo>,
}

pub(crate) struct CatalogProbe {
    pub provider: ProviderId,
    pub generation: u64,
    pub query: ModelCatalogQuery,
    pub previous: Option<ModelCatalogQueryCache>,
    pub cancellation: CancellationToken,
}

impl SuccessCache {
    pub fn new(
        provider: &ProviderId,
        identity: &str,
        etag: Option<String>,
        models: Vec<ModelInfo>,
        success_at: i64,
    ) -> Self {
        Self {
            schema: 2,
            normalization_revision: NORMALIZATION_REVISION,
            identity: full_identity(provider, identity),
            success_at,
            checked_at: crate::studio::unix_seconds(),
            etag,
            models,
        }
    }
    pub fn query_etag(&self) -> Option<&str> {
        // A previous normalization cannot be upgraded from a bodyless 304. Keep
        // its snapshot for failures but fetch the body under the current rules.
        (self.normalization_revision == NORMALIZATION_REVISION)
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
    pub fn persist(
        &self,
        paths: &ConfigPaths,
        provider: &ProviderId,
        identity: &str,
    ) -> Result<()> {
        let path = cache_path(paths, provider, identity);
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
        let bytes = serde_json::to_vec(self).map_err(|_| {
            pl_protocol::PureError::ConfigError("could not encode model observation".into())
        })?;
        if bytes.len() > CACHE_BYTES_LIMIT {
            return Err(pl_protocol::PureError::ConfigError(
                "model observation exceeds cache size limit".into(),
            ));
        }
        pl_tool::workspace::write_file_atomically(&path, &bytes)?;
        Ok(())
    }
}

pub(super) fn reconcile(
    paths: &ConfigPaths,
    desired: &StudioConfig,
    old: &BTreeMap<ProviderId, Observation>,
) -> Result<BTreeMap<ProviderId, Observation>> {
    let mut next = BTreeMap::new();
    for (id, provider) in &desired.models.providers {
        let supported = provider.discovery_profile()?.is_some();
        let query = if supported {
            match ModelCatalogQuery::for_provider(provider) {
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
        if let Some(identity) = identity {
            match read_cache(paths, id, &identity, provider) {
                Ok(Some(cache)) => {
                    observation.status.source = Source::Cached;
                    observation.status.last_success_at = Some(cache.success_at);
                    observation.status.checked_at = Some(cache.checked_at);
                    observation.cache = Some(cache);
                }
                Ok(None) => {}
                Err(warning) => observation.status.cache_warning = Some(warning),
            }
        }
        next.insert(id.clone(), observation);
    }
    Ok(next)
}

pub(super) fn effective(
    desired: &StudioConfig,
    observations: &BTreeMap<ProviderId, Observation>,
) -> Result<StudioConfig> {
    let mut config = desired.clone();
    for (id, provider) in &mut config.models.providers {
        provider.clear_model_catalog_overlay();
        if let Some(cache) = observations
            .get(id)
            .and_then(|observation| observation.cache.as_ref())
        {
            provider.set_model_catalog_overlay(cache.models.clone())?;
        }
    }
    config.models.reconcile_model_catalog()?;
    Ok(config)
}

fn read_cache(
    paths: &ConfigPaths,
    provider_id: &ProviderId,
    identity: &str,
    provider: &ProviderConfig,
) -> std::result::Result<Option<SuccessCache>, CacheWarning> {
    let file = match fs::File::open(cache_path(paths, provider_id, identity)) {
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
    let migrated = value.get("schema").and_then(serde_json::Value::as_u64) == Some(1);
    if migrated {
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
        value["schema"] = 2.into();
        value["normalizationRevision"] = 1.into();
    }
    let cache: SuccessCache = serde_json::from_value(value).map_err(|_| CacheWarning::Schema)?;
    if cache.schema != 2
        || cache.normalization_revision > NORMALIZATION_REVISION
        || cache.success_at <= 0
        || cache.checked_at < cache.success_at
    {
        return Err(CacheWarning::Schema);
    }
    if cache.identity != full_identity(provider_id, identity) {
        return Err(CacheWarning::Identity);
    }
    if cache
        .etag
        .as_ref()
        .is_some_and(|etag| etag.len() > 1024 || etag.bytes().any(|byte| byte < 32 || byte == 127))
    {
        return Err(CacheWarning::Declaration);
    }
    let mut checked = provider.clone();
    checked
        .set_model_catalog_overlay(cache.models.clone())
        .map_err(|_| CacheWarning::Declaration)?;
    if migrated {
        cache
            .persist(paths, provider_id, identity)
            .map_err(|_| CacheWarning::Read)?;
    }
    Ok(Some(cache))
}

fn full_identity(provider: &ProviderId, query: &str) -> String {
    let mut digest = Sha256::new();
    for part in [
        b"studio-model-catalog-v1".as_slice(),
        provider.as_str().as_bytes(),
        query.as_bytes(),
    ] {
        digest.update((part.len() as u64).to_be_bytes());
        digest.update(part);
    }
    hex::encode(digest.finalize())
}
fn cache_path(paths: &ConfigPaths, provider: &ProviderId, query: &str) -> PathBuf {
    paths
        .config_dir()
        .join("v2/model-catalogs")
        .join(hex::encode(Sha256::digest(provider.as_str().as_bytes())))
        .join(full_identity(provider, query))
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
    use pl_model::{
        config::ModelCatalogId, model::ModelTransportProfile, provider::ProviderEndpoint,
    };

    fn legacy_cache(
        paths: &ConfigPaths,
        conflict: bool,
    ) -> (ProviderId, ProviderConfig, String, Vec<u8>) {
        let id = ProviderId::new("migration-instance").unwrap();
        let provider = ProviderConfig::from_bundled_catalog(
            ProviderEndpoint::openai(None),
            ModelCatalogId::new("openai").unwrap(),
            vec![],
        );
        let identity = ModelCatalogQuery::for_provider(&provider)
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
        (id, provider, identity, bytes)
    }

    #[test]
    fn old_cache_migrates_atomically_keeps_snapshot_and_forces_a_body_once() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let (id, mut provider, identity, _) = legacy_cache(&paths, false);
        let cache = read_cache(&paths, &id, &identity, &provider)
            .unwrap()
            .unwrap();
        assert_eq!(cache.models[0].model_id, "exact-Unchanged-ID");
        assert!(cache.models[0].observation.is_none());
        assert_eq!(cache.query_etag(), None);
        assert_eq!(cache.success_at, 123);
        provider
            .set_model_catalog_overlay(cache.models.clone())
            .unwrap();
        assert_eq!(provider.effective_models(None).unwrap()[0], cache.models[0]);
        let persisted = fs::read(cache_path(&paths, &id, &identity)).unwrap();
        let again = read_cache(&paths, &id, &identity, &provider)
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
        let previous = read_cache(&paths, &id, &identity, &provider)
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
        let reloaded = read_cache(&paths, &id, &identity, &provider)
            .unwrap()
            .unwrap();
        assert_eq!(reloaded.query_etag(), Some("\"current\""));
    }

    #[test]
    fn conflicting_cached_ids_keep_original_bytes() {
        let home = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(home.path());
        let (id, provider, identity, original) = legacy_cache(&paths, true);
        assert!(matches!(
            read_cache(&paths, &id, &identity, &provider),
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
}
