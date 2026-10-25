//! Selection queries over complete immutable Models material, not current Configuration reads.
use anyhow::Result;
use pl_model::model::{ModelParameter, ModelType};
use pl_protocol::products::models::{AccountModelKey, ModelSelection};
use pl_protocol::studio::{StudioError, StudioErrorCode};

use crate::ConfigRuntimeSnapshot;

/// The read owner's policy material. It retains only model identity, original validated effort
/// declarations and Rust text eligibility: no credentials, routes, mutable owner or IO handle.
pub(super) struct ModelSelectionMaterial {
    accounts: Vec<AccountModels>,
}

struct AccountModels {
    account_id: String,
    models: Vec<SelectableModel>,
}

struct SelectableModel {
    model_id: String,
    effort: Option<ModelParameter>,
    text_supported: bool,
}

impl ModelSelectionMaterial {
    pub(super) fn same_policy(&self, other: &Self) -> bool {
        self.accounts.len() == other.accounts.len()
            && self
                .accounts
                .iter()
                .zip(&other.accounts)
                .all(|(left, right)| left.same_policy(right))
    }

    pub(super) fn same_account_policy(
        &self,
        index: usize,
        other: &Self,
        other_index: usize,
    ) -> bool {
        match (self.accounts.get(index), other.accounts.get(other_index)) {
            (Some(left), Some(right)) => left.same_policy(right),
            _ => false,
        }
    }

    /// Called with the Models source's original coherent capture. This function never reads a
    /// runtime owner, discovers models or writes configuration; all account/model order is kept.
    pub(super) fn capture(snapshot: &ConfigRuntimeSnapshot) -> Result<Self> {
        let mut accounts = Vec::with_capacity(snapshot.config.models.accounts.len());
        for (id, account) in &snapshot.config.models.accounts {
            let mut models = Vec::new();
            for entry in account.effective_catalog(None)? {
                models.push(SelectableModel {
                    text_supported: entry.enabled
                        && entry.type_support(ModelType::Text).exclusions.is_empty(),
                    effort: entry.model.effort_parameter().cloned(),
                    model_id: entry.model.model_id,
                });
            }
            accounts.push(AccountModels {
                account_id: id.to_string(),
                models,
            });
        }
        Ok(Self { accounts })
    }

    pub(super) fn effort_after_model_selection(
        &self,
        account_id: &str,
        model_id: &str,
        candidate: Option<&str>,
    ) -> Result<Option<String>, StudioError> {
        let account = self
            .accounts
            .iter()
            .find(|account| account.account_id == account_id)
            .ok_or_else(|| StudioError::not_found("Account"))?;
        let model = account
            .models
            .iter()
            .find(|model| model.model_id == model_id)
            .ok_or_else(|| StudioError::not_found("Model"))?;
        model.suggest_effort(candidate)
    }

    pub(super) fn first_text_model(&self) -> Result<Option<ModelSelection>, StudioError> {
        for account in &self.accounts {
            if account.account_id.is_empty() {
                continue;
            }
            for model in &account.models {
                if model.model_id.is_empty() || !model.text_supported {
                    continue;
                }
                return Ok(Some(ModelSelection {
                    model: AccountModelKey {
                        account_id: account.account_id.clone(),
                        model_id: model.model_id.clone(),
                    },
                    effort: model.suggest_effort(None)?,
                }));
            }
        }
        Ok(None)
    }
}

impl AccountModels {
    fn same_policy(&self, other: &Self) -> bool {
        self.account_id == other.account_id
            && self.models.len() == other.models.len()
            && self.models.iter().zip(&other.models).all(|(left, right)| {
                left.model_id == right.model_id
                    && left.text_supported == right.text_supported
                    && match (&left.effort, &right.effort) {
                        (None, None) => true,
                        (Some(left), Some(right)) => {
                            left.candidates == right.candidates
                                && left.default_candidate(None) == right.default_candidate(None)
                        }
                        _ => false,
                    }
            })
    }
}

impl SelectableModel {
    fn suggest_effort(&self, candidate: Option<&str>) -> Result<Option<String>, StudioError> {
        let Some(parameter) = &self.effort else {
            return Ok(None);
        };
        // This is the original editing suggestion rule, not strict resolve_candidate and not a
        // second implementation of candidate/default/declaration-order precedence.
        parameter
            .default_candidate(candidate)
            .map(Some)
            .ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Protocol,
                    "A validated model effort declaration has no candidate",
                    false,
                )
            })
    }
}
