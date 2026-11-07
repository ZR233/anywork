//! The single erased dispatch boundary between hosts and tools.

use std::{error::Error as StdError, fmt, future::Future};

use futures::future::BoxFuture;

use crate::{Tool, ToolDefinition};

/// Private erased executor; this is not a second trait for tool authors.
trait Executor<I, C, O, E>: Send + Sync {
    fn definition(&self) -> &ToolDefinition;

    fn execute(&self, input: I, context: C) -> BoxFuture<'_, Result<O, E>>;

    fn close(&self) -> BoxFuture<'_, Result<(), E>>;
}

impl<T> Executor<T::Input, T::Context, T::Output, T::Error> for T
where
    T: Tool,
{
    fn definition(&self) -> &ToolDefinition {
        Tool::definition(self)
    }

    fn execute(
        &self,
        input: T::Input,
        context: T::Context,
    ) -> BoxFuture<'_, Result<T::Output, T::Error>> {
        Box::pin(Tool::execute(self, input, context))
    }

    fn close(&self) -> BoxFuture<'_, Result<(), T::Error>> {
        Box::pin(Tool::close(self))
    }
}

/// A type-erased handle over one fully composed [`Tool`].
///
/// All static input, output, and error wrappers compose first; the single
/// call to [`ToolHandle::new`] is the one new dynamic dispatch boundary this
/// library adds. The handle is not `Clone`, does not implement [`Tool`], and
/// provides no blanket `From`: sharing an underlying service is the adapter
/// layer's explicit lease job, and double erasure buys nothing.
pub struct ToolHandle<I, C, O, E> {
    inner: Box<dyn Executor<I, C, O, E>>,
}

impl<I, C, O, E> ToolHandle<I, C, O, E>
where
    I: Send + 'static,
    C: Send + 'static,
    O: Send + 'static,
    E: StdError + Send + Sync + 'static,
{
    /// Takes over one composed tool instance; this cannot fail.
    pub fn new<T>(tool: T) -> Self
    where
        T: Tool<Input = I, Context = C, Output = O, Error = E>,
    {
        Self {
            inner: Box::new(tool),
        }
    }

    /// Returns the tool's immutable declaration snapshot.
    pub fn definition(&self) -> &ToolDefinition {
        self.inner.definition()
    }

    /// Executes one call, returning the already boxed executor future.
    pub fn execute(&self, input: I, context: C) -> impl Future<Output = Result<O, E>> + Send + '_ {
        self.inner.execute(input, context)
    }

    /// Closes the tool under the host retirement contract.
    pub fn close(&self) -> impl Future<Output = Result<(), E>> + Send + '_ {
        self.inner.close()
    }
}

impl<I, C, O, E> fmt::Debug for ToolHandle<I, C, O, E> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ToolHandle")
            .field("name", &self.inner.definition().name())
            .finish_non_exhaustive()
    }
}
