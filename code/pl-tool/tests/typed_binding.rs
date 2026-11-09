#[path = "../examples/support/typed_authors.rs"]
mod authors;
#[path = "support/binding_host.rs"]
mod host;

use pl_agent_tool::{Tool, ToolHandle};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, ToolError},
};
use pl_core::{
    context::{ContextContent, ContextSource, OpaquePayload},
    model::DynModelSession,
    thread::ThreadHandle,
};
use pl_tool::binding::{JsonOutputError, prepare_json_tool, prepare_native_tool};
use std::sync::atomic::{AtomicUsize, Ordering};

fn context() -> CallContext {
    CallContext {
        thread_id: "binding".into(),
        turn_id: "turn".into(),
        call_id: "call".into(),
        cancellation: Default::default(),
        extensions: Default::default(),
        catalog: Arc::from([]),
        extension_sequence: 0,
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
    }
}

#[pl_agent_tool::tool_args]
#[serde(deny_unknown_fields)]
pub struct EmptyArgs {}

#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EncodingArgs {}

static ENCODING_INPUT_SCHEMAS: AtomicUsize = AtomicUsize::new(0);

impl schemars::JsonSchema for EncodingArgs {
    fn schema_name() -> std::borrow::Cow<'static, str> {
        "EncodingArgs".into()
    }

    fn json_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
        ENCODING_INPUT_SCHEMAS.fetch_add(1, Ordering::SeqCst);
        EmptyArgs::json_schema(generator)
    }
}

struct EncodingTool {
    calls: Arc<AtomicUsize>,
    encodes: Arc<AtomicUsize>,
    fail: bool,
}

struct Encoded {
    encodes: Arc<AtomicUsize>,
    fail: bool,
}

impl serde::Serialize for Encoded {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.encodes.fetch_add(1, Ordering::SeqCst);
        if self.fail {
            return Err(serde::ser::Error::custom("output cannot be encoded"));
        }
        serializer.serialize_str("verbatim")
    }
}

impl schemars::JsonSchema for Encoded {
    fn schema_name() -> std::borrow::Cow<'static, str> {
        "Encoded".into()
    }
    fn json_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
        String::json_schema(generator)
    }
}

#[pl_agent_tool::tool(name = "encode")]
impl EncodingTool {
    /// Returns an output whose serialization can be observed independently.
    async fn execute(
        &self,
        _args: EncodingArgs,
        _context: (),
    ) -> Result<Encoded, authors::AddError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(Encoded {
            encodes: self.encodes.clone(),
            fail: self.fail,
        })
    }
}

#[tokio::test]
async fn json_binding_decodes_before_handler_and_encodes_success_exactly_once() {
    for fail in [false, true] {
        let schemas_before = ENCODING_INPUT_SCHEMAS.load(Ordering::SeqCst);
        let calls = Arc::new(AtomicUsize::new(0));
        let encodes = Arc::new(AtomicUsize::new(0));
        let prepared = prepare_json_tool::<EncodingTool>(|_| (), ToolError::new).unwrap();
        assert!(prepared.definition().output_schema().is_none());
        let prepared = prepared.with_output_schema().unwrap();
        assert!(prepared.definition().output_schema().is_some());
        assert_eq!(
            ENCODING_INPUT_SCHEMAS.load(Ordering::SeqCst),
            schemas_before + 1
        );
        let tool = ToolHandle::new(prepared.attach(EncodingTool {
            calls: calls.clone(),
            encodes: encodes.clone(),
            fail,
        }));
        for input in [
            OpaquePayload::text("{}"),
            OpaquePayload::new("application/json", 1, r#"{"unknown":1}"#).unwrap(),
            OpaquePayload::new("application/json", 1, "{} {}").unwrap(),
        ] {
            let error = tool.execute(input, context()).await.unwrap_err();
            assert!(
                error
                    .source
                    .downcast_ref::<pl_agent_tool::typed::ArgumentError>()
                    .is_some()
            );
        }
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        assert_eq!(encodes.load(Ordering::SeqCst), 0);
        let result = tool
            .execute(
                OpaquePayload::new("application/json", 1, "{}").unwrap(),
                context(),
            )
            .await;
        if fail {
            let error = result.unwrap_err();
            let error = error.source.downcast_ref::<JsonOutputError>().unwrap();
            assert_eq!(error.tool, "encode");
            assert!(error.to_string().contains("returned successfully"));
            assert!(error.to_string().contains("side effects may have occurred"));
            assert!(error.to_string().contains("did not retry"));
            assert!(
                std::error::Error::source(error)
                    .unwrap()
                    .is::<pl_tool::binding::JsonError>()
            );
        } else {
            let output = result.unwrap();
            assert_eq!(output.payload().format(), "application/json");
            assert_eq!(output.payload().version(), 1);
            assert_eq!(output.payload().content(), r#""verbatim""#);
            assert!(
                matches!(&output.context()[0], ContextContent::Text { text } if text.as_ref() == output.payload().content())
            );
        }
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert_eq!(encodes.load(Ordering::SeqCst), 1);
        tool.close().await.unwrap();
        assert_eq!(
            ENCODING_INPUT_SCHEMAS.load(Ordering::SeqCst),
            schemas_before + 1,
            "attaching, decoding, serializing and closing must not regenerate the input schema"
        );
    }
}

struct ObservedFailure {
    fail_close: bool,
    storage_source: Option<Arc<pl_core::thread::cold::ColdStoreError>>,
}

#[derive(Debug, thiserror::Error)]
#[error("native producer failed after observing output")]
struct NativeFailure;

impl ObservedFailure {
    fn failure(&self) -> ToolError {
        match &self.storage_source {
            Some(source) => ToolError::new(pl_core::thread::cold::OutputStorageFault::new(
                pl_core::thread::cold::StorageFaultKind::WriteFailed,
                source.clone(),
            )),
            None => ToolError::new(NativeFailure),
        }
    }
}

#[pl_agent_tool::tool(name = "observed_failure")]
impl ObservedFailure {
    /// Fails after producing facts; these are not successful control proposals.
    async fn execute(
        &self,
        _args: EmptyArgs,
        _context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        Err(self.failure().with_output(ToolOutput::new(
            OpaquePayload::text("observed before failure"),
            vec![ContextContent::Text {
                text: "delivered before failure".into(),
            }],
        )))
    }

    async fn close(&self) -> Result<(), ToolError> {
        if self.fail_close {
            Err(self.failure())
        } else {
            Ok(())
        }
    }
}

#[tokio::test]
async fn native_errors_keep_source_output_and_close_identity() {
    let source = Arc::new(pl_core::thread::cold::ColdStoreError {
        source: Box::new(NativeFailure),
    });
    let tool = prepare_native_tool::<ObservedFailure>()
        .unwrap()
        .attach(ObservedFailure {
            fail_close: true,
            storage_source: Some(source.clone()),
        });
    let error = tool
        .execute(
            OpaquePayload::new("application/json", 1, "{}").unwrap(),
            context(),
        )
        .await
        .unwrap_err();
    let fault = error
        .source
        .downcast_ref::<pl_core::thread::cold::OutputStorageFault>()
        .unwrap();
    assert!(Arc::ptr_eq(&fault.source, &source));
    let error = tool.close().await.unwrap_err();
    let fault = error
        .source
        .downcast_ref::<pl_core::thread::cold::OutputStorageFault>()
        .unwrap();
    assert!(Arc::ptr_eq(&fault.source, &source));
    let tool = prepare_native_tool::<ObservedFailure>().unwrap();
    let prepared = pl_tool::binding::prepare_registration(
        "native.observed",
        tool.definition(),
        pl_tool::binding::ToolCallPolicy::DirectOnly,
    )
    .unwrap();
    let thread = ThreadHandle::start(
        "native-observed".into(),
        DynModelSession::new(host::Calls {
            calls: [("native.observed".into(), "{}".into())].into(),
            requests: Arc::new(Mutex::new(Vec::new())),
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![prepared.attach(ToolHandle::new(tool.attach(
            ObservedFailure {
                fail_close: false,
                storage_source: None,
            },
        )))])
        .await
        .unwrap();
    thread.run_turn(host::turn("native")).await.unwrap();
    let effects = thread.effects().await.unwrap();
    let deliveries = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .collect::<Vec<_>>();
    assert_eq!(deliveries.len(), 1);
    assert_eq!(
        deliveries[0].output.payload().content(),
        "observed before failure"
    );
    assert!(
        matches!(&deliveries[0].output.context()[0], ContextContent::Text { text } if text.as_ref() == "delivered before failure")
    );
    thread.close().await.unwrap();
}

use std::sync::{Arc, Mutex};

#[tokio::test]
async fn host_keeps_internal_id_distinct_and_only_explicitly_grants_completion() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let thread = ThreadHandle::start(
        "typed-add".into(),
        DynModelSession::new(host::Calls {
            calls: [("example.add".into(), r#"{"left":2,"right":3}"#.into())].into(),
            requests: requests.clone(),
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![authors::register_add(10).unwrap()])
        .await
        .unwrap();
    thread.run_turn(host::turn("add")).await.unwrap();
    {
        let requests = requests.lock().unwrap();
        assert_eq!(requests[0].tools[0].tool_id, "example.add");
        let spec: pl_protocol::ToolSpec =
            serde_json::from_str(requests[0].tools[0].declaration.content()).unwrap();
        assert_eq!(spec.name(), "add");
    }
    let context = thread.snapshot().context;
    assert!(context.records.iter().filter(|record| matches!(record.source, ContextSource::ToolResult { .. }))
        .flat_map(|record| &record.content)
        .any(|part| matches!(part, ContextContent::Text { text } if text.as_ref() == r#"{"value":15}"#)));
    thread.close().await.unwrap();

    for allowed in [false, true] {
        let requests = Arc::new(Mutex::new(Vec::new()));
        let thread = ThreadHandle::start(
            format!("finish-{allowed}"),
            DynModelSession::new(host::Calls {
                calls: [("example.finish".into(), r#"{"message":"complete"}"#.into())].into(),
                requests: requests.clone(),
            }),
        )
        .unwrap();
        let candidate = authors::register_finish("Result".into()).unwrap();
        let registration = if allowed {
            candidate.with_turn_completion()
        } else {
            candidate
        };
        thread.register_tools(vec![registration]).await.unwrap();
        thread.run_turn(host::turn("finish")).await.unwrap();
        assert_eq!(requests.lock().unwrap().len(), if allowed { 1 } else { 2 });
        let saved = serde_json::to_string(
            &thread
                .checkpoint(thread.snapshot().commit_sequence)
                .unwrap(),
        )
        .unwrap();
        // Denied control is an error, but the already-observed output must remain saved.
        assert!(saved.contains("Result [finish]"));
        assert_eq!(
            saved.contains("tool returned framework control without registered authority"),
            !allowed
        );
        thread.close().await.unwrap();
    }
}

fn assert_dynamic_argument_error(error: &ToolError, expected_path: Option<&str>) {
    use pl_agent_tool::typed::{ArgumentError, JsonError};
    let argument = error
        .source
        .downcast_ref::<ArgumentError>()
        .expect("dynamic adapter must retain ArgumentError identity");
    match (argument, expected_path) {
        (ArgumentError::Decode { path, source }, Some(expected)) => {
            assert_eq!(path, expected);
            assert!(source.is_data());
        }
        (ArgumentError::Trailing { source }, None) => assert!(source.is_syntax()),
        _ => panic!("unexpected argument error classification: {argument:?}"),
    }
    assert!(
        std::error::Error::source(argument)
            .unwrap()
            .is::<JsonError>()
    );
}

#[tokio::test]
async fn dynamic_note_adapter_retains_argument_types_paths_and_trailing_source() {
    use pl_tool::session_note::{NoteTool, SessionNoteToolKind};
    let kind = SessionNoteToolKind::Write;
    let definition = pl_tool::thread_catalog::ThreadBuiltin::Note(kind).declaration();
    let tool = NoteTool::new(kind, definition);
    for (raw, path) in [
        (
            r#"{"content":"x","expectedRevision":null}"#,
            Some("expectedRevision"),
        ),
        (r#"{"content":7,"expectedRevision":0}"#, Some("content")),
        (r#"{"content":"x","expectedRevision":0} true"#, None),
    ] {
        let error = tool
            .execute(
                OpaquePayload::new("application/json", 1, raw).unwrap(),
                context(),
            )
            .await
            .unwrap_err();
        assert_dynamic_argument_error(&error, path);
    }
    // The same adapter can produce a real mutation only after successful decoding.
    let output = tool
        .execute(
            OpaquePayload::new(
                "application/json",
                1,
                r#"{"content":"x","expectedRevision":0}"#,
            )
            .unwrap(),
            context(),
        )
        .await
        .unwrap();
    assert_eq!(output.extension_mutations().len(), 1);
    tool.close().await.unwrap();
}

#[derive(Debug)]
struct UnreachableBotHost;

impl pl_tool::bots::BotSessionHost for UnreachableBotHost {
    type Error = std::io::Error;
    type Connection = ();
    type Conversation = ();
    type Message = ();
    type Segment = ();
    type Receipt = ();
    async fn list_bots(&self, _: &str) -> Result<Vec<pl_tool::bots::Bot<()>>, std::io::Error> {
        panic!("argument failure entered a business handler")
    }
    async fn list_conversations(
        &self,
        _: &str,
        _: String,
        _: Option<String>,
        _: Option<u32>,
    ) -> Result<pl_tool::bots::Page<()>, std::io::Error> {
        panic!("argument failure entered a business handler")
    }
    async fn read_messages(
        &self,
        _: &str,
        _: pl_tool::bots::ReadMessages,
    ) -> Result<pl_tool::bots::Page<()>, std::io::Error> {
        panic!("argument failure entered a business handler")
    }
    async fn send_message(
        &self,
        _: &str,
        _: String,
        _: String,
        _: String,
        _: String,
    ) -> Result<pl_tool::bots::Sent<(), ()>, std::io::Error> {
        panic!("argument failure entered a business handler")
    }
}

#[tokio::test]
async fn dynamic_bot_adapter_rejects_arguments_before_entering_business_handler() {
    use pl_tool::bots::{BotToolKind, ThreadBotTool};
    let kind = BotToolKind::ListConversations;
    let tool = ThreadBotTool::new(
        Arc::new(UnreachableBotHost),
        kind,
        "workspace".into(),
        kind.declaration(),
    );
    for (raw, path) in [
        (r#"{"botId":7}"#, Some("botId")),
        (r#"{"botId":"bot"} true"#, None),
    ] {
        let error = tool
            .execute(
                OpaquePayload::new("application/json", 1, raw).unwrap(),
                context(),
            )
            .await
            .unwrap_err();
        assert_dynamic_argument_error(&error, path);
    }
    tool.close().await.unwrap();
}
