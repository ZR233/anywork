//! Nested calls retain ordinary task, authorization, output and persistence ownership.
use super::*;

impl Owner {
    pub(super) async fn begin_nested(
        &mut self,
        caller: String,
        authority: crate::tool::opaque::ExecutionAuthority,
        tool_id: String,
        arguments: OpaquePayload,
        cancellation: CancellationToken,
    ) -> Result<String, ThreadError> {
        if !authority.may_call_nested() || !authority.remains_authorized(&self.tools) {
            return Err(ThreadError::ToolPermissionRevoked);
        }
        let parent = self
            .state
            .tasks
            .get(&caller)
            .filter(|task| task.status == task::TaskStatus::Running)
            .ok_or(ThreadError::TaskAccessExpired)?
            .clone();
        let scope = self
            .nested_plans
            .get(&caller)
            .ok_or(ThreadError::TaskAccessExpired)?;
        let executor = scope
            .plan
            .nested_get(&tool_id)
            .ok_or(ThreadError::ToolPermissionRevoked)?
            .clone();
        let context = scope.context.clone();
        let model_projection = scope.model_projection.clone();
        let invocations = scope.invocations.clone();
        if cancellation.is_cancelled() {
            return Err(ThreadError::ToolPermissionRevoked);
        }
        self.nested_sequence = self
            .nested_sequence
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        let id = format!("{}:nested:{}", parent.call_id, self.nested_sequence);
        self.await_storage_admission(&cancellation).await?;
        let operation = super::tool_execution::tool_output_operation(&id);
        self.reserve_operation_output(&operation, &cancellation)
            .await?;
        if !authority.remains_authorized(&self.tools)
            || cancellation.is_cancelled()
            || !self
                .state
                .tasks
                .get(&caller)
                .is_some_and(|task| task.status == task::TaskStatus::Running)
        {
            self.finish_operation_output(&operation);
            return Err(ThreadError::ToolPermissionRevoked);
        }
        self.pending.insert(
            id.clone(),
            PendingCall {
                context,
                model_projection,
                turn_id: parent.turn_id,
                call: crate::model::ModelToolCall {
                    call_id: id.clone(),
                    tool_id,
                    arguments,
                    presentation_contract: executor.declaration().presentation_contract.clone(),
                    rejection: None,
                },
                executor,
                parent_call_id: Some(parent.call_id),
                nested_plan: None,
            },
        );
        match self.begin_tool_execution(id.clone(), cancellation) {
            Ok(execution) => {
                invocations
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .push(id.clone());
                self.background.push(execution);
                Ok(id)
            }
            Err(error) => {
                self.pending.remove(&id);
                self.finish_operation_output(&operation);
                Err(error)
            }
        }
    }
}
