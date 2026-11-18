use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4-flashx-250414",
    name: "GLM-4-FlashX-250414",
    description: "Zhipu high-speed low-cost Flash model with higher concurrency.",
    context: 128_000,
    max_output_tokens: Some(16_000),
    tiers: &[TokenPriceTier::flat(0.1, 0.1, Some(0.1), None)],
};
