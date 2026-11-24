//! Native Gemini REST (`generateContent` / `streamGenerateContent`) protocol adapter.
//!
//! Completely independent of OpenAI wire formats; implements `pl_model_wire::wire_codec::WireCodec`
//! for both Google Cloud Vertex AI (API key) and Google Gemini Developer API.

pub mod adapter;
pub mod catalog;
pub mod codec;
pub mod endpoint;
pub mod error;
pub mod models;
pub mod request;
pub mod sse;
pub mod usage;

pub use codec::{GEMINI_WIRE_CODEC, GeminiWireCodec};
pub use models::bundled_definition;
