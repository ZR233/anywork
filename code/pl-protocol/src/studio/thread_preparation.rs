//! Transient progress of one root Thread creation; never a persisted Thread fact.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ThreadPreparationStage {
    CheckingProject,
    PreparingWorkspace,
    ResolvingRepository,
    CreatingWorktree,
    InitializingSession,
    SubmittingPrompt,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ThreadPreparationProgress {
    pub project_id: String,
    pub input_id: String,
    pub stage: ThreadPreparationStage,
    pub workspace_path: Option<String>,
    pub branch: Option<String>,
}
