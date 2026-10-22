//! 每个物理 helper 的 FD 资源准入（v1.6）。
//!
//! 这里只做两件事：启动期用成熟 procfs 测量本机 nofile 与真实 baseline 并派生两个互不挪用
//! 的 [`tokio::sync::Semaphore`] 池；运行期按请求类别整份 `try_acquire_many_owned` 准入。
//!
//! 预算来源（见 interface contract §12.3）：
//! `F = representable_soft - baseline - 维护预留2`，
//! `workspace = min(511, floor(F * workspace_open / (workspace_open + spawn)))`，
//! `operation = F - workspace`。两个池都必须能装下最小需求，否则启动明确失败、不发布 Hello。
//! 维护预留只覆盖 procfs 探测自身的头寸（`Process` 的 O_PATH 句柄与 limits/FD 目录句柄）；
//! 业务清理都发生在已计费的 lease 内，因此不额外预留、也不改变既有 drain 语义。
//!
//! baseline 直接使用 `fd_count()` 的测量值，不扣除探测自身的 1-2 个句柄：允许保守多计，
//! 不从估算减回。任何测量失败都返回明确的 [`ServerError`]，不做猜测性 fallback。

use std::sync::Arc;

use pl_protocol::remote::{
    RemoteError, RemoteErrorCode, RemoteRequest, RemoteResourceClass, RemoteResourceCosts,
    RemoteResourceLimits,
};
use tokio::sync::{OwnedSemaphorePermit, Semaphore};

use super::path::remote_error;
use crate::ServerError;

/// helper 唯一声明的普通操作 FD 成本（保守峰值上界；consumer 不得复制这些常量）。
const WORKSPACE_OPEN: u32 = 3;
const WORKSPACE_RETAINED: u32 = 1;
const METADATA: u32 = 4;
const DIRECTORY: u32 = 3;
const READ_FILE: u32 = 3;
const WRITE_FILE: u32 = 4;
const COPY_FILE: u32 = 5;
const SPAWN: u32 = 15;

/// workspace 池的表示上限来自流预算（连接级并发上限），不是业务会话数常量。
const WORKSPACE_SLOTS: u64 = 511;
/// procfs 探测头寸：`Process` 的 O_PATH 句柄与 limits / FD 目录的短时句柄。
const MAINTENANCE_RESERVE: u64 = 2;

/// 连接级 FD 资源：两个互不挪用的池与 helper 声明的成本。
pub(super) struct Resources {
    workspace: Arc<Semaphore>,
    operation: Arc<Semaphore>,
    limits: RemoteResourceLimits,
}

impl Resources {
    /// 启动期测量本机 nofile 与真实 baseline，并派生两个池。
    pub(super) fn measure() -> Result<Self, ServerError> {
        let process = procfs::process::Process::myself()
            .map_err(|error| measurement_failure("read /proc/self", error))?;
        let limits = process
            .limits()
            .map_err(|error| measurement_failure("read process descriptor limits", error))?;
        let baseline = process
            .fd_count()
            .map_err(|error| measurement_failure("count own descriptors", error))?;
        // 探测句柄随 Process 释放；baseline 保留其保守多计。
        drop(process);
        let soft = match limits.max_open_files.soft_limit {
            // OS 明确报告 unlimited：这是表示范围上限，不改 OS 限额。
            procfs::process::LimitValue::Unlimited => u64::MAX,
            procfs::process::LimitValue::Value(value) => value,
        };
        Self::from_measurement(soft, baseline as u64)
    }

    fn from_measurement(soft: u64, baseline: u64) -> Result<Self, ServerError> {
        let representable = soft
            .min(Semaphore::MAX_PERMITS as u64)
            .min(u64::from(u32::MAX));
        let available = representable
            .checked_sub(baseline)
            .and_then(|remaining| remaining.checked_sub(MAINTENANCE_RESERVE))
            .ok_or_else(|| {
                startup_failure(format!(
                    "remote helper descriptor limit is too small: soft={soft} baseline={baseline} \
                     maintenance reserve={MAINTENANCE_RESERVE}"
                ))
            })?;
        let workspace = (available * u64::from(WORKSPACE_OPEN)
            / (u64::from(WORKSPACE_OPEN) + u64::from(SPAWN)))
        .min(WORKSPACE_SLOTS);
        let operation = available - workspace;
        // 两个池都必须装下最小需求，成本必须是正数；否则不发布 Hello。
        if workspace < u64::from(WORKSPACE_OPEN)
            || operation < u64::from(SPAWN)
            || WORKSPACE_RETAINED == 0
            || WORKSPACE_RETAINED > WORKSPACE_OPEN
        {
            return Err(startup_failure(format!(
                "remote helper descriptor budget cannot admit one workspace open and one spawn: \
                 available={available} workspace={workspace} operation={operation}"
            )));
        }
        let workspace_fds = u32::try_from(workspace).map_err(|_| {
            startup_failure(format!(
                "workspace descriptor budget does not fit u32: {workspace}"
            ))
        })?;
        let operation_fds = u32::try_from(operation).map_err(|_| {
            startup_failure(format!(
                "operation descriptor budget does not fit u32: {operation}"
            ))
        })?;
        let costs = RemoteResourceCosts {
            workspace_open: WORKSPACE_OPEN,
            workspace_retained: WORKSPACE_RETAINED,
            metadata: METADATA,
            directory: DIRECTORY,
            read_file: READ_FILE,
            write_file: WRITE_FILE,
            copy_file: COPY_FILE,
            spawn: SPAWN,
        };
        if costs.spawn > operation_fds
            || costs.metadata > operation_fds
            || costs.directory > operation_fds
            || costs.read_file > operation_fds
            || costs.write_file > operation_fds
            || costs.copy_file > operation_fds
            || costs.workspace_open > workspace_fds
        {
            return Err(startup_failure(format!(
                "remote helper descriptor pools cannot cover advertised costs: \
                 operation={operation_fds} workspace={workspace_fds}"
            )));
        }
        Ok(Self {
            workspace: Arc::new(Semaphore::new(workspace_fds as usize)),
            operation: Arc::new(Semaphore::new(operation_fds as usize)),
            limits: RemoteResourceLimits {
                operation_fds,
                workspace_fds,
                costs,
            },
        })
    }

    /// 发布在 `Hello.resources` 的预算；consumer 只消费，不复制成本常量。
    pub(super) fn limits(&self) -> RemoteResourceLimits {
        self.limits
    }

    /// 收到完整请求后立刻按类别整份准入；不够就是该操作的 typed 错误，不进入等待。
    ///
    /// Control 类不占业务预算（控制面本身不打开 FD）。
    pub(super) fn admit(&self, request: &RemoteRequest) -> Result<Grants, RemoteError> {
        match request.resource_class() {
            RemoteResourceClass::Control => Ok(Grants::None),
            RemoteResourceClass::OpenWorkspace => self.try_workspace().map(Grants::Workspace),
            class => self.try_operation(class).map(Grants::Operation),
        }
    }

    fn try_operation(&self, class: RemoteResourceClass) -> Result<ResourceLease, RemoteError> {
        let permits = self.permits_of(class);
        let permit = self
            .operation
            .clone()
            .try_acquire_many_owned(permits)
            .map_err(|_| exhausted(class))?;
        Ok(ResourceLease::new(permit))
    }

    fn try_workspace(&self) -> Result<WorkspaceLeases, RemoteError> {
        let permit = self
            .workspace
            .clone()
            .try_acquire_many_owned(self.limits.costs.workspace_open)
            .map_err(|_| exhausted(RemoteResourceClass::OpenWorkspace))?;
        Ok(WorkspaceLeases {
            permit,
            retained: self.limits.costs.workspace_retained,
        })
    }

    fn permits_of(&self, class: RemoteResourceClass) -> u32 {
        match class {
            RemoteResourceClass::Control => 0,
            RemoteResourceClass::OpenWorkspace => self.limits.costs.workspace_open,
            RemoteResourceClass::Metadata => self.limits.costs.metadata,
            RemoteResourceClass::Directory => self.limits.costs.directory,
            RemoteResourceClass::ReadFile => self.limits.costs.read_file,
            RemoteResourceClass::WriteFile => self.limits.costs.write_file,
            RemoteResourceClass::CopyFile => self.limits.costs.copy_file,
            // 递归操作独占整个 operation 池：仍用成熟 cap 递归/DFS，不新增深度业务限额。
            RemoteResourceClass::Recursive => self.limits.operation_fds,
            RemoteResourceClass::Spawn => self.limits.costs.spawn,
        }
    }
}

/// 一条操作已经准入的预算。
pub(super) enum Grants {
    /// 控制类请求不占业务预算。
    None,
    /// 普通操作的整份 operation 预算。
    Operation(ResourceLease),
    /// `OpenWorkspace` 的 workspace 池 open 峰值。
    Workspace(WorkspaceLeases),
}

impl Grants {
    /// 取普通操作的 lease：准入与分类都由同一个 `resource_class()` 推导，不会不匹配。
    pub(super) fn expect_operation(self) -> Result<ResourceLease, RemoteError> {
        match self {
            Self::Operation(lease) => Ok(lease),
            Self::None | Self::Workspace(_) => Err(grant_mismatch()),
        }
    }

    /// 取 `OpenWorkspace` 的 workspace 预算。
    pub(super) fn expect_workspace(self) -> Result<WorkspaceLeases, RemoteError> {
        match self {
            Self::Workspace(leases) => Ok(leases),
            Self::None | Self::Operation(_) => Err(grant_mismatch()),
        }
    }
}

/// 一条操作持有的 FD 预算。
///
/// `Arc` 克隆共享**同一个** owned permit，因此把 lease 放进真正持 FD 的对象（`Target`、
/// `Directory`、`StagedUpload`、进程 `Job`）以及 blocking/retire 闭包时不会重复计费；只有最后
/// 一个持有者释放才归还预算。取消/连接 abort 只会丢掉「等结果的权利」，仍在运行的 syscall 与
/// 暂存清理由它们的 lease 继续计费。
#[derive(Clone)]
pub(super) struct ResourceLease {
    /// 只为 Drop 语义而持有：最后一个克隆释放时归还预算，本身不需要被读取。
    _permit: Arc<OwnedSemaphorePermit>,
}

impl ResourceLease {
    fn new(permit: OwnedSemaphorePermit) -> Self {
        Self {
            _permit: Arc::new(permit),
        }
    }
}

/// `OpenWorkspace` 的整份 workspace 预算；打开期间一直在手。
pub(super) struct WorkspaceLeases {
    permit: OwnedSemaphorePermit,
    retained: u32,
}

impl WorkspaceLeases {
    /// 拆成「跟 `WorkspaceRoot` 走的持久 retained」与「打开阶段结束即归还的瞬时余量」。
    pub(super) fn split(mut self) -> Result<(ResourceLease, ResourceLease), RemoteError> {
        let retained = self
            .permit
            .split(self.retained as usize)
            .ok_or_else(grant_mismatch)?;
        Ok((
            ResourceLease::new(retained),
            ResourceLease::new(self.permit),
        ))
    }
}

fn exhausted(class: RemoteResourceClass) -> RemoteError {
    remote_error(
        RemoteErrorCode::ResourceExhausted,
        format!("physical helper descriptor budget cannot admit {class:?}"),
    )
}

fn grant_mismatch() -> RemoteError {
    remote_error(
        RemoteErrorCode::Io,
        "resource grant does not match the request class",
    )
}

fn measurement_failure(operation: &str, error: impl std::fmt::Display) -> ServerError {
    ServerError::Io(std::io::Error::other(format!(
        "remote helper resource measurement failed to {operation}: {error}"
    )))
}

fn startup_failure(message: String) -> ServerError {
    ServerError::Io(std::io::Error::other(message))
}
