//! 单物理 helper 的文件描述符准入，与复用器的物理流预算相互独立。
//!
//! helper 在 hello 中公布该物理进程的 workspace、operation 两个 FD 预算以及每类请求的峰值成本；
//! 本模块只把它们变成两个真实 semaphore，并在发送请求前整份预留。成本数值不在这里复制，
//! 也不把不同物理连接的预算当作平台身份的一部分：每个连接都有自己的两池。
//!
//! 普通请求的峰值覆盖启动中间句柄、capture、阻塞工作、发布与取消后的清理，因此租约跟随真正
//! 持有 FD 的对象（操作流、文件/目录 reader、进程 owner）直到本地收尾；workspace 根能力的
//! 持久份额在打开成功后从同一份预留里拆出，跟随活跃句柄直到确认释放或连接终态。

use std::sync::Arc;

use pl_protocol::remote::{RemoteResourceClass, RemoteResourceCosts, RemoteResourceLimits};
use tokio::sync::{OwnedSemaphorePermit, Semaphore};

/// Outcome of one non-blocking descriptor admission attempt.
#[derive(Debug)]
pub(in crate::remote) enum FdAdmission {
    /// The whole descriptor peak of this class is reserved.
    Granted(FdLease),
    /// Every descriptor of this class is in use on this helper.
    Exhausted,
    /// The pool was closed by admission sealing; nothing may start any more.
    Closed,
}

/// Outcome of one cancellable descriptor admission wait.
pub(in crate::remote) enum FdAcquire {
    Granted(FdLease),
    /// The connection stopped admitting descriptors while this waiter was queued.
    Closed,
}

/// The whole descriptor peak of one request on its physical helper.
///
/// Dropping the lease returns exactly what it holds, so a cancelled or failed next step can never
/// leave a half reservation behind.
#[derive(Debug)]
pub(in crate::remote) struct FdLease {
    class: RemoteResourceClass,
    /// Ordinary-operation descriptors: files, directories, processes and recursive work.
    operation: Option<OwnedSemaphorePermit>,
    /// Workspace-root descriptors, charged only by `openWorkspace`.
    workspace: Option<OwnedSemaphorePermit>,
}

impl FdLease {
    /// The class this lease was granted for; a request of another class must not use it.
    pub(in crate::remote) fn class(&self) -> RemoteResourceClass {
        self.class
    }

    /// Descriptors this lease holds from each pool: `(operation, workspace)`.
    ///
    /// Only used for admission diagnostics; the permit objects themselves are the real charge.
    pub(in crate::remote) fn permits(&self) -> (usize, usize) {
        (
            self.operation
                .as_ref()
                .map_or(0, OwnedSemaphorePermit::num_permits),
            self.workspace
                .as_ref()
                .map_or(0, OwnedSemaphorePermit::num_permits),
        )
    }

    /// Splits the persistent workspace-root charge out of a granted `openWorkspace` lease.
    ///
    /// The returned permit belongs to the active root handle; the returned lease keeps the rest of
    /// the open peak, which its owner releases as soon as the open phase really ended.
    pub(in crate::remote) fn into_workspace_root(
        mut self,
        retained: u32,
    ) -> (Option<OwnedSemaphorePermit>, Self) {
        let share = self
            .workspace
            .as_mut()
            .and_then(|permit| permit.split(retained as usize));
        (share, self)
    }
}

/// Persistent descriptor charge of one active remote workspace root.
///
/// The charge belongs to the opaque handle rather than to one caller: every real user shares it
/// through an `Arc`, so a second open of the same handle never charges twice and the permits return
/// only after the helper confirmed the release or the whole connection ended.
#[derive(Debug)]
pub(in crate::remote) struct WorkspaceRetained {
    id: String,
    permit: OwnedSemaphorePermit,
}

impl WorkspaceRetained {
    pub(in crate::remote) fn new(id: String, permit: OwnedSemaphorePermit) -> Self {
        Self { id, permit }
    }

    /// The opaque helper handle this charge belongs to.
    pub(in crate::remote) fn id(&self) -> &str {
        &self.id
    }

    /// Descriptors this root still charges on its helper.
    pub(in crate::remote) fn permits(&self) -> usize {
        self.permit.num_permits()
    }
}

/// Both descriptor pools of one physical helper plus the peaks the helper advertised.
#[derive(Debug)]
pub(in crate::remote) struct FdBudget {
    limits: RemoteResourceLimits,
    operation: Arc<Semaphore>,
    workspace: Arc<Semaphore>,
}

impl FdBudget {
    /// Validates the advertised budget and builds the two descriptor pools.
    ///
    /// A budget that cannot hold its own advertised peaks is a handshake failure, not a reason to
    /// guess a smaller cost: the helper is the only authority for these numbers.
    pub(in crate::remote) fn new(limits: RemoteResourceLimits) -> Result<Self, String> {
        let representable = Semaphore::MAX_PERMITS;
        let operation = limits.operation_fds as usize;
        let workspace = limits.workspace_fds as usize;
        if operation == 0 || operation > representable {
            return Err(format!(
                "helper advertised {operation} operation descriptors, which is outside 1..={representable}"
            ));
        }
        if workspace == 0 || workspace > representable {
            return Err(format!(
                "helper advertised {workspace} workspace descriptors, which is outside 1..={representable}"
            ));
        }
        let RemoteResourceCosts {
            workspace_open,
            workspace_retained,
            metadata,
            directory,
            read_file,
            write_file,
            copy_file,
            spawn,
        } = limits.costs;
        let advertised = [
            ("workspace open", workspace_open),
            ("workspace retained", workspace_retained),
            ("metadata", metadata),
            ("directory", directory),
            ("read file", read_file),
            ("write file", write_file),
            ("copy file", copy_file),
            ("spawn", spawn),
        ];
        if let Some((class, _)) = advertised.iter().copied().find(|(_, cost)| *cost == 0) {
            return Err(format!(
                "helper advertised the {class} descriptor cost as zero"
            ));
        }
        if workspace_retained > workspace_open || workspace_open as usize > workspace {
            return Err(format!(
                "helper workspace descriptors {workspace} cannot hold a retained root of {workspace_retained} and an open peak of {workspace_open}"
            ));
        }
        let ordinary = [
            ("metadata", metadata),
            ("directory", directory),
            ("read file", read_file),
            ("write file", write_file),
            ("copy file", copy_file),
            ("spawn", spawn),
        ];
        if let Some((class, cost)) = ordinary
            .iter()
            .copied()
            .find(|(_, cost)| *cost as usize > operation)
        {
            return Err(format!(
                "helper operation descriptors {operation} cannot hold a {class} operation peak of {cost}"
            ));
        }
        Ok(Self {
            limits,
            operation: Arc::new(Semaphore::new(operation)),
            workspace: Arc::new(Semaphore::new(workspace)),
        })
    }

    /// The peaks this helper advertised; consumers never keep their own copy.
    pub(in crate::remote) fn limits(&self) -> RemoteResourceLimits {
        self.limits
    }

    /// Descriptor peak of one class on this helper; `None` means the class has no descriptor budget.
    ///
    /// `Recursive` takes the whole operation budget, so a recursive copy or remove never competes with
    /// an unrelated upload, process or unfinished cleanup on the same helper.
    fn cost(&self, class: RemoteResourceClass) -> Option<u32> {
        let costs = self.limits.costs;
        match class {
            RemoteResourceClass::Control => None,
            RemoteResourceClass::OpenWorkspace => Some(costs.workspace_open),
            RemoteResourceClass::Metadata => Some(costs.metadata),
            RemoteResourceClass::Directory => Some(costs.directory),
            RemoteResourceClass::ReadFile => Some(costs.read_file),
            RemoteResourceClass::WriteFile => Some(costs.write_file),
            RemoteResourceClass::CopyFile => Some(costs.copy_file),
            RemoteResourceClass::Recursive => Some(self.limits.operation_fds),
            RemoteResourceClass::Spawn => Some(costs.spawn),
        }
    }

    /// The pool a class is charged against: workspace roots have their own budget.
    fn pool(&self, class: RemoteResourceClass) -> &Arc<Semaphore> {
        match class {
            RemoteResourceClass::OpenWorkspace => &self.workspace,
            _ => &self.operation,
        }
    }

    /// Takes the whole peak of `class` without waiting.
    pub(in crate::remote) fn try_lease(&self, class: RemoteResourceClass) -> FdAdmission {
        let Some(cost) = self.cost(class) else {
            // `Control` never takes a business budget; a caller that asks for one has a defect.
            return FdAdmission::Closed;
        };
        // Tokio's owned acquisition consumes one `Arc` of the pool, so the budget itself keeps its own.
        let permit = match Arc::clone(self.pool(class)).try_acquire_many_owned(cost) {
            Ok(permit) => permit,
            Err(tokio::sync::TryAcquireError::NoPermits) => return FdAdmission::Exhausted,
            Err(tokio::sync::TryAcquireError::Closed) => return FdAdmission::Closed,
        };
        FdAdmission::Granted(Self::grants(class, permit))
    }

    /// Waits for the whole peak of `class`; the wait ends when the pool is closed.
    ///
    /// Tokio's owned acquisition is cancel safe, so a cancelled waiter returns every descriptor it was
    /// still queued for instead of leaving the budget partially held.
    pub(in crate::remote) async fn acquire(&self, class: RemoteResourceClass) -> FdAcquire {
        let Some(cost) = self.cost(class) else {
            return FdAcquire::Closed;
        };
        match Arc::clone(self.pool(class)).acquire_many_owned(cost).await {
            Ok(permit) => FdAcquire::Granted(Self::grants(class, permit)),
            Err(_) => FdAcquire::Closed,
        }
    }

    /// Stops both pools and wakes every waiter with the real closed state.
    pub(in crate::remote) fn close(&self) {
        self.operation.close();
        self.workspace.close();
    }

    /// Whether `class` is charged against the workspace pool.
    fn is_workspace(class: RemoteResourceClass) -> bool {
        matches!(class, RemoteResourceClass::OpenWorkspace)
    }

    fn grants(class: RemoteResourceClass, permit: OwnedSemaphorePermit) -> FdLease {
        if Self::is_workspace(class) {
            FdLease {
                class,
                operation: None,
                workspace: Some(permit),
            }
        } else {
            FdLease {
                class,
                operation: Some(permit),
                workspace: None,
            }
        }
    }
}
