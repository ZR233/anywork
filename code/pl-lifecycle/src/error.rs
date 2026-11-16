use std::sync::Arc;

macro_rules! id_type {
    ($name:ident, $description:literal) => {
        #[doc = $description]
        #[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
        pub struct $name(pub(crate) u64);

        impl $name {
            /// 取得仅用于本地身份关联与诊断的数值，不用于业务协议。
            pub fn get(self) -> u64 {
                self.0
            }
        }
    };
}

id_type!(ScopeId, "同一根作用域树中唯一的作用域标识。");
id_type!(
    ResourceId,
    "所属作用域内唯一的资源标识，与 ScopeId 共同确定资源身份。"
);
id_type!(
    AttemptId,
    "原资源的尝试标识：构造为 0，首次清理为 1，显式重试递增。"
);

/// 受管成员的操作阶段；资源已关闭与关闭报告无诊断错误分别判定。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Phase {
    Opening,
    Active,
    Closing,
    Failed,
    Closed,
}

/// 所有者已消失或作用域已封门，无法接纳新的子作用域或资源。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ScopeClosed;

#[derive(Debug)]
/// 构造过程的终态；业务错误以 `Arc` 原样保留，不要求错误实现 `Clone`。
pub enum OpenError<E> {
    /// 作用域封门先于登记，工厂没有执行。
    ScopeClosed,
    /// 已登记的构造失去交付资格；迟到原件仍由作用域清理。
    Cancelled,
    /// 工厂返回的原始业务错误；没有产出资源时不污染关闭报告。
    Resource(Arc<E>),
    /// 创建工厂 future 或轮询它时发生 panic，关闭报告保留诊断。
    Panicked,
    /// 监督工作未能正常结束，例如注入的运行时已停止。
    WorkerStopped,
}

#[derive(Debug)]
/// 清理尝试的终态；业务错误以 `Arc` 原样保留。
pub enum CloseError<E> {
    /// 原资源清理失败；保留同一实例及错误，等待显式重试。
    Resource(Arc<E>),
    /// 清理发生 panic；原件仍在时可显式重试。
    Panicked,
    /// 监督工作意外终止，不能据此认定资源已释放。
    WorkerStopped,
}

impl<E> Clone for OpenError<E> {
    fn clone(&self) -> Self {
        match self {
            Self::ScopeClosed => Self::ScopeClosed,
            Self::Cancelled => Self::Cancelled,
            Self::Resource(error) => Self::Resource(Arc::clone(error)),
            Self::Panicked => Self::Panicked,
            Self::WorkerStopped => Self::WorkerStopped,
        }
    }
}

impl<E> Clone for CloseError<E> {
    fn clone(&self) -> Self {
        match self {
            Self::Resource(error) => Self::Resource(Arc::clone(error)),
            Self::Panicked => Self::Panicked,
            Self::WorkerStopped => Self::WorkerStopped,
        }
    }
}

/// 同步解绑登记失败；即使拒绝接纳，也会先尝试执行传入的解绑回调。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RegistrationError {
    /// 已封门，拒绝登记时的解绑已成功完成。
    ScopeClosed,
    /// 已封门，且拒绝登记时执行的解绑回调发生 panic。
    RejectedCleanupPanicked,
}

#[derive(Clone, Debug, Eq, PartialEq)]
/// 由作用域标识与作用域内资源标识共同确定的成员身份。
pub struct ResourceInfo {
    pub scope_id: ScopeId,
    pub resource_id: ResourceId,
    pub label: &'static str,
}

#[derive(Debug)]
/// 一个失败的构造或清理操作；`retained` 表示原资源仍需清理。
pub struct FailedResource<E> {
    pub resource: ResourceInfo,
    pub attempt_id: AttemptId,
    pub phase: Phase,
    pub error: CloseError<E>,
    pub retained: bool,
}

impl<E> Clone for FailedResource<E> {
    fn clone(&self) -> Self {
        Self {
            resource: self.resource.clone(),
            attempt_id: self.attempt_id,
            phase: self.phase,
            error: self.error.clone(),
            retained: self.retained,
        }
    }
}

#[derive(Clone, Debug)]
/// 截止时刻仍在执行的构造或清理操作。
pub struct PendingResource {
    pub resource: ResourceInfo,
    pub attempt_id: AttemptId,
    pub phase: Phase,
}

#[derive(Debug)]
/// 当前作用域及子树的关闭观察结果。
///
/// `workers_finished` 覆盖全部受监督工作；诊断错误可在原资源释放后继续存在，
/// 因此资源已经释放不代表 `is_clean()` 为真。
pub struct CloseReport<E> {
    pub scope_id: ScopeId,
    pub sealed: bool,
    pub workers_finished: bool,
    pub failures: Vec<FailedResource<E>>,
    pub pending: Vec<PendingResource>,
}

impl<E> Clone for CloseReport<E> {
    fn clone(&self) -> Self {
        Self {
            scope_id: self.scope_id,
            sealed: self.sealed,
            workers_finished: self.workers_finished,
            failures: self.failures.clone(),
            pending: self.pending.clone(),
        }
    }
}

impl<E> CloseReport<E> {
    /// 已封门、全子树监督工作结束，且没有失败诊断或待完成资源才返回真。
    ///
    /// 超时只结束本次等待；取消令牌触发或任务计数为空均不能单独证明关闭完成。
    pub fn is_clean(&self) -> bool {
        self.sealed && self.workers_finished && self.failures.is_empty() && self.pending.is_empty()
    }
}
