//! Original execution admission outcomes, bound to the immutable effective catalog members.
use pl_model::config::{AccountId, AccountModelEntry};
use pl_protocol::studio::StudioError;

use crate::StudioConfig;
use crate::studio::delegation::resolve_catalog_selection;

/// A detail's execution qualification, not descriptor availability or an editing suggestion.
/// The original resolved route is discarded; neither variant retains credentials or endpoints.
#[derive(PartialEq, Eq)]
pub(crate) enum ModelExecutionQualification {
    Available,
    Unavailable { reason: String },
}

impl ModelExecutionQualification {
    pub(crate) fn is_available(&self) -> bool {
        matches!(self, Self::Available)
    }

    pub(crate) fn unavailable_reason(&self) -> Option<&str> {
        match self {
            Self::Available => None,
            Self::Unavailable { reason } => Some(reason.as_str()),
        }
    }
}

#[derive(PartialEq, Eq)]
pub(super) struct AccountModelQualifications {
    account_id: AccountId,
    models: Vec<QualifiedModel>,
}

#[derive(PartialEq, Eq)]
struct QualifiedModel {
    model_id: String,
    qualification: ModelExecutionQualification,
}

impl AccountModelQualifications {
    /// Uses the same effective config and unfiltered entries as the original exact detail.
    /// A candidate rejection is a member fact, not failure of the entire Models capture.
    pub(super) fn capture(
        config: &StudioConfig,
        account_id: &AccountId,
        entries: &[AccountModelEntry],
    ) -> Self {
        let models = entries
            .iter()
            .map(|entry| QualifiedModel {
                model_id: entry.model.model_id.clone(),
                qualification: match resolve_catalog_selection(config, account_id, entry) {
                    Ok(_) => ModelExecutionQualification::Available,
                    Err(error) => ModelExecutionQualification::Unavailable {
                        reason: error.to_string(),
                    },
                },
            })
            .collect();
        Self {
            account_id: account_id.clone(),
            models,
        }
    }

    pub(super) fn account_id(&self) -> &str {
        self.account_id.as_str()
    }

    pub(super) fn model(
        &self,
        model_id: &str,
    ) -> Result<&ModelExecutionQualification, StudioError> {
        self.models
            .iter()
            .find(|model| model.model_id == model_id)
            .map(|model| &model.qualification)
            .ok_or_else(|| StudioError::not_found("Current account model"))
    }
}
