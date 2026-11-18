use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.7-flashx",
    name: "GLM-4.7-FlashX",
    description: "Zhipu lightweight high-speed model for general text tasks.",
    context: 200_000,
    max_output_tokens: Some(128_000),
    tiers: &[TokenPriceTier::flat(0.5, 3.0, Some(0.1), None)],
};
