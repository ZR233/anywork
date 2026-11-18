use super::Definition;

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.6",
    name: "GLM-4.6",
    description: "Zhipu model with stronger coding, reasoning, and tool calling.",
    context: 200_000,
    max_output_tokens: Some(128_000),
    tiers: &[],
};
