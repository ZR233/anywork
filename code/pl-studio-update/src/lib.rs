//! anywork 稳定版更新检查、可信下载与安装边界。

mod client;
mod error;
mod install;
mod manifest;
mod transfer;
mod types;
mod verification;

pub use client::{STUDIO_VERSION, StudioUpdater};
pub use error::{StudioUpdateError, StudioUpdateErrorCode};
pub use install::{PreparedStudioUpdate, StudioUpdateCancellation, StudioUpdateLaunch};
pub use types::{StudioUpdate, StudioUpdateAsset, StudioUpdateCheck, StudioUpdateEvent};

#[cfg(test)]
mod test_support;
