use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.7-flash",
    name: "GLM-4.7-Flash",
    description: "Zhipu free GLM-4.7 base model.",
    context: 200_000,
    max_output_tokens: Some(128_000),
    tiers: &[TokenPriceTier::flat(0.0, 0.0, Some(0.0), None)],
};
