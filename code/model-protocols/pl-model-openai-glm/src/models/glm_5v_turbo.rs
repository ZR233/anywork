use super::{Definition, TokenPriceTier, context_tiers};

pub(super) const MODEL: Definition = Definition {
    id: "glm-5v-turbo",
    name: "GLM-5V-Turbo",
    description: "Zhipu multimodal coding model for visual understanding and agent workflows.",
    context: 200_000,
    max_output_tokens: Some(128_000),
    tiers: &context_tiers(
        TokenPriceTier::flat(5.0, 22.0, Some(1.2), None),
        TokenPriceTier::flat(7.0, 26.0, Some(1.8), None),
    ),
};
