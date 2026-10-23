use super::labels::thread_mode_from_label;
use super::store_error;
use crate::PureError;
use crate::studio::entity::thread;
use crate::studio::records::DirectoryState;
use pl_protocol::LabeledEnum;
use pl_protocol::Thread as ThreadRecord;

impl TryFrom<thread::Model> for ThreadRecord {
    type Error = PureError;

    fn try_from(model: thread::Model) -> Result<Self, Self::Error> {
        let state: DirectoryState = serde_json::from_str(&model.state_json)?;
        if state.kind_label() != model.state_kind {
            return Err(store_error(format!(
                "Agent state discriminator mismatch: JSON is {}, generated column is {}",
                state.kind_label(),
                model.state_kind
            )));
        }
        let status = if model.parent_thread_id.is_some() {
            crate::studio::agent_close::directory_status(state.kind, model.explicitly_closed != 0)
        } else {
            state.kind
        };
        Ok(Self {
            id: model.id,
            project_id: model.project_id,
            title: model.title,
            mode: thread_mode_from_label(&model.mode)?,
            workspace_mode: pl_protocol::ThreadWorkspaceMode::from_label(&model.workspace_mode)
                .map_err(|error| store_error(error.to_string()))?,
            workspace_path: model.workspace_path,
            delegation_mode: pl_protocol::DelegationMode::from_label(&model.delegation_mode)
                .map_err(|error| store_error(error.to_string()))?,
            delegation_preference: pl_protocol::DelegationPreference::from_label(
                &model.delegation_preference,
            )
            .map_err(|error| store_error(error.to_string()))?,
            frozen_model: model
                .frozen_model_json
                .as_deref()
                .map(serde_json::from_str)
                .transpose()?,
            root_thread_id: model.root_thread_id,
            parent_thread_id: model.parent_thread_id,
            role: model.role,
            agent_path: model.agent_path,
            status,
            created_at: model.created_at,
            updated_at: model.updated_at,
            last_user_message_at: model.last_user_message_at,
            archived: model.archived != 0,
        })
    }
}
