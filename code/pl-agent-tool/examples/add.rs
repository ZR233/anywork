//! A standalone stateful Add tool with a hand-written `TypedTool`.
//!
//! The tool keeps a fixed offset; the adapter owns all JSON handling. The
//! `macros` feature removes the boilerplate `TypedTool` impl below, while
//! this example stays macro-free to show the complete author contract.

use std::future::Future;

use pl_agent_tool::typed::{InvocationError, TypedTool, prepare_json};
use pl_agent_tool::{DefinitionError, ToolHandle};

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AddArgs {
    /// The first integer.
    pub left: i64,
    /// The second integer.
    pub right: i64,
}

/// Plain owned output; the adapter never re-encodes it as JSON.
pub struct Sum {
    pub value: i64,
}

#[derive(Debug, thiserror::Error)]
#[error("integer addition overflow")]
pub struct AddError;

pub struct Add {
    offset: i64,
}

impl TypedTool for Add {
    const NAME: &'static str = "add";
    const DESCRIPTION: &'static str = "将两个整数与工具固定的偏移相加。";

    type Args = AddArgs;
    type Context = ();
    type Output = Sum;
    type Error = AddError;

    fn execute(
        &self,
        args: Self::Args,
        _context: Self::Context,
    ) -> impl Future<Output = Result<Self::Output, Self::Error>> + Send {
        let value = args
            .left
            .checked_add(args.right)
            .and_then(|sum| sum.checked_add(self.offset));
        async move {
            Ok(Sum {
                value: value.ok_or(AddError)?,
            })
        }
    }
}

/// The endpoint type any standalone consumer would fix once.
type AddEndpoint = ToolHandle<String, (), Sum, InvocationError<AddError>>;

fn add_tool(offset: i64) -> Result<AddEndpoint, DefinitionError> {
    let prepared = prepare_json::<Add>()?;
    Ok(ToolHandle::new(prepared.attach(Add { offset })))
}

async fn call_add(tool: &AddEndpoint) -> Result<Sum, InvocationError<AddError>> {
    tool.execute(r#"{"left":2,"right":3}"#.to_owned(), ()).await
}

fn main() {
    let endpoint = add_tool(10).expect("tool definition is valid");
    let sum = futures::executor::block_on(call_add(&endpoint)).expect("add executes");
    assert_eq!(sum.value, 15);
    futures::executor::block_on(endpoint.close())
        .expect("the default close releases nothing and succeeds");
    println!("add(2, 3) with offset 10 = {}", sum.value);
}
