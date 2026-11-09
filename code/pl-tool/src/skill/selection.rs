pub use pl_tool_skill::support::{SkillSelection, SkillSelectionRequest, SkillSelector};

impl pl_tool_skill::support::SelectionCandidate for super::SkillMetadata {
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
        self.invocation.model_invocable
    }
}
