//! Typed layer contract: schema generation, preparation, decoding, adapters,
//! and error identity. Runs only with the `typed` feature.
#![cfg(feature = "typed")]

use std::{cell::Cell, error::Error as StdError, future::Future};

use pl_agent_tool::ToolHandle;
use pl_agent_tool::typed::{
    ArgumentError, InvocationError, PreparedJson, TypedTool, decode_json, input_schema_for,
    prepare_json,
};

/// Extracts an error without requiring the success type to implement `Debug`;
/// author types here deliberately keep proving they need no `Debug`.
trait ExpectError<E> {
    fn expect_error(self, message: &str) -> E;
}

impl<E> ExpectError<E> for Option<E> {
    fn expect_error(self, message: &str) -> E {
        match self {
            Some(error) => error,
            None => panic!("{message}"),
        }
    }
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
struct AddArgs {
    left: i64,
    right: i64,
}

#[derive(Debug, thiserror::Error)]
#[error("integer addition overflow")]
struct AddError;

/// Plain owned output without `Serialize`: the adapter must never encode it.
struct Sum {
    value: i64,
}

struct Add {
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
        (): Self::Context,
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

/// A type whose serialization differs from its deserialization, proving that
/// `with_output_schema` really generates `for_serialize`.
#[derive(serde::Deserialize, serde::Serialize, schemars::JsonSchema)]
struct SkewedOutput {
    kept: i64,
    #[serde(skip_serializing)]
    hidden_from_serialization: i64,
}

#[derive(Debug, thiserror::Error)]
#[error("skew never fails")]
struct SkewError;

struct SkewTool;

impl TypedTool for SkewTool {
    const NAME: &'static str = "skew";
    const DESCRIPTION: &'static str = "Output skew probe.";

    type Args = AddArgs;
    type Context = ();
    type Output = SkewedOutput;
    type Error = SkewError;

    async fn execute(
        &self,
        args: Self::Args,
        (): Self::Context,
    ) -> Result<Self::Output, Self::Error> {
        Ok(SkewedOutput {
            kept: args.left,
            hidden_from_serialization: args.right,
        })
    }
}

#[test]
fn output_schema_is_generated_for_serialization() {
    let prepared: PreparedJson<SkewTool> = prepare_json().unwrap();
    assert!(prepared.definition().output_schema().is_none());

    let prepared = prepared.with_output_schema().unwrap();
    let output_schema = prepared.definition().output_schema().expect("present");

    // The serialization schema drops the field that never serializes...
    assert!(
        output_schema["properties"]
            .as_object()
            .expect("object properties")
            .contains_key("kept")
    );
    assert!(
        !output_schema["properties"]
            .as_object()
            .expect("object properties")
            .contains_key("hidden_from_serialization"),
        "for_serialize must respect skip_serializing: {output_schema}"
    );
    // ...while the deserialization schema of the same type keeps it.
    let input_schema = input_schema_for::<SkewedOutput>();
    assert!(
        input_schema["properties"]
            .as_object()
            .expect("object properties")
            .contains_key("hidden_from_serialization")
    );
    assert_eq!(
        output_schema["$schema"],
        "https://json-schema.org/draft/2020-12/schema"
    );

    // The executed output stays the plain owned value; nothing serializes it.
    let handle = ToolHandle::new(prepared.attach(SkewTool));
    let output =
        futures::executor::block_on(handle.execute(r#"{"left":2,"right":3}"#.to_owned(), ()))
            .unwrap();
    assert_eq!((output.kept, output.hidden_from_serialization), (2, 3));
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
struct Outer {
    inner: Inner,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
struct Inner {
    value: u32,
}

#[test]
fn decode_json_reports_real_paths_and_keeps_the_json_source() {
    let args = decode_json::<AddArgs>(r#"{"left": 2, "right": 3}"#).unwrap();
    assert_eq!((args.left, args.right), (2, 3));

    let error = decode_json::<AddArgs>(r#"{"left": "two", "right": 3}"#)
        .err()
        .expect_error("type mismatch rejected");
    let ArgumentError::Decode { path, source } = &error else {
        panic!("expected decode error, got {error:?}");
    };
    assert_eq!(path, "left");
    assert!(source.is_syntax() || source.is_data(), "json source kept");

    let error = decode_json::<Outer>(r#"{"inner": {"value": "NaN"}}"#)
        .err()
        .expect_error("nested path rejected");
    let ArgumentError::Decode { path, .. } = &error else {
        panic!("expected decode error, got {error:?}");
    };
    assert_eq!(path, "inner.value");

    let outer = decode_json::<Outer>(r#"{"inner": {"value": 7}}"#).unwrap();
    assert_eq!(outer.inner.value, 7);
}

#[test]
fn decode_json_rejects_trailing_input() {
    decode_json::<AddArgs>(r#"{"left":2,"right":3} "#).unwrap();

    let error = decode_json::<AddArgs>(r#"{"left":2,"right":3} trailing"#)
        .err()
        .expect_error("trailing input rejected");
    let ArgumentError::Trailing { source } = &error else {
        panic!("expected trailing error, got {error:?}");
    };
    assert!(source.is_syntax());

    let error = decode_json::<AddArgs>(r#"{"left":2,"right":3}{"left":0,"right":0}"#)
        .err()
        .expect_error("second document rejected");
    assert!(matches!(error, ArgumentError::Trailing { .. }));
}

#[test]
fn adapter_executes_through_the_handle_and_keeps_output_identity() {
    let prepared = prepare_json::<Add>().unwrap();
    let handle = ToolHandle::new(prepared.attach(Add { offset: 10 }));

    let sum = futures::executor::block_on(handle.execute(r#"{"left":2,"right":3}"#.to_owned(), ()))
        .unwrap();
    assert_eq!(sum.value, 15);
}

#[test]
fn adapter_surfaces_argument_errors_with_source_chain() {
    let prepared = prepare_json::<Add>().unwrap();
    let handle = ToolHandle::new(prepared.attach(Add { offset: 0 }));

    let error =
        futures::executor::block_on(handle.execute(r#"{"left":"two","right":3}"#.to_owned(), ()))
            .err()
            .expect_error("argument error surfaced");

    let InvocationError::Arguments(argument) = &error else {
        panic!("expected argument error, got {error:?}");
    };
    assert!(matches!(argument, ArgumentError::Decode { .. }));
    assert!(
        error
            .source()
            .and_then(|source| source.downcast_ref::<ArgumentError>())
            .is_some(),
        "source keeps the ArgumentError identity"
    );
}

#[test]
fn adapter_keeps_the_original_tool_error_identity() {
    let prepared = prepare_json::<Add>().unwrap();
    let handle = ToolHandle::new(prepared.attach(Add { offset: i64::MAX }));

    let error = futures::executor::block_on(
        handle.execute(r#"{"left":9223372036854775807,"right":1}"#.to_owned(), ()),
    )
    .err()
    .expect_error("tool error surfaced");

    let InvocationError::Tool(tool_error) = &error else {
        panic!("expected tool error, got {error:?}");
    };
    let source = error
        .source()
        .and_then(|source| source.downcast_ref::<AddError>())
        .expect("source keeps the concrete AddError");
    assert_eq!(source.to_string(), "integer addition overflow");
    assert_eq!(tool_error.to_string(), "integer addition overflow");
}

#[derive(Debug, thiserror::Error)]
#[error("close refused")]
struct CloseMarker;

struct Closable;

impl TypedTool for Closable {
    const NAME: &'static str = "closable";
    const DESCRIPTION: &'static str = "Close forwarding probe.";

    type Args = AddArgs;
    type Context = ();
    type Output = Sum;
    type Error = CloseMarker;

    async fn execute(
        &self,
        args: Self::Args,
        (): Self::Context,
    ) -> Result<Self::Output, Self::Error> {
        Ok(Sum {
            value: args.left + args.right,
        })
    }

    async fn close(&self) -> Result<(), Self::Error> {
        Err(CloseMarker)
    }
}

#[test]
fn adapter_close_forwards_the_original_error_type() {
    let prepared = prepare_json::<Closable>().unwrap();
    let handle = ToolHandle::new(prepared.attach(Closable));

    let error = futures::executor::block_on(handle.close())
        .err()
        .expect_error("close error surfaced");
    let InvocationError::Tool(_) = &error else {
        panic!("expected tool close error, got {error:?}");
    };
    assert!(
        error
            .source()
            .and_then(|source| source.downcast_ref::<CloseMarker>())
            .is_some(),
        "close keeps the original error identity"
    );

    // The default close of a tool without resources succeeds.
    let prepared = prepare_json::<Add>().unwrap();
    let handle = ToolHandle::new(prepared.attach(Add { offset: 0 }));
    futures::executor::block_on(handle.close()).unwrap();
}

/// `Send` but not `Sync`: the adapter input contract only requires `Send`.
struct OnceInput(Cell<&'static str>);

fn static_text(raw: &OnceInput) -> Result<&'static str, ArgumentError> {
    Ok(raw.0.get())
}

#[test]
fn adapter_inputs_only_need_send_not_sync() {
    fn assert_send<T: Send>() {}
    assert_send::<OnceInput>();

    let prepared = prepare_json::<Add>().unwrap();
    let handle = ToolHandle::new(prepared.attach_input(Add { offset: 10 }, static_text));

    let sum = futures::executor::block_on(
        handle.execute(OnceInput(Cell::new(r#"{"left":2,"right":3}"#)), ()),
    )
    .unwrap();
    assert_eq!(sum.value, 15);
}

#[test]
fn adapter_supports_payload_rejection_from_the_extractor() {
    struct Versioned {
        text: &'static str,
        format: &'static str,
        version: u32,
    }

    fn require_json_v1(raw: &Versioned) -> Result<&'static str, ArgumentError> {
        if raw.format != "application/json" || raw.version != 1 {
            return Err(ArgumentError::UnsupportedPayload {
                format: raw.format.to_owned(),
                version: raw.version,
            });
        }
        Ok(raw.text)
    }

    let prepared = prepare_json::<Add>().unwrap();
    let handle = ToolHandle::new(prepared.attach_input(Add { offset: 0 }, require_json_v1));

    let error = futures::executor::block_on(handle.execute(
        Versioned {
            text: "{}",
            format: "text/plain",
            version: 2,
        },
        (),
    ))
    .err()
    .expect_error("payload rejection surfaced");
    let InvocationError::Arguments(ArgumentError::UnsupportedPayload { format, version }) = &error
    else {
        panic!("expected payload rejection, got {error:?}");
    };
    assert_eq!((format.as_str(), *version), ("text/plain", 2));
}
