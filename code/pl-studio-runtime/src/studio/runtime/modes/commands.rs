use super::super::{StudioRuntime, read_budget::require_budget};
use anyhow::Result;
use pl_protocol::products::read::modes::ModeDefinitionCommandReply;
use pl_protocol::studio::CommandEffectPoint;
use pl_protocol::{
    ThreadModeDefinitionSnapshot, ThreadModeDocument, ThreadModeId, ThreadModeValidationResult,
    WorkflowPreviewRequest, WorkflowPreviewSnapshot,
};
use std::future::Future;

impl StudioRuntime {
    pub fn read_mode_definition(
        &self,
        id: ThreadModeId,
    ) -> impl Future<Output = Result<ThreadModeDefinitionSnapshot>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let value = runtime.config_runtime.read_thread_mode_definition(&id)?;
            require_budget(&value)?;
            Ok(value)
        })
    }
    pub fn validate_mode_definition(
        &self,
        raw_json: String,
    ) -> impl Future<Output = Result<ThreadModeValidationResult>> + Send + 'static + use<> {
        self.read_calls.run(async move {
            require_budget(&raw_json)?;
            let value = crate::mode::validate_mode_json(&raw_json);
            require_budget(&value)?;
            Ok(value)
        })
    }
    pub fn mode_definition_schema(
        &self,
    ) -> impl Future<Output = Result<String>> + Send + 'static + use<> {
        self.read_calls.run(async move {
            let value = crate::mode::mode_document_schema();
            require_budget(&value)?;
            Ok(value)
        })
    }
    pub fn preview_mode_workflow(
        &self,
        request: WorkflowPreviewRequest,
    ) -> impl Future<Output = Result<WorkflowPreviewSnapshot>> + Send + 'static + use<> {
        self.read_calls.run(async move {
            require_budget(&request)?;
            let value = crate::mode::preview_workflow(request)?;
            require_budget(&value)?;
            Ok(value)
        })
    }
    pub fn save_mode_definition(
        &self,
        document: ThreadModeDocument,
        expected_revision: u64,
        operation_id: String,
    ) -> impl Future<Output = Result<ModeDefinitionCommandReply>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            Self::validate_operation_id(&operation_id)?;
            require_budget(&document)?;
            let outcome = runtime
                .config_runtime
                .save_thread_mode_definition(expected_revision, document)?;
            runtime.finish_mode_product_command(operation_id, outcome)
        })
    }
    pub fn delete_mode_definition(
        &self,
        mode: ThreadModeId,
        expected_revision: u64,
        operation_id: String,
    ) -> impl Future<Output = Result<ModeDefinitionCommandReply>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            Self::validate_operation_id(&operation_id)?;
            let outcome = runtime
                .config_runtime
                .delete_thread_mode_definition(expected_revision, &mode)?;
            runtime.finish_mode_product_command(operation_id, outcome)
        })
    }
    pub fn reload_mode_definitions(
        &self,
        expected_revision: u64,
        operation_id: String,
    ) -> impl Future<Output = Result<ModeDefinitionCommandReply>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            Self::validate_operation_id(&operation_id)?;
            let outcome = runtime
                .config_runtime
                .reload_thread_mode_definitions(expected_revision)?;
            runtime.finish_mode_product_command(operation_id, outcome)
        })
    }
    fn finish_mode_product_command(
        &self,
        operation_id: String,
        outcome: crate::config::ModeDefinitionCommandOutcome,
    ) -> Result<ModeDefinitionCommandReply> {
        let material = self.modes_source.publish(outcome.catalog.clone())?;
        let catalog = self.modes_source.expose_committed(material)?;
        let _ = self
            .agent_facility
            .product_events
            .emit_thread_mode_catalog(outcome.catalog.clone());
        let reply = ModeDefinitionCommandReply {
            catalog,
            definition: outcome.definition,
            receipt: self.command_receipt(
                operation_id,
                outcome.changed,
                vec![self.resource_stamp("thread-mode-catalog", outcome.catalog.revision)],
                CommandEffectPoint::NextTurn,
                true,
            ),
        };
        require_budget(&reply)?;
        Ok(reply)
    }
}
