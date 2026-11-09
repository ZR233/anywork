//! Shared skill selection and provider-neutral document access.
mod selection;
mod validation;
pub use selection::{SkillSelection, SkillSelectionRequest, SkillSelector};
use serde::{Deserialize, Serialize};
use std::{error::Error, future::Future};
use tokio_util::sync::CancellationToken;
pub use validation::{category_path, validate_document, validate_name};

pub trait SelectionCandidate {
    fn name(&self) -> &str;
    fn description(&self) -> &str;
    fn category(&self) -> Option<&str>;
    fn model_invocable(&self) -> bool;
}
#[derive(Debug, Clone)]
pub struct Listing {
    pub name: String,
    pub description: String,
    pub category: Option<String>,
    pub model_invocable: bool,
}
impl SelectionCandidate for Listing {
    fn name(&self) -> &str {
        &self.name
    }
    fn description(&self) -> &str {
        &self.description
    }
    fn category(&self) -> Option<&str> {
        self.category.as_deref()
    }
    fn model_invocable(&self) -> bool {
        self.model_invocable
    }
}

#[derive(Debug)]
pub struct Document<S, R> {
    pub name: String,
    pub summary: S,
    pub resource_base: R,
    pub content: String,
}
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ViewedSkill<S, R> {
    pub success: bool,
    pub skill: S,
    pub file_path: String,
    pub resource_base: R,
    pub resource_hint: String,
    pub content: String,
}
pub trait SkillReader: Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;
    type Summary: Send + Sync + std::fmt::Debug + 'static;
    type ResourceBase: Send + Sync + std::fmt::Debug + 'static;
    fn load(
        &self,
        name: &str,
        cancellation: CancellationToken,
    ) -> impl Future<Output = Result<Document<Self::Summary, Self::ResourceBase>, Self::Error>> + Send;
    fn read_resource(
        &self,
        name: &str,
        path: &str,
        cancellation: CancellationToken,
    ) -> impl Future<Output = Result<String, Self::Error>> + Send;
    fn record_view(
        &self,
        name: &str,
        cancellation: CancellationToken,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
}
pub fn is_main_skill_path(path: &str) -> bool {
    let normalized = path.trim().replace('\\', "/");
    let normalized = normalized.trim_start_matches("./");
    normalized.is_empty()
        || normalized == "."
        || normalized.eq_ignore_ascii_case(pl_skill_core::SKILL_FILE_NAME)
}
