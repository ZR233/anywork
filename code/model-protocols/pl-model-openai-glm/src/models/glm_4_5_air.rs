use super::{Definition, TokenPriceTier, context_output_tiers};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.5-air",
    name: "GLM-4.5-Air",
    description: "Zhipu cost-effective model for reasoning, coding, and agent tasks.",
    context: 128_000,
    max_output_tokens: Some(96_000),
    tiers: &context_output_tiers(
        TokenPriceTier::flat(0.8, 2.0, Some(0.16), None),
        TokenPriceTier::flat(0.8, 6.0, Some(0.16), None),
        TokenPriceTier::flat(1.2, 8.0, Some(0.24), None),
    ),
};
