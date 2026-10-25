//! Closed native products supported by this domain owner. This is only dispatch: each native
//! feed retains its own source, delivery window and exact wire frame (no extra JSON envelope).
use pl_protocol::products::feed::{
    agent_profiles::AgentProfilesFrame, configuration::ConfigurationFrame,
};
use pl_protocol::products::identity::ProductFeedIdentity;
use pl_protocol::studio::StudioError;
use pl_studio_runtime::{
    StudioRuntime,
    configuration::{StudioAgentProfilesFeed, StudioConfigurationFeed},
};

#[derive(Clone, Copy)]
pub(super) enum FeedKind {
    Configuration,
    AgentProfiles,
}
pub(super) enum NativeFeed {
    Configuration(StudioConfigurationFeed),
    AgentProfiles(StudioAgentProfilesFeed),
}
#[derive(serde::Serialize)]
#[serde(untagged)]
pub(super) enum NativeFrame {
    Configuration(ConfigurationFrame),
    AgentProfiles(AgentProfilesFrame),
}
impl NativeFrame {
    pub(super) fn sequence(&self) -> Option<u64> {
        match self {
            Self::Configuration(ConfigurationFrame::Data {
                delivery_sequence, ..
            })
            | Self::AgentProfiles(AgentProfilesFrame::Data {
                delivery_sequence, ..
            }) => Some(*delivery_sequence),
            Self::Configuration(_) | Self::AgentProfiles(_) => None,
        }
    }
}
impl FeedKind {
    pub(super) async fn open(self, runtime: &StudioRuntime) -> anyhow::Result<NativeFeed> {
        Ok(match self {
            Self::Configuration => NativeFeed::Configuration(runtime.open_configuration().await?),
            Self::AgentProfiles => NativeFeed::AgentProfiles(runtime.open_agent_profiles().await?),
        })
    }
}
impl NativeFeed {
    pub(super) fn identity(&self) -> ProductFeedIdentity {
        match self {
            Self::Configuration(feed) => feed.identity(),
            Self::AgentProfiles(feed) => feed.identity(),
        }
    }
    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        match self {
            Self::Configuration(feed) => feed.ensure_open(),
            Self::AgentProfiles(feed) => feed.ensure_open(),
        }
    }
    pub(super) fn claim(&self) -> Result<(), StudioError> {
        match self {
            Self::Configuration(feed) => feed.claim(),
            Self::AgentProfiles(feed) => feed.claim(),
        }
    }
    pub(super) fn is_closing(&self) -> bool {
        match self {
            Self::Configuration(feed) => feed.is_closing(),
            Self::AgentProfiles(feed) => feed.is_closing(),
        }
    }
    pub(super) fn request_close(&self) {
        match self {
            Self::Configuration(feed) => feed.request_close(),
            Self::AgentProfiles(feed) => feed.request_close(),
        }
    }
    pub(super) fn ack_through(&self, sequence: u64) -> Result<(), StudioError> {
        match self {
            Self::Configuration(feed) => feed.ack_through(sequence),
            Self::AgentProfiles(feed) => feed.ack_through(sequence),
        }
    }
    pub(super) async fn changed(&self) -> Result<(), StudioError> {
        match self {
            Self::Configuration(feed) => feed.changed().await,
            Self::AgentProfiles(feed) => feed.changed().await,
        }
    }
    pub(super) async fn cancelled(&self) {
        match self {
            Self::Configuration(feed) => feed.cancelled().await,
            Self::AgentProfiles(feed) => feed.cancelled().await,
        }
    }
    pub(super) fn send_pending(
        &self,
        send: impl FnOnce(NativeFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        match self {
            Self::Configuration(feed) => {
                feed.send_pending(|frame| send(NativeFrame::Configuration(frame)))
            }
            Self::AgentProfiles(feed) => {
                feed.send_pending(|frame| send(NativeFrame::AgentProfiles(frame)))
            }
        }
    }
    pub(super) fn send_closed(
        &self,
        send: impl FnOnce(NativeFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        match self {
            Self::Configuration(feed) => {
                feed.send_closed(|frame| send(NativeFrame::Configuration(frame)))
            }
            Self::AgentProfiles(feed) => {
                feed.send_closed(|frame| send(NativeFrame::AgentProfiles(frame)))
            }
        }
    }
    pub(super) fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(NativeFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        match self {
            Self::Configuration(feed) => {
                feed.send_failure(error, |frame| send(NativeFrame::Configuration(frame)))
            }
            Self::AgentProfiles(feed) => {
                feed.send_failure(error, |frame| send(NativeFrame::AgentProfiles(frame)))
            }
        }
    }
}
