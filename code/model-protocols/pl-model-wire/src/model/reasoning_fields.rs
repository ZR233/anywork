use super::ReasoningInterleavedField;

/// Named interleaved fields of the OpenAI-family Chat format.
pub const REASONING: ReasoningInterleavedField =
    ReasoningInterleavedField::from_static("reasoning");
pub const REASONING_CONTENT: ReasoningInterleavedField =
    ReasoningInterleavedField::from_static("reasoning_content");
pub const REASONING_DETAILS: ReasoningInterleavedField =
    ReasoningInterleavedField::from_static("reasoning_details");
