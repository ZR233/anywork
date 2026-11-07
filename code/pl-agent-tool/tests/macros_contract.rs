//! Facade-side macro contract. Runs only with the `macros` feature and the
//! real `pl-agent-tool-macros` implementation; these tests are prepared now
//! and executed once the macro crate lands.
#![cfg(feature = "macros")]

use std::collections::BTreeMap;

use pl_agent_tool::typed::{InvocationError, prepare_json};
use pl_agent_tool::{ToolHandle, tool, tool_args};

/// Extracts an error without requiring the success type to implement `Debug`;
/// macro-generated author types keep proving they need no `Debug`.
fn expect_error<E>(error: Option<E>, message: &str) -> E {
    match error {
        Some(error) => error,
        None => panic!("{message}"),
    }
}

/// The canonical authoring shape from the issue: stateful Add with offset.
#[tool_args]
#[serde(deny_unknown_fields)]
pub struct AddArgs {
    /// 第一个整数。
    pub left: i64,
    /// 第二个整数。
    pub right: i64,
}

pub struct Sum {
    pub value: i64,
}

#[derive(Debug, thiserror::Error)]
#[error("integer addition overflow")]
pub struct AddError;

pub struct Add {
    offset: i64,
}

#[tool(name = "add")]
impl Add {
    /// 将两个整数与工具固定的偏移相加。
    async fn execute(&self, args: AddArgs, _context: ()) -> Result<Sum, AddError> {
        let value = args
            .left
            .checked_add(args.right)
            .and_then(|sum| sum.checked_add(self.offset))
            .ok_or(AddError)?;
        Ok(Sum { value })
    }
}

#[test]
fn macro_add_executes_through_the_typed_pipeline() {
    let prepared = prepare_json::<Add>().unwrap();
    assert_eq!(prepared.definition().name(), "add");
    assert_eq!(
        prepared.definition().description(),
        "将两个整数与工具固定的偏移相加。"
    );

    let handle = ToolHandle::new(prepared.attach(Add { offset: 10 }));
    let sum = futures::executor::block_on(handle.execute(r#"{"left":2,"right":3}"#.to_owned(), ()))
        .unwrap();
    assert_eq!(sum.value, 15);

    let error = expect_error(
        futures::executor::block_on(
            handle.execute(r#"{"left":2,"right":3,"extra":1}"#.to_owned(), ()),
        )
        .err(),
        "unknown fields must surface as an argument error",
    );
    assert!(matches!(
        error,
        InvocationError::Arguments(pl_agent_tool::typed::ArgumentError::Decode { .. })
    ));
}

#[tool_args]
#[derive(Clone)]
pub struct Page {
    pub offset: u64,
    pub limit: u64,
}

#[tool_args]
pub struct SearchArgs {
    pub query: String,
    #[serde(flatten)]
    pub page: Page,
}

#[tool_args]
pub struct TaggedArgs {
    pub name: String,
    #[serde(flatten)]
    pub tags: BTreeMap<String, String>,
}

#[derive(Debug, thiserror::Error)]
#[error("search failed")]
struct SearchError;

struct SearchTool;

#[tool(name = "search", description = "Searches with flattened paging.")]
impl SearchTool {
    async fn execute(&self, args: SearchArgs, _context: ()) -> Result<SearchArgs, SearchError> {
        let _ = args;
        Err(SearchError)
    }
}

#[test]
fn tool_args_keeps_serde_attributes_for_flatten_and_open_maps() {
    let args = pl_agent_tool::typed::decode_json::<SearchArgs>(
        r#"{"query":"rust","offset":0,"limit":20}"#,
    )
    .unwrap();
    assert_eq!(args.query, "rust");
    assert_eq!((args.page.offset, args.page.limit), (0, 20));

    let args =
        pl_agent_tool::typed::decode_json::<TaggedArgs>(r#"{"name":"build","environment":"test"}"#)
            .unwrap();
    assert_eq!(
        args.tags.get("environment").map(String::as_str),
        Some("test")
    );

    let prepared = prepare_json::<SearchTool>().unwrap();
    assert_eq!(prepared.definition().name(), "search");
    assert_eq!(
        prepared.definition().description(),
        "Searches with flattened paging."
    );

    let handle = ToolHandle::new(prepared.attach(SearchTool));
    let error = expect_error(
        futures::executor::block_on(
            handle.execute(r#"{"query":"x","offset":0,"limit":1}"#.to_owned(), ()),
        )
        .err(),
        "flattened arguments must reach the business error",
    );
    assert!(matches!(error, InvocationError::Tool(SearchError)));
}

#[derive(Debug, thiserror::Error)]
#[error("len failed")]
pub struct LenError;

pub struct Len<T> {
    items: Vec<T>,
}

/// Generic inherent impls pass their generics, self type, and where clause
/// through untouched, and the forward is not recursive.
#[tool(name = "len")]
impl<T> Len<T>
where
    T: Send + Sync + 'static,
{
    /// Returns the number of items.
    pub async fn execute(&self, _args: LenArgs, _context: ()) -> Result<i64, LenError> {
        Ok(self.items.len() as i64)
    }

    /// Other inherent methods stay untouched.
    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }
}

#[tool_args]
pub struct LenArgs {
    pub probe: bool,
}

#[test]
fn tool_macro_forwards_generic_impls_and_keeps_other_methods() {
    let prepared = prepare_json::<Len<String>>().unwrap();
    let len = Len {
        items: vec![String::from("a"), String::from("b")],
    };
    assert!(!len.is_empty(), "other inherent methods stay callable");
    let handle = ToolHandle::new(prepared.attach(len));
    let count =
        futures::executor::block_on(handle.execute(r#"{"probe":true}"#.to_owned(), ())).unwrap();
    assert_eq!(count, 2);
}

#[derive(Debug, thiserror::Error)]
#[error("closer failed")]
pub struct CloseError;

pub struct ClosableTool;

#[tool(name = "closable", crate = "pl_agent_tool")]
impl ClosableTool {
    /// Returns nothing.
    pub(crate) async fn execute(
        &self,
        args: LenArgs,
        _context: (),
    ) -> std::result::Result<(), CloseError> {
        let _ = args;
        Ok(())
    }

    /// Fails on purpose.
    async fn close(&self) -> Result<(), CloseError> {
        Err(CloseError)
    }
}

#[test]
fn tool_macro_forwards_close_and_accepts_full_result_paths() {
    let prepared = prepare_json::<ClosableTool>().unwrap();
    assert_eq!(prepared.definition().name(), "closable");
    assert_eq!(prepared.definition().description(), "Returns nothing.");

    let handle = ToolHandle::new(prepared.attach(ClosableTool));
    futures::executor::block_on(handle.execute(r#"{"probe":false}"#.to_owned(), ())).unwrap();
    let error = futures::executor::block_on(handle.close()).unwrap_err();
    assert!(matches!(error, InvocationError::Tool(CloseError)));
}
