//! A pure consumer using only the base `pl-agent-tool` contract.
//!
//! This example needs no `typed` or `macros` feature, no serde derive, no
//! schemars, and no tool author crate: the consumer fixes its endpoint types
//! once and calls through [`pl_agent_tool::ToolHandle`].

use std::error::Error as StdError;

use pl_agent_tool::{Tool, ToolDefinition, ToolHandle};

#[derive(Debug, thiserror::Error)]
pub enum EchoError {
    #[error("message must contain a non-whitespace character")]
    Empty,
}

pub struct Echo {
    definition: ToolDefinition,
}

impl Tool for Echo {
    type Input = String;
    type Context = ();
    type Output = String;
    type Error = EchoError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: Self::Input,
        _context: Self::Context,
    ) -> Result<Self::Output, Self::Error> {
        if input.trim().is_empty() {
            return Err(EchoError::Empty);
        }
        Ok(format!("echo: {input}"))
    }
}

/// The generic consumer shape from the contract: one function, any tool.
pub async fn invoke<I, C, O, E>(tool: &ToolHandle<I, C, O, E>, input: I, context: C) -> Result<O, E>
where
    I: Send + 'static,
    C: Send + 'static,
    O: Send + 'static,
    E: StdError + Send + Sync + 'static,
{
    // The consumer may hand tool.definition() to its own publishing layer.
    tool.execute(input, context).await
}

fn main() {
    let definition =
        ToolDefinition::text("echo", "Returns the input prefixed with echo.").expect("valid name");
    let handle = ToolHandle::new(Echo { definition });

    let output = futures::executor::block_on(invoke(&handle, "hello".to_owned(), ()))
        .expect("echo executes");
    assert_eq!(output, "echo: hello");

    let error = futures::executor::block_on(invoke(&handle, "   ".to_owned(), ()))
        .expect_err("whitespace-only input is rejected");
    assert!(matches!(error, EchoError::Empty));

    println!("{output}");
}
