use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.5-flash",
    name: "GLM-4.5-Flash",
    description: "Zhipu free GLM-4.5 model, marked by the official docs as being phased out.",
    context: 128_000,
    max_output_tokens: Some(96_000),
    tiers: &[TokenPriceTier::flat(0.0, 0.0, Some(0.0), None)],
};
