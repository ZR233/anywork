//! Retained read-only inputs of the same Thread projection owner, not a new publisher or bus.
use crate::config::{ConfigRuntime, ConfigRuntimeSnapshot};
use anyhow::Result;
use pl_protocol::studio::ConfigProjectionStamp;

pub(in crate::studio::runtime) struct ConfigurationInputs {
    pub(in crate::studio::runtime) stamp: ConfigProjectionStamp,
    config_updates: tokio::sync::watch::Receiver<ConfigProjectionStamp>,
    mode_revision: u64,
    mode_updates: tokio::sync::watch::Receiver<u64>,
    config_dirty: bool,
    modes_dirty: bool,
}

impl ConfigurationInputs {
    pub(in crate::studio::runtime) fn observe(
        config: &ConfigRuntime,
        modes: &crate::mode::ThreadModeManager,
    ) -> Result<(Self, ConfigRuntimeSnapshot)> {
        let config: crate::config::ConfigProjectionObservation =
            config.observe_projection_sources()?;
        let modes = modes.observe_registry();
        Ok((
            Self {
                stamp: config.stamp,
                config_updates: config.updates,
                mode_revision: modes.current.revision(),
                mode_updates: modes.updates,
                config_dirty: false,
                modes_dirty: false,
            },
            config.current.0,
        ))
    }

    pub(in crate::studio::runtime) fn refresh(
        &mut self,
        config: &ConfigRuntime,
        modes: &crate::mode::ThreadModeManager,
    ) -> Result<Option<ConfigRuntimeSnapshot>> {
        let policy =
            if !self.stamp.closing && (self.config_dirty || self.config_updates.has_changed()?) {
                Some(self.read_policy(config)?)
            } else {
                None
            };
        if self.modes_dirty || self.mode_updates.has_changed()? {
            let modes = modes.observe_registry();
            self.mode_revision = modes.current.revision();
            self.mode_updates = modes.updates;
            self.modes_dirty = false;
        }
        Ok(policy)
    }

    pub(in crate::studio::runtime) fn read_policy(
        &mut self,
        config: &ConfigRuntime,
    ) -> Result<ConfigRuntimeSnapshot> {
        let config = config.observe_projection_sources()?;
        self.stamp = config.stamp;
        self.config_updates = config.updates;
        self.config_dirty = false;
        // Only watermarks and observation registration remain resident. Do not retain a second
        // per-Thread copy of account configuration, credentials or the full model/Mode catalog.
        Ok(config.current.0)
    }

    pub(in crate::studio::runtime) fn mode_revision(&self) -> u64 {
        self.mode_revision
    }

    pub(in crate::studio::runtime) async fn changed(&mut self) {
        // A closing Config source retains last-known policy and is never awaited again. Thread
        // execution and reliable persistence still finish through their original wake sources.
        tokio::select! {
            _ = self.config_updates.changed(), if !self.stamp.closing => self.config_dirty = true,
            _ = self.mode_updates.changed() => self.modes_dirty = true,
        }
    }
}
