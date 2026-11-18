use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.6v-flash",
    name: "GLM-4.6V-Flash",
    description: "Zhipu free visual reasoning model with tool calling.",
    context: 128_000,
    max_output_tokens: Some(32_000),
    tiers: &[TokenPriceTier::flat(0.0, 0.0, Some(0.0), None)],
};
