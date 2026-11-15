use std::sync::Arc;

macro_rules! id_type {
    ($name:ident) => {
        #[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
        pub struct $name(pub(crate) u64);

        impl $name {
            pub fn get(self) -> u64 {
                self.0
            }
        }
    };
}

id_type!(ScopeId);
id_type!(ResourceId);
id_type!(AttemptId);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Phase {
    Opening,
    Active,
    Closing,
    Failed,
    Closed,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ScopeClosed;

#[derive(Debug)]
/// 构造过程的终态；业务错误以 `Arc` 原样保留，不要求错误实现 `Clone`。
pub enum OpenError<E> {
    ScopeClosed,
    Cancelled,
    Resource(Arc<E>),
    Panicked,
    WorkerStopped,
}

#[derive(Debug)]
/// 清理尝试的终态；业务错误以 `Arc` 原样保留。
pub enum CloseError<E> {
    Resource(Arc<E>),
    Panicked,
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RegistrationError {
    ScopeClosed,
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
    pub fn is_clean(&self) -> bool {
        self.sealed && self.workers_finished && self.failures.is_empty() && self.pending.is_empty()
    }
}
