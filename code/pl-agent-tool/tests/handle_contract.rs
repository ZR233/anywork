//! Base handle contract: single erasure, default and overridden close,
//! and bounded debug.

use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

use pl_agent_tool::{Tool, ToolDefinition, ToolHandle};

#[derive(Debug, thiserror::Error)]
enum EchoError {
    #[error("message must contain a non-whitespace character")]
    Empty,
    #[error("echo failed")]
    Boom,
}

struct Echo {
    definition: ToolDefinition,
    closed: Arc<AtomicBool>,
    fail: bool,
}

impl Echo {
    fn new(fail: bool) -> Self {
        Self {
            definition: ToolDefinition::text("echo", "SECRET-DESCRIPTION").unwrap(),
            closed: Arc::new(AtomicBool::new(false)),
            fail,
        }
    }
}

impl Tool for Echo {
    type Input = String;
    type Context = u32;
    type Output = String;
    type Error = EchoError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: Self::Input,
        context: Self::Context,
    ) -> Result<Self::Output, Self::Error> {
        if input.trim().is_empty() {
            return Err(EchoError::Empty);
        }
        if self.fail {
            return Err(EchoError::Boom);
        }
        Ok(format!("{input} #{context}"))
    }

    async fn close(&self) -> Result<(), Self::Error> {
        self.closed.store(true, Ordering::SeqCst);
        Ok(())
    }
}

#[test]
fn handle_erases_once_and_executes_with_owned_values() {
    let handle = ToolHandle::new(Echo::new(false));

    let output = futures::executor::block_on(handle.execute("hi".to_owned(), 7_u32)).unwrap();
    assert_eq!(output, "hi #7");

    // The handle stays usable; execution is stateless here.
    let output = futures::executor::block_on(handle.execute("again".to_owned(), 8_u32)).unwrap();
    assert_eq!(output, "again #8");
}

#[test]
fn errors_keep_their_concrete_type_through_the_handle() {
    let handle = ToolHandle::new(Echo::new(true));
    let error = futures::executor::block_on(handle.execute("boom".to_owned(), 0_u32)).unwrap_err();
    assert!(matches!(error, EchoError::Boom));
    assert_eq!(error.to_string(), "echo failed");
}

#[test]
fn default_and_overridden_close_behave() {
    struct Plain {
        definition: ToolDefinition,
    }

    impl Tool for Plain {
        type Input = ();
        type Context = ();
        type Output = ();
        type Error = std::convert::Infallible;

        fn definition(&self) -> &ToolDefinition {
            &self.definition
        }

        async fn execute(
            &self,
            (): Self::Input,
            (): Self::Context,
        ) -> Result<Self::Output, Self::Error> {
            Ok(())
        }
    }

    let plain = ToolHandle::new(Plain {
        definition: ToolDefinition::text("plain", "Closes nothing.").unwrap(),
    });
    futures::executor::block_on(plain.close()).unwrap();

    let echo = Echo::new(false);
    let closed = Arc::clone(&echo.closed);
    let handle = ToolHandle::new(echo);
    futures::executor::block_on(handle.close()).unwrap();
    assert!(closed.load(Ordering::SeqCst));
}

#[test]
fn handle_debug_shows_only_the_tool_name() {
    let handle = ToolHandle::new(Echo::new(false));
    let debug = format!("{handle:?}");
    assert!(debug.contains("echo"), "{debug}");
    assert!(debug.contains("ToolHandle"), "{debug}");
    assert!(!debug.contains("SECRET-DESCRIPTION"), "{debug}");
}
