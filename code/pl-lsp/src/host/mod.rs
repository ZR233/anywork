//! LSP workspace 与 language server 进程的宿主边界。

mod backend;
mod executor;
pub use executor::ExecutorLspHost;

pub use backend::{
    LspHostBackend, LspHostError, LspHostFileStat, LspHostProcess, LspHostProcessExit,
    LspHostSpawnRequest, LspPathStyle,
};
pub(crate) use backend::{LspHostReader, LspHostWriter};
