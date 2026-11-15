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
pub enum OpenError<E> {
    ScopeClosed,
    Cancelled,
    Resource(Arc<E>),
    Panicked,
    WorkerStopped,
}

#[derive(Debug)]
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
pub struct ResourceInfo {
    pub scope_id: ScopeId,
    pub resource_id: ResourceId,
    pub label: &'static str,
}

#[derive(Debug)]
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
pub struct PendingResource {
    pub resource: ResourceInfo,
    pub attempt_id: AttemptId,
    pub phase: Phase,
}

#[derive(Debug)]
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
