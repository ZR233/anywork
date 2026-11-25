//! Published LSP state, explicit commands, and live Thread association projection.

mod api;
mod state;
mod watcher;

pub(super) use state::LspStateRuntime;
pub(crate) use state::execution_endpoint;

#[cfg(test)]
pub(super) use watcher::WorkspaceLspSnapshots;

#[cfg(test)]
pub(super) mod test_support;

#[cfg(test)]
mod tests;
