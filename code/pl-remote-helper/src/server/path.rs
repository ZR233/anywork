//! 远端 workspace 的目录能力边界。
//!
//! 只有“打开用户明确指定的 workspace root（以及 GUI 浏览的显式目录）”使用 ambient authority；
//! 此后所有文件原语都通过 [`cap_std::fs::Dir`] 的相对操作完成，不再把校验过的 [`PathBuf`]
//! 交回 ambient API。上传的暂存与原子发布在 [`super::upload`]，同样只使用这里的目录能力。
//!
//! 安全边界仍是“拒绝任何符号链接组件”：路径先按 POSIX 单段拆分（拒绝 `..`、根和前缀），
//! 然后逐目录用 [`cap_fs_ext::DirExt::open_dir_nofollow`] 取得 parent capability；文件打开用
//! [`cap_fs_ext::OpenOptionsFollowExt::follow`] 配 `FollowSymlinks::No` 与 `O_NONBLOCK`，并
//! 验证实际句柄是普通文件。目录创建、stat、列举、复制、重命名、删除都复用这些 Dir 能力。
//!
//! 展示用 canonical 字符串只用于诊断与命令 cwd，不参与文件授权；打开 root 时会核对“已打开
//! 目录对象”与 canonical 路径的身份（dev/ino），不一致就明确失败而不是猜。所有短时同步系统
//! 调用都提交给连接的 [`super::tasks::BlockingTasks`]，调用方取消也不会让它们逃出清理责任。

use std::collections::HashMap;
use std::ffi::OsString;
use std::fmt;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use cap_fs_ext::{DirExt, FollowSymlinks, MetadataExt, OpenOptionsFollowExt};
use cap_std::ambient_authority;
use cap_std::fs::{Dir, Metadata, OpenOptions, OpenOptionsExt, PermissionsExt};
use pl_protocol::remote::{RemoteError, RemoteErrorCode};

use super::fd::{LeasedFd, OperationFd};
use super::resources::{ResourceLease, WorkspaceLeases};
use super::tasks::BlockingTasks;

/// 单次枚举页大小：分页读取，不收集整个目录。
const ENTRY_PAGE: usize = 64;

/// 单个已打开 workspace 的能力；canonical 路径只用于展示。
pub(crate) struct WorkspaceRoot {
    /// 目录句柄与 workspace 池的持久 retained 预算不可分：句柄先关闭、预算后归还。
    root: LeasedFd<Dir>,
    canonical: PathBuf,
    tasks: BlockingTasks,
}

impl WorkspaceRoot {
    /// 唯一使用 ambient authority 的位置：用户明确指定的 workspace root。
    ///
    /// 先取 canonical 身份，再打开该身份，最后用 dev/ino 核对“打开的目录对象就是它”，
    /// 避免路径在两次调用之间被替换成别的目录。
    ///
    /// `leases` 是本 workspace 的 open 峰值：整份预算随闭包进入阻塞任务，调用方取消不会让
    /// `canonicalize`/`open` 在预算已归还的情况下继续跑。成功时只交回持久 retained（随本结构
    /// 直到最后使用者释放），打开期瞬时余量在闭包内（即真实打开结束后）归还；失败全部归还。
    pub(crate) async fn open(
        path: &str,
        tasks: BlockingTasks,
        leases: WorkspaceLeases,
    ) -> Result<Self, RemoteError> {
        let requested = path.to_owned();
        let worker = tasks.clone();
        let (root, canonical) = tasks
            .run(move || {
                let (retained, transient) = leases.split()?;
                let canonical = std::fs::canonicalize(&requested)
                    .map_err(|error| io_error("failed to inspect workspace", error))?;
                let root = Dir::open_ambient_dir(&canonical, ambient_authority())
                    .map_err(|error| io_error("failed to open workspace", error))?;
                let opened = root
                    .dir_metadata()
                    .map_err(|error| io_error("failed to inspect opened workspace", error))?;
                let observed = std::fs::metadata(&canonical)
                    .map_err(|error| io_error("failed to inspect workspace", error))?;
                if opened.dev() != observed.dev() || opened.ino() != observed.ino() {
                    return Err(remote_error(
                        RemoteErrorCode::Io,
                        format!(
                            "workspace root changed while opening: {}",
                            canonical.display()
                        ),
                    ));
                }
                // 打开阶段真实结束：瞬时余量在闭包内归还；目录句柄与持久 retained 是同一个
                // 所有权对象，随 `WorkspaceRoot` 一起走到最后一个使用者释放。
                drop(transient);
                Ok((LeasedFd::new(root, retained), canonical))
            })
            .await?;
        Ok(Self {
            root,
            canonical,
            tasks: worker,
        })
    }

    /// 只为展示与命令 cwd 使用；文件授权始终通过目录能力完成。
    pub(crate) fn canonical_path(&self) -> &Path {
        &self.canonical
    }

    /// 逐组件 no-follow 打开目录能力，同时返回展示用绝对路径。
    pub(crate) async fn open_directory(
        &self,
        path: &str,
        lease: &ResourceLease,
    ) -> Result<(LeasedFd<Dir>, PathBuf), RemoteError> {
        let parts = components(path)?;
        let display = display_path(&self.canonical, &parts);
        let root = self.clone_capability()?;
        let lease = lease.clone();
        self.tasks
            .run(move || {
                // 新目录句柄与本次操作的预算绑定后才交回：取消后 owner 仍 join 到真实结束，
                // 交接链上的句柄也一直计费。root 只是遍历用的短暂能力，随闭包结束关闭。
                let (root_dir, _root_budget) = root.split();
                Ok((LeasedFd::new(open_dir(root_dir, &parts)?, lease), display))
            })
            .await
    }

    /// 打开子目录用于分页枚举（workspace 相对路径）。
    pub(crate) async fn directory(
        &self,
        path: &str,
        lease: &ResourceLease,
    ) -> Result<Directory, RemoteError> {
        let parts = components(path)?;
        let display = display_path(&self.canonical, &parts);
        let root = self.clone_capability()?;
        let tasks = self.tasks.clone();
        let lease = lease.clone();
        self.tasks
            .run(move || {
                let (root_dir, _root_budget) = root.split();
                let dir = open_dir(root_dir, &parts)?;
                // 枚举能力与预算绑定：目录流句柄在 `Directory` 存活期间一直计费。
                Directory::new(LeasedFd::new(dir, lease), display, tasks)
            })
            .await
    }

    /// 打开用户明确指定的目录（GUI 浏览）用于分页枚举。
    pub(crate) async fn browse(
        path: &str,
        tasks: BlockingTasks,
        lease: &ResourceLease,
    ) -> Result<Directory, RemoteError> {
        let requested = path.to_owned();
        let worker = tasks.clone();
        let lease = lease.clone();
        tasks
            .run(move || {
                let display = std::fs::canonicalize(&requested)
                    .map_err(|error| io_error("failed to inspect browsed directory", error))?;
                let metadata = std::fs::metadata(&display)
                    .map_err(|error| io_error("failed to inspect browsed directory", error))?;
                if !metadata.is_dir() {
                    return Err(remote_error(
                        RemoteErrorCode::InvalidRequest,
                        "browse path is not a directory",
                    ));
                }
                let dir = Dir::open_ambient_dir(&display, ambient_authority())
                    .map_err(|error| io_error("failed to browse directory", error))?;
                Directory::new(LeasedFd::new(dir, lease), display, worker)
            })
            .await
    }

    /// 目标项的 lstat 事实；空路径表示 workspace 根本身。
    pub(crate) async fn facts(
        &self,
        path: &str,
        lease: &ResourceLease,
    ) -> Result<FileFacts, RemoteError> {
        if components(path)?.is_empty() {
            return self.root_facts(lease).await;
        }
        self.target(path, lease).await?.facts().await
    }

    /// 取得目标项的 parent 能力与叶子名（路径本身必须已存在）。
    pub(crate) async fn target(
        &self,
        path: &str,
        lease: &ResourceLease,
    ) -> Result<Target, RemoteError> {
        let parts = components(path)?;
        let display = display_path(&self.canonical, &parts);
        let root = self.clone_capability()?;
        let tasks = self.tasks.clone();
        let lease = lease.clone();
        self.tasks
            .run(move || target_in(root, &parts, display, tasks, lease))
            .await
    }

    /// 同上，但创建缺失的父目录（写路径用）。
    pub(crate) async fn ensure_target(
        &self,
        path: &str,
        lease: &ResourceLease,
    ) -> Result<Target, RemoteError> {
        let parts = components(path)?;
        let display = display_path(&self.canonical, &parts);
        let root = self.clone_capability()?;
        let tasks = self.tasks.clone();
        let lease = lease.clone();
        self.tasks
            .run(move || {
                let (parents, leaf) = split_leaf(&parts)?;
                let (root_dir, _root_budget) = root.split();
                let parent = ensure_dir(root_dir, &parents)?;
                Ok(Target {
                    parent: LeasedFd::new(parent, lease),
                    leaf,
                    display,
                    tasks,
                })
            })
            .await
    }

    /// 创建（含缺失父目录）并返回目标目录能力。
    pub(crate) async fn ensure_directory(
        &self,
        path: &str,
        lease: &ResourceLease,
    ) -> Result<LeasedFd<Dir>, RemoteError> {
        let parts = components(path)?;
        let root = self.clone_capability()?;
        let lease = lease.clone();
        self.tasks
            .run(move || {
                // 新建目录句柄与本次操作的预算绑定后交回；root 只是遍历用的短暂能力。
                let (root_dir, _root_budget) = root.split();
                Ok(LeasedFd::new(ensure_dir(root_dir, &parts)?, lease))
            })
            .await
    }

    /// workspace 根本身的事实（相对路径为空时使用）。
    ///
    /// 根能力只携带 workspace 池的 retained 预算，**不能**当作本操作的 metadata 预算：这里把
    /// 本次 operation lease 与根克隆句柄绑定成同一个 owner，并固定「句柄关闭 → retained 归还
    /// → operation 预算归还」的析构次序。调用方取消时 owner 仍随阻塞任务存活，metadata 系统
    /// 调用与它的 FD 都在 operation 预算内结束；结果没有 FD，所以句柄在返回前显式关闭。
    pub(crate) async fn root_facts(&self, lease: &ResourceLease) -> Result<FileFacts, RemoteError> {
        let root = self.clone_capability()?;
        let operation = lease.clone();
        self.tasks
            .run(move || {
                let owner = OperationFd::new(root, operation);
                let metadata = owner
                    .get()
                    .dir_metadata()
                    .map_err(|error| io_error("failed to inspect workspace root", error))?;
                let facts = facts(&metadata);
                // 无 FD 结果：句柄先关闭，operation 预算随后归还，再交出结果。
                drop(owner);
                Ok(facts)
            })
            .await
    }

    fn clone_capability(&self) -> Result<LeasedFd<Dir>, RemoteError> {
        self.root.try_clone()
    }
}

impl fmt::Debug for WorkspaceRoot {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("WorkspaceRoot")
            .field("canonical", &self.canonical)
            .finish_non_exhaustive()
    }
}

/// 一个目标项的 parent 能力、单段叶子名与展示路径。
pub(crate) struct Target {
    /// parent 句柄与本操作的 FD 预算不可分：句柄先关闭、预算后归还。
    parent: LeasedFd<Dir>,
    leaf: OsString,
    display: PathBuf,
    tasks: BlockingTasks,
}

impl Target {
    /// 目标项的 lstat 事实；叶子是符号链接时按既有边界拒绝。
    pub(crate) async fn facts(&self) -> Result<FileFacts, RemoteError> {
        let parent = self.clone_parent()?;
        let leaf = self.leaf.clone();
        self.tasks
            .run(move || {
                // parent 自身持有预算：取消后仍在运行的 stat 继续计费。
                let metadata = parent
                    .get()
                    .symlink_metadata(&leaf)
                    .map_err(|error| walk_error("failed to inspect remote path", &leaf, error))?;
                if metadata.file_type().is_symlink() {
                    return Err(symbolic_link(&leaf));
                }
                Ok(facts(&metadata))
            })
            .await
    }

    /// no-follow 打开只读普通文件句柄。
    pub(crate) async fn open_read(&self) -> Result<LeasedFd<std::fs::File>, RemoteError> {
        let parent = self.clone_parent()?;
        let leaf = self.leaf.clone();
        self.tasks
            .run(move || {
                // 新句柄与本操作的预算绑定后才交回：交接链上的 FD 一直计费。
                let budget = parent.share();
                let file = open_regular(parent.get(), &leaf, RegularAccess::Read)?;
                Ok(LeasedFd::new(file, budget))
            })
            .await
    }

    /// no-follow 打开追加句柄；保留真实的部分追加副作用。
    pub(crate) async fn open_append(&self) -> Result<LeasedFd<std::fs::File>, RemoteError> {
        let parent = self.clone_parent()?;
        let leaf = self.leaf.clone();
        self.tasks
            .run(move || {
                let budget = parent.share();
                let file = open_regular(parent.get(), &leaf, RegularAccess::Append)?;
                Ok(LeasedFd::new(file, budget))
            })
            .await
    }

    /// no-follow 创建/截断普通文件（命令 capture 用）。
    pub(crate) async fn create_regular(&self) -> Result<LeasedFd<std::fs::File>, RemoteError> {
        let parent = self.clone_parent()?;
        let leaf = self.leaf.clone();
        self.tasks
            .run(move || {
                let budget = parent.share();
                let file = open_regular(parent.get(), &leaf, RegularAccess::Create)?;
                Ok(LeasedFd::new(file, budget))
            })
            .await
    }

    pub(crate) async fn remove(self, recursive: bool) -> Result<(), RemoteError> {
        let Self {
            parent,
            leaf,
            tasks,
            ..
        } = self;
        tasks
            .run(move || {
                // parent 持有本操作的预算：取消后仍在运行的删除继续计费。
                let parent = parent.get();
                let metadata = parent.symlink_metadata(&leaf).map_err(|error| {
                    walk_error("failed to inspect removal target", &leaf, error)
                })?;
                if metadata.file_type().is_symlink() {
                    return Err(symbolic_link(&leaf));
                }
                if metadata.is_dir() {
                    if recursive {
                        parent
                            .remove_dir_all(&leaf)
                            .map_err(|error| io_error("failed to remove directory", error))
                    } else {
                        parent
                            .remove_dir(&leaf)
                            .map_err(|error| io_error("failed to remove empty directory", error))
                    }
                } else {
                    parent
                        .remove_file(&leaf)
                        .map_err(|error| io_error("failed to remove file", error))
                }
            })
            .await
    }

    /// 把本目标项改名到另一个目标位置；两者都在各自 parent capability 内定位。
    ///
    /// rename 本身在内核层不会跟随叶子链接，但“链接被当成普通项改名”仍然违反本项目的拒绝
    /// 语义，因此提交边界再次核对源叶子（必须存在且不是链接）与目标叶子（不存在，或不是链接）。
    pub(crate) async fn rename_to(self, target: Target) -> Result<(), RemoteError> {
        let Self {
            parent,
            leaf,
            tasks,
            ..
        } = self;
        let Target {
            parent: target_parent,
            leaf: target_leaf,
            ..
        } = target;
        tasks
            .run(move || {
                // 源与目标的句柄各自持有预算：rename 真实结束前谁也不归还。
                let parent = parent.get();
                let target_parent = target_parent.get();
                let source = parent
                    .symlink_metadata(&leaf)
                    .map_err(|error| walk_error("failed to inspect rename source", &leaf, error))?;
                if source.file_type().is_symlink() {
                    return Err(symbolic_link(&leaf));
                }
                match target_parent.symlink_metadata(&target_leaf) {
                    Ok(metadata) if metadata.file_type().is_symlink() => {
                        return Err(symbolic_link(&target_leaf));
                    }
                    Ok(_) => {}
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(error) => {
                        return Err(walk_error(
                            "failed to inspect rename target",
                            &target_leaf,
                            error,
                        ));
                    }
                }
                parent
                    .rename(&leaf, target_parent, &target_leaf)
                    .map_err(|error| io_error("failed to rename path", error))
            })
            .await
    }

    /// 复制普通文件到另一个目标，保留源权限。
    pub(crate) async fn copy_file_to(self, target: Target) -> Result<(), RemoteError> {
        let Self {
            parent,
            leaf,
            tasks,
            ..
        } = self;
        let Target {
            parent: target_parent,
            leaf: target_leaf,
            ..
        } = target;
        tasks
            .run(move || {
                // 两个 parent 句柄都持有预算：复制期间一直计费。
                copy_regular(parent.get(), &leaf, target_parent.get(), &target_leaf).map(|_| ())
            })
            .await
    }

    /// 拆出 parent capability（自带本操作预算）、叶子名、展示路径与连接 owner，供上传暂存使用。
    pub(crate) fn into_parts(self) -> (LeasedFd<Dir>, OsString, PathBuf, BlockingTasks) {
        (self.parent, self.leaf, self.display, self.tasks)
    }

    fn clone_parent(&self) -> Result<LeasedFd<Dir>, RemoteError> {
        self.parent.try_clone()
    }
}

impl fmt::Debug for Target {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("Target")
            .field("display", &self.display)
            .finish_non_exhaustive()
    }
}

/// 一个已打开目录：分页枚举，不收集整个目录。
pub(crate) struct Directory {
    /// 目录能力与预算不可分；枚举流句柄 `entries` 同样各自带着预算。
    dir: LeasedFd<Dir>,
    display: PathBuf,
    entries: Option<LeasedFd<cap_std::fs::ReadDir>>,
    tasks: BlockingTasks,
}

impl Directory {
    fn new(
        dir: LeasedFd<Dir>,
        display: PathBuf,
        tasks: BlockingTasks,
    ) -> Result<Self, RemoteError> {
        let entries = dir
            .get()
            .entries()
            .map_err(|error| io_error("failed to read directory", error))?;
        // 枚举流是独立句柄：立刻与同一份预算绑定，分页之间也不会脱离计费。
        let entries = LeasedFd::new(entries, dir.share());
        Ok(Self {
            dir,
            display,
            entries: Some(entries),
            tasks,
        })
    }

    pub(crate) fn display(&self) -> &Path {
        &self.display
    }

    /// 读取下一页条目；空页表示已读完。
    pub(crate) async fn page(&mut self) -> Result<Vec<DirectoryEntryFacts>, RemoteError> {
        let Some(entries) = self.entries.take() else {
            return Ok(Vec::new());
        };
        // 符号链接的目录判定需要同一个目录能力；克隆句柄同样绑定本页的预算。
        let dir = self.dir.try_clone()?;
        let (entries, page) = self
            .tasks
            .run(move || {
                let mut entries = entries;
                let mut page = Vec::with_capacity(ENTRY_PAGE);
                for _ in 0..ENTRY_PAGE {
                    let Some(next) = entries.get_mut().next() else {
                        return Ok((None, page));
                    };
                    let entry =
                        next.map_err(|error| io_error("failed to read directory entry", error))?;
                    let name = entry.file_name();
                    let file_type = entry
                        .file_type()
                        .map_err(|error| io_error("failed to inspect directory entry", error))?;
                    let is_symlink = file_type.is_symlink();
                    // 符号链接本身按 entry 事实发布；只有目录判定需要目标类型。
                    let is_directory = if is_symlink {
                        dir.get()
                            .metadata(&name)
                            .is_ok_and(|metadata| metadata.is_dir())
                    } else {
                        file_type.is_dir()
                    };
                    page.push(DirectoryEntryFacts {
                        name,
                        is_directory,
                        is_symlink,
                    });
                }
                Ok((Some(entries), page))
            })
            .await?;
        self.entries = entries;
        Ok(page)
    }

    /// 递归复制到目标目录能力；遇到任何符号链接立即拒绝。
    ///
    /// 只在遍历深度上持有能力（每层一个源 Dir、一个目标 Dir 与其迭代器），不按目录扇出
    /// 打开全部子目录，也没有全目录条目数硬顶。
    pub(crate) async fn copy_tree_to(self, target: LeasedFd<Dir>) -> Result<(), RemoteError> {
        let Directory { dir, tasks, .. } = self;
        tasks
            .run(move || {
                // 递归复制整段期间持有独占的 operation 预算：句柄被 `copy_tree` 消费并在其中
                // 关闭，预算作为具名局部变量活到同一作用域结束，因此关闭先于归还。
                let (source, _source_budget) = dir.split();
                let (target, _target_budget) = target.split();
                copy_tree(source, target)
            })
            .await
    }
}

/// 目录条目事实；路径拼接与展示语义由调用方决定。
pub(crate) struct DirectoryEntryFacts {
    pub(crate) name: OsString,
    pub(crate) is_directory: bool,
    pub(crate) is_symlink: bool,
}

/// 单个文件的事实（与 wire 上的 `RemoteFileStat` 解耦）。
pub(crate) struct FileFacts {
    pub(crate) is_file: bool,
    pub(crate) is_directory: bool,
    pub(crate) len: u64,
    pub(crate) readonly: bool,
    pub(crate) modified_at: Option<i64>,
}

/// workspace id 到已打开 workspace 能力的登记表；`close` 后 id 立即不可再用。
#[derive(Debug, Default)]
pub(crate) struct WorkspaceRegistry {
    entries: Mutex<Entries>,
}

#[derive(Debug, Default)]
struct Entries {
    roots: HashMap<String, Arc<WorkspaceRoot>>,
    next_id: u64,
}

impl WorkspaceRegistry {
    pub(crate) fn new() -> Self {
        Self::default()
    }

    /// 打开并登记一个 workspace；返回的 claim 在 commit 之前持有撤销责任。
    pub(crate) async fn open(
        &self,
        path: &str,
        tasks: BlockingTasks,
        leases: WorkspaceLeases,
    ) -> Result<PendingWorkspace<'_>, RemoteError> {
        let root = Arc::new(WorkspaceRoot::open(path, tasks, leases).await?);
        let mut entries = self.entries();
        let next_id = entries.next_id.checked_add(1).ok_or_else(|| {
            remote_error(
                RemoteErrorCode::Io,
                "remote workspace identity space is exhausted",
            )
        })?;
        entries.next_id = next_id;
        let workspace_id = format!("workspace-{next_id}");
        entries.roots.insert(workspace_id.clone(), root.clone());
        Ok(PendingWorkspace {
            registry: self,
            workspace_id,
            root,
            committed: false,
        })
    }

    pub(crate) fn lease(&self, workspace_id: &str) -> Result<Arc<WorkspaceRoot>, RemoteError> {
        self.entries()
            .roots
            .get(workspace_id)
            .cloned()
            .ok_or_else(|| unknown_workspace(workspace_id))
    }

    pub(crate) fn close(&self, workspace_id: &str) -> Result<(), RemoteError> {
        self.entries()
            .roots
            .remove(workspace_id)
            .map(|_| ())
            .ok_or_else(|| unknown_workspace(workspace_id))
    }

    /// 撤销一次尚未交付的登记：client 没拿到 id 就没有其他 close 路径。
    fn withdraw(&self, workspace_id: &str) {
        self.entries().roots.remove(workspace_id);
    }

    fn entries(&self) -> MutexGuard<'_, Entries> {
        self.entries.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// 已登记、尚未交付给 client 的 workspace 身份；登记即由本 guard 持有撤销责任。
///
/// `WorkspaceOpened` 响应完整发布后才 [`PendingWorkspace::commit`]，把关闭责任交给 client
/// （T3 在它自己的 owner 里裁决取消与 close）。在那之前任何 `?`、提前返回或取消都会撤销登记，
/// 因此 client 没拿到 id 时不会留下只能等连接结束才能回收的登记；已取得 `Arc<WorkspaceRoot>`
/// 的在途操作仍按自己的持有时长完成。
pub(crate) struct PendingWorkspace<'a> {
    registry: &'a WorkspaceRegistry,
    workspace_id: String,
    root: Arc<WorkspaceRoot>,
    committed: bool,
}

impl PendingWorkspace<'_> {
    pub(crate) fn workspace_id(&self) -> &str {
        &self.workspace_id
    }

    pub(crate) fn root(&self) -> &WorkspaceRoot {
        self.root.as_ref()
    }

    /// 响应已完整发出（协议交付线）：交出关闭责任。
    pub(crate) fn commit(mut self) {
        self.committed = true;
    }
}

impl Drop for PendingWorkspace<'_> {
    fn drop(&mut self) {
        if !self.committed {
            self.registry.withdraw(&self.workspace_id);
        }
    }
}

/// 把 workspace-relative POSIX 路径拆成经过校验的单段组件。
fn components(path: &str) -> Result<Vec<OsString>, RemoteError> {
    let mut parts = Vec::new();
    for component in Path::new(path).components() {
        match component {
            Component::CurDir => {}
            Component::Normal(value) => parts.push(value.to_os_string()),
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(remote_error(
                    RemoteErrorCode::WorkspaceEscape,
                    format!("path '{path}' escapes the workspace"),
                ));
            }
        }
    }
    Ok(parts)
}

fn display_path(canonical: &Path, parts: &[OsString]) -> PathBuf {
    let mut display = canonical.to_path_buf();
    for part in parts {
        display.push(part);
    }
    display
}

fn split_leaf(parts: &[OsString]) -> Result<(Vec<OsString>, OsString), RemoteError> {
    let Some((leaf, parents)) = parts.split_last() else {
        return Err(remote_error(
            RemoteErrorCode::InvalidRequest,
            "path names the workspace root",
        ));
    };
    Ok((parents.to_vec(), leaf.clone()))
}

fn open_dir(mut dir: Dir, parts: &[OsString]) -> Result<Dir, RemoteError> {
    for component in parts {
        dir = dir
            .open_dir_nofollow(component)
            .map_err(|error| walk_error("failed to resolve remote path", component, error))?;
    }
    Ok(dir)
}

fn target_in(
    root: LeasedFd<Dir>,
    parts: &[OsString],
    display: PathBuf,
    tasks: BlockingTasks,
    lease: ResourceLease,
) -> Result<Target, RemoteError> {
    let (parents, leaf) = split_leaf(parts)?;
    // root 只是遍历用的短暂能力；交回的 parent 句柄与本次操作的预算绑定。
    let (root_dir, _root_budget) = root.split();
    Ok(Target {
        parent: LeasedFd::new(open_dir(root_dir, &parents)?, lease),
        leaf,
        display,
        tasks,
    })
}

fn ensure_dir(mut dir: Dir, parts: &[OsString]) -> Result<Dir, RemoteError> {
    for component in parts {
        dir = match dir.open_dir_nofollow(component) {
            Ok(next) => next,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                dir.create_dir(component)
                    .map_err(|error| io_error("failed to create directory", error))?;
                dir.open_dir_nofollow(component).map_err(|error| {
                    walk_error("failed to resolve created directory", component, error)
                })?
            }
            Err(error) => {
                return Err(walk_error(
                    "failed to resolve remote path",
                    component,
                    error,
                ));
            }
        };
    }
    Ok(dir)
}

enum RegularAccess {
    Read,
    Append,
    Create,
}

/// no-follow + `O_NONBLOCK` 打开并验证普通文件；特殊文件不会占住工作线程。
fn open_regular(
    parent: &Dir,
    leaf: &OsString,
    access: RegularAccess,
) -> Result<std::fs::File, RemoteError> {
    let mut options = OpenOptions::new();
    match access {
        RegularAccess::Read => {
            options.read(true);
        }
        RegularAccess::Append => {
            options.write(true).append(true).create(true);
        }
        RegularAccess::Create => {
            options.write(true).create(true).truncate(false);
        }
    }
    options.follow(FollowSymlinks::No);
    options.custom_flags(libc::O_NONBLOCK);
    let file = parent
        .open_with(leaf, &options)
        .map_err(|error| walk_error("failed to open regular file", leaf, error))?;
    let metadata = file
        .metadata()
        .map_err(|error| io_error("failed to inspect opened file", error))?;
    if !metadata.is_file() {
        return Err(remote_error(
            RemoteErrorCode::InvalidRequest,
            "path is not a regular file",
        ));
    }
    if matches!(access, RegularAccess::Create) {
        // 先确认实际句柄是普通文件，再截断已有内容。
        file.set_len(0)
            .map_err(|error| io_error("failed to truncate file", error))?;
    }
    Ok(file.into_std())
}

fn copy_regular(
    source: &Dir,
    source_leaf: &OsString,
    target: &Dir,
    target_leaf: &OsString,
) -> Result<u64, RemoteError> {
    let mut input = open_regular(source, source_leaf, RegularAccess::Read)?;
    let permissions = input
        .metadata()
        .map_err(|error| io_error("failed to inspect copy source", error))?
        .permissions();
    let mut options = OpenOptions::new();
    options.write(true).create(true).truncate(false);
    options.follow(FollowSymlinks::No);
    options.custom_flags(libc::O_NONBLOCK);
    let mut output = target
        .open_with(target_leaf, &options)
        .map_err(|error| walk_error("failed to create copy target", target_leaf, error))?
        .into_std();
    let output_metadata = output
        .metadata()
        .map_err(|error| io_error("failed to inspect copy target", error))?;
    if !output_metadata.is_file() {
        return Err(remote_error(
            RemoteErrorCode::InvalidRequest,
            "copy target is not a regular file",
        ));
    }
    output
        .set_len(0)
        .map_err(|error| io_error("failed to truncate copy target", error))?;
    output
        .set_permissions(permissions)
        .map_err(|error| io_error("failed to preserve copy permissions", error))?;
    io::copy(&mut input, &mut output).map_err(|error| io_error("failed to copy file", error))
}

/// 一层目录的遍历状态：源/目标能力与它们的条目迭代器。
struct CopyFrame {
    source: Dir,
    target: Dir,
    entries: cap_std::fs::ReadDir,
}

/// 深度优先复制：只在遍历深度上持有能力，不按扇出打开全部子目录。
fn copy_tree(source: Dir, target: Dir) -> Result<(), RemoteError> {
    let mut stack = vec![CopyFrame {
        entries: source
            .entries()
            .map_err(|error| io_error("failed to read copied directory", error))?,
        source,
        target,
    }];
    while !stack.is_empty() {
        let index = stack.len() - 1;
        let next = stack[index]
            .entries
            .next()
            .transpose()
            .map_err(|error| io_error("failed to read copied entry", error))?;
        let Some(entry) = next else {
            stack.pop();
            continue;
        };
        let name = entry.file_name();
        let file_type = entry
            .file_type()
            .map_err(|error| io_error("failed to inspect copied entry", error))?;
        if file_type.is_symlink() {
            return Err(remote_error(
                RemoteErrorCode::WorkspaceEscape,
                "copying symbolic links is not allowed",
            ));
        }
        let frame = &stack[index];
        if file_type.is_dir() {
            match frame.target.create_dir(&name) {
                Ok(()) => {}
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
                Err(error) => {
                    return Err(io_error("failed to create copied directory", error));
                }
            }
            let child_source = frame
                .source
                .open_dir_nofollow(&name)
                .map_err(|error| walk_error("failed to read copied directory", &name, error))?;
            let child_target = frame
                .target
                .open_dir_nofollow(&name)
                .map_err(|error| walk_error("failed to open copied directory", &name, error))?;
            let entries = child_source
                .entries()
                .map_err(|error| io_error("failed to read copied directory", error))?;
            stack.push(CopyFrame {
                source: child_source,
                target: child_target,
                entries,
            });
        } else if file_type.is_file() {
            copy_regular(&frame.source, &name, &frame.target, &name)?;
        }
    }
    Ok(())
}

fn facts(metadata: &Metadata) -> FileFacts {
    FileFacts {
        is_file: metadata.is_file(),
        is_directory: metadata.is_dir(),
        len: metadata.len(),
        // 与 std 的 readonly 语义一致：任何写位存在即可写。
        readonly: metadata.permissions().mode() & 0o222 == 0,
        modified_at: metadata
            .modified()
            .ok()
            .map(cap_std::time::SystemTime::into_std)
            .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
            .and_then(|duration| i64::try_from(duration.as_secs()).ok()),
    }
}

fn walk_error(context: &'static str, component: &OsString, error: io::Error) -> RemoteError {
    if error.raw_os_error() == Some(libc::ELOOP) {
        symbolic_link(component)
    } else {
        io_error(context, error)
    }
}

pub(crate) fn symbolic_link(component: &OsString) -> RemoteError {
    remote_error(
        RemoteErrorCode::WorkspaceEscape,
        format!(
            "symbolic link entry '{}' is not allowed",
            component.to_string_lossy()
        ),
    )
}

fn unknown_workspace(workspace_id: &str) -> RemoteError {
    remote_error(
        RemoteErrorCode::WorkspaceNotFound,
        format!("unknown workspace id '{workspace_id}'"),
    )
}

pub(crate) fn remote_error(code: RemoteErrorCode, message: impl Into<String>) -> RemoteError {
    RemoteError {
        code,
        message: message.into(),
    }
}

pub(crate) fn io_error(operation: &str, error: io::Error) -> RemoteError {
    let code = if error.kind() == io::ErrorKind::NotFound {
        RemoteErrorCode::PathNotFound
    } else {
        RemoteErrorCode::Io
    };
    remote_error(code, format!("{operation}: {error}"))
}
