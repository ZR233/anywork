//! Statistics-only FRB entrance, typed DTOs, immutable scopes, and bridge-owned lifecycle.

pub mod feed;
pub mod types;

mod convert;
pub(crate) mod registry;

pub(crate) use feed::BridgeStatisticsFeedInner;
pub(crate) use registry::{PendingStatisticsFeedCancellation, StatisticsFeedRegistry};
