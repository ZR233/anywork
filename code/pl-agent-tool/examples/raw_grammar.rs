//! A raw grammar-input tool implementing the base `Tool` contract directly.
//!
//! Non-JSON tools skip the typed layer entirely: the author declares an
//! [`InputFormat::Grammar`] and executes raw text with their own validation.

use pl_agent_tool::{DefinitionError, Tool, ToolDefinition, ToolHandle};

#[derive(Debug, thiserror::Error)]
pub enum ShoutError {
    #[error("input does not match the declared grammar: {0:?}")]
    NoMatch(String),
}

pub struct Shout {
    definition: ToolDefinition,
}

impl Tool for Shout {
    type Input = String;
    type Context = ();
    type Output = String;
    type Error = ShoutError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: Self::Input,
        _context: Self::Context,
    ) -> Result<Self::Output, Self::Error> {
        if input.is_empty() || !input.chars().all(|c| c.is_ascii_lowercase()) {
            return Err(ShoutError::NoMatch(input));
        }
        Ok(input.to_ascii_uppercase())
    }
}

fn shout_tool() -> Result<ToolHandle<String, (), String, ShoutError>, DefinitionError> {
    let definition = ToolDefinition::grammar(
        "shout",
        "Upper-cases a run of lowercase ASCII letters.",
        "regex",
        "[a-z]+",
    )?;
    Ok(ToolHandle::new(Shout { definition }))
}

fn main() {
    let tool = shout_tool().expect("grammar declaration is valid");

    let output = futures::executor::block_on(tool.execute("hello".to_owned(), ()))
        .expect("grammar input matches");
    assert_eq!(output, "HELLO");

    let error = futures::executor::block_on(tool.execute("Hello!".to_owned(), ()))
        .expect_err("upper-case and punctuation input is rejected");
    assert!(matches!(error, ShoutError::NoMatch(_)));

    println!("{output}");
}
