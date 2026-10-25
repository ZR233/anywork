//! Local audience control and observation. The bot database remains the sole route/authority owner.

mod command;
mod prepare;
mod read;
pub(in crate::bots) use command::{first_start, permission_close_reason, prepare_permission};
pub(in crate::bots) use prepare::AudiencePrepareTasks;

use super::owner::ManagedBot;
use crate::studio::thread_audience::BotAudienceWatchVersion;

impl ManagedBot {
    /// Called by the managed mutation owner, never by a caller's wait future. `send_modify`
    /// retains the newest invalidation even without receivers and serializes concurrent publishers.
    pub(in crate::bots) fn audience_changed(&self) {
        self.audience_changes.send_modify(|stamp| {
            if let Some(next) = stamp.version.checked_add(1) {
                stamp.version = next;
            } else {
                stamp.owner_epoch = crate::studio::new_id("bot-audience");
                stamp.version = 1;
            }
        });
    }
}

pub(in crate::bots) fn watch_channel() -> tokio::sync::watch::Sender<BotAudienceWatchVersion> {
    tokio::sync::watch::channel(BotAudienceWatchVersion {
        owner_epoch: crate::studio::new_id("bot-audience"),
        version: 1,
    })
    .0
}
