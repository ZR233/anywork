//! Runtime facade for file-backed Thread Mode authoring.

use anyhow::Result;
use pl_protocol::studio::CommandEffectPoint;
use pl_protocol::{
    ThreadModeDefinitionCommandReply, ThreadModeDefinitionSnapshot, ThreadModeDocument,
    ThreadModeId, ThreadModeValidationResult, WorkflowPreviewRequest, WorkflowPreviewSnapshot,
};

use super::StudioRuntime;

impl StudioRuntime {
    pub fn read_thread_mode_definition(
        &self,
        mode_id: &ThreadModeId,
    ) -> Result<ThreadModeDefinitionSnapshot> {
        self.config_runtime.read_thread_mode_definition(mode_id)
    }

    pub async fn save_thread_mode_definition(
        &self,
        operation_id: &str,
        expected_revision: u64,
        document: ThreadModeDocument,
    ) -> Result<ThreadModeDefinitionCommandReply> {
        Self::validate_operation_id(operation_id)?;
        let outcome = self
            .config_runtime
            .save_thread_mode_definition(expected_revision, document)?;
        self.finish_mode_command(operation_id, outcome)
    }

    pub async fn delete_thread_mode_definition(
        &self,
        operation_id: &str,
        expected_revision: u64,
        mode_id: &ThreadModeId,
    ) -> Result<ThreadModeDefinitionCommandReply> {
        Self::validate_operation_id(operation_id)?;
        let outcome = self
            .config_runtime
            .delete_thread_mode_definition(expected_revision, mode_id)?;
        self.finish_mode_command(operation_id, outcome)
    }

    pub async fn reload_thread_mode_definitions(
        &self,
        operation_id: &str,
        expected_revision: u64,
    ) -> Result<ThreadModeDefinitionCommandReply> {
        Self::validate_operation_id(operation_id)?;
        let outcome = self
            .config_runtime
            .reload_thread_mode_definitions(expected_revision)?;
        self.finish_mode_command(operation_id, outcome)
    }

    pub fn validate_thread_mode_definition(&self, json: &str) -> ThreadModeValidationResult {
        crate::mode::validate_mode_json(json)
    }

    pub fn thread_mode_definition_schema(&self) -> String {
        crate::mode::mode_document_schema()
    }

    pub fn preview_thread_mode_workflow(
        &self,
        request: WorkflowPreviewRequest,
    ) -> Result<WorkflowPreviewSnapshot> {
        Ok(crate::mode::preview_workflow(request)?)
    }

    fn finish_mode_command(
        &self,
        operation_id: &str,
        outcome: crate::config::ModeDefinitionCommandOutcome,
    ) -> Result<ThreadModeDefinitionCommandReply> {
        self.modes_source.publish(outcome.catalog.clone())?;
        let _ = self
            .agent_facility
            .product_events
            .emit_thread_mode_catalog(outcome.catalog.clone());
        Ok(ThreadModeDefinitionCommandReply {
            receipt: self.command_receipt(
                operation_id.to_string(),
                outcome.changed,
                vec![self.resource_stamp("thread-mode-catalog", outcome.catalog.revision)],
                CommandEffectPoint::NextTurn,
                true,
            ),
            definition: outcome.definition,
            catalog: outcome.catalog,
        })
    }
}
