//! Profiles remains an independent source/origin despite sharing Configuration's read plumbing.
mod feed;
mod frames;
mod material;
mod read;

pub use feed::StudioAgentProfilesFeed;
pub use pl_protocol::products::feed::agent_profiles::AgentProfilesFrame;
pub use pl_protocol::products::read::agent_profiles::*;
pub use pl_protocol::products::references::AgentProfilesReadRef;
pub use read::StudioAgentProfilesRead;
