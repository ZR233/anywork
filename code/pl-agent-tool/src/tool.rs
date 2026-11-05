//! The consumer-side tool contract.

use std::{error::Error as StdError, future::Future};

use crate::ToolDefinition;

/// A tool as consumed by hosts through [`crate::ToolHandle`].
///
/// Implementations own their input, context, output, and error types; all
/// four travel as owned values with explicit `Send + 'static` contracts that
/// match the owning call contexts of current hosts. There is deliberately no
/// `Debug`, `Clone`, `Serialize`, `Deserialize`, or schema bound on the tool
/// itself: hosts erase once through [`crate::ToolHandle`] and authors keep
/// full control of their types.
///
/// `close` follows the host retirement contract: the owner stops admission,
/// waits for in-flight executions to release their leases, and then calls
/// `close`; on failure the same instance is retried, so implementations must
/// support safe retries and only release what this tool itself holds.
pub trait Tool: Send + Sync + 'static {
    /// Owned input transferred into one execution.
    type Input: Send + 'static;

    /// Owned per-call context transferred into one execution.
    type Context: Send + 'static;

    /// Owned output of a successful execution.
    type Output: Send + 'static;

    /// The tool's concrete error type.
    type Error: StdError + Send + Sync + 'static;

    /// Returns the same-generation immutable declaration snapshot.
    ///
    /// This performs no I/O and never rediscovers tools or rebuilds schemas.
    fn definition(&self) -> &ToolDefinition;

    /// Executes one call with owned input and context.
    fn execute(
        &self,
        input: Self::Input,
        context: Self::Context,
    ) -> impl Future<Output = Result<Self::Output, Self::Error>> + Send;

    /// Releases tool-held resources; the default closes nothing.
    fn close(&self) -> impl Future<Output = Result<(), Self::Error>> + Send {
        async { Ok(()) }
    }
}
