//! Closed result ownership used by the existing transport registry; not a new writer or bus.
use super::super::StudioRuntime;
use super::{ConfigurationCommandResult, ConfigurationReloadCommandResult, ProfileCommandResult};
use pl_protocol::products::configuration_calls::{
    ConfigurationCallOutcome, ConfigurationCallRequest,
};

pub enum ConfigurationCallResult {
    Configuration(ConfigurationCommandResult),
    Profile(ProfileCommandResult),
    Reload(ConfigurationReloadCommandResult),
}
impl ConfigurationCallResult {
    pub async fn run(runtime: &StudioRuntime, request: ConfigurationCallRequest) -> Self {
        match request {
            ConfigurationCallRequest::Configuration(request) => {
                Self::Configuration(runtime.configuration_command(request).await)
            }
            ConfigurationCallRequest::Profile(request) => {
                Self::Profile(runtime.profile_command(request).await)
            }
            ConfigurationCallRequest::Reload(request) => {
                Self::Reload(runtime.configuration_reload(request).await)
            }
        }
    }
    /// Clone only the pure outcome; retain this actual resource until explicit call close.
    pub fn outcome(&self) -> ConfigurationCallOutcome {
        match self {
            Self::Configuration(result) => {
                ConfigurationCallOutcome::Configuration(result.outcome().clone())
            }
            Self::Profile(result) => ConfigurationCallOutcome::Profile(result.outcome().clone()),
            Self::Reload(result) => ConfigurationCallOutcome::Reload(result.outcome().clone()),
        }
    }
}
