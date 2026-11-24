//! 认证前的受管安装离线发现与完整验证（只读）。
//!
//! 认证只能用受管大版本 `1` 范围内（`>= 1.5.2, < 2.0.0`）、且经**完整验证**的已安装版本启动：
//! 这里离线扫描 `<Studio home>/studio/acp-servers/installed/<provider>/<target>/` 下的受管安装目录，
//! 校验每个安装的回执身份与发行来源，跳过不受支持的版本，并用安装器的完整性校验核对最高
//! 受支持版本的成员集合、权限、大小、SHA-256 和入口执行位。
//!
//! 扫描只读。没有受支持的候选是"需要准备"；
//! 目录或回执身份异常、所选版本完整性校验失败是"安装无效"（design/28 §28.3、§28.7、§28.8）。
//!
//! 与安装资产锁的关系：本模块只读取**已发布**安装。发布是不可被业务取消回滚的原子 rename，安装器
//! 从不修改已发布树，因此认证验证既不获取跨进程资产锁，也不会与安装器形成锁序死锁。

use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use crate::{
    AcpInstallFailure, AcpInstallFailureCode, AcpInstallRelease, AcpInstallStage,
    AcpInstalledServer, AcpProvider,
};
use tokio_util::sync::CancellationToken;

use super::archive::{self, ExpectedInstall};
use super::paths::ManagedRoot;
use super::source::{self, ResolvedRelease, SourcePolicy, VersionClassification};

const MAX_INSTALLED_DIRS_SCAN: usize = 64;

/// 验证通过的启动资格：绝对 program 与固定 argv 只在 runtime 私有边界内存在。
///
/// 它不是 wire 类型：账号 DTO、HTTP 与 FRB 都不携带 program/argv，避免恢复任意执行入口。
#[derive(Debug, Clone)]
pub(in crate::studio::runtime) struct VerifiedInstall {
    pub(in crate::studio::runtime) program: PathBuf,
    pub(in crate::studio::runtime) args: Vec<String>,
    pub(in crate::studio::runtime) installation_id: String,
    pub(in crate::studio::runtime) release: AcpInstallRelease,
}

/// 前置验证失败的安全类别；由认证 owner 映射成 `AcpAuthStage::Prepare` 上的 typed 失败。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::studio::runtime) enum PrepareFailure {
    /// 宿主下尚未准备任何符合条件的 `1.x` 受管安装：需要用户显式准备。
    PreparationRequired,
    /// 安装存在但回执、来源政策、完整成员、权限或入口执行位不合格。
    InstallationInvalid,
    /// 宿主平台没有产品支持的官方发行。
    UnsupportedPlatform,
    /// 真实本地 IO 失败：无法确认安装，不放行启动。
    Io,
    /// 验证过程中收到取消。
    Cancelled,
}

/// 离线验证当前宿主已安装的最高大版本 `1` 受管 server 并返回冻结启动资格。
pub(in crate::studio::runtime) async fn verified_install(
    store: &crate::studio::StudioStore,
    provider: crate::config::AcpProvider,
    cancellation: &CancellationToken,
) -> Result<VerifiedInstall, PrepareFailure> {
    let home = store.paths().home().to_path_buf();
    let root = store.acp_servers_root();
    let cancel = cancellation.clone();
    match tokio::task::spawn_blocking(move || {
        verify(&home, root, &SourcePolicy::official(), provider, &cancel)
    })
    .await
    {
        Ok(result) => result,
        Err(_) => Err(PrepareFailure::Io),
    }
}

/// 供 `AcpInstallRuntime` 启动阶段做只读扫描（不因缺失或失败阻断启动）。
pub(super) async fn scan_installed(
    store: &crate::studio::StudioStore,
    policy: SourcePolicy,
    provider: AcpProvider,
    cancellation: &CancellationToken,
) -> Option<AcpInstalledServer> {
    let home = store.paths().home().to_path_buf();
    let root = store.acp_servers_root();
    let cancel = cancellation.clone();
    let config_provider = match provider {
        AcpProvider::Antigravity => crate::config::AcpProvider::Antigravity,
    };
    tokio::task::spawn_blocking(move || {
        let verified = verify(&home, root, &policy, config_provider, &cancel).ok()?;
        let receipt_path = verified
            .program
            .parent()
            .map(|parent| parent.join(archive::RECEIPT_NAME));
        let ready_at = receipt_path
            .and_then(|path| std::fs::symlink_metadata(path).ok())
            .and_then(|meta| meta.modified().ok())
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
            .and_then(|dur| i64::try_from(dur.as_secs()).ok())
            .unwrap_or_else(crate::studio::unix_seconds);
        Some(AcpInstalledServer {
            installation_id: verified.installation_id,
            release: verified.release,
            program: verified.program.to_string_lossy().into_owned(),
            ready_at,
            reused: true,
        })
    })
    .await
    .ok()
    .flatten()
}

/// 查找本机已安装且通过完整性校验的最高 `1.x` 发行描述符，供远端出现 `2.x` 时复核现有 `1.x`。
pub(super) async fn best_local_release(
    store: &crate::studio::StudioStore,
    policy: SourcePolicy,
    provider: AcpProvider,
    cancellation: &CancellationToken,
) -> Option<ResolvedRelease> {
    let home = store.paths().home().to_path_buf();
    let root = store.acp_servers_root();
    let cancel = cancellation.clone();
    let config_provider = match provider {
        AcpProvider::Antigravity => crate::config::AcpProvider::Antigravity,
    };
    tokio::task::spawn_blocking(move || {
        let verified = verify(&home, root, &policy, config_provider, &cancel).ok()?;
        let command = archive::normalize_relative(verified.program.file_name()?.to_str()?);
        Some(ResolvedRelease {
            release: verified.release,
            command,
            args: verified.args,
        })
    })
    .await
    .ok()
    .flatten()
}

pub(super) fn verify(
    home: &Path,
    root_path: PathBuf,
    policy: &SourcePolicy,
    provider: crate::config::AcpProvider,
    cancellation: &CancellationToken,
) -> Result<VerifiedInstall, PrepareFailure> {
    if cancellation.is_cancelled() {
        return Err(PrepareFailure::Cancelled);
    }
    let stage = AcpInstallStage::Verify;
    let Some(target) = source::current_target() else {
        return Err(PrepareFailure::UnsupportedPlatform);
    };
    let wire_provider = protocol_provider(provider);

    // 只读打开安装根：不创建目录，缺失就是"尚未准备"。
    let Some(root) =
        ManagedRoot::open_existing(home, root_path, stage).map_err(map_install_failure)?
    else {
        return Err(PrepareFailure::PreparationRequired);
    };

    let installed_root = root.anchor().join("installed");
    let provider_dir = installed_root.join(wire_provider.as_str());
    let target_dir = provider_dir.join(target);
    for dir in [&installed_root, &provider_dir, &target_dir] {
        match std::fs::symlink_metadata(dir) {
            Ok(_) => root
                .require_directory(dir, stage)
                .map_err(map_install_failure)?,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Err(PrepareFailure::PreparationRequired);
            }
            Err(_) => return Err(PrepareFailure::Io),
        }
    }

    let entries = root
        .entries_strict(&target_dir, stage)
        .map_err(map_install_failure)?;
    if entries.len() > MAX_INSTALLED_DIRS_SCAN {
        return Err(PrepareFailure::InstallationInvalid);
    }

    let mut candidates: Vec<(semver::Version, String, PathBuf, archive::Receipt)> = Vec::new();
    for (entry_path, metadata) in entries {
        if cancellation.is_cancelled() {
            return Err(PrepareFailure::Cancelled);
        }
        if !metadata.is_dir() {
            return Err(PrepareFailure::InstallationInvalid);
        }
        root.require_directory(&entry_path, stage)
            .map_err(map_install_failure)?;
        let Some(dir_name) = entry_path.file_name().and_then(|name| name.to_str()) else {
            return Err(PrepareFailure::InstallationInvalid);
        };
        if !is_hex_storage_key(dir_name) {
            return Err(PrepareFailure::InstallationInvalid);
        }
        let receipt = archive::read_receipt(&root, &entry_path).map_err(map_install_failure)?;
        if receipt.release.target != target {
            return Err(PrepareFailure::InstallationInvalid);
        }
        let archive_url = reqwest::Url::parse(&receipt.release.archive_url)
            .map_err(|_| PrepareFailure::InstallationInvalid)?;
        policy
            .validate_archive_url(&archive_url)
            .map_err(|_| PrepareFailure::InstallationInvalid)?;
        source::validate_optional_sha256(receipt.release.sha256.as_deref(), stage)
            .map_err(|_| PrepareFailure::InstallationInvalid)?;
        let normalized_cmd =
            source::validate_target_command_args(target, &receipt.command, &receipt.args, stage)
                .map_err(|_| PrepareFailure::InstallationInvalid)?;
        if normalized_cmd != archive::normalize_relative(&receipt.command) {
            return Err(PrepareFailure::InstallationInvalid);
        }
        let resolved = ResolvedRelease {
            release: receipt.release.clone(),
            command: normalized_cmd,
            args: receipt.args.clone(),
        };
        let expected_id = source::installation_id(wire_provider, &resolved);
        if receipt.installation_id != expected_id
            || source::storage_key(&expected_id).as_deref() != Some(dir_name)
        {
            return Err(PrepareFailure::InstallationInvalid);
        }
        match source::classify_version(&receipt.release.version) {
            VersionClassification::Supported(version) => {
                candidates.push((version, dir_name.to_string(), entry_path, receipt));
            }
            VersionClassification::Unsupported | VersionClassification::IncompatibleMajor(_) => {}
            VersionClassification::Malformed => return Err(PrepareFailure::InstallationInvalid),
        }
    }

    let Some((_, _, best_path, expected_receipt)) = candidates
        .into_iter()
        .max_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)))
    else {
        return Err(PrepareFailure::PreparationRequired);
    };

    let receipt = archive::verify_installed(
        &root,
        &best_path,
        ExpectedInstall {
            installation_id: &expected_receipt.installation_id,
            release: &expected_receipt.release,
            command: &expected_receipt.command,
            args: &expected_receipt.args,
        },
        cancellation,
        &|_completed, _total| {},
    )
    .map_err(map_install_failure)?;

    Ok(VerifiedInstall {
        program: best_path.join(&receipt.command),
        args: receipt.args,
        installation_id: receipt.installation_id,
        release: receipt.release,
    })
}

fn is_hex_storage_key(name: &str) -> bool {
    name.len() == 64
        && name
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

/// 安装失败分类到前置验证类别的穷尽映射。
///
/// 不可重试的 `Io`（链接、非目录等边界拒绝）是"安装不合格"；可重试的真实 IO 与其它无法确认的
/// 情形按本地 IO 失败处理，绝不放行。
fn map_install_failure(failure: AcpInstallFailure) -> PrepareFailure {
    match failure.code {
        AcpInstallFailureCode::UnsupportedPlatform => PrepareFailure::UnsupportedPlatform,
        AcpInstallFailureCode::Cancelled => PrepareFailure::Cancelled,
        AcpInstallFailureCode::CacheCorrupt
        | AcpInstallFailureCode::MissingExecutable
        | AcpInstallFailureCode::InvalidArchive
        | AcpInstallFailureCode::ChecksumMismatch => PrepareFailure::InstallationInvalid,
        AcpInstallFailureCode::Io if !failure.retryable => PrepareFailure::InstallationInvalid,
        AcpInstallFailureCode::SourceRejected
        | AcpInstallFailureCode::Network
        | AcpInstallFailureCode::Timeout
        | AcpInstallFailureCode::TooLarge
        | AcpInstallFailureCode::Io
        | AcpInstallFailureCode::Busy
        | AcpInstallFailureCode::StaleOperation
        | AcpInstallFailureCode::ResourceClose => PrepareFailure::Io,
    }
}

/// 配置侧接入类型 → 协议侧接入类型；两套表示刻意分离，这里只在 runtime 私有边界桥接一次。
fn protocol_provider(provider: crate::config::AcpProvider) -> AcpProvider {
    match provider {
        crate::config::AcpProvider::Antigravity => AcpProvider::Antigravity,
    }
}
