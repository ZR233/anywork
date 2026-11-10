//! ACP business resources; membership and preparation remain owned by SessionRuntime.
mod api;
mod observation;
mod projection;
mod resources;
#[cfg(all(test, target_os = "linux"))]
mod tests;

pub use api::AcpSessionOpen;
pub use observation::{AcpSessionCompletion, AcpSessionObservation};
pub(crate) use resources::{AcpCloseOutcome, AcpResources};
