use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4-flash-250414",
    name: "GLM-4-Flash-250414",
    description: "Zhipu free GLM-4 Flash model for long-context multilingual tool use.",
    context: 128_000,
    max_output_tokens: Some(16_000),
    tiers: &[TokenPriceTier::flat(0.0, 0.0, Some(0.0), None)],
};
