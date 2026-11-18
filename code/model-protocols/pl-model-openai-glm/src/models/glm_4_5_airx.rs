use super::Definition;

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.5-airx",
    name: "GLM-4.5-AirX",
    description: "Zhipu fast cost-effective model for latency-sensitive tasks.",
    context: 128_000,
    max_output_tokens: Some(96_000),
    tiers: &[],
};
