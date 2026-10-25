//! Closed kind dispatch shared only by the original Configuration call owners. Public wire
//! endpoints keep their concrete request/result schemas, not this internal dispatch envelope.
use super::configuration_commands::{ConfigurationCommandOutcome, ConfigurationCommandRequest};
use super::profile_commands::{
    ConfigurationReloadOutcome, ConfigurationReloadRequest, ProfileCommandOutcome,
    ProfileCommandRequest,
};
use crate::studio::StudioError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfigurationCallKind {
    Configuration,
    Profile,
    Reload,
}
#[derive(Debug, Clone, PartialEq)]
pub enum ConfigurationCallRequest {
    Configuration(ConfigurationCommandRequest),
    Profile(ProfileCommandRequest),
    Reload(ConfigurationReloadRequest),
}
impl ConfigurationCallRequest {
    pub fn kind(&self) -> ConfigurationCallKind {
        match self {
            Self::Configuration(_) => ConfigurationCallKind::Configuration,
            Self::Profile(_) => ConfigurationCallKind::Profile,
            Self::Reload(_) => ConfigurationCallKind::Reload,
        }
    }
    pub fn operation_id(&self) -> &str {
        match self {
            Self::Configuration(request) => request.operation_id(),
            Self::Profile(request) => request.operation_id(),
            Self::Reload(request) => &request.operation_id,
        }
    }
    pub fn unknown(&self, error: StudioError) -> ConfigurationCallOutcome {
        let operation_id = self.operation_id().to_owned();
        match self {
            Self::Configuration(_) => {
                ConfigurationCallOutcome::Configuration(ConfigurationCommandOutcome::Unknown {
                    operation_id,
                    error,
                })
            }
            Self::Profile(_) => ConfigurationCallOutcome::Profile(ProfileCommandOutcome::Unknown {
                operation_id,
                error,
            }),
            Self::Reload(_) => {
                ConfigurationCallOutcome::Reload(ConfigurationReloadOutcome::Unknown {
                    operation_id,
                    error,
                })
            }
        }
    }
}
#[derive(Debug, Clone, PartialEq)]
pub enum ConfigurationCallOutcome {
    Configuration(ConfigurationCommandOutcome),
    Profile(ProfileCommandOutcome),
    Reload(ConfigurationReloadOutcome),
}
