//! ACP business resources; membership and preparation remain owned by SessionRuntime.
mod api;

mod observation;
mod projection;
mod resources;
#[cfg(all(test, target_os = "linux"))]
mod title_tests;
mod workflow_plan;

pub(crate) use api::AcpBusinessOwner;
pub use api::AcpSessionOpen;
pub use observation::{AcpSessionCompletion, AcpSessionObservation};
pub(crate) use resources::{AcpCloseOutcome, AcpResources};
pub(crate) use workflow_plan::{AcpPlanToolContext, AcpWorkflowPlanOwner};

#[cfg(all(test, target_os = "linux"))]
mod collaboration_tests;

#[cfg(all(test, target_os = "linux"))]
mod session_tests;
