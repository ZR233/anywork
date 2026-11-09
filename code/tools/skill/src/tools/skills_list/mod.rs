//! Skill querying over a host-frozen catalog.
use crate::support::{Listing, SkillSelectionRequest, SkillSelector};
use pl_agent_tool::typed::TypedTool;
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Args {
    /// Optional category filter.
    pub category: Option<String>,
    /// Optional natural-language name and description query.
    pub query: Option<String>,
    /// Maximum query results. Defaults to 10 and must be between 1 and 50.
    pub limit: Option<usize>,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillSummary {
    pub name: String,
    pub description: String,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Output {
    pub success: bool,
    pub count: usize,
    pub truncated: bool,
    pub skills: Vec<SkillSummary>,
}
#[derive(Debug, thiserror::Error)]
#[error("limit must be between 1 and 50")]
pub struct InvalidLimit;
#[derive(Debug)]
pub struct SkillsList {
    catalog: Vec<Listing>,
}
impl SkillsList {
    pub fn new(catalog: Vec<Listing>) -> Self {
        Self { catalog }
    }
}
impl TypedTool for SkillsList {
    const NAME: &'static str = "skills_list";
    const DESCRIPTION: &'static str =
        "List or search available skill names and descriptions before loading one by exact name.";
    type Args = Args;
    type Context = ();
    type Output = Output;
    type Error = InvalidLimit;
    async fn execute(&self, input: Args, _: ()) -> Result<Output, InvalidLimit> {
        let query = input
            .query
            .as_deref()
            .map(str::trim)
            .filter(|query| !query.is_empty());
        let (selected, truncated) = if let Some(query) = query {
            let limit = input.limit.unwrap_or(10);
            if !(1..=50).contains(&limit) {
                return Err(InvalidLimit);
            }
            let selection = SkillSelector.select(
                &self.catalog,
                SkillSelectionRequest {
                    query,
                    limit,
                    category: input.category.as_deref(),
                    excluded_names: &[],
                    model_invocable_only: true,
                },
            );
            let truncated = selection.truncated();
            (selection.matches, truncated)
        } else {
            let mut skills: Vec<_> = self
                .catalog
                .iter()
                .filter(|skill| skill.model_invocable)
                .filter(|skill| {
                    input.category.as_deref().is_none_or(|category| {
                        skill
                            .category
                            .as_deref()
                            .is_some_and(|value| value.eq_ignore_ascii_case(category))
                    })
                })
                .collect();
            skills.sort_by(|left, right| {
                left.name
                    .to_ascii_lowercase()
                    .cmp(&right.name.to_ascii_lowercase())
                    .then_with(|| left.name.cmp(&right.name))
            });
            (skills, false)
        };
        let skills: Vec<_> = selected
            .into_iter()
            .map(|skill| SkillSummary {
                name: skill.name.clone(),
                description: skill.description.clone(),
            })
            .collect();
        Ok(Output {
            success: true,
            count: skills.len(),
            truncated,
            skills,
        })
    }
}
