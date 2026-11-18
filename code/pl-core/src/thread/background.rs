//! Background ownership and immutable result delivery through the Thread inbox.
use super::*;

impl Owner {
    pub(super) fn acknowledge_task(
        &mut self,
        call_id: &str,
    ) -> Result<task::TaskRecord, ThreadError> {
        let mut task = self
            .state
            .tasks
            .get(&format!("task:{call_id}"))
            .cloned()
            .ok_or(ThreadError::InvalidIdentity)?;
        if task.acknowledgement.is_some() || task.status != task::TaskStatus::Running {
            return Err(ThreadError::InvalidIdentity);
        }
        let revision = self
            .state
            .context
            .revision
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        let id = unique_id(
            "task-receipt",
            self.state
                .context
                .records
                .iter()
                .map(|record| record.id.as_str()),
        )?;
        let content = vec![ContextContent::Text {
            text: Arc::from(
                serde_json::json!({
                    "taskId": task.id,
                    "toolName": task.tool_id,
                    "status": task.status,
                })
                .to_string(),
            ),
        }];
        let mut context = self.state.context.clone();
        current::pair_known_call_result(
            &mut context,
            ContextRecord {
                id: id.clone(),
                turn_id: Some(task.turn_id.clone()),
                source: ContextSource::ToolResult {
                    call_id: task.call_id.clone(),
                    tool_id: task.tool_id.clone(),
                },
                content,
                tool_calls: Vec::new(),
            },
        )
        .map_err(|error| ThreadError::CurrentResume(Arc::new(error)))?;
        context.pending_calls()?;
        task.revision = task
            .revision
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        task.acknowledgement = Some(task::TaskAcknowledgement {
            record_id: id,
            context_revision: revision,
        });
        self.state.context = context;
        task::record_change(&mut self.state, task.clone());
        // The task receipt belongs to the still-running call whose reliable output ceiling funds it.
        self.claim_output(task.id.clone());
        self.publish()?;
        Ok(task)
    }

    pub(super) fn finish_background(
        &mut self,
        completion: super::tool_execution::ToolExecutionCompletion,
    ) {
        let id = completion.call.call.call_id.clone();
        let result = self.commit_tool_execution(completion);
        if let Some(run) = self.active.as_mut()
            && let super::execution::RunPhase::ToolBatch(batch) = &mut run.phase
        {
            let belongs_to_batch = batch.waiting.remove(&id);
            if belongs_to_batch
                && let Ok(output) = &result
                && output.control() != crate::tool::ToolControl::Continue
            {
                batch.control = Some(output.control());
            }
        }
        if let Some(super::execution::ToolWaiter { reply, .. }) = self.tool_waiters.remove(&id) {
            let _ = reply.send(result.map(ToolDispatch::Completed));
            return;
        }
        if let Some(reply) = self.nested_replies.remove(&id) {
            let _ = reply.send(result);
            return;
        }
        if let Err(error) = result
            && !matches!(error, ThreadError::Tool(_) | ThreadError::Cancelled)
        {
            tracing::error!(thread = self.id, %error, "background result commit failed");
        }
    }
}

pub(super) fn append_result_message(
    state: &mut ThreadSnapshot,
    task: &task::TaskRecord,
    output: &crate::tool::ToolOutput,
    context: Vec<ContextContent>,
) -> Result<String, ThreadError> {
    // The bounded identity ledger is not an allocator: old IDs remain durable after pruning.
    // This owner performs identity selection and admission synchronously, so both use the same
    // checkpointed sequence. Legacy gap-based IDs are smaller than their admission sequence.
    let id = format!("task-result:{}", inbox::next_sequence(state)?);
    let message = inbox::ThreadMessage {
        kind: crate::context::AgentMessageKind::Report,
        id: id.clone(),
        source_id: task.id.clone(),
        payload: output.payload().clone(),
        context,
    };
    inbox::admit_message(state, message)?;
    Ok(id)
}

pub(super) fn result_context(
    task: &task::TaskRecord,
    status: task::TaskStatus,
    mut content: Vec<ContextContent>,
) -> Vec<ContextContent> {
    content.insert(
        0,
        ContextContent::Text {
            text: Arc::from(format!(
                "Task {} for tool {} finished: {status:?}.",
                task.id, task.tool_id
            )),
        },
    );
    content
}

pub(super) fn unique_id<'a>(
    prefix: &str,
    existing: impl Iterator<Item = &'a str>,
) -> Result<String, ThreadError> {
    let existing = existing.collect::<std::collections::BTreeSet<_>>();
    (0..=existing.len())
        .map(|index| format!("{prefix}:{index}"))
        .find(|candidate| !existing.contains(candidate.as_str()))
        .ok_or(ThreadError::InvalidIdentity)
}
