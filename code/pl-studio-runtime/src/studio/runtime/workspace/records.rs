use pl_protocol::products::read::workspace::*;
use pl_protocol::products::source::SourceStateErrorRead;
use pl_protocol::studio::{NewThreadModelRoute, StudioError};
use pl_protocol::{AgentState, StateError};

use super::material::RecordText;
use super::source::{DirectoryRows, DirectorySnapshot};

impl DirectorySnapshot {
    pub(super) fn record_text(&self, index: usize, field: RecordText) -> Result<&str, StudioError> {
        use RecordText::*;
        if index >= self.capture.rows.len() {
            return Err(super::wrong_field());
        }
        if matches!(field, AccountId | ModelId | Effort) {
            let model = self.frozen_model(index)?.ok_or_else(super::wrong_field)?;
            return match field {
                AccountId => Ok(&model.account_id),
                ModelId => Ok(&model.model_id),
                Effort => model.effort.as_deref().ok_or_else(super::wrong_field),
                _ => Err(super::wrong_field()),
            };
        }
        match &self.capture.rows {
            DirectoryRows::Projects(rows) => {
                let row = &rows[index];
                match field {
                    Id => Ok(&row.id),
                    Name => Ok(&row.name),
                    Path => Ok(&row.path),
                    SshAlias => row.ssh_alias.as_deref().ok_or_else(super::wrong_field),
                    _ => Err(super::wrong_field()),
                }
            }
            DirectoryRows::Threads(rows) => {
                let row = &rows[index];
                match field {
                    Id => Ok(&row.id),
                    ProjectId => Ok(&row.project_id),
                    Title => Ok(&row.title),
                    Mode => Ok(row.mode.as_str()),
                    WorkspacePath => Ok(&row.workspace_path),
                    RootThreadId => Ok(&row.root_thread_id),
                    ParentThreadId => row
                        .parent_thread_id
                        .as_deref()
                        .ok_or_else(super::wrong_field),
                    Role => Ok(&row.role),
                    AgentPath => Ok(&row.agent_path),
                    _ => Err(super::wrong_field()),
                }
            }
            DirectoryRows::Agents(rows) => {
                let row = &rows[index];
                match field {
                    Id => Ok(&row.id),
                    ThreadId => Ok(&row.thread_id),
                    RootThreadId => Ok(&row.root_thread_id),
                    Path => Ok(&row.path),
                    ParentPath => row.parent_path.as_deref().ok_or_else(super::wrong_field),
                    Role => Ok(&row.role),
                    Task => Ok(&row.task),
                    Summary => row.summary.as_deref().ok_or_else(super::wrong_field),
                    TurnId => match &row.state {
                        AgentState::Idle(state) => state
                            .budget_pause()
                            .map(|pause| pause.turn_id().as_str())
                            .ok_or_else(super::wrong_field),
                        state => state
                            .turn_id()
                            .map(|id| id.as_str())
                            .ok_or_else(super::wrong_field),
                    },
                    InteractionId => match &row.state {
                        AgentState::WaitingInteraction(state) => Ok(state.interaction_id()),
                        _ => Err(super::wrong_field()),
                    },
                    ErrorCode => self
                        .agent_error(index)
                        .map(|error| error.code.as_str())
                        .ok_or_else(super::wrong_field),
                    ErrorMessage => self
                        .agent_error(index)
                        .map(|error| error.message.as_str())
                        .ok_or_else(super::wrong_field),
                    _ => Err(super::wrong_field()),
                }
            }
        }
    }

    pub(super) fn project_record(
        &self,
        index: usize,
        inline: usize,
    ) -> Result<ProjectRecordRead, StudioError> {
        let DirectoryRows::Projects(rows) = &self.capture.rows else {
            return Err(super::wrong_field());
        };
        let row = rows.get(index).ok_or_else(super::wrong_field)?;
        let text = |field| self.read_text(index, field, inline);
        Ok(ProjectRecordRead {
            id: text(RecordText::Id)?,
            name: text(RecordText::Name)?,
            path: text(RecordText::Path)?,
            ssh_alias: row
                .ssh_alias
                .as_ref()
                .map(|_| text(RecordText::SshAlias))
                .transpose()?,
            updated_at: row.updated_at,
        })
    }

    pub(super) fn thread_record(
        &self,
        index: usize,
        inline: usize,
    ) -> Result<WorkspaceThreadRecordRead, StudioError> {
        let DirectoryRows::Threads(rows) = &self.capture.rows else {
            return Err(super::wrong_field());
        };
        let row = rows.get(index).ok_or_else(super::wrong_field)?;
        let text = |field| self.read_text(index, field, inline);
        Ok(WorkspaceThreadRecordRead {
            id: text(RecordText::Id)?,
            project_id: text(RecordText::ProjectId)?,
            title: text(RecordText::Title)?,
            mode: text(RecordText::Mode)?,
            workspace_mode: row.workspace_mode,
            delegation_mode: row.delegation_mode,
            delegation_preference: row.delegation_preference,
            frozen_model: self.frozen_model_read(index, inline)?,
            workspace_path: text(RecordText::WorkspacePath)?,
            root_thread_id: text(RecordText::RootThreadId)?,
            parent_thread_id: row
                .parent_thread_id
                .as_ref()
                .map(|_| text(RecordText::ParentThreadId))
                .transpose()?,
            role: text(RecordText::Role)?,
            agent_path: text(RecordText::AgentPath)?,
            status: row.status,
            created_at: row.created_at,
            updated_at: row.updated_at,
            last_user_message_at: row.last_user_message_at,
            archived: row.archived,
        })
    }

    pub(super) fn agent_record(
        &self,
        index: usize,
        inline: usize,
    ) -> Result<AgentDirectoryEntryRead, StudioError> {
        let DirectoryRows::Agents(rows) = &self.capture.rows else {
            return Err(super::wrong_field());
        };
        let row = rows.get(index).ok_or_else(super::wrong_field)?;
        let text = |field| self.read_text(index, field, inline);
        Ok(AgentDirectoryEntryRead {
            id: text(RecordText::Id)?,
            thread_id: text(RecordText::ThreadId)?,
            root_thread_id: text(RecordText::RootThreadId)?,
            path: text(RecordText::Path)?,
            parent_path: row
                .parent_path
                .as_ref()
                .map(|_| text(RecordText::ParentPath))
                .transpose()?,
            role: text(RecordText::Role)?,
            task: text(RecordText::Task)?,
            summary: row
                .summary
                .as_ref()
                .map(|_| text(RecordText::Summary))
                .transpose()?,
            delegation_mode: row.delegation_mode,
            delegation_preference: row.delegation_preference,
            frozen_model: self.frozen_model_read(index, inline)?,
            depth: row.depth,
            state: self.agent_state(index, inline)?,
            execution: row.execution.clone(),
            can_stop: row.can_stop,
            awaiting_scheduling: row.awaiting_scheduling,
            updated_at: row.updated_at,
        })
    }

    fn frozen_model(&self, index: usize) -> Result<Option<&NewThreadModelRoute>, StudioError> {
        match &self.capture.rows {
            DirectoryRows::Threads(rows) => Ok(rows
                .get(index)
                .ok_or_else(super::wrong_field)?
                .frozen_model
                .as_ref()),
            DirectoryRows::Agents(rows) => Ok(rows
                .get(index)
                .ok_or_else(super::wrong_field)?
                .frozen_model
                .as_ref()),
            DirectoryRows::Projects(_) => Err(super::wrong_field()),
        }
    }
    fn frozen_model_read(
        &self,
        index: usize,
        inline: usize,
    ) -> Result<Option<FrozenModelSelectionRead>, StudioError> {
        self.frozen_model(index)?
            .map(|model| {
                Ok(FrozenModelSelectionRead {
                    account_id: self.read_text(index, RecordText::AccountId, inline)?,
                    model_id: self.read_text(index, RecordText::ModelId, inline)?,
                    effort: model
                        .effort
                        .as_ref()
                        .map(|_| self.read_text(index, RecordText::Effort, inline))
                        .transpose()?,
                })
            })
            .transpose()
    }
    fn agent_error(&self, index: usize) -> Option<&StateError> {
        let DirectoryRows::Agents(rows) = &self.capture.rows else {
            return None;
        };
        match &rows.get(index)?.state {
            AgentState::Closing(state) => state.error(),
            AgentState::Faulted(state) => Some(state.error()),
            _ => None,
        }
    }
    fn agent_state(&self, index: usize, inline: usize) -> Result<AgentStateRead, StudioError> {
        let DirectoryRows::Agents(rows) = &self.capture.rows else {
            return Err(super::wrong_field());
        };
        let row = rows.get(index).ok_or_else(super::wrong_field)?;
        let text = |field| self.read_text(index, field, inline);
        let error = |error: &StateError| -> Result<SourceStateErrorRead, StudioError> {
            Ok(SourceStateErrorRead {
                code: text(RecordText::ErrorCode)?,
                message: text(RecordText::ErrorMessage)?,
                retryable: error.retryable,
            })
        };
        Ok(match &row.state {
            AgentState::Idle(state) => AgentStateRead::Idle {
                budget_pause: state
                    .budget_pause()
                    .map(|pause| -> Result<AgentBudgetPauseRead, StudioError> {
                        Ok(AgentBudgetPauseRead {
                            turn_id: text(RecordText::TurnId)?,
                            limit: *pause.limit(),
                            paused_at: pause.paused_at(),
                        })
                    })
                    .transpose()?,
            },
            AgentState::Queued(_) => AgentStateRead::Queued {
                turn_id: text(RecordText::TurnId)?,
            },
            AgentState::Running(_) => AgentStateRead::Running {
                turn_id: text(RecordText::TurnId)?,
            },
            AgentState::WaitingTool(_) => AgentStateRead::WaitingTool {
                turn_id: text(RecordText::TurnId)?,
            },
            AgentState::WaitingInteraction(_) => AgentStateRead::WaitingInteraction {
                turn_id: text(RecordText::TurnId)?,
                interaction_id: text(RecordText::InteractionId)?,
            },
            AgentState::Cancelling(_) => AgentStateRead::Cancelling {
                turn_id: text(RecordText::TurnId)?,
            },
            AgentState::Closing(state) => AgentStateRead::Closing {
                workspace_disposition: state.workspace_disposition(),
                turn_id: state
                    .turn_id()
                    .map(|_| text(RecordText::TurnId))
                    .transpose()?,
                error: state.error().map(error).transpose()?,
            },
            AgentState::Closed(_) => AgentStateRead::Closed,
            AgentState::Faulted(state) => AgentStateRead::Faulted {
                error: error(state.error())?,
                turn_id: state
                    .turn_id()
                    .map(|_| text(RecordText::TurnId))
                    .transpose()?,
                classification: state.classification(),
            },
        })
    }
}
