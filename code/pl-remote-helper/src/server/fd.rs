//! FD 与 FD 预算的绑定所有权。
//!
//! 阻塞调用由连接的 [`super::tasks::BlockingTasks`] 真实 join，再通过 oneshot 把结果交回
//! 调用方。调用方取消时结果仍可能活在这条交接链上（`JoinHandle`、oneshot、被丢弃的错误
//! payload）。如果闭包只在自己作用域内持有 lease 并返回裸句柄，那么从闭包返回到结果析构
//! 之间句柄仍然打开却已经不计费，准入就会低估实际 FD 占用。
//!
//! 因此所有带 FD 的阻塞结果都用 [`LeasedFd`] 表达：真实句柄与同一份
//! [`super::resources::ResourceLease`] 是**同一个对象**，整份在闭包 → `JoinHandle` → oneshot
//! → 调用方/取消析构之间移交。`fd` 字段声明在 `lease` 之前，析构顺序因此固定为「先关闭
//! 句柄、再归还预算」，与结果在何处被析构无关。
//!
//! 解包（[`LeasedFd::split`]）只用于同步移交给**继续持有预算**的接收者，例如把目录句柄换成
//! std 文件句柄、或把 parent 能力移进上传暂存区；不产生脱离预算的裸句柄。

use cap_std::fs::Dir;
use pl_protocol::remote::RemoteError;

use super::path::io_error;
use super::resources::ResourceLease;

pub(super) struct LeasedFd<T> {
    /// 真实句柄必须先于预算析构。
    fd: T,
    lease: ResourceLease,
}

impl<T> LeasedFd<T> {
    pub(super) fn new(fd: T, lease: ResourceLease) -> Self {
        Self { fd, lease }
    }

    /// 只读借用真实句柄：句柄仍由本对象持有并随它关闭。
    pub(super) fn get(&self) -> &T {
        &self.fd
    }

    /// 可变借用真实句柄（read/write/seek 等同步 IO）。
    pub(super) fn get_mut(&mut self) -> &mut T {
        &mut self.fd
    }

    /// 为从本句柄派生出的新 FD 取得同一份预算；新 FD 必须立刻用 [`LeasedFd::new`] 绑定，
    /// 否则它会在本对象之外的窗口里脱离预算。
    pub(super) fn share(&self) -> ResourceLease {
        self.lease.clone()
    }

    /// 同步移交：句柄与同一份预算一起交给继续持有预算的接收者。
    ///
    /// 调用方若把句柄交给一个同步函数消费（该函数内部关闭它），必须让返回的预算作为具名
    /// 局部变量活到同一作用域结束，从而保证句柄先关闭。
    pub(super) fn split(self) -> (T, ResourceLease) {
        (self.fd, self.lease)
    }
}

impl LeasedFd<Dir> {
    /// 克隆目录能力：新句柄同样绑定同一份预算（同一次准入内的峰值 FD）。
    pub(super) fn try_clone(&self) -> Result<Self, RemoteError> {
        Ok(Self {
            fd: self
                .fd
                .try_clone()
                .map_err(|error| io_error("failed to clone directory capability", error))?,
            lease: self.lease.clone(),
        })
    }
}

/// 同时绑定「句柄自身预算」与「本次 operation 预算」的组合 owner。
///
/// 有些句柄只携带 workspace 池的 retained 预算（例如 workspace 根的克隆），它不能充当本次
/// 操作的 FD 预算。把 operation lease 直接绑定到持有该句柄的同一个对象上，析构次序就由字段
/// 声明顺序固定：先关闭句柄（连同它自身预算），再归还 operation 预算。调用方取消后 owner 仍
/// 随阻塞任务存活，系统调用与句柄都在 operation 预算内结束。
pub(super) struct OperationFd<T> {
    fd: LeasedFd<T>,
    /// 本次 operation 的预算：必须晚于 `fd` 归还。
    #[expect(dead_code, reason = "RAII 持有：字段只为析构顺序存在，不参与读取")]
    operation: ResourceLease,
}

impl<T> OperationFd<T> {
    pub(super) fn new(fd: LeasedFd<T>, operation: ResourceLease) -> Self {
        Self { fd, operation }
    }

    /// 只读借用真实句柄：句柄仍随本对象关闭。
    pub(super) fn get(&self) -> &T {
        self.fd.get()
    }
}
