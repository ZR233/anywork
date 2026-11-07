//! A dynamic tool family that picks and freezes its input schema at bind time.
//!
//! The family members do not share one static `TypedTool`: each binding
//! chooses the argument type, derives its schema once through
//! [`input_schema_for`], freezes a declaration, and implements the base
//! `Tool` directly. This is the shape dynamic families such as Git or session
//! note tool kinds use.

use pl_agent_tool::typed::{ArgumentError, decode_json, input_schema_for};
use pl_agent_tool::{DefinitionError, Tool, ToolDefinition, ToolHandle};

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
struct SearchArgs {
    query: String,
    offset: u64,
    limit: u64,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
struct CountArgs {
    query: String,
}

#[derive(Clone, Copy)]
enum Operation {
    Search,
    Count,
}

struct QueryTool {
    definition: ToolDefinition,
    operation: Operation,
}

#[derive(Debug, thiserror::Error)]
enum QueryError {
    #[error("invalid query arguments: {0}")]
    Arguments(#[source] ArgumentError),
    #[error("query must contain a non-whitespace character")]
    Empty,
}

impl Tool for QueryTool {
    type Input = String;
    type Context = ();
    type Output = String;
    type Error = QueryError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: Self::Input,
        _context: Self::Context,
    ) -> Result<Self::Output, Self::Error> {
        if input.trim().is_empty() {
            return Err(QueryError::Empty);
        }
        match self.operation {
            Operation::Search => {
                let args = decode_json::<SearchArgs>(&input).map_err(QueryError::Arguments)?;
                Ok(format!(
                    "search '{}' [{};{}]",
                    args.query, args.offset, args.limit
                ))
            }
            Operation::Count => {
                let args = decode_json::<CountArgs>(&input).map_err(QueryError::Arguments)?;
                Ok(format!("count of '{}'", args.query))
            }
        }
    }
}

type QueryEndpoint = ToolHandle<String, (), String, QueryError>;

fn bind(operation: Operation) -> Result<QueryEndpoint, DefinitionError> {
    let (name, description, schema) = match operation {
        Operation::Search => (
            "search",
            "Searches items by query with paging.",
            input_schema_for::<SearchArgs>(),
        ),
        Operation::Count => (
            "count",
            "Counts items matching the query.",
            input_schema_for::<CountArgs>(),
        ),
    };
    let definition = ToolDefinition::json(name, description, schema)?;
    Ok(ToolHandle::new(QueryTool {
        definition,
        operation,
    }))
}

fn main() {
    let search = bind(Operation::Search).expect("search declaration is valid");
    let count = bind(Operation::Count).expect("count declaration is valid");

    let output = futures::executor::block_on(
        search.execute(r#"{"query":"rust","offset":0,"limit":20}"#.to_owned(), ()),
    )
    .expect("search executes");
    assert_eq!(output, "search 'rust' [0;20]");

    let output = futures::executor::block_on(count.execute(r#"{"query":"rust"}"#.to_owned(), ()))
        .expect("count executes");
    assert_eq!(output, "count of 'rust'");

    println!("{output}");
}
