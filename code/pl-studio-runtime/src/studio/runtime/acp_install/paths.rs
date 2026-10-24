//! 安装根下的受管路径边界。
//!
//! 安装根位于受信 Studio home 之下，但根内的一切（下载缓存、`.part`/sidecar、锁文件、暂存、
//! 已发布目录）都会写入磁盘并可能被其它工具改动，因此不能直接用 `create_dir_all`/`try_exists`/
//! `OpenOptions::open` 跟随链接。这里统一复用仓内成熟的 [`pl_tool::workspace::path_safety`]：
//! 从**已声明的 Studio home 锚点**逐层 `symlink_metadata` 判定，Unix symlink 与 Windows reparse
//! point 都视为显式边界；创建只用 fail-if-exists 的 `create_dir`/`create_new`，创建后立即复核并
//! 显式设置权限（不依赖 umask），本操作拥有的暂存用 no-follow 递归删除。
//!
//! 本模块不写 unsafe、不自研文件系统原语、也不擅自新增依赖；能力升级路径与各平台持久化等级由
//! 上游统一决定，本层只如实报告实际观测到的结果。
//!
//! 威胁边界按 [design/28 §28.7] 确认的标准桌面应用模型：防护不可信分发内容、预先存在的符号
//! 链接/reparse、路径越界和损坏安装；不承诺抵御能同时改写当前用户配置、安装管理树或进程权限的
//! 同权限恶意进程或管理员，也不构成 OS 沙箱。Studio home 与祖先必须是宿主选择的受信产品路径，
//! 任意可被其他主体并发改写的共享目录不因路径形状符合布局就成为可信锚点。该边界只界定不承诺
//! 什么，不豁免下文任何实际链接、权限与完整性检查。
//!
//! [design/28 §28.7]: ../../../../../../design/28-acp.md

use std::path::{Path, PathBuf};

use pl_protocol::studio::{AcpInstallFailure, AcpInstallFailureCode, AcpInstallStage};
use pl_tool::workspace::path_safety;

use super::mapping::failure;

/// 产品自建目录权限：仅属主可读写执行（显式设置，不依赖 umask）。
#[cfg(unix)]
pub(super) const DIRECTORY_MODE: u32 = 0o700;
#[cfg(not(unix))]
pub(super) const DIRECTORY_MODE: u32 = 0;

/// 一个已确认是真实目录的安装根。
#[derive(Debug, Clone)]
pub(super) struct ManagedRoot {
    root: PathBuf,
}

impl ManagedRoot {
    /// 从受信 Studio home 锚点逐层核验并创建安装根；任何一层已存在但不是真实目录都拒绝。
    pub(super) fn open(
        trusted_home: &Path,
        root: PathBuf,
        stage: AcpInstallStage,
    ) -> Result<Self, AcpInstallFailure> {
        if !path_safety::is_lexically_within(trusted_home, &root) {
            return Err(link_rejected(stage));
        }
        walk_real_directories(trusted_home, &root, &root, stage)?;
        // Unix：本次可能新建了安装根及其祖先，新建目录项的父目录必须进入持久化屏障；只同步到
        // 受信 Studio home 为止，不越过锚点去声称同步任意宿主父链（design/28 §28.7）。
        #[cfg(unix)]
        sync_directory_chain(trusted_home, &root, stage)?;
        let managed = Self { root };
        managed.require_private_directory(&managed.root.clone(), stage)?;
        Ok(managed)
    }

    /// 逐层确保 `relative` 目录存在；既有每一层都必须是真实目录，新层显式设置权限。
    pub(super) fn ensure_dir(
        &self,
        relative: &[&str],
        stage: AcpInstallStage,
    ) -> Result<PathBuf, AcpInstallFailure> {
        let mut current = self.root.clone();
        for component in relative {
            current.push(component);
            walk_real_directories(&self.root, &current, &self.root, stage)?;
        }
        Ok(current)
    }

    /// 只读打开**已存在**的安装根：不创建任何目录，缺失时返回 `Ok(None)`。
    ///
    /// 认证前的安装验证只读取已发布资产，不能因为一次检查就在宿主上新建目录树。缺失表示"尚未
    /// 准备"；既存但不是真实目录、或任一祖先出现链接/reparse，明确拒绝（design/28 §28.7）。
    pub(super) fn open_existing(
        trusted_home: &Path,
        root: PathBuf,
        stage: AcpInstallStage,
    ) -> Result<Option<Self>, AcpInstallFailure> {
        if !path_safety::is_lexically_within(trusted_home, &root) {
            return Err(link_rejected(stage));
        }
        let metadata = path_safety::metadata_if_real(&root).map_err(|_| io(stage))?;
        let Some(metadata) = metadata else {
            // 区分"确实缺失"与"存在但不是真实目录（链接/reparse）"。
            return match std::fs::symlink_metadata(&root) {
                Ok(_) => Err(link_rejected(stage)),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
                Err(_) => Err(io(stage)),
            };
        };
        if !metadata.is_dir() {
            return Err(not_a_directory(stage));
        }
        // 受信 home 到安装根的整条既有链都必须是真实目录；这里只校验，不创建、不 chmod。
        path_safety::validate_existing_path(trusted_home, &root)
            .map_err(|_| link_rejected(stage))?;
        let managed = Self { root };
        managed.require_private_directory(&managed.root.clone(), stage)?;
        Ok(Some(managed))
    }

    /// 安装根自身；供需要同步祖先链的调用方从根开始逐层持久化。
    pub(super) fn anchor(&self) -> &Path {
        &self.root
    }

    /// 既有条目（不跟随链接）的 metadata；链接与缺失都返回 `None`。
    pub(super) fn probe(
        &self,
        path: &Path,
        stage: AcpInstallStage,
    ) -> Result<Option<std::fs::Metadata>, AcpInstallFailure> {
        path_safety::validate_path_for_write(&self.root, path).map_err(|_| link_rejected(stage))?;
        path_safety::metadata_if_real(path).map_err(|_| io(stage))
    }

    /// 校验既有路径（含最终目标）没有链接边界。
    pub(super) fn validate_existing(
        &self,
        path: &Path,
        stage: AcpInstallStage,
    ) -> Result<(), AcpInstallFailure> {
        path_safety::validate_existing_path(&self.root, path).map_err(|_| link_rejected(stage))
    }

    /// 校验一个既有受管目录既是真实目录（无链接），又是产品私有权限。
    ///
    /// 用于安装根、已发布安装目录这类不在 `ensure_dir` 链路上、但仍属于产品管理树的目录。
    pub(super) fn require_private_directory(
        &self,
        path: &Path,
        stage: AcpInstallStage,
    ) -> Result<(), AcpInstallFailure> {
        self.validate_existing(path, stage)?;
        let Some(metadata) = path_safety::metadata_if_real(path).map_err(|_| io(stage))? else {
            return Err(link_rejected(stage));
        };
        if !metadata.is_dir() {
            return Err(not_a_directory(stage));
        }
        super::private_acl::verify_private_object(path, true, stage)
    }

    /// 校验一个既有受管文件是真实普通文件（无链接），且满足私有性规则。
    ///
    /// 覆盖 part/sidecar、锁文件、回执与已安装成员：在**使用或写入资产之前**检查，
    /// 不会因为目录已校验过就让文件绕过边界（design/28 §28.7）。
    pub(super) fn require_private_file(
        &self,
        path: &Path,
        stage: AcpInstallStage,
    ) -> Result<bool, AcpInstallFailure> {
        let Some(metadata) = path_safety::metadata_if_real(path).map_err(|_| io(stage))? else {
            return Ok(false);
        };
        if !metadata.is_file() {
            return Err(failure(AcpInstallFailureCode::Io, stage, false));
        }
        self.validate_existing(path, stage)?;
        super::private_acl::verify_private_object(path, false, stage)?;
        Ok(true)
    }

    /// 校验写入目标（允许缺失后缀），用于把路径交给库（例如下载器）之前。
    pub(super) fn validate_write(
        &self,
        path: &Path,
        stage: AcpInstallStage,
    ) -> Result<(), AcpInstallFailure> {
        path_safety::validate_path_for_write(&self.root, path).map_err(|_| link_rejected(stage))
    }

    /// 校验路径：存在则必须无链接边界，缺失则校验写入路径。
    pub(super) fn validate_existing_or_missing(
        &self,
        path: &Path,
        stage: AcpInstallStage,
    ) -> Result<(), AcpInstallFailure> {
        match path_safety::metadata_if_real(path).map_err(|_| io(stage))? {
            Some(_) => self.validate_existing(path, stage),
            None => {
                if std::fs::symlink_metadata(path).is_ok() {
                    return Err(link_rejected(stage));
                }
                self.validate_write(path, stage)
            }
        }
    }

    /// 严格列举目录内容：链接/reparse 与特殊文件是**错误**而不是被过滤掉的条目。
    pub(super) fn entries_strict(
        &self,
        directory: &Path,
        stage: AcpInstallStage,
    ) -> Result<Vec<(PathBuf, std::fs::Metadata)>, AcpInstallFailure> {
        self.validate_existing(directory, stage)?;
        let read = std::fs::read_dir(directory).map_err(|_| io(stage))?;
        let mut entries = Vec::new();
        for entry in read {
            let entry = entry.map_err(|_| io(stage))?;
            let path = entry.path();
            let metadata = std::fs::symlink_metadata(&path).map_err(|_| io(stage))?;
            if path_safety::is_link_or_reparse(&metadata) {
                return Err(link_rejected(stage));
            }
            if !metadata.is_file() && !metadata.is_dir() {
                return Err(failure(AcpInstallFailureCode::CacheCorrupt, stage, false));
            }
            entries.push((path, metadata));
        }
        Ok(entries)
    }

    /// 删除本操作拥有的暂存树；不跟随链接，不触碰根外路径。
    pub(super) fn remove_owned_tree(
        &self,
        target: &Path,
        stage: AcpInstallStage,
    ) -> Result<(), AcpInstallFailure> {
        if path_safety::metadata_if_real(target)
            .map_err(|_| io(stage))?
            .is_none()
        {
            return Ok(());
        }
        path_safety::remove_dir_all_no_follow(&self.root, target)
            .map_err(|_| failure(AcpInstallFailureCode::ResourceClose, stage, true))
    }
}

/// 已发布安装目录的规范布局：`<安装根>/installed/<provider>/<target>/<storage key>`。
///
/// 安装与认证前的验证共用这一处布局定义，避免两条路径各自拼接。只构造路径，不创建目录，
/// 也不跟随链接。
pub(super) fn installed_path(
    root: &ManagedRoot,
    provider: &str,
    target: &str,
    storage_key: &str,
) -> PathBuf {
    root.anchor()
        .join("installed")
        .join(provider)
        .join(target)
        .join(storage_key)
}

/// 从锚点逐层走到 `target`：既有的必须是真实目录，缺失的用显式权限创建。
///
/// 私有权限只在**安装根及其以下**（`acp-servers`、downloads/locks/staging/installed 与其
/// provider/target 层）要求；锚点与中间层（受信 Studio home、Studio 自己的 `studio/` 目录）是宿主
/// 可信布局，只要求是真实目录，不因为它们的既有 mode 拒绝整个接入，也不去 chmod 别人的目录。
/// 安装根以下的既存目录若已不是私有权限（如 0755/0777），一律拒绝而不是悄悄收权
/// （design/28 §28.7）。
fn walk_real_directories(
    anchor: &Path,
    target: &Path,
    private_from: &Path,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    let relative = target
        .strip_prefix(anchor)
        .map_err(|_| link_rejected(stage))?;
    let mut current = anchor.to_path_buf();
    match std::fs::symlink_metadata(anchor) {
        Ok(metadata) if metadata.is_dir() && !path_safety::is_link_or_reparse(&metadata) => {}
        Ok(_) => return Err(link_rejected(stage)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            create_private_directory(anchor)?;
            apply_directory_mode(anchor)?;
            // 新建目录在写入任何子资产之前就要被证明是私有的（Windows 读真实 owner+DACL，
            // 不推断继承结果；Unix 复核 0700）。
            require_private_directory(anchor, stage)?;
        }
        Err(_) => return Err(io(stage)),
    }
    for component in relative.components() {
        let std::path::Component::Normal(part) = component else {
            return Err(link_rejected(stage));
        };
        current.push(part);
        match std::fs::symlink_metadata(&current) {
            Ok(metadata) if metadata.is_dir() && !path_safety::is_link_or_reparse(&metadata) => {
                if current.starts_with(private_from) {
                    require_private_directory(&current, stage)?;
                }
            }
            Ok(_) => return Err(link_rejected(stage)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                create_private_directory(&current)?;
                apply_directory_mode(&current)?;
                require_private_directory(&current, stage)?;
            }
            Err(_) => return Err(io(stage)),
        }
    }
    Ok(())
}

/// 受管目录的私有性核验：Unix 看 mode，Windows 看真实 owner + DACL（见 `private_acl`）。
fn require_private_directory(path: &Path, stage: AcpInstallStage) -> Result<(), AcpInstallFailure> {
    super::private_acl::verify_private_object(path, true, stage)
}

/// 以显式权限创建目录：Unix 在创建调用上就限制为产品私有权限，不留"先宽后收"的窗口。
///
/// 创建权限仍会被进程 umask 收紧，因此调用方随后必须显式设置最终权限。
fn create_private_directory(path: &Path) -> Result<(), AcpInstallFailure> {
    let mut builder = std::fs::DirBuilder::new();
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        builder.mode(DIRECTORY_MODE);
    }
    builder
        .create(path)
        .map_err(|_| io(AcpInstallStage::Extract))
}

/// 显式目录权限；Unix 上创建后立即设置，避免依赖 umask。
pub(super) fn apply_directory_mode(path: &Path) -> Result<(), AcpInstallFailure> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(DIRECTORY_MODE))
            .map_err(|_| io(AcpInstallStage::Extract))?;
    }
    #[cfg(not(unix))]
    {
        let _ = path;
    }
    Ok(())
}

/// Unix 专用：同步从锚点到目标父目录的每一层，保证新建目录项逐级 durable。
///
/// Windows 不提供（也不声称提供）Unix 等价的目录 fsync：那里的落盘保证来自成员文件的
/// `sync_all` 与同卷 write-through 移动，见 design/28 §28.7。因此该函数在非 Unix 平台上不存在，
/// 调用点也由 `cfg(unix)` 守着，不会出现"调用了但空操作返回成功"的伪确认。
#[cfg(unix)]
pub(super) fn sync_ancestors(
    anchor: &Path,
    target_parent: &Path,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    let mut chain: Vec<PathBuf> = Vec::new();
    let mut current = target_parent.to_path_buf();
    while current.starts_with(anchor) {
        chain.push(current.clone());
        if current == anchor {
            break;
        }
        match current.parent() {
            Some(parent) => current = parent.to_path_buf(),
            None => break,
        }
    }
    // 由浅到深：父目录项先持久化。
    for directory in chain.into_iter().rev() {
        let handle = std::fs::File::open(&directory).map_err(|_| io(stage))?;
        handle.sync_all().map_err(|_| io(stage))?;
    }
    Ok(())
}

/// Unix 专用目录 fsync；失败是真实收束问题，不能当作已 durable。
#[cfg(unix)]
pub(super) fn sync_directory(path: &Path, stage: AcpInstallStage) -> Result<(), AcpInstallFailure> {
    let handle = std::fs::File::open(path).map_err(|_| io(stage))?;
    handle.sync_all().map_err(|_| io(stage))
}

/// Unix 专用：同步从 `top` 到 `bottom`（含两端）的每一层目录项。
///
/// 用于"安装根可能在本次操作中被新建"的场景：新建目录的父目录项必须落盘，否则崩溃后可能出现
/// 目录存在而其父项未知的状态。`top` 是受信 Studio home，绝不越过它继续向宿主父链同步。
#[cfg(unix)]
pub(super) fn sync_directory_chain(
    top: &Path,
    bottom: &Path,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    let relative = bottom.strip_prefix(top).map_err(|_| link_rejected(stage))?;
    let mut chain = vec![top.to_path_buf()];
    let mut current = top.to_path_buf();
    for component in relative.components() {
        let std::path::Component::Normal(part) = component else {
            return Err(link_rejected(stage));
        };
        current.push(part);
        chain.push(current.clone());
    }
    // 由浅到深：父目录项先持久化。
    for directory in chain {
        sync_directory(&directory, stage)?;
    }
    Ok(())
}

fn io(stage: AcpInstallStage) -> AcpInstallFailure {
    failure(AcpInstallFailureCode::Io, stage, true)
}

fn not_a_directory(stage: AcpInstallStage) -> AcpInstallFailure {
    failure(AcpInstallFailureCode::Io, stage, false)
}

fn link_rejected(stage: AcpInstallStage) -> AcpInstallFailure {
    failure(AcpInstallFailureCode::Io, stage, false)
}
