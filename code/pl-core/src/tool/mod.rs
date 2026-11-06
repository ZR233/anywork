//! Thread-owned tool registration, trusted execution controls and immutable producer output.
//! Authors implement `pl_agent_tool::Tool`; `opaque::RuntimeTool` fixes its Anywork boundary.
pub mod execution_policy;
pub mod opaque;
mod output;
pub use output::{ToolControl, ToolOutput};
