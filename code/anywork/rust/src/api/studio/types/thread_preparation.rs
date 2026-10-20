use serde::{Deserialize, Serialize};

use super::{BridgeError, BridgeStudioPromptInput, StartNewThreadResponse};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeStartNewThreadRequest {
    pub project_id: String,
    pub input: BridgeStudioPromptInput,
    pub mode: String,
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
    pub workspace_mode: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeThreadPreparationStage {
    CheckingProject,
    PreparingWorkspace,
    ResolvingRepository,
    CreatingWorktree,
    InitializingSession,
    SubmittingPrompt,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeThreadPreparationProgress {
    pub project_id: String,
    pub input_id: String,
    pub stage: BridgeThreadPreparationStage,
    pub workspace_path: Option<String>,
    pub branch: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", tag = "kind", content = "value")]
pub enum BridgeNewThreadStartEvent {
    Progress(BridgeThreadPreparationProgress),
    Succeeded(Box<StartNewThreadResponse>),
    Failed(BridgeError),
}

impl From<pl_protocol::studio::ThreadPreparationProgress> for BridgeThreadPreparationProgress {
    fn from(progress: pl_protocol::studio::ThreadPreparationProgress) -> Self {
        use pl_protocol::studio::ThreadPreparationStage;
        Self {
            project_id: progress.project_id,
            input_id: progress.input_id,
            stage: match progress.stage {
                ThreadPreparationStage::CheckingProject => {
                    BridgeThreadPreparationStage::CheckingProject
                }
                ThreadPreparationStage::PreparingWorkspace => {
                    BridgeThreadPreparationStage::PreparingWorkspace
                }
                ThreadPreparationStage::ResolvingRepository => {
                    BridgeThreadPreparationStage::ResolvingRepository
                }
                ThreadPreparationStage::CreatingWorktree => {
                    BridgeThreadPreparationStage::CreatingWorktree
                }
                ThreadPreparationStage::InitializingSession => {
                    BridgeThreadPreparationStage::InitializingSession
                }
                ThreadPreparationStage::SubmittingPrompt => {
                    BridgeThreadPreparationStage::SubmittingPrompt
                }
            },
            workspace_path: progress.workspace_path,
            branch: progress.branch,
        }
    }
}
