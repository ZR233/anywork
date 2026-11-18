//! Idle qualification and staging for host-owned application changes.
use super::*;

impl Owner {
    pub(super) fn ensure_idle(&self) -> Result<(), ThreadError> {
        if self.current_task_start_ordinal.is_some() && self.current_model_running {
            return Err(ThreadError::InputRequiresIdle);
        }
        // A newly loaded current has pending logical work but owns no executing resources. The
        // host can bind its fresh services while user-authorized resume remains separately gated.
        if self.current_saved_lifecycle.is_some() && !self.interrupt.is_closing() {
            return Ok(());
        }
        if !self.active_inputs.is_empty()
            || self
                .state
                .turns
                .iter()
                .any(|turn| turn.state == TurnState::Running)
            || self
                .state
                .inputs
                .iter()
                .any(|input| input.state == input::InputState::Pending)
            || self
                .state
                .tasks
                .values()
                .any(|task| task.status == task::TaskStatus::Running)
            || !self.pending.is_empty()
        {
            return Err(ThreadError::InputRequiresIdle);
        }
        if self
            .state
            .interactions
            .values()
            .any(|record| record.state == interactions::InteractionState::Pending)
            || self
                .state
                .permissions
                .values()
                .any(|record| matches!(record.state, permissions::PermissionState::Pending))
        {
            return Err(ThreadError::PendingInteraction);
        }
        Ok(())
    }

    pub(super) fn stage_reconfiguration(
        &self,
        candidate: &mut ThreadSnapshot,
        update: extensions::ApplicationUpdate,
        context: Option<ReplaceContext>,
        fact_changes: Vec<RuntimeFact>,
    ) -> Result<(), ThreadError> {
        extensions::stage_extensions(candidate, update.mutations)?;
        facts::stage_facts(candidate, update.facts)?;
        if !fact_changes.is_empty() {
            facts::stage_fact_changes(candidate, fact_changes)?;
        }
        if let Some(mut replacement) = context {
            if replacement.expected_revision != self.state.context.revision {
                return Err(ThreadError::ContextConflict {
                    expected: replacement.expected_revision,
                    actual: self.state.context.revision,
                });
            }
            candidate.context = self.state.context.clone();
            replacement.expected_revision = candidate.context.revision;
            replacement::stage_replacement(candidate, replacement)?;
        }
        Ok(())
    }
}
