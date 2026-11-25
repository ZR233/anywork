//! Runtime assembly, startup, recovery, and shutdown.

mod builder;
mod framework;
mod initialization;
mod project;
mod recovery;
mod recovery_task;
pub(crate) mod shutdown;
mod snapshot;

mod thread_activation;
