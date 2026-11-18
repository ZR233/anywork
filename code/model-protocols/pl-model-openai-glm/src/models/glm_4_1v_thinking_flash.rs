use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.1v-thinking-flash",
    name: "GLM-4.1V-Thinking-Flash",
    description: "Zhipu free visual reasoning model for multi-step analysis.",
    context: 64_000,
    max_output_tokens: Some(16_000),
    tiers: &[TokenPriceTier::flat(0.0, 0.0, Some(0.0), None)],
};
