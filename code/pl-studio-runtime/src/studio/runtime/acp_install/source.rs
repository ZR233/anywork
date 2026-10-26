//! 产品固定发行清单与分发包来源政策。
//!
//! 本阶段只支持 Antigravity 官方 server 1.4.1：provider、版本、target、归档、摘要策略、包内入口
//! 与 argv 全部由这里的产品代码冻结，运行期**不访问**任何 registry，也不解析远端版本或自定义
//! 环境。客户端显示平台不参与决策，版本更新只能通过后续产品代码变更与验证完成
//! （见 design/28 §28.5）。
//!
//! 官方 1.4.1 清单未提供发行方 SHA256，因此这里如实返回 `sha256: None`：信任边界只到官方 HTTPS
//! 来源，本地 ZIP CRC、摘要与安装回执仍然完整核验。

use std::time::Duration;

use pl_protocol::studio::{
    AcpInstallAvailability, AcpInstallFailure, AcpInstallFailureCode, AcpInstallRelease,
    AcpInstallStage, AcpProvider,
};

use super::mapping::failure;

/// 产品固定支持的官方 server 版本；与模板 `supportedVersion`、安装资格和认证版本核对共用。
pub(in crate::studio::runtime) const SERVER_VERSION: &str = "1.4.1";
/// 固定分发包的共同 URL 前缀；归档路径只来自下面的静态表。
const ARCHIVE_BASE_URL: &str = "https://dl.google.com/agy-extensions/releases/";
/// 允许的分发包来源。
const ARCHIVE_HOST: &str = "dl.google.com";
const ARCHIVE_PATH_PREFIX: &str = "/agy-extensions/releases/";
const MAX_REDIRECTS: usize = 5;

/// 一个固定发行目标的静态条目：归档相对路径、包内入口与不可变 argv。
struct FixedTarget {
    target: &'static str,
    archive_path: &'static str,
    /// 包内相对入口路径（POSIX 分隔）。官方清单写作 `./agy_acp_server.par`，这里的归一化只去掉
    /// 已由既有安全路径规则处理的 `./` 前缀，不改变路径语义。
    command: &'static str,
    args: &'static [&'static str],
}

/// 产品清单的唯一静态表；不支持的 target 没有条目，也不存在回退分支。
const FIXED_TARGETS: &[FixedTarget] = &[
    FixedTarget {
        target: "linux-x86_64",
        archive_path: "linux/agy-acp-server-1.4.1-linux-x86_64.zip",
        command: "agy_acp_server.par",
        args: &["--uid="],
    },
    FixedTarget {
        target: "linux-aarch64",
        archive_path: "linux/agy-acp-server-1.4.1-linux-arm64.zip",
        command: "agy_acp_server.par",
        args: &["--uid="],
    },
    FixedTarget {
        target: "windows-x86_64",
        archive_path: "windows/agy-acp-server-1.4.1-windows-x86_64.zip",
        command: "agy_acp_server.exe",
        args: &[],
    },
    FixedTarget {
        target: "windows-aarch64",
        archive_path: "windows/agy-acp-server-1.4.1-windows-arm64.zip",
        command: "agy_acp_server.exe",
        args: &[],
    },
];

/// 一次准备的冻结结果：wire 发行身份 + 包内入口与固定 argv。
///
/// `command`/`args` 只在内核安装与认证边界内部使用，不进入账号 DTO、HTTP 或 FRB 的接入字段。
#[derive(Debug, Clone)]
pub(super) struct ResolvedRelease {
    pub(super) release: AcpInstallRelease,
    /// 包内相对入口路径（POSIX 分隔）。
    pub(super) command: String,
    pub(super) args: Vec<String>,
}

/// 当前后端宿主平台对应的清单 target；不受支持时返回 `None`。
pub(super) fn current_target() -> Option<&'static str> {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("linux", "x86_64") => Some("linux-x86_64"),
        ("linux", "aarch64") => Some("linux-aarch64"),
        ("windows", "x86_64") => Some("windows-x86_64"),
        ("windows", "aarch64") => Some("windows-aarch64"),
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

/// 安装身份：provider/version/target/archive/sha256/cmd/args 的确定摘要。
///
/// 采用确定序列化 + 摘要，不把版本直接拼进路径；provider/target 同时进入目录分层，因此不同
/// 平台或后续固定版本不会互相覆盖。
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

/// provider 对应的固定清单表；只有产品确实提供官方发行的接入类型才有条目。
fn fixed_targets(provider: AcpProvider) -> &'static [FixedTarget] {
    match provider {
        AcpProvider::Antigravity => FIXED_TARGETS,
    }
}

/// 解析产品固定清单：纯本地计算，不联网、不读配置、不依赖环境变量。
///
/// 失败只可能是宿主平台没有固定发行（`UnsupportedPlatform`），或静态条目自身不再满足来源政策
/// （`SourceRejected`，不变量护栏）。两种情况都不可重试，也不存在回退到远端或本地程序的路径。
pub(super) fn resolve(provider: AcpProvider) -> Result<ResolvedRelease, AcpInstallFailure> {
    let stage = AcpInstallStage::Resolve;
    let Some(target) = current_target() else {
        return Err(failure(
            AcpInstallFailureCode::UnsupportedPlatform,
            stage,
            false,
        ));
    };
    let Some(fixed) = fixed_targets(provider)
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
    // 静态条目必须自身满足运行期来源政策：清单写错时明确失败，而不是放宽校验。
    validate_archive_url(&archive_url)?;
    Ok(ResolvedRelease {
        release: AcpInstallRelease {
            version: SERVER_VERSION.to_string(),
            target: target.to_string(),
            archive_url: archive_url.to_string(),
            // 官方 1.4.1 清单未提供发行方摘要：不伪造 checksum 分支。
            sha256: None,
        },
        command: fixed.command.to_string(),
        args: fixed.args.iter().map(|arg| (*arg).to_string()).collect(),
    })
}

/// 分发包客户端：每一跳都按官方来源政策校验，最多 5 跳，并有独立连接/读取超时。
///
/// 不做"默认 client"回退：构造失败按 typed `Network` 传播，不丢来源政策与超时。
pub(super) fn archive_client() -> Result<reqwest::Client, AcpInstallFailure> {
    reqwest::Client::builder()
        .user_agent(user_agent())
        .connect_timeout(Duration::from_secs(10))
        .read_timeout(Duration::from_secs(30))
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            if attempt.previous().len() > MAX_REDIRECTS {
                return attempt.error("too many redirects");
            }
            if validate_archive_url(attempt.url()).is_err() {
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

/// 产品自身的正常 User-Agent；不冒充其它客户端。
fn user_agent() -> String {
    format!("anywork/{}", crate::updater::STUDIO_VERSION.trim())
}

/// 分发包来源政策：仅官方 Google HTTPS ZIP 路径，拒绝用户信息、额外端口、fragment 与越界路径。
pub(super) fn validate_archive_url(url: &reqwest::Url) -> Result<(), AcpInstallFailure> {
    let rejected = || {
        failure(
            AcpInstallFailureCode::SourceRejected,
            AcpInstallStage::Resolve,
            false,
        )
    };
    if url.scheme() != "https" || url.host_str() != Some(ARCHIVE_HOST) {
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
    if !path.starts_with(ARCHIVE_PATH_PREFIX) || path.contains('\\') {
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
    if !lowered.ends_with(".zip") {
        return Err(rejected());
    }
    Ok(())
}

/// authority 是否出现了 userinfo 分隔符；空用户名（`https://@host/…`）也算 userinfo。
fn authority_has_userinfo(url: &reqwest::Url) -> bool {
    url.as_str()
        .split_once("://")
        .and_then(|(_, rest)| rest.split('/').next())
        .is_some_and(|authority| authority.contains('@'))
}
