//! Start's original edit/overlay semantics over one issued configuration/catalog pair.
use pl_protocol::products::models::{AccountModelKey, ModelSelection};
use pl_protocol::studio::{StudioError, StudioErrorCode};

use super::{RoleRouteRead, StartRouteIntent, StartRouteQuery, StartRouteRead};
use crate::config::ConfigurationPair;

impl ConfigurationPair {
    pub(super) fn role_route(&self, role_id: &str) -> Result<RoleRouteRead, StudioError> {
        if let Some(route) = self
            .configuration
            .value
            .roles
            .iter()
            .find(|route| route.key == role_id)
        {
            // Configured empty or unknown efforts remain configured; existence is not eligibility.
            return Ok(RoleRouteRead::Configured {
                route: route.clone(),
            });
        }
        Ok(RoleRouteRead::Missing {
            suggestion: self.models.first_text_model()?,
        })
    }

    pub(super) fn start_route(
        &self,
        query: StartRouteQuery,
    ) -> Result<StartRouteRead, StudioError> {
        let mut intent = match &query {
            StartRouteQuery::Resolve { intent } | StartRouteQuery::SelectModel { intent, .. } => {
                intent.clone()
            }
        };
        let base = self.base(&intent);
        if let StartRouteQuery::SelectModel { selected, .. } = &query {
            let previous = intent
                .model
                .as_ref()
                .or_else(|| base.as_ref().map(|route| &route.model));
            if previous != Some(selected) {
                // This is the original Models editing suggestion, not an enabled/text admission
                // check. A known disabled member still has its original canonical effort policy.
                intent.effort = match self.models.effort_after_model_selection(
                    &selected.account_id,
                    &selected.model_id,
                    None,
                ) {
                    Ok(effort) => effort.filter(|value| !value.is_empty()),
                    Err(error) if error.code == StudioErrorCode::NotFound => None,
                    Err(error) => return Err(error),
                };
            }
            intent.model = Some(selected.clone());
        }
        let desired = self.overlay(&intent, base.as_ref());
        let defaults = self.configuration.value.delegation;
        let unavailable = |intent, desired, error| StartRouteRead::Unavailable {
            sources: self.target.clone(),
            query: query.clone(),
            intent,
            desired,
            defaults,
            error,
        };
        let Some(mut route) = desired else {
            return Ok(unavailable(
                intent,
                None,
                StudioError::new(
                    StudioErrorCode::Unavailable,
                    "The original configuration has no complete Start model route",
                    false,
                ),
            ));
        };
        if route.effort.as_ref().is_none_or(String::is_empty) {
            match self.models.effort_after_model_selection(
                &route.model.account_id,
                &route.model.model_id,
                None,
            ) {
                Ok(effort) => route.effort = effort,
                Err(error) if error.code == StudioErrorCode::NotFound => {
                    return Ok(unavailable(intent, Some(route), error));
                }
                Err(error) => return Err(error),
            }
        }
        if let Err(error) = self.available(&route.model) {
            return Ok(unavailable(intent, Some(route), error));
        }
        // Nonempty effort is deliberately not normalized or strictly validated here. The original
        // creation command remains the sole route validator and mode admission boundary.
        Ok(StartRouteRead::Ready {
            sources: self.target.clone(),
            query,
            intent,
            route,
            defaults,
        })
    }

    fn base(&self, intent: &StartRouteIntent) -> Option<ModelSelection> {
        let routes = &self.configuration.value.mode_model_routes;
        let route = routes
            .iter()
            .find(|route| route.mode_id == intent.mode.as_str())
            .or_else(|| {
                routes
                    .iter()
                    .find(|route| route.mode_id == pl_protocol::ThreadModeId::simple().as_str())
            })?;
        Some(ModelSelection {
            model: AccountModelKey {
                account_id: route.account_id.clone(),
                model_id: route.model_id.clone(),
            },
            effort: (!route.effort.is_empty()).then(|| route.effort.clone()),
        })
    }

    fn overlay(
        &self,
        intent: &StartRouteIntent,
        base: Option<&ModelSelection>,
    ) -> Option<ModelSelection> {
        let model = intent
            .model
            .as_ref()
            .filter(|model| complete(model))
            .or_else(|| base.map(|route| &route.model))
            .filter(|model| complete(model))?
            .clone();
        let effort = intent
            .effort
            .clone()
            .filter(|value| !value.is_empty())
            .or_else(|| {
                base.filter(|route| route.model == model)
                    .and_then(|route| route.effort.clone())
                    .filter(|value| !value.is_empty())
            });
        Some(ModelSelection { model, effort })
    }

    fn available(&self, model: &AccountModelKey) -> Result<(), StudioError> {
        let account = self
            .models
            .value()
            .accounts
            .iter()
            .find(|account| account.account_id == model.account_id)
            .ok_or_else(|| StudioError::not_found("Start model account"))?;
        let model = account
            .effective_models
            .iter()
            .find(|entry| entry.model_id == model.model_id)
            .ok_or_else(|| StudioError::not_found("Start model"))?;
        if !model.enabled {
            return Err(StudioError::new(
                StudioErrorCode::Unavailable,
                "The original Start model is disabled",
                false,
            ));
        }
        Ok(())
    }
}

fn complete(model: &AccountModelKey) -> bool {
    !model.account_id.is_empty() && !model.model_id.is_empty()
}
