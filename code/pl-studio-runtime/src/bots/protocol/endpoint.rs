//! 飞书 HTTP/WS 来源策略。生产只走官方地址；debug 人工验收可绑定隔离 fixture。
use super::error::{FeishuError, FeishuErrorKind};
use super::{FEISHU_ACCOUNTS_HOST, FEISHU_OPEN_API_HOST};
use crate::studio::StudioPaths;
use serde::Deserialize;
use std::io::Read;
use std::path::{Path, PathBuf};
use url::Url;

pub const FIXTURE_MANIFEST_ENV: &str = "ANYWORK_BOTS_FIXTURE_MANIFEST";
pub const FIXTURE_APP_ID_PREFIX: &str = "cli_anywork_fixture_";
const RESERVED_DEV_PORT: u16 = 1420;
const MANIFEST_MAX_BYTES: u64 = 8 * 1024;

#[derive(Clone)]
pub struct EndpointPolicy {
    pub open_api: Url,
    pub accounts: Url,
    fixture: Option<FixtureBind>,
}

#[derive(Clone)]
struct FixtureBind {
    host: String,
    port: u16,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct FixtureManifest {
    schema_version: u32,
    studio_home: String,
    base_url: String,
}

impl EndpointPolicy {
    pub fn for_studio(paths: &StudioPaths) -> Result<Self, FeishuError> {
        match std::env::var_os(FIXTURE_MANIFEST_ENV) {
            None => Self::production(),
            Some(_) if !cfg!(debug_assertions) => Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "bots fixture manifest is only allowed in debug native acceptance",
                false,
                None,
            )),
            Some(path) => Self::from_manifest(PathBuf::from(path), paths.home()),
        }
    }

    pub fn production() -> Result<Self, FeishuError> {
        Ok(Self {
            open_api: parse_url(FEISHU_OPEN_API_HOST, "open API host")?,
            accounts: parse_url(&format!("https://{FEISHU_ACCOUNTS_HOST}"), "accounts host")?,
            fixture: None,
        })
    }

    pub fn validate_verification_url(&self, value: &str) -> Result<Url, FeishuError> {
        let url = Url::parse(value).map_err(|_| rejected_origin())?;
        if url.username() != "" || url.password().is_some() || url.fragment().is_some() {
            return Err(rejected_origin());
        }
        let host = url.host_str().ok_or_else(rejected_origin)?;
        if let Some(fixture) = &self.fixture {
            let default_http_port = url.scheme() == "http" && url.port().is_none();
            if url.scheme() != "http"
                || host != fixture.host
                || url.port() != Some(fixture.port)
                || default_http_port
            {
                return Err(rejected_origin());
            }
            return Ok(url);
        }
        let default_https = url.scheme() == "https" && url.port().is_none();
        if !default_https || !(host == "accounts.feishu.cn" || host == "open.feishu.cn") {
            return Err(rejected_origin());
        }
        Ok(url)
    }

    pub fn require_synthetic_app(&self, app_id: &str) -> Result<(), FeishuError> {
        if self.fixture.is_some() && !app_id.starts_with(FIXTURE_APP_ID_PREFIX) {
            return Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "fixture mode rejects non-synthetic app identities",
                false,
                None,
            ));
        }
        Ok(())
    }

    pub fn validate_ws_url(&self, value: &str) -> Result<(), FeishuError> {
        let url = Url::parse(value).map_err(|_| protocol("invalid ws url"))?;
        if url.username() != "" || url.password().is_some() || url.fragment().is_some() {
            return Err(protocol("ws url must not carry userinfo or fragment"));
        }
        let host = url
            .host_str()
            .ok_or_else(|| protocol("ws url missing host"))?;
        if let Some(fixture) = &self.fixture {
            if url.scheme() != "ws" || host != fixture.host || url.port() != Some(fixture.port) {
                return Err(protocol(
                    "fixture ws url must use the bound loopback origin",
                ));
            }
            return Ok(());
        }
        if url.scheme() != "wss" || is_loopback(&url) {
            return Err(protocol(
                "production ws url must be a verified official wss address",
            ));
        }
        if !(host == "feishu.cn"
            || host.ends_with(".feishu.cn")
            || host == "larksuite.com"
            || host.ends_with(".larksuite.com"))
        {
            return Err(protocol(
                "production ws host is not an official Feishu endpoint",
            ));
        }
        Ok(())
    }

    fn from_manifest(path: PathBuf, studio_home: &Path) -> Result<Self, FeishuError> {
        let canonical_path = path
            .canonicalize()
            .map_err(|_| protocol("bots fixture manifest path is not readable"))?;
        let canonical_home = studio_home
            .canonicalize()
            .map_err(|_| protocol("studio home cannot be canonicalized for fixture bind"))?;
        if !canonical_path.starts_with(&canonical_home) {
            return Err(protocol(
                "bots fixture manifest must live inside the bound studio home",
            ));
        }
        let file = std::fs::File::open(&canonical_path)
            .map_err(|_| protocol("failed to read bots fixture manifest"))?;
        let mut limited = file.take(MANIFEST_MAX_BYTES + 1);
        let mut bytes = Vec::new();
        limited
            .read_to_end(&mut bytes)
            .map_err(|_| protocol("failed to read bots fixture manifest"))?;
        if bytes.len() as u64 > MANIFEST_MAX_BYTES {
            return Err(protocol("bots fixture manifest exceeds size bound"));
        }
        let manifest: FixtureManifest = serde_json::from_slice(&bytes).map_err(|_| {
            protocol("bots fixture manifest is not a valid schemaVersion=1 document")
        })?;
        if manifest.schema_version != 1 {
            return Err(protocol("unsupported bots fixture manifest schema"));
        }
        let declared_home = PathBuf::from(&manifest.studio_home)
            .canonicalize()
            .map_err(|_| protocol("fixture studioHome cannot be canonicalized"))?;
        if declared_home != canonical_home {
            return Err(protocol(
                "fixture studioHome does not match the running Studio home",
            ));
        }
        let http = parse_fixture_http(&manifest.base_url)?;
        Ok(Self {
            open_api: http.clone(),
            accounts: http.clone(),
            fixture: Some(FixtureBind {
                host: http.host_str().unwrap_or("127.0.0.1").to_string(),
                port: http.port().unwrap_or(0),
            }),
        })
    }
}

fn parse_fixture_http(value: &str) -> Result<Url, FeishuError> {
    let url = Url::parse(value).map_err(|_| protocol("invalid fixture baseUrl"))?;
    let port = url.port().unwrap_or(0);
    if url.scheme() != "http"
        || url.host_str() != Some("127.0.0.1")
        || port == 0
        || port == RESERVED_DEV_PORT
        || url.username() != ""
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || !(url.path() == "/" || url.path().is_empty())
    {
        return Err(protocol(
            "fixture baseUrl must be http://127.0.0.1:<ephemeral-port>/",
        ));
    }
    Ok(url)
}

fn parse_url(value: &str, label: &str) -> Result<Url, FeishuError> {
    Url::parse(value).map_err(|_| protocol(&format!("invalid {label}")))
}

fn is_loopback(url: &Url) -> bool {
    matches!(url.host_str(), Some("127.0.0.1" | "localhost" | "::1"))
}

fn protocol(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Protocol, message, false, None)
}

fn rejected_origin() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Rejected,
        "verification url origin is not allowed",
        false,
        None,
    )
}
