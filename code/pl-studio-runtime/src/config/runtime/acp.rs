use super::{
    ConfigRuntime, ConfigRuntimeResult, ConfigRuntimeSnapshot, config_runtime_poisoned,
    ensure_revision,
};
use crate::config::{AcpDefinitionsSnapshot, AcpServiceDefinition};

impl ConfigRuntime {
    /// Published user-level ACP resource; no IO, install, probe or launch.
    pub fn read_acp_definitions(&self) -> AcpDefinitionsSnapshot {
        self.acp.read()
    }

    pub fn subscribe_acp_definitions(&self) -> tokio::sync::watch::Receiver<u64> {
        self.acp.subscribe()
    }

    pub fn resolve_acp_definition(
        &self,
        id: &str,
        expected_connection_revision: u64,
    ) -> Result<AcpServiceDefinition, crate::config::AcpDefinitionError> {
        self.acp.resolve(id, expected_connection_revision)
    }

    /// Create requires no previous document; update compares the exact published document digest.
    /// A concurrent external edit is a conflict until explicitly reloaded.
    pub fn save_acp_definition(
        &self,
        expected_settings_revision: u64,
        definition: &AcpServiceDefinition,
        expected_document_revision: Option<u64>,
    ) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let current = self.read()?;
        ensure_revision(expected_settings_revision, current.revision)?;
        let published =
            self.acp
                .save(self.store.paths(), definition, expected_document_revision)?;
        self.publish_acp_snapshot(current, published)
    }

    pub fn delete_acp_definition(
        &self,
        expected_settings_revision: u64,
        id: &str,
        expected_document_revision: u64,
    ) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let current = self.read()?;
        ensure_revision(expected_settings_revision, current.revision)?;
        let published = self
            .acp
            .delete(self.store.paths(), id, expected_document_revision)?;
        self.publish_acp_snapshot(current, published)
    }

    pub fn reload_acp_definitions(&self) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        self.publish_acp_snapshot(self.read()?, self.acp.reload(self.store.paths()))
    }

    fn publish_acp_snapshot(
        &self,
        mut next: ConfigRuntimeSnapshot,
        published: AcpDefinitionsSnapshot,
    ) -> ConfigRuntimeResult<ConfigRuntimeSnapshot> {
        if published == next.acp {
            return Ok(next);
        }
        next.acp = published;
        next.revision = next
            .revision
            .checked_add(1)
            .expect("settings revision exhausted");
        next.updated_at = crate::studio::unix_seconds();
        let mut state = self.state.write().map_err(|_| config_runtime_poisoned())?;
        let catalog = state.catalog.clone();
        super::update_account_projection_revisions(&mut state, &next, &catalog);
        state.snapshot = next.clone();
        drop(state);
        self.profiles
            .adopt_scan(self.store.paths(), &next.config, &next.acp);
        self.notify_settings_committed(&next);
        Ok(next)
    }

    /// Shared command boundary for ACP admission. The supplied snapshot is immutable and cache-only.
    pub(crate) fn with_acp_snapshot<T>(
        &self,
        run: impl FnOnce(u64, &AcpDefinitionsSnapshot) -> T,
    ) -> ConfigRuntimeResult<T> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let current = self.read()?;
        Ok(run(current.revision, &current.acp))
    }
}
