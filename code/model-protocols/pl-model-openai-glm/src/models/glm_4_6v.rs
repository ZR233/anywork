use super::{Definition, TokenPriceTier, context_tiers};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.6v",
    name: "GLM-4.6V",
    description: "Zhipu visual reasoning model with native tool calling.",
    context: 128_000,
    max_output_tokens: Some(32_000),
    tiers: &context_tiers(
        TokenPriceTier::flat(1.0, 3.0, Some(0.2), None),
        TokenPriceTier::flat(2.0, 6.0, Some(0.4), None),
    ),
};
