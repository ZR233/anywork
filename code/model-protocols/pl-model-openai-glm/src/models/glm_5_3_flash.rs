use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-5.3-flash",
    name: "GLM-5.3-Flash",
    description: "Zhipu native multimodal coding model with always-on thinking and image input.",
    context: 1_000_000,
    max_output_tokens: Some(128_000),
    // Introductory tariff published on 2026-09-05.
    tiers: &[TokenPriceTier::flat(0.4, 1.4, Some(0.115), None)],
};
