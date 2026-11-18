use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.1v-thinking-flashx",
    name: "GLM-4.1V-Thinking-FlashX",
    description: "Zhipu lightweight visual reasoning model for complex scene understanding.",
    context: 64_000,
    max_output_tokens: Some(16_000),
    tiers: &[TokenPriceTier::flat(2.0, 2.0, Some(2.0), None)],
};
