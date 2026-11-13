pub mod api;
mod desktop_instance;
mod diagnostics;

pub use pl_protocol::ThreadSubscriptionUpdate;

#[allow(clippy::not_unsafe_ptr_arg_deref)]
// FRB sets this cfg for source expansion. Its generated output is not an
// expansion input; normal builds still compile and validate the whole module.
#[cfg(not(frb_expand))]
pub mod frb_generated;

#[cfg(test)]
#[cfg(all(test, target_os = "linux"))]
#[expect(
    dead_code,
    reason = "Shared fixture also serves direct runtime consumers"
)]
#[path = "../../../pl-studio-runtime/tests/support/acp_transport_fixture.rs"]
mod test_fixture_acp_transport_fixture;
