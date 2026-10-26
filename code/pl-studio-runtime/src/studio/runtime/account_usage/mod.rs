//! Usage product projection; the original AccountUsageRuntime remains the only query writer.
mod commands;
mod feed;
mod material;
mod owner;
mod read;
mod scope;
mod source;
mod source_status;
pub use feed::StudioAccountUsageFeed;
pub(crate) use owner::AccountUsageRuntime;
pub use owner::{AccountUsageStateData, AccountUsageStateSnapshot};
pub use pl_protocol::products::feed::account_usage::AccountUsageFrame;
pub use pl_protocol::products::identity::{
    ProductEntityRef, ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity,
    ProductSourceStatusRef,
};
pub use pl_protocol::products::read::account_usage::*;
pub use pl_protocol::products::references::{AccountUsageReadRef, AccountUsageReadTarget};
pub use pl_protocol::products::source::ProductSourceStatusReadHeader;
pub use read::StudioAccountUsageRead;
pub(in crate::studio::runtime) use source::{UsageMaterial, UsageSource};
pub use source_status::StudioAccountUsageSourceStatusRead;
