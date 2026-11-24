//! Endpoint-owned model discovery, independent of inference/model selection.

/// Version of the Codex model catalog contract decoded by this client.
const CATALOG_CLIENT_VERSION: &str = "0.170.0";
pub(crate) use pl_model_wire::discovery::enrich_unknown_model_fallback;
use pl_model_wire::{adapter::Adapter, catalog_http::CatalogResponse, discovery::models};

use super::{ProtocolEndpoint, ProtocolId};
use crate::{
    config::{AccountConfig, AccountModelCatalogConfig},
    model::ModelDefinition,
};
use reqwest::Url;
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    time::Duration,
};

pub use pl_protocol::ProviderFailureKind;

pub use pl_model_wire::discovery::ModelCatalogQueryError;

const MAX_DISCOVERY_PAGES: usize = 8;
const MAX_DISCOVERY_TOTAL_BYTES: usize = 4 * 1024 * 1024;

/// Only a successful, same-query observation may be used as a conditional request or metadata source.
#[derive(Debug, Clone, PartialEq)]
pub struct ModelCatalogQueryCache {
    pub identity: String,
    pub etag: Option<String>,
    /// Successful route declarations, including supported online token pricing.
    pub models: Vec<ModelDefinition>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ModelCatalogQueryResult {
    Updated {
        identity: String,
        etag: Option<String>,
        models: Vec<ModelDefinition>,
    },
    NotModified {
        identity: String,
        etag: Option<String>,
    },
}

/// Immutable request identity + credentials. Debug intentionally exposes only safe fingerprint.
pub struct ModelCatalogQuery {
    endpoint: ProtocolEndpoint,
    url: Url,
    standard_url: Url,
    previous_identity: String,
    identity: String,
    /// 上一版查询身份，仅用于配置迁移定位旧缓存文件。
    legacy_v1_identity: String,
    defaults: Vec<ModelDefinition>,
    adapter: &'static Adapter,
    discovery: crate::config::ModelCatalogDiscovery,
}

impl std::fmt::Debug for ModelCatalogQuery {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ModelCatalogQuery")
            .field("identity", &self.identity)
            .finish_non_exhaustive()
    }
}

impl ModelCatalogQuery {
    /// Prepare the account’s compatible model-list request without selecting an inference model.
    /// # Errors
    /// Unsupported source/adapter, malformed URL/header or bundled packaging failure.
    pub fn for_account(account: &AccountConfig) -> Result<Self, ModelCatalogQueryError> {
        Self::for_account_with_registry(account, super::builtin_protocols())
    }

    pub fn for_account_with_registry(
        account: &AccountConfig,
        registry: super::ProtocolRegistry<'_>,
    ) -> Result<Self, ModelCatalogQueryError> {
        let discovery = account
            .discovery_profile()
            .map_err(|_| ModelCatalogQueryError::Configuration)?
            .ok_or(ModelCatalogQueryError::Unsupported)?;
        let (catalog_id, defaults) = match &account.catalog {
            AccountModelCatalogConfig::Bundled { catalog, .. } => (
                catalog.as_str(),
                crate::config::builtin_model_catalog(catalog)
                    .map_err(|_| ModelCatalogQueryError::Configuration)?
                    .models,
            ),
            AccountModelCatalogConfig::Explicit { .. } => ("", Vec::new()),
        };
        let endpoint = account
            .to_endpoint_with_registry(registry)
            .map_err(|_| ModelCatalogQueryError::Configuration)?;
        let adapter = registry
            .resolve(&endpoint.protocol)
            .map_err(|_| ModelCatalogQueryError::Unsupported)?;
        let mut url =
            Url::parse(&endpoint.base_url).map_err(|_| ModelCatalogQueryError::Configuration)?;
        if !matches!(url.scheme(), "http" | "https")
            || !url.username().is_empty()
            || url.password().is_some()
            || url.fragment().is_some()
        {
            return Err(ModelCatalogQueryError::Configuration);
        }
        url.path_segments_mut()
            .map_err(|_| ModelCatalogQueryError::Configuration)?
            .pop_if_empty()
            .push("models");
        if !adapter.discovery_query_params.is_empty() {
            let mut pairs = url.query_pairs_mut();
            for &(name, value) in adapter.discovery_query_params {
                pairs.append_pair(name, value);
            }
        }
        let standard_url = url.clone();
        let headers = endpoint
            .request_headers(endpoint.bearer_token.as_deref(), &HashMap::new())
            .map_err(|_| ModelCatalogQueryError::Configuration)?;
        // 当前身份包含厂商协议；同一 catalog/URL/headers 换成另一协议时，旧 decoder 的结果
        // 不能被复用。
        let identity = query_identity(
            b"model-catalog-query-v2",
            Some(&endpoint.protocol),
            catalog_id,
            discovery_transport_id(&discovery.transport),
            url.as_str(),
            &headers,
        );
        let identity = if let Some(session) = &endpoint.authorization {
            let mut hash = Sha256::new();
            hash.update(identity.as_bytes());
            hash.update(session.registration_id().as_bytes());
            hex::encode(hash.finalize())
        } else {
            identity
        };
        let legacy_v1_identity = query_identity(
            b"model-catalog-query-v1",
            None,
            catalog_id,
            discovery_transport_id(&discovery.transport),
            url.as_str(),
            &headers,
        );
        let previous_identity = identity;
        let (url, identity) =
            if discovery.transport.protocol != crate::protocol::WireApi::GeminiGenerateContent {
                let mut versioned = standard_url.clone();
                versioned
                    .query_pairs_mut()
                    .append_pair("client_version", CATALOG_CLIENT_VERSION);
                let current_identity = hex::encode(Sha256::digest(format!(
                    "model-catalog-query-v3:{CATALOG_CLIENT_VERSION}:{previous_identity}"
                )));
                (versioned, current_identity)
            } else {
                (standard_url.clone(), previous_identity.clone())
            };
        Ok(Self {
            adapter,
            endpoint,
            standard_url,
            previous_identity,
            url,
            identity,
            legacy_v1_identity,
            defaults,
            discovery,
        })
    }

    /// Retired v2 fingerprint, used only to locate the last successful snapshot.
    pub fn previous_identity_for_migration(&self) -> &str {
        &self.previous_identity
    }

    /// SHA-256 of the request version and the endpoint, protocol and credential identity.
    /// The account ID is a separate outer cache namespace.
    pub fn identity(&self) -> &str {
        &self.identity
    }

    /// 上一版查询身份，仅供配置迁移定位该查询身份的旧缓存文件。
    ///
    /// 旧算法不含厂商协议；它不能用于当前 `execute`/缓存比较，也不是第二种正常身份。
    /// 迁移只在缓存升级边界使用这一身份定位历史快照。
    pub fn legacy_v1_identity_for_migration(&self) -> &str {
        &self.legacy_v1_identity
    }

    /// Query the versioned catalog and retry a rejected version using the standard endpoint.
    /// Both attempts share one ten-second deadline.
    /// Dropping this future releases the request; it never spawns a detached task or mutates a cache.
    /// # Errors
    /// Typed/redacted transport, HTTP, envelope, declaration or conditional-cache failure.
    pub async fn execute(
        &self,
        previous: Option<&ModelCatalogQueryCache>,
    ) -> Result<ModelCatalogQueryResult, ModelCatalogQueryError> {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
        if let Some(cache) = previous {
            if cache.identity != self.identity {
                return Err(ModelCatalogQueryError::CacheIdentity);
            }
            crate::model::validate_inventory(&cache.models)
                .map_err(|_| ModelCatalogQueryError::Protocol)?;
            if cache.models.iter().any(|model| {
                !valid_discovery_transport(
                    &model.extra.binding.transport,
                    &self.discovery.transport,
                )
            }) {
                return Err(ModelCatalogQueryError::Protocol);
            }
        }
        let result = tokio::time::timeout_at(deadline, self.execute_inner(previous))
            .await
            .map_err(|_| ModelCatalogQueryError::Timeout)?;
        // Synchronous bounded decoding cannot yield to Tokio's timer. Never publish
        // a late success if decoding/normalization crossed the operation deadline.
        if tokio::time::Instant::now() >= deadline {
            return Err(ModelCatalogQueryError::Timeout);
        }
        result
    }

    async fn execute_inner(
        &self,
        previous: Option<&ModelCatalogQueryCache>,
    ) -> Result<ModelCatalogQueryResult, ModelCatalogQueryError> {
        let token = self
            .endpoint
            .resolve_bearer_token()
            .await
            .map_err(|_| ModelCatalogQueryError::Authentication)?;
        let headers = self
            .endpoint
            .request_headers(token.as_deref(), &HashMap::new())
            .map_err(|_| ModelCatalogQueryError::Configuration)?;
        let response = pl_model_wire::catalog_http::fetch(
            self.url.clone(),
            headers.clone(),
            previous.and_then(|cache| cache.etag.as_deref()),
        )
        .await;
        let response = match response {
            Err(ModelCatalogQueryError::Http { status: 400 | 422 })
                if self.standard_url != self.url =>
            {
                // Different representation: neither send nor retain a conditional ETag.
                match pl_model_wire::catalog_http::fetch(
                    self.standard_url.clone(),
                    headers.clone(),
                    None,
                )
                .await?
                {
                    CatalogResponse::Updated { bytes, .. } => {
                        CatalogResponse::Updated { bytes, etag: None }
                    }
                    _ => return Err(ModelCatalogQueryError::UnexpectedNotModified),
                }
            }
            result => result?,
        };
        let (bytes, page1_etag) = match response {
            CatalogResponse::Updated { bytes, etag } => (bytes, etag),
            CatalogResponse::NotModified { etag } => {
                let previous = previous.ok_or(ModelCatalogQueryError::UnexpectedNotModified)?;
                return Ok(ModelCatalogQueryResult::NotModified {
                    identity: self.identity.clone(),
                    etag: etag.or_else(|| previous.etag.clone()),
                });
            }
        };
        let mut total_bytes = bytes.len();
        let first_page = (self.adapter.parse_catalog_page)(&bytes)?;
        let mut all_records = first_page.records;
        let mut next_token = first_page.next_page_token;
        let mut page_count = 1_usize;

        if let Some(token_param) = self.adapter.discovery_page_token_param {
            let mut seen_tokens = HashSet::new();
            while let Some(page_token) = next_token.take() {
                if page_token.trim().is_empty() {
                    break;
                }
                if !seen_tokens.insert(page_token.clone()) {
                    return Err(ModelCatalogQueryError::Protocol);
                }
                if page_count >= MAX_DISCOVERY_PAGES {
                    break;
                }
                let mut next_url = self.url.clone();
                next_url
                    .query_pairs_mut()
                    .append_pair(token_param, &page_token);
                let CatalogResponse::Updated { bytes, .. } =
                    pl_model_wire::catalog_http::fetch(next_url, headers.clone(), None).await?
                else {
                    return Err(ModelCatalogQueryError::UnexpectedNotModified);
                };
                total_bytes = total_bytes
                    .checked_add(bytes.len())
                    .filter(|&sum| sum <= MAX_DISCOVERY_TOTAL_BYTES)
                    .ok_or(ModelCatalogQueryError::TooLarge)?;
                let page = (self.adapter.parse_catalog_page)(&bytes)?;
                all_records.extend(page.records);
                next_token = page.next_page_token;
                page_count += 1;
            }
        }
        let etag = if page_count == 1 { page1_etag } else { None };
        let models = models(
            all_records,
            &self.discovery,
            self.adapter.discovery,
            previous.map(|p| p.models.as_slice()),
            &self.defaults,
        )?;
        Ok(ModelCatalogQueryResult::Updated {
            identity: self.identity.clone(),
            etag,
            models,
        })
    }
}

pub(crate) use pl_model_wire::discovery::valid_discovery_transport;

/// Length-prefixed canonical query identity; vendor protocol is part of the current version.
fn query_identity(
    magic: &[u8],
    protocol: Option<&ProtocolId>,
    catalog: &str,
    discovery_transport: &str,
    url: &str,
    headers: &reqwest::header::HeaderMap,
) -> String {
    let mut hash = Sha256::new();
    let mut part = |bytes: &[u8]| {
        hash.update((bytes.len() as u64).to_be_bytes());
        hash.update(bytes);
    };
    part(magic);
    part(catalog.as_bytes());
    if let Some(protocol) = protocol {
        part(protocol.as_str().as_bytes());
    }
    part(discovery_transport.as_bytes());
    part(url.as_bytes());
    let mut sorted = headers.iter().collect::<Vec<_>>();
    sorted.sort_by(|a, b| a.0.as_str().cmp(b.0.as_str()));
    for (name, value) in sorted {
        part(name.as_str().as_bytes());
        part(value.as_bytes());
    }
    hex::encode(hash.finalize())
}

fn discovery_transport_id(profile: &crate::model::ModelTransportProfile) -> &'static str {
    match (
        profile.protocol,
        profile.default_connection_mode,
        profile.supported_connection_modes.as_slice(),
    ) {
        (
            crate::protocol::WireApi::Responses,
            crate::protocol::ConnectionMode::WebSocket,
            [
                crate::protocol::ConnectionMode::WebSocket,
                crate::protocol::ConnectionMode::Http,
            ],
        ) => "responses-websocket",
        (
            crate::protocol::WireApi::Responses,
            crate::protocol::ConnectionMode::Http,
            [crate::protocol::ConnectionMode::Http],
        ) => "responses-http",
        (
            crate::protocol::WireApi::ChatCompletions,
            crate::protocol::ConnectionMode::Http,
            [crate::protocol::ConnectionMode::Http],
        ) => "chat-completions-http",
        (
            crate::protocol::WireApi::GeminiGenerateContent,
            crate::protocol::ConnectionMode::Http,
            [crate::protocol::ConnectionMode::Http],
        ) => "gemini-generate-content-http",
        _ => "unsupported",
    }
}
