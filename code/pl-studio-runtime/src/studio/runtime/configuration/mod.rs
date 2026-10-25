//! Typed Configuration feeds, immutable reads and compatible role/Start queries.
//! ConfigRuntime is the only writer; transport and SDK never reconstruct canonical material.
mod calls;
mod commands;
mod feed;
mod fields;
mod frames;
mod material;
mod pages;
mod profile_commands;
mod read;
mod routes;
mod scope;
mod source_status;
pub use calls::ConfigurationCallResult;
pub use pl_protocol::products::profile_commands::{
    ConfigurationReloadOutcome, ConfigurationReloadRequest, ConfigurationReloadResult,
    ProfileCommandOutcome, ProfileCommandReply, ProfileCommandRequest,
};
pub use profile_commands::{ConfigurationReloadCommandResult, ProfileCommandResult};
mod profiles;
pub use profiles::*;

pub use commands::ConfigurationCommandResult;
pub use feed::StudioConfigurationFeed;
pub use pl_protocol::products::configuration_commands::{
    ConfigurationCommandOutcome, ConfigurationCommandReply, ConfigurationCommandRequest,
};
pub use read::{
    StudioConfigurationRead, StudioConfigurationRoleRead, StudioConfigurationStartRead,
};
pub use source_status::StudioConfigurationSourceStatusRead;

pub use pl_protocol::products::configuration::{
    ConfigurationRoleReadRef, ConfigurationRoleReadTarget, RoleRouteRead, StartRouteIntent,
    StartRouteQuery, StartRouteRead,
};
pub use pl_protocol::products::feed::configuration::ConfigurationFrame;
pub use pl_protocol::products::identity::{
    ProductEntityRef, ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity,
    ProductSourceStatusRef,
};
pub use pl_protocol::products::read::configuration::*;
pub use pl_protocol::products::read::configuration_pages::*;
pub use pl_protocol::products::read::model_pages::{
    ModelInputCapabilityReadPage, ModelInputSourceReadPage,
};
pub use pl_protocol::products::read::primitives::TextReadPage;
pub use pl_protocol::products::references::ConfigurationReadRef;
pub use pl_protocol::products::source::ProductSourceStatusReadHeader;
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
