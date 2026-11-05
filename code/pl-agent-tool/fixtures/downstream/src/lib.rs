//! Independent downstream fixture for `pl-agent-tool` behind a renamed
//! `tool_api` dependency.
//!
//! The fixture is its own workspace on purpose, so its feature selection
//! never unifies with the outer repository, and it declares no dependency of
//! its own besides the facade: no direct serde, schemars, thiserror, or
//! futures crate. Unsupported macro shapes are rejected at compile time:
//!
//! `#[tool_args]` only accepts named-field structs:
//!
//! ```compile_fail
//! use tool_api::tool_args;
//!
//! #[tool_args]
//! pub enum NotANamedStruct {
//!     No,
//! }
//! ```
//!
//! `#[tool]` requires an `async fn execute` method:
//!
//! ```compile_fail
//! use tool_api::tool;
//!
//! struct Missing;
//!
//! #[tool(name = "missing")]
//! impl Missing {
//!     async fn not_execute(&self) {}
//! }
//! ```
//!
//! and it must be `async`:
//!
//! ```compile_fail
//! use tool_api::tool;
//!
//! struct Sync;
//!
//! #[tool(name = "sync")]
//! impl Sync {
//!     fn execute(
//!         &self,
//!         args: (),
//!         context: (),
//!     ) -> Result<(), std::convert::Infallible> {
//!         let _ = (args, context);
//!         Ok(())
//!     }
//! }
//! ```
