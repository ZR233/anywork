//! ACP 官方 server 自动准备与大版本 `1` 升级 owner 的目录页。
//!
//! 子模块职责（唯一 canonical 路径，不复制第二套事实）：
//! - `registry`：owner 内唯一可变事实——独立 `acpInstall` revision、关闭闸门、每 provider 当前
//!   target 的操作槽位、已安装版本、更新检查状态与已受理 operation 身份，以及全部状态转换。
//! - `admission`：命令入口（受理/取消/手动检查更新/启动并行检查/关闭回收）；受理与取消都是同步命令。
//! - `source`：官方 ACP 注册表客户端、大版本 `1` 兼容性策略、内置 `1.4.5` 基线与安装身份。
//! - `download`：`downlowd` 装配、约 250ms 有界进度合并、累计重试与"等待库真正关闭文件"的取消。
//! - `archive`：ZIP 安全边界、私有 staging 解压、版本化回执、完整复用校验与原子发布。
//! - `operation`：单次准备/升级操作的 supervisor（解析→锁→下载→校验→解压→发布→终态）。
//! - `prepare`：认证前多版本离线扫描与完整验证；复用同一验证边界，不新建第二套校验器。
//! - `mapping`：失败分类到安全摘要与命令错误的映射。
//! - `permissions`：Unix 受管对象的权限位核验；Windows 沿用用户目录的原生 ACL。

mod admission;
mod archive;
mod download;
mod mapping;
mod operation;
mod paths;
#[cfg(unix)]
mod permissions;
mod prepare;
mod registry;
mod source;
#[cfg(test)]
mod upgrade_tests;

pub(crate) use admission::AcpInstallRuntime;
pub(in crate::studio::runtime) use prepare::{PrepareFailure, VerifiedInstall, verified_install};
/// 模板目录展示的支持范围标识（`1.x`）。
pub(in crate::studio::runtime) use source::SUPPORTED_VERSION_RANGE;
pub(crate) use source::availability as automatic_install_availability;

/// 合成生命周期 peer 的测试安装；只在隔离测试 home 构造本地回执，不下载或冒充真实发行验收。
#[cfg(all(test, target_os = "linux"))]
pub(in crate::studio::runtime) fn seed_synthetic_install(
    store: &crate::studio::StudioStore,
    program: &[u8],
) {
    seed_synthetic_install_version(store, source::MINIMUM_SUPPORTED_VERSION, program);
}

#[cfg(all(test, target_os = "linux"))]
pub(in crate::studio::runtime) fn seed_synthetic_install_version(
    store: &crate::studio::StudioStore,
    version: &str,
    program: &[u8],
) {
    use sha2::Digest;
    use std::os::unix::fs::PermissionsExt;
    let base = source::resolve_bundled(crate::AcpProvider::Antigravity).unwrap();
    let release = source::ResolvedRelease {
        release: crate::AcpInstallRelease {
            version: version.to_string(),
            target: base.release.target.clone(),
            archive_url: base
                .release
                .archive_url
                .replace(source::MINIMUM_SUPPORTED_VERSION, version),
            sha256: base.release.sha256.clone(),
        },
        command: base.command,
        args: base.args,
    };
    let id = source::installation_id(crate::AcpProvider::Antigravity, &release);
    let key = source::storage_key(&id).unwrap();
    let root = paths::ManagedRoot::open(
        store.paths().home(),
        store.acp_servers_root(),
        crate::AcpInstallStage::Publish,
    )
    .unwrap();
    let installed = root
        .ensure_dir(
            &["installed", "antigravity", &release.release.target, &key],
            crate::AcpInstallStage::Publish,
        )
        .unwrap();
    let path = installed.join(&release.command);
    std::fs::write(&path, program).unwrap();
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700)).unwrap();
    archive::write_receipt(
        &root,
        &installed,
        &archive::Receipt {
            format: 1,
            installation_id: id,
            release: release.release,
            command: release.command.clone(),
            args: release.args,
            archive_sha256: "synthetic-no-archive".into(),
            members: vec![archive::ReceiptMember {
                path: release.command,
                size: program.len() as u64,
                sha256: hex::encode(sha2::Sha256::digest(program)),
                mode: Some(0o700),
            }],
            directories: Vec::new(),
        },
    )
    .unwrap();
}
