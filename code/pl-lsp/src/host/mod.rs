//! LSP workspace 与 language server 进程的宿主边界。

mod backend;
mod executor;
pub use executor::ExecutorLspHost;

pub use backend::{
    LspHostBackend, LspHostError, LspHostFileStat, LspHostProcess, LspHostProcessExit,
    LspHostSpawnRequest, LspPathStyle,
};
pub(crate) use backend::{LspHostReader, LspHostWriter};

pub(crate) fn join_path(
    base: &std::path::Path,
    path: &str,
    host: Option<&dyn LspHostBackend>,
) -> Result<std::path::PathBuf, LspHostError> {
    match host {
        Some(host) => host.join_path(base, path),
        None => Ok(base.join(path)),
    }
}
