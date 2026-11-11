pub mod api;
mod desktop_instance;
mod diagnostics;

pub use pl_protocol::ThreadSubscriptionUpdate;

#[allow(clippy::not_unsafe_ptr_arg_deref)]
// FRB sets this cfg for source expansion. Its generated output is not an
// expansion input; normal builds still compile and validate the whole module.
#[cfg(not(frb_expand))]
pub mod frb_generated;
