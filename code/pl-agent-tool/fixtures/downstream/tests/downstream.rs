//! Real downstream proof over the renamed `tool_api` dependency: automatic
//! rename detection, an explicit `crate` override, generic tools with close
//! forwarding, and macro hygiene under locally shadowed names. The fixture
//! declares no direct serde/schemars/thiserror/futures dependency; errors and
//! the tiny test poll loop below are plain std.

use std::{
    error::Error,
    fmt,
    future::Future,
    pin::pin,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    task::{Context, Poll, Wake, Waker},
};

use tool_api::typed::prepare_json;
use tool_api::{ToolHandle, tool, tool_args};

/// Extracts an error without requiring the success type to implement `Debug`.
fn expect_error<E>(error: Option<E>, message: &str) -> E {
    match error {
        Some(error) => error,
        None => panic!("{message}"),
    }
}

struct NoopWaker;

impl Wake for NoopWaker {
    fn wake(self: Arc<Self>) {}
}

/// Polls a future to completion; fixture futures never park on real I/O.
fn block_on<F: Future>(future: F) -> F::Output {
    let waker = Waker::from(Arc::new(NoopWaker));
    let mut context = Context::from_waker(&waker);
    let mut future = pin!(future);
    loop {
        if let Poll::Ready(output) = future.as_mut().poll(&mut context) {
            return output;
        }
        std::hint::spin_loop();
    }
}

// The macro detects the renamed dependency on its own; no `crate` override.
#[tool_args]
#[serde(deny_unknown_fields)]
pub struct AddArgs {
    /// The first integer.
    pub left: i64,
    /// The second integer.
    pub right: i64,
}

/// Plain owned output; nothing here derives `Serialize` or `Debug`.
pub struct Sum {
    pub value: i64,
}

#[derive(Debug)]
pub struct AddError;

impl fmt::Display for AddError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("integer addition overflow")
    }
}

impl Error for AddError {}

pub struct Add {
    offset: i64,
}

#[tool(name = "add")]
impl Add {
    /// Adds two integers with the tool's fixed offset.
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
fn renamed_dependency_is_detected_and_the_tool_executes() {
    let prepared = prepare_json::<Add>().unwrap();
    assert_eq!(prepared.definition().name(), "add");
    assert_eq!(
        prepared.definition().description(),
        "Adds two integers with the tool's fixed offset."
    );

    let handle = ToolHandle::new(prepared.attach(Add { offset: 10 }));
    let sum = block_on(handle.execute(r#"{"left":2,"right":3}"#.to_owned(), ())).unwrap();
    assert_eq!(sum.value, 15);

    let error = expect_error(
        block_on(handle.execute(r#"{"left":2,"right":3,"extra":1}"#.to_owned(), ())).err(),
        "author deny_unknown_fields must survive the derive combination",
    );
    assert!(
        matches!(
            error,
            tool_api::typed::InvocationError::Arguments(
                tool_api::typed::ArgumentError::Decode { .. }
            )
        ),
        "unexpected error class: {error:?}"
    );
}

#[tool_args]
pub struct ShiftArgs {
    pub delta: i64,
}

pub struct Shift;

#[tool(name = "shift", description = "Shifts by one.", crate = "tool_api")]
impl Shift {
    async fn execute(&self, args: ShiftArgs, _context: ()) -> Result<i64, AddError> {
        Ok(args.delta + 1)
    }
}

#[test]
fn explicit_crate_override_compiles_and_runs() {
    let prepared = prepare_json::<Shift>().unwrap();
    assert_eq!(prepared.definition().name(), "shift");
    assert_eq!(prepared.definition().description(), "Shifts by one.");

    let handle = ToolHandle::new(prepared.attach(Shift));
    let shifted = block_on(handle.execute(r#"{"delta":41}"#.to_owned(), ())).unwrap();
    assert_eq!(shifted, 42);
}

#[tool_args]
pub struct PoolArgs {
    pub probe: bool,
}

#[derive(Debug)]
pub struct PoolError;

impl fmt::Display for PoolError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("pool failed")
    }
}

impl Error for PoolError {}

pub struct Pool<T> {
    items: Vec<T>,
    closed: Arc<AtomicBool>,
}

#[tool(name = "pool")]
impl<T> Pool<T>
where
    T: Send + Sync + 'static,
{
    /// Counts the pooled items.
    pub async fn execute(&self, _args: PoolArgs, _context: ()) -> Result<u32, PoolError> {
        Ok(self.items.len() as u32)
    }

    /// Marks the pool as closed.
    pub async fn close(&self) -> Result<(), PoolError> {
        self.closed.store(true, Ordering::SeqCst);
        Ok(())
    }
}

#[test]
fn generic_tool_forwards_close_to_the_business_method() {
    let prepared = prepare_json::<Pool<String>>().unwrap();
    assert_eq!(
        prepared.definition().description(),
        "Counts the pooled items."
    );

    let closed = Arc::new(AtomicBool::new(false));
    let pool = Pool {
        items: vec![String::from("a"), String::from("b"), String::from("c")],
        closed: Arc::clone(&closed),
    };
    let handle = ToolHandle::new(prepared.attach(pool));

    let count = block_on(handle.execute(r#"{"probe":true}"#.to_owned(), ())).unwrap();
    assert_eq!(count, 3);

    block_on(handle.close()).unwrap();
    assert!(
        closed.load(Ordering::SeqCst),
        "the forwarded close must reach the business close method"
    );
}

/// Local names that generated code must not depend on by bare path; the macro
/// emits absolute `::core` and `::tool_api` paths, so these stay inert.
mod shadow {
    use tool_api::{ToolHandle, tool, tool_args};

    pub struct Send;
    pub struct Future;
    /// An alias to the real `Result`, proving user-side aliases stay usable
    /// while generated signatures use `::core::result::Result` verbatim.
    pub type Result<T, E> = std::result::Result<T, E>;

    #[derive(Debug)]
    pub struct EchoError;

    impl std::fmt::Display for EchoError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.write_str("echo failed")
        }
    }

    impl std::error::Error for EchoError {}

    #[tool_args]
    pub struct EchoArgs {
        pub text: String,
    }

    pub struct EchoOut {
        pub text: String,
    }

    pub struct Echo;

    #[tool(name = "echo_shadowed")]
    impl Echo {
        /// Echoes under locally shadowed names.
        async fn execute(&self, args: EchoArgs, _context: ()) -> Result<EchoOut, EchoError> {
            Ok(EchoOut { text: args.text })
        }
    }

    pub fn run() -> (String, String) {
        let prepared = tool_api::typed::prepare_json::<Echo>().unwrap();
        assert_eq!(
            prepared.definition().description(),
            "Echoes under locally shadowed names."
        );
        let name = prepared.definition().name().to_string();
        let handle = ToolHandle::new(prepared.attach(Echo));
        let out = super::block_on(handle.execute(r#"{"text":"hygiene"}"#.to_owned(), ())).unwrap();
        (out.text, name)
    }
}

#[test]
fn generated_paths_survive_local_shadowing() {
    // The shadowing names exist for real, not just in a comment.
    let _: shadow::Send = shadow::Send;
    let _: shadow::Future = shadow::Future;

    let (text, name) = shadow::run();
    assert_eq!(text, "hygiene");
    assert_eq!(name, "echo_shadowed");
}
