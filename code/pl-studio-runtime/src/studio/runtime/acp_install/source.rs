//! 受管发行来源解析、大版本 1 兼容性校验与官方注册表客户端。
//!
//! 受管 Antigravity 支持大版本 `1` 范围内的兼容发行（`>= 1.4.5, < 2.0.0`）：
//! - 在线更新与发现严格固定从官方 ACP 注册表（`cdn.agentclientprotocol.com`）读取，且分发包必须位于
//!   官方 Google HTTPS 目录（`https://dl.google.com/agy-extensions/releases/`）；
//! - 保留官方 `1.4.5` 四平台发行清单作为内置兼容基线，保证仅查看/离线复用已装版本时无需硬编码第二套来源；
//! - 严禁从环境变量、用户输入或任意第三方域名覆盖官方来源（仅单元测试可在 `#[cfg(test)]` 注入本机回环服务）。

use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use serde::Deserialize;
use tokio_util::sync::CancellationToken;

use crate::{
    AcpInstallAvailability, AcpInstallFailure, AcpInstallFailureCode, AcpInstallRelease,
    AcpInstallStage, AcpProvider,
};

use super::mapping::failure;

/// 受管 Antigravity 支持的最低兼容版本。
pub(in crate::studio::runtime) const MINIMUM_SUPPORTED_VERSION: &str = "1.4.5";
/// 受管 Antigravity 允许的语义化主版本号。
pub(in crate::studio::runtime) const SUPPORTED_MAJOR_VERSION: u64 = 1;
/// 模板目录展示的支持范围标识。
pub(in crate::studio::runtime) const SUPPORTED_VERSION_RANGE: &str = "1.x";
/// 默认受管 agent ID（ACP 注册表标准标识）。
const ANTIGRAVITY_REGISTRY_AGENT_ID: &str = "antigravity-acp";
/// 官方 ACP 注册表 `latest` 地址。
const REGISTRY_URL: &str = "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json";
const REGISTRY_HOST: &str = "cdn.agentclientprotocol.com";
const REGISTRY_PATH_PREFIX: &str = "/registry/v1/";
/// 固定分发包的共同 URL 前缀；内置基线归档路径只来自下面的静态表。
const ARCHIVE_BASE_URL: &str = "https://dl.google.com/agy-extensions/releases/";
/// 允许的分发包来源。
const ARCHIVE_HOST: &str = "dl.google.com";
const ARCHIVE_PATH_PREFIX: &str = "/agy-extensions/releases/";
const MAX_REDIRECTS: usize = 5;
const MAX_REGISTRY_BYTES: usize = 2 * 1024 * 1024;
const REGISTRY_CHECK_TIMEOUT: Duration = Duration::from_secs(20);
const MAX_ARGS: usize = 8;
const MAX_ARG_BYTES: usize = 64;

/// 测试期可注入回环注册表/归档基址；生产编译不包含此类型，绝不开放外部覆盖。
#[cfg(test)]
#[derive(Debug, Clone)]
pub(in crate::studio::runtime) struct TestSourceOverride {
    pub registry_url: String,
    pub archive_base_url: String,
}

#[derive(Debug, Clone)]
pub(super) struct SourcePolicy {
    #[cfg(test)]
    test_override: Option<TestSourceOverride>,
}

impl SourcePolicy {
    pub(super) const fn official() -> Self {
        Self {
            #[cfg(test)]
            test_override: None,
        }
    }

    #[cfg(test)]
    pub(super) fn for_test(override_source: TestSourceOverride) -> Self {
        Self {
            test_override: Some(override_source),
        }
    }

    fn registry_url(&self) -> &str {
        #[cfg(test)]
        if let Some(custom) = &self.test_override {
            return &custom.registry_url;
        }
        REGISTRY_URL
    }

    fn validate_registry_url(&self, url: &reqwest::Url) -> Result<(), AcpInstallFailure> {
        #[cfg(test)]
        if self.test_override.is_some() {
            return validate_loopback_test_url(url, AcpInstallStage::Resolve, false);
        }
        validate_official_https_url(
            url,
            REGISTRY_HOST,
            REGISTRY_PATH_PREFIX,
            None,
            AcpInstallStage::Resolve,
        )
    }

    pub(super) fn validate_archive_url(&self, url: &reqwest::Url) -> Result<(), AcpInstallFailure> {
        #[cfg(test)]
        if let Some(custom) = &self.test_override {
            validate_loopback_test_url(url, AcpInstallStage::Resolve, true)?;
            if !url.as_str().starts_with(&custom.archive_base_url) {
                return Err(failure(
                    AcpInstallFailureCode::SourceRejected,
                    AcpInstallStage::Resolve,
                    false,
                ));
            }
            return Ok(());
        }
        validate_archive_url(url)
    }

    pub(super) fn archive_client(&self) -> Result<reqwest::Client, AcpInstallFailure> {
        let policy = self.clone();
        reqwest::Client::builder()
            .user_agent(user_agent())
            .connect_timeout(Duration::from_secs(10))
            .read_timeout(Duration::from_secs(30))
            .redirect(reqwest::redirect::Policy::custom(move |attempt| {
                if attempt.previous().len() > MAX_REDIRECTS {
                    return attempt.error("too many redirects");
                }
                if policy.validate_archive_url(attempt.url()).is_err() {
                    return attempt.error("redirect target rejected");
                }
                attempt.follow()
            }))
            .build()
            .map_err(|_| {
                failure(
                    AcpInstallFailureCode::Network,
                    AcpInstallStage::Download,
                    false,
                )
            })
    }
}

/// 一个固定基线发行目标的静态条目：归档相对路径、包内入口与不可变 argv。
struct FixedTarget {
    target: &'static str,
    archive_path: &'static str,
    sha256: &'static str,
    command: &'static str,
    args: &'static [&'static str],
}

/// 内置 `1.4.5` 基线清单（来自 ACP registry revision `02b460362cfedf4d43b03df7aad6d79a353fe064`）。
/// macOS（`darwin-*`）自 `1.5.x` 起由官方注册表正式发布。
const BUNDLED_TARGETS: &[FixedTarget] = &[
    FixedTarget {
        target: "linux-x86_64",
        sha256: "923923a0d7dc8073f66cc6f78647a3107e3a7ee2b7e1a24df8b3927b5188013b",
        archive_path: "linux/agy-acp-server-1.4.5-linux-x86_64.zip",
        command: "agy_acp_server.par",
        args: &["--uid="],
    },
    FixedTarget {
        target: "linux-aarch64",
        sha256: "7d64246633ae094f67e3bbcd2d679e89048f91346d5339313336e7483f40f056",
        archive_path: "linux/agy-acp-server-1.4.5-linux-arm64.zip",
        command: "agy_acp_server.par",
        args: &["--uid="],
    },
    FixedTarget {
        target: "windows-x86_64",
        sha256: "d24f4c73c9f96d4f44384e281c855a56c72d8eaa9c5b0fad7ccb1635c6b63f50",
        archive_path: "windows/agy-acp-server-1.4.5-windows-x86_64.zip",
        command: "agy_acp_server.exe",
        args: &[],
    },
    FixedTarget {
        target: "windows-aarch64",
        sha256: "ab0a9aac8349e08ef289be6d16da8f89e3abe60eba5158032ef78c4a1220261c",
        archive_path: "windows/agy-acp-server-1.4.5-windows-arm64.zip",
        command: "agy_acp_server.exe",
        args: &[],
    },
];

/// 一次准备/解析的冻结结果：wire 发行身份 + 包内入口与固定 argv。
///
/// `command`/`args` 只在内核安装与认证边界内部使用，不进入账号 DTO、HTTP 或 FRB 的接入字段。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct ResolvedRelease {
    pub(super) release: AcpInstallRelease,
    /// 包内相对入口路径（POSIX 分隔）。
    pub(super) command: String,
    pub(super) args: Vec<String>,
}

/// 语义化版本号在大版本 1 兼容性策略下的分类。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum VersionClassification {
    Supported(semver::Version),
    IncompatibleMajor(semver::Version),
    Rejected,
}

/// 从官方注册表解析一次最新发行查找结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum RegistryLookup {
    Release(ResolvedRelease),
    IncompatibleMajor { version: String },
}

/// 当前后端宿主平台对应的清单 target；不受支持时返回 `None`。
pub(super) fn current_target() -> Option<&'static str> {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("linux", "x86_64") => Some("linux-x86_64"),
        ("linux", "aarch64") => Some("linux-aarch64"),
        ("windows", "x86_64") => Some("windows-x86_64"),
        ("windows", "aarch64") => Some("windows-aarch64"),
        ("macos", "x86_64") => Some("darwin-x86_64"),
        ("macos", "aarch64") => Some("darwin-aarch64"),
        _ => None,
    }
}

/// 模板上的自动准备可用性；不支持平台没有可准备的官方发行。
pub(crate) fn availability() -> AcpInstallAvailability {
    match current_target() {
        Some(target) => AcpInstallAvailability::Available {
            target: target.to_string(),
        },
        None => AcpInstallAvailability::UnsupportedPlatform,
    }
}

/// 严格校验语义化版本号并按大版本 1 兼容性归类（`>= 1.4.5, < 2.0.0`）。
pub(super) fn classify_version(raw: &str) -> VersionClassification {
    if raw.trim() != raw || raw.is_empty() {
        return VersionClassification::Rejected;
    }
    let Ok(version) = semver::Version::parse(raw) else {
        return VersionClassification::Rejected;
    };
    if !version.pre.is_empty() || !version.build.is_empty() {
        return VersionClassification::Rejected;
    }
    let min = semver::Version::parse(MINIMUM_SUPPORTED_VERSION).expect("valid minimum version");
    if version.major == SUPPORTED_MAJOR_VERSION && version >= min {
        VersionClassification::Supported(version)
    } else if version.major > SUPPORTED_MAJOR_VERSION {
        VersionClassification::IncompatibleMajor(version)
    } else {
        VersionClassification::Rejected
    }
}

/// 校验可选官方 SHA-256 摘要（存在时必须是 64 位小写十六进制）。
pub(super) fn validate_optional_sha256(
    sha256: Option<&str>,
    stage: AcpInstallStage,
) -> Result<Option<String>, AcpInstallFailure> {
    let Some(raw) = sha256 else {
        return Ok(None);
    };
    let normalized = raw.trim();
    if normalized != raw
        || normalized.len() != 64
        || !normalized
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(failure(AcpInstallFailureCode::SourceRejected, stage, false));
    }
    Ok(Some(normalized.to_string()))
}

/// 按受支持平台严格校验包内入口与启动参数白名单，拒绝任意可执行名与危险参数。
pub(super) fn validate_target_command_args(
    target: &str,
    command: &str,
    args: &[String],
    stage: AcpInstallStage,
) -> Result<String, AcpInstallFailure> {
    if command.trim() != command || command.contains('\\') || command.contains("..") {
        return Err(failure(AcpInstallFailureCode::SourceRejected, stage, false));
    }
    let normalized = command.strip_prefix("./").unwrap_or(command);
    let allowed = match target {
        "linux-x86_64" | "linux-aarch64" | "darwin-x86_64" | "darwin-aarch64" => {
            normalized == "agy_acp_server.par"
        }
        "windows-x86_64" | "windows-aarch64" => normalized == "agy_acp_server.exe",
        _ => {
            return Err(failure(
                AcpInstallFailureCode::UnsupportedPlatform,
                stage,
                false,
            ));
        }
    };
    if !allowed {
        return Err(failure(AcpInstallFailureCode::SourceRejected, stage, false));
    }
    if args.len() > MAX_ARGS {
        return Err(failure(AcpInstallFailureCode::SourceRejected, stage, false));
    }
    for arg in args {
        if arg.is_empty()
            || arg.len() > MAX_ARG_BYTES
            || !arg.starts_with('-')
            || !arg.bytes().all(|byte| {
                byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'=')
            })
        {
            return Err(failure(AcpInstallFailureCode::SourceRejected, stage, false));
        }
    }
    Ok(normalized.to_string())
}

/// 安装身份：provider/version/target/archive/sha256/cmd/args 的确定摘要。
///
/// 采用确定序列化 + 摘要，不把版本直接拼进路径；provider/target 同时进入目录分层，因此不同
/// 平台或同大版本内的升级包不会互相覆盖。
pub(super) fn installation_id(provider: AcpProvider, resolved: &ResolvedRelease) -> String {
    let descriptor = serde_json::json!({
        "format": 1,
        "provider": provider.as_str(),
        "version": resolved.release.version,
        "target": resolved.release.target,
        "archiveUrl": resolved.release.archive_url,
        "sha256": resolved.release.sha256,
        "command": resolved.command,
        "args": resolved.args,
    });
    crate::hash::canonical_json_hash(&descriptor)
}

/// wire 安装身份的**存储键**：必须是 `sha256:` + 64 位小写十六进制。
///
/// 文件/目录组件只用 key，receipt 保留 wire 身份。未通过严格校验的身份不参与任何路径拼接，
/// 也不做二次哈希。
pub(super) fn storage_key(installation_id: &str) -> Option<String> {
    let hex = installation_id.strip_prefix("sha256:")?;
    if hex.len() != 64 {
        return None;
    }
    if !hex
        .bytes()
        .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return None;
    }
    Some(hex.to_string())
}

fn bundled_targets(provider: AcpProvider) -> &'static [FixedTarget] {
    match provider {
        AcpProvider::Antigravity => BUNDLED_TARGETS,
    }
}

/// 解析内置 `1.4.5` 基线清单（仅本地、不联网）；用于测试夹具或远端不可用/超前大版本时的受支持基线兜底。
pub(super) fn resolve_bundled(provider: AcpProvider) -> Result<ResolvedRelease, AcpInstallFailure> {
    let stage = AcpInstallStage::Resolve;
    let Some(target) = current_target() else {
        return Err(failure(
            AcpInstallFailureCode::UnsupportedPlatform,
            stage,
            false,
        ));
    };
    let Some(fixed) = bundled_targets(provider)
        .iter()
        .find(|fixed| fixed.target == target)
    else {
        return Err(failure(
            AcpInstallFailureCode::UnsupportedPlatform,
            stage,
            false,
        ));
    };
    let archive_url = reqwest::Url::parse(&format!("{ARCHIVE_BASE_URL}{}", fixed.archive_path))
        .map_err(|_| failure(AcpInstallFailureCode::SourceRejected, stage, false))?;
    validate_archive_url(&archive_url)?;
    Ok(ResolvedRelease {
        release: AcpInstallRelease {
            version: MINIMUM_SUPPORTED_VERSION.to_string(),
            target: target.to_string(),
            archive_url: archive_url.to_string(),
            sha256: Some(fixed.sha256.to_string()),
        },
        command: fixed.command.to_string(),
        args: fixed.args.iter().map(|arg| (*arg).to_string()).collect(),
    })
}

#[derive(Deserialize)]
struct RegistryDocument {
    #[serde(default)]
    agents: Vec<RegistryAgent>,
}

#[derive(Deserialize)]
struct RegistryAgent {
    id: String,
    version: String,
    distribution: Option<RegistryDistribution>,
}

#[derive(Deserialize)]
struct RegistryDistribution {
    #[serde(default)]
    binary: BTreeMap<String, RegistryBinaryTarget>,
}

#[derive(Deserialize)]
struct RegistryBinaryTarget {
    archive: String,
    cmd: String,
    #[serde(default)]
    args: Vec<String>,
    sha256: Option<String>,
}

fn registry_agent_id(provider: AcpProvider) -> &'static str {
    match provider {
        AcpProvider::Antigravity => ANTIGRAVITY_REGISTRY_AGENT_ID,
    }
}

/// 向官方 ACP 注册表发起一次有界 HTTPS GET 并解析当前平台的大版本 `1` 最新发行。
pub(super) async fn fetch_latest_from_registry(
    policy: &SourcePolicy,
    provider: AcpProvider,
    cancel: &CancellationToken,
) -> Result<RegistryLookup, AcpInstallFailure> {
    let stage = AcpInstallStage::Resolve;
    let Some(target) = current_target() else {
        return Err(failure(
            AcpInstallFailureCode::UnsupportedPlatform,
            stage,
            false,
        ));
    };
    let url = reqwest::Url::parse(policy.registry_url())
        .map_err(|_| failure(AcpInstallFailureCode::SourceRejected, stage, false))?;
    policy.validate_registry_url(&url)?;
    let redirect_rejected = Arc::new(AtomicBool::new(false));
    let client_policy = policy.clone();
    let flag = Arc::clone(&redirect_rejected);
    let client = reqwest::Client::builder()
        .user_agent(user_agent())
        .connect_timeout(Duration::from_secs(10))
        .read_timeout(Duration::from_secs(15))
        .redirect(reqwest::redirect::Policy::custom(move |attempt| {
            if attempt.previous().len() > MAX_REDIRECTS {
                return attempt.error("too many redirects");
            }
            if client_policy.validate_registry_url(attempt.url()).is_err() {
                flag.store(true, Ordering::Release);
                return attempt.error("registry redirect target rejected");
            }
            attempt.follow()
        }))
        .build()
        .map_err(|_| failure(AcpInstallFailureCode::Network, stage, true))?;

    let work = async {
        let mut response = tokio::select! {
            biased;
            () = cancel.cancelled() => {
                return Err(failure(AcpInstallFailureCode::Cancelled, stage, true));
            }
            result = client.get(url).send() => {
                result.map_err(|error| map_registry_reqwest_error(&error, &redirect_rejected))?
            }
        };
        if !response.status().is_success() {
            return Err(failure(AcpInstallFailureCode::Network, stage, true));
        }
        if response
            .content_length()
            .is_some_and(|len| len > MAX_REGISTRY_BYTES as u64)
        {
            return Err(failure(AcpInstallFailureCode::TooLarge, stage, false));
        }
        let mut body = Vec::new();
        loop {
            let next = tokio::select! {
                biased;
                () = cancel.cancelled() => {
                    return Err(failure(AcpInstallFailureCode::Cancelled, stage, true));
                }
                chunk = response.chunk() => {
                    chunk.map_err(|error| map_registry_reqwest_error(&error, &redirect_rejected))?
                }
            };
            let Some(chunk) = next else {
                break;
            };
            if body.len().saturating_add(chunk.len()) > MAX_REGISTRY_BYTES {
                return Err(failure(AcpInstallFailureCode::TooLarge, stage, false));
            }
            body.extend_from_slice(&chunk);
        }
        parse_registry_payload(policy, provider, target, &body)
    };

    tokio::select! {
        biased;
        () = cancel.cancelled() => Err(failure(AcpInstallFailureCode::Cancelled, stage, true)),
        timed = tokio::time::timeout(REGISTRY_CHECK_TIMEOUT, work) => {
            timed.unwrap_or_else(|_| Err(failure(AcpInstallFailureCode::Timeout, stage, true)))
        }
    }
}

fn map_registry_reqwest_error(
    error: &reqwest::Error,
    redirect_rejected: &AtomicBool,
) -> AcpInstallFailure {
    if redirect_rejected.load(Ordering::Acquire) {
        return failure(
            AcpInstallFailureCode::SourceRejected,
            AcpInstallStage::Resolve,
            false,
        );
    }
    if error.is_timeout() {
        return failure(
            AcpInstallFailureCode::Timeout,
            AcpInstallStage::Resolve,
            true,
        );
    }
    failure(
        AcpInstallFailureCode::Network,
        AcpInstallStage::Resolve,
        true,
    )
}

pub(super) fn parse_registry_payload(
    policy: &SourcePolicy,
    provider: AcpProvider,
    target: &str,
    bytes: &[u8],
) -> Result<RegistryLookup, AcpInstallFailure> {
    let stage = AcpInstallStage::Resolve;
    let document: RegistryDocument = serde_json::from_slice(bytes)
        .map_err(|_| failure(AcpInstallFailureCode::SourceRejected, stage, false))?;
    let expected_id = registry_agent_id(provider);
    let Some(agent) = document
        .agents
        .into_iter()
        .find(|agent| agent.id == expected_id)
    else {
        return Err(failure(AcpInstallFailureCode::SourceRejected, stage, false));
    };
    let version = match classify_version(&agent.version) {
        VersionClassification::Supported(version) => version,
        VersionClassification::IncompatibleMajor(version) => {
            return Ok(RegistryLookup::IncompatibleMajor {
                version: version.to_string(),
            });
        }
        VersionClassification::Rejected => {
            return Err(failure(AcpInstallFailureCode::SourceRejected, stage, false));
        }
    };
    let Some(distribution) = agent.distribution else {
        return Err(failure(AcpInstallFailureCode::SourceRejected, stage, false));
    };
    let Some(entry) = distribution.binary.get(target) else {
        return Err(failure(
            AcpInstallFailureCode::UnsupportedPlatform,
            stage,
            false,
        ));
    };
    let archive_url = reqwest::Url::parse(&entry.archive)
        .map_err(|_| failure(AcpInstallFailureCode::SourceRejected, stage, false))?;
    policy.validate_archive_url(&archive_url)?;
    let sha256 = validate_optional_sha256(entry.sha256.as_deref(), stage)?;
    let command = validate_target_command_args(target, &entry.cmd, &entry.args, stage)?;
    Ok(RegistryLookup::Release(ResolvedRelease {
        release: AcpInstallRelease {
            version: version.to_string(),
            target: target.to_string(),
            archive_url: archive_url.to_string(),
            sha256,
        },
        command,
        args: entry.args.clone(),
    }))
}

/// 分发包来源政策：仅官方 Google HTTPS ZIP 路径，拒绝用户信息、额外端口、fragment 与越界路径。
pub(super) fn validate_archive_url(url: &reqwest::Url) -> Result<(), AcpInstallFailure> {
    validate_official_https_url(
        url,
        ARCHIVE_HOST,
        ARCHIVE_PATH_PREFIX,
        Some(".zip"),
        AcpInstallStage::Resolve,
    )
}

fn validate_official_https_url(
    url: &reqwest::Url,
    expected_host: &str,
    expected_prefix: &str,
    required_suffix: Option<&str>,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    let rejected = || failure(AcpInstallFailureCode::SourceRejected, stage, false);
    if url.scheme() != "https" || url.host_str() != Some(expected_host) {
        return Err(rejected());
    }
    if url.port_or_known_default() != Some(443)
        || !url.username().is_empty()
        || url.password().is_some()
        || authority_has_userinfo(url)
        || url.fragment().is_some()
    {
        return Err(rejected());
    }
    let path = url.path();
    if !path.starts_with(expected_prefix) || path.contains('\\') {
        return Err(rejected());
    }
    let lowered = path.to_ascii_lowercase();
    if lowered.contains("%2e") || lowered.contains("%2f") || lowered.contains("%5c") {
        return Err(rejected());
    }
    if path
        .split('/')
        .any(|segment| segment == "." || segment == "..")
        || path.contains("//")
    {
        return Err(rejected());
    }
    if let Some(suffix) = required_suffix
        && !lowered.ends_with(suffix)
    {
        return Err(rejected());
    }
    Ok(())
}

#[cfg(test)]
fn validate_loopback_test_url(
    url: &reqwest::Url,
    stage: AcpInstallStage,
    require_zip: bool,
) -> Result<(), AcpInstallFailure> {
    let rejected = || failure(AcpInstallFailureCode::SourceRejected, stage, false);
    if !matches!(url.scheme(), "http" | "https")
        || !matches!(url.host_str(), Some("127.0.0.1" | "::1" | "localhost"))
        || !url.username().is_empty()
        || url.password().is_some()
        || authority_has_userinfo(url)
        || url.fragment().is_some()
    {
        return Err(rejected());
    }
    let path = url.path();
    if path.contains('\\')
        || path.contains("//")
        || path
            .split('/')
            .any(|segment| segment == "." || segment == "..")
    {
        return Err(rejected());
    }
    if require_zip && !path.to_ascii_lowercase().ends_with(".zip") {
        return Err(rejected());
    }
    Ok(())
}

/// 产品自身的正常 User-Agent；不冒充其它客户端。
fn user_agent() -> String {
    format!("anywork/{}", pl_studio_update::STUDIO_VERSION.trim())
}

/// authority 是否出现了 userinfo 分隔符；空用户名（`https://@host/…`）也算 userinfo。
fn authority_has_userinfo(url: &reqwest::Url) -> bool {
    url.as_str()
        .split_once("://")
        .and_then(|(_, rest)| rest.split('/').next())
        .is_some_and(|authority| authority.contains('@'))
}
