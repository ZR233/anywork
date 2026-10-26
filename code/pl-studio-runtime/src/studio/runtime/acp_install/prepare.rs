//! 认证前的固定受管安装验证（只读）。
//!
//! 认证只能用产品固定发行、且经**完整验证**的受管安装启动：这里按产品清单重新计算冻结描述符，
//! 定位 `<Studio home>/studio/acp-servers/installed/<provider>/<target>/<installation>`，并用安装
//! 器自己的完整验证边界（回执、完整成员集合、size/hash、权限、入口执行位）核对实际磁盘内容。
//!
//! 只验证，不下载、不修复、不创建目录、不写回执：缺失是"需要准备"，不合格是"安装无效"，
//! 都不隐式补救，也不把 runtime 曾发布过的 Ready 缓存当成磁盘事实（design/28 §28.3、§28.8）。
//!
//! 与安装资产锁的关系：本模块只读取**已发布**安装。发布是不可被业务取消回滚的原子 rename，安装器
//! 从不修改已发布树，因此认证验证既不获取跨进程资产锁，也不会与安装器形成锁序死锁；任何无法确认
//! 的情形都按失败处理，绝不放行启动。验证本身只占用阻塞线程与只读句柄，不派生进程或管道，因此
//! supervisor 只需等待它返回，不存在需要额外回收的物理资源。

use std::path::{Path, PathBuf};

use pl_protocol::studio::{
    AcpInstallFailure, AcpInstallFailureCode, AcpInstallRelease, AcpInstallStage, AcpProvider,
};
use tokio_util::sync::CancellationToken;

use super::archive::{self, ExpectedInstall};
use super::paths::ManagedRoot;
use super::source;

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
    /// 没有该固定发行的受管安装：需要用户显式准备。
    PreparationRequired,
    /// 安装存在但回执、完整成员、权限或入口执行位不合格。
    InstallationInvalid,
    /// 宿主平台没有产品固定支持的官方发行。
    UnsupportedPlatform,
    /// 真实本地 IO 失败：无法确认安装，不放行启动。
    Io,
    /// 验证过程中收到取消。
    Cancelled,
}

/// 产品固定发行身份（版本 + 宿主 target）；平台不支持时为 `None`。
///
/// 认证的连接代次由 provider 与该身份共同决定：产品更换固定版本后旧代次自然失效，而名称编辑不会
/// 改变它（design/28 §28.2）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::studio::runtime) struct ReleaseIdentity {
    pub(in crate::studio::runtime) version: String,
    pub(in crate::studio::runtime) target: String,
}

/// 当前宿主的固定发行身份；不联网，也不读配置。
pub(in crate::studio::runtime) fn release_identity(
    provider: crate::config::AcpProvider,
) -> Option<ReleaseIdentity> {
    let resolved = source::resolve(protocol_provider(provider)).ok()?;
    Some(ReleaseIdentity {
        version: resolved.release.version,
        target: resolved.release.target,
    })
}

/// 验证指定固定发行的受管安装并返回冻结启动资格。
pub(in crate::studio::runtime) async fn verified_install(
    store: &crate::studio::StudioStore,
    provider: crate::config::AcpProvider,
    cancellation: &CancellationToken,
) -> Result<VerifiedInstall, PrepareFailure> {
    let home = store.paths().home().to_path_buf();
    let root = store.acp_servers_root();
    let cancel = cancellation.clone();
    // 完整验证是同步文件工作：放进阻塞池，不占用异步 worker；只读，不需要额外的 join 责任。
    match tokio::task::spawn_blocking(move || verify(&home, root, provider, &cancel)).await {
        Ok(result) => result,
        // 阻塞任务 panic 不是"未准备"，也无法确认安装：如实按本地 IO 失败。
        Err(_) => Err(PrepareFailure::Io),
    }
}

fn verify(
    home: &Path,
    root_path: PathBuf,
    provider: crate::config::AcpProvider,
    cancellation: &CancellationToken,
) -> Result<VerifiedInstall, PrepareFailure> {
    if cancellation.is_cancelled() {
        return Err(PrepareFailure::Cancelled);
    }
    let wire_provider = protocol_provider(provider);
    let resolved = source::resolve(wire_provider).map_err(map_install_failure)?;
    let installation_id = source::installation_id(wire_provider, &resolved);
    let storage_key =
        source::storage_key(&installation_id).ok_or(PrepareFailure::InstallationInvalid)?;
    let stage = AcpInstallStage::Verify;
    // 只读打开安装根：不创建目录，缺失就是"尚未准备"。
    let Some(root) =
        ManagedRoot::open_existing(home, root_path, stage).map_err(map_install_failure)?
    else {
        return Err(PrepareFailure::PreparationRequired);
    };
    let installed = super::paths::installed_path(
        &root,
        wire_provider.as_str(),
        &resolved.release.target,
        &storage_key,
    );
    match std::fs::symlink_metadata(&installed) {
        // 存在（含链接）：交给完整验证按类型/权限拒绝，不在这里猜结论。
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Err(PrepareFailure::PreparationRequired);
        }
        Err(_) => return Err(PrepareFailure::Io),
    }
    let receipt = archive::verify_installed(
        &root,
        &installed,
        ExpectedInstall {
            installation_id: &installation_id,
            release: &resolved.release,
            command: &resolved.command,
            args: &resolved.args,
        },
        cancellation,
        &|_completed, _total| {},
    )
    .map_err(map_install_failure)?;
    Ok(VerifiedInstall {
        program: installed.join(&receipt.command),
        args: resolved.args,
        installation_id: receipt.installation_id,
        release: receipt.release,
    })
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
