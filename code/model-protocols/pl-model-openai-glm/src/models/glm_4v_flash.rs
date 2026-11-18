use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4v-flash",
    name: "GLM-4V-Flash",
    description: "Zhipu free image understanding model with multilingual support.",
    context: 16_000,
    max_output_tokens: Some(1_000),
    tiers: &[TokenPriceTier::flat(0.0, 0.0, Some(0.0), None)],
};
