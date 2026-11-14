//! ACP 官方 server 自动准备 owner 的目录页。
//!
//! 子模块职责（唯一 canonical 路径，不复制第二套事实）：
//! - `registry`：owner 内唯一可变事实——独立 `acpInstall` revision、关闭闸门、每 provider 当前
//!   target 的操作槽位与已受理 operation 身份，以及全部状态转换。
//! - `admission`：命令入口（受理/取消/关闭回收）；受理与取消都是同步命令，任务在 owner 锁内登记。
//! - `source`：产品固定发行清单（本地解析）、宿主 target 判定、分发包来源政策与安装身份。
//! - `download`：`downlowd` 装配、约 250ms 有界进度合并、累计重试与"等待库真正关闭文件"的取消。
//! - `archive`：ZIP 安全边界、私有 staging 解压、版本化回执、完整复用校验与原子发布。
//! - `operation`：单次操作的 supervisor（解析→锁→下载→校验→解压→发布→终态）。
//! - `prepare`：认证前的固定受管安装只读验证；复用同一验证边界，不新建第二套校验器。
//! - `mapping`：失败分类到安全摘要与命令错误的映射。
//! - `permissions`：Unix 受管对象的权限位核验；Windows 沿用用户目录的原生 ACL。
//!
//! 只读查询与订阅都不联网、不扫描、不启动任何程序：只有显式 start 命令才写文件，而 `prepare`
//! 只对既有安装做只读验证（不联网、不下载、不修复）。安装是共享资产：它不绑定账号、不写
//! Settings、不启动认证（见 design/28 §28.5–28.8）。

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

pub(crate) use admission::AcpInstallRuntime;
pub(in crate::studio::runtime) use prepare::{
    PrepareFailure, ReleaseIdentity, VerifiedInstall, release_identity, verified_install,
};
/// 产品固定支持的官方 server 版本；模板、安装与认证版本核对共用这一份事实。
pub(in crate::studio::runtime) use source::SERVER_VERSION;
pub(crate) use source::availability as automatic_install_availability;

/// 合成生命周期 peer 的测试安装；只在隔离测试 home 构造本地回执，不下载或冒充真实发行验收。
#[cfg(all(test, target_os = "linux"))]
pub(in crate::studio::runtime) fn seed_synthetic_install(
    store: &crate::studio::StudioStore,
    program: &[u8],
) {
    use sha2::Digest;
    use std::os::unix::fs::PermissionsExt;
    let release = source::resolve(pl_protocol::studio::AcpProvider::Antigravity).unwrap();
    let id = source::installation_id(pl_protocol::studio::AcpProvider::Antigravity, &release);
    let key = source::storage_key(&id).unwrap();
    let root = paths::ManagedRoot::open(
        store.paths().home(),
        store.acp_servers_root(),
        pl_protocol::studio::AcpInstallStage::Publish,
    )
    .unwrap();
    let installed = root
        .ensure_dir(
            &["installed", "antigravity", &release.release.target, &key],
            pl_protocol::studio::AcpInstallStage::Publish,
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
