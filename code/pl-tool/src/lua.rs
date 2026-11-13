//! Lua's narrow binding to the original Thread owner; no direct executor access.
use pl_agent_tool::{Tool, ToolDefinition};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::TaskAccess,
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_protocol::ToolSpec;
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};
use tokio_util::sync::CancellationToken;

pub use pl_tool_lua::ExecInput;

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct Receipt<'a> {
    #[serde(flatten)]
    execution: &'a pl_tool_lua::ExecOutput,
    nested_call_ids: Vec<String>,
}

/// Reads owner-assigned child identities retained in the original Lua receipt.
pub fn saved_nested_call_ids(payload: &OpaquePayload) -> Result<Option<Vec<String>>, ToolError> {
    if payload.format() != "pl.tool.lua" {
        return Ok(None);
    }
    if payload.version() != 1 {
        return Err(ToolError::new(std::io::Error::other(
            "unsupported Lua receipt version",
        )));
    }
    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Children {
        nested_call_ids: Vec<String>,
    }
    let children: Children = serde_json::from_str(payload.content()).map_err(ToolError::new)?;
    Ok(Some(children.nested_call_ids))
}

#[derive(Debug)]
pub struct LuaTool {
    definition: ToolDefinition,
}
impl LuaTool {
    pub fn new(sdk: &str) -> Self {
        Self {
            definition: pl_tool_lua::definition(sdk),
        }
    }
}

struct Binding {
    id: String,
    text_input: bool,
    parallel: bool,
}
struct Host {
    tasks: TaskAccess,
    bindings: BTreeMap<String, Binding>,
    cancellation: CancellationToken,
    resources: Arc<Mutex<Vec<ContextContent>>>,
}

impl Host {
    fn retain_resources(&self, output: &ToolOutput) -> Result<(), String> {
        let mut media = Vec::new();
        for part in output.context() {
            let retain = match part {
                ContextContent::Resource { .. } => true,
                ContextContent::Opaque { payload } => pl_model::runtime::decode_attachment(payload)
                    .map_err(|error| error.to_string())?
                    .is_some(),
                _ => false,
            };
            if retain {
                media.push(part.clone());
            }
        }
        let mut saved = self
            .resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for part in media {
            if !saved.contains(&part) {
                saved.push(part);
            }
        }
        Ok(())
    }
}

impl pl_tool_lua::ToolHost for Host {
    fn bindings(&self) -> Vec<pl_tool_lua::Binding> {
        self.bindings
            .iter()
            .map(|(name, binding)| pl_tool_lua::Binding {
                name: name.clone(),
                parallel: binding.parallel,
            })
            .collect()
    }
    async fn call(
        &self,
        name: String,
        arguments: serde_json::Value,
    ) -> Result<serde_json::Value, pl_tool_lua::CallFailure> {
        let binding = self.bindings.get(&name).ok_or("unknown program tool")?;
        let arguments = if binding.text_input {
            OpaquePayload::text(
                arguments
                    .as_str()
                    .ok_or("this tool requires a string argument")?
                    .to_owned(),
            )
        } else {
            OpaquePayload::new("application/json", 1, arguments.to_string())
                .map_err(|e| e.to_string())?
        };
        let outcome = self
            .tasks
            .call_nested(binding.id.clone(), arguments, self.cancellation.clone())
            .await;
        // A completed command's exit status is data the program can inspect and filter.
        // Core still retains the child's real failed task and original output. Transport,
        // cancellation, permission, capture and archive failures keep their error semantics.
        if let Err(pl_core::thread::ThreadError::Tool(error)) = &outcome
            && matches!(
                error.source.downcast_ref::<crate::exec::ExecFailure>(),
                Some(crate::exec::ExecFailure::NonzeroExit { .. })
            )
            && let Some(output) = error.observed_output()
        {
            self.retain_resources(output)?;
            return program_output(output).map_err(Into::into);
        }
        let output = outcome.map_err(|error| {
            let mut message = error.to_string();
            let output = match &error {
                pl_core::thread::ThreadError::Tool(error) => {
                    error.observed_output().and_then(|output| {
                        if let Err(error) = self.retain_resources(output) {
                            message.push_str(&format!("; attachment: {error}"));
                        }
                        match decode_output(output) {
                            Ok(value) => Some(value),
                            Err(error) => {
                                message.push_str(&format!("; result encoding: {error}"));
                                None
                            }
                        }
                    })
                }
                _ => None,
            };
            pl_tool_lua::CallFailure { message, output }
        })?;
        self.retain_resources(&output)?;
        program_output(&output).map_err(Into::into)
    }
}

/// The Lua command view carries execution decisions, not the original archive envelope.
/// Error inspection and task queries retain the full authored receipt.
fn program_output(output: &ToolOutput) -> Result<serde_json::Value, String> {
    let mut value = decode_output(output)?;
    if output.payload().format() != "pl.tool.exec" {
        return Ok(value);
    }
    let record = value
        .as_object_mut()
        .ok_or("command receipt must be an object")?;
    // The authored exec envelope also carries observed stdin results. Its explicit
    // targetTaskId distinguishes the input call from the target command's output.
    if record.contains_key("targetTaskId") {
        record.retain(|key, _| matches!(key.as_str(), "taskId" | "targetTaskId" | "inputReceipt"));
        return Ok(value);
    }
    let mut paths = Vec::new();
    for (stream, file) in [("stdout", "stdoutFile"), ("stderr", "stderrFile")] {
        let body = record
            .get_mut(stream)
            .and_then(serde_json::Value::as_object_mut)
            .ok_or("command receipt must contain both streams")?;
        if !body
            .get("content")
            .is_some_and(serde_json::Value::is_string)
        {
            return Err("command receipt stream must contain text".into());
        }
        let truncated = body.get("wasTruncated") == Some(&serde_json::Value::Bool(true));
        let lossy = body.get("textLossy") == Some(&serde_json::Value::Bool(true));
        body.retain(|key, _| {
            key == "content"
                || (truncated && matches!(key.as_str(), "wasTruncated" | "omittedBytes"))
                || (lossy && key == "textLossy")
        });
        if truncated {
            paths.push(file);
        }
    }
    record.retain(|key, _| {
        matches!(key.as_str(), "taskId" | "exitCode" | "stdout" | "stderr")
            || paths.contains(&key.as_str())
    });
    Ok(value)
}

fn decode_output(output: &ToolOutput) -> Result<serde_json::Value, String> {
    let payload = output.payload();
    match payload.format() {
        // MCP outputSchema describes structuredContent. Retain the complete protocol
        // receipt as the child original; expose its declared structured value to Lua.
        "pl.tool.mcp-result" => {
            let value: serde_json::Value =
                serde_json::from_str(payload.content()).map_err(|error| error.to_string())?;
            Ok(value.get("structuredContent").cloned().unwrap_or(value))
        }
        // Task tools deliberately keep complete facts in payload and expose a bounded,
        // cursor-aware receipt. Preserve that authored return contract inside Lua as well.
        "pl.tool.task" | "pl.tool.list-tasks" => {
            let text = output
                .context()
                .iter()
                .find_map(|part| match part {
                    ContextContent::Text { text } => Some(text),
                    _ => None,
                })
                .ok_or("task result has no declared JSON receipt")?;
            serde_json::from_str(text).map_err(|error| error.to_string())
        }
        "application/json"
        | "pl.tool.exec"
        | "pl.tool.stdin"
        | "pl.tool.git"
        | "pl.tool.lsp"
        | "pl.tool.path-stat"
        | "pl.tool.todo"
        | "pl.tool.mcp"
        | "pl.tool.mcp-resources"
        | "pl.tool.mcp-unarchived"
        | "pl.tool.mcp-resources-unarchived"
        | "pl.tool.file-write"
        | "pl.tool.skill-list"
        | "pl.tool.skill-view"
        | "pl.tool.skill-mutation"
        | "pl.tool.web-search"
        | "pl.tool.task-result"
        | "pl.tool.files"
        | "pl.tool.image"
        | "pl.tool.image-card"
        | "pl.tool.image-generation"
        | "pl.studio.agent-control"
        | "pl.studio.bot-tool" => {
            serde_json::from_str(payload.content()).map_err(|e| e.to_string())
        }
        _ => Ok(serde_json::Value::String(payload.content().to_owned())),
    }
}

fn selected_text(result: &pl_tool_lua::ExecOutput, task_id: &str) -> String {
    let maximum = result.model_output_bytes;
    let mut text = result.output.clone();
    if let Some(error) = &result.error {
        text.push_str(&format!("\nLua execution failed: {error}"));
    }
    if text.is_empty() {
        return pl_output::bounded_text("Lua execution completed with no output.", maximum, 0).text;
    }
    if text.len() <= maximum {
        return text;
    }
    let status = if result.error.is_some() {
        "Lua execution failed; "
    } else {
        ""
    };
    let notice = format!(
        "[{status}Output truncated; originalBytes={}; tools.get_tool_task({{taskId={},resultCursor=0}})]\n",
        text.len(),
        serde_json::to_string(task_id).expect("task identity encodes as JSON")
    );
    let mut selected = pl_output::bounded_text(&notice, maximum, 0).text;
    let preview = pl_output::OutputExcerpt::from_parts(text.into_bytes(), Vec::new(), 0)
        .project(maximum.saturating_sub(selected.len()));
    selected.push_str(&preview.content);
    selected
}

impl Tool for LuaTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(ToolError::new(std::io::Error::other(
                "Lua exec requires application/json@1 arguments",
            )));
        }
        let tasks = context
            .tasks
            .ok_or_else(|| ToolError::new(std::io::Error::other("missing Lua task scope")))?;
        let mut bindings = BTreeMap::new();
        for tool in tasks.nested_tools() {
            let spec: ToolSpec = serde_json::from_str(tool.declaration.declaration.content())
                .map_err(ToolError::new)?;
            let text_input = matches!(spec, ToolSpec::Custom { .. });
            bindings.insert(
                spec.name().to_owned(),
                Binding {
                    id: tool.declaration.tool_id,
                    text_input,
                    parallel: tool.parallel,
                },
            );
        }
        let scope = context.cancellation.child_token();
        let resources = Arc::new(Mutex::new(Vec::new()));
        let result = pl_tool_lua::ExecTool::<Host>::new(self.definition.clone())
            .execute(
                input.content().to_owned(),
                pl_tool_lua::ExecContext {
                    host: Host {
                        tasks: tasks.clone(),
                        bindings,
                        cancellation: scope.clone(),
                        resources: resources.clone(),
                    },
                    cancellation: scope.clone(),
                },
            )
            .await;
        scope.cancel();
        tasks.drain_nested().await.map_err(ToolError::new)?;
        let result = result.map_err(ToolError::new)?;
        let payload = OpaquePayload::new(
            "pl.tool.lua",
            1,
            serde_json::to_string(&Receipt {
                execution: &result,
                nested_call_ids: tasks.nested_call_ids(),
            })
            .map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        let text = selected_text(&result, tasks.current_task_id());
        let selected_resources: Vec<_> = resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .filter(|part| match part {
                ContextContent::Resource { reference } => {
                    text.contains(reference.id())
                        || reference.media_type().starts_with("image/")
                        || reference.media_type().starts_with("audio/")
                        || reference.media_type().starts_with("video/")
                }
                ContextContent::Opaque { .. } => true,
                _ => false,
            })
            .cloned()
            .collect();
        let mut content = vec![ContextContent::Text { text: text.into() }];
        content.extend(selected_resources);
        let output = ToolOutput::new(payload, content);
        match result.error {
            Some(_) => Err(ToolError::new(std::io::Error::other(
                "Lua execution failed; original diagnostic retained in task result",
            ))
            .with_output(output)),
            None => Ok(output),
        }
    }
}

/// Projects the same authored schemas used for dispatch, in deterministic catalog order.
pub fn sdk(
    declarations: impl IntoIterator<Item = (String, OpaquePayload)>,
) -> Result<String, serde_json::Error> {
    let mut tools = BTreeMap::new();
    for (id, payload) in declarations {
        let spec: ToolSpec = serde_json::from_str(payload.content())?;
        let line = match &spec {
            ToolSpec::Function {
                name,
                description,
                input_schema,
                output_schema,
                ..
            } => {
                let mut line = format!(
                    "tools[{name:?}](args) -- {description}\ninput: {}",
                    sdk_schema(input_schema)
                );
                if let Some(output) = output_schema {
                    line.push_str(&format!("\noutput: {}", sdk_schema(output)));
                }
                line
            }
            ToolSpec::Custom {
                name,
                description,
                output_schema,
                ..
            } => {
                let mut line = format!("tools[{name:?}](text) -- {description}\ninput: Lua string");
                if let Some(output) = output_schema {
                    line.push_str(&format!("\noutput: {}", sdk_schema(output)));
                }
                line
            }
            _ => continue,
        };
        tools.insert(id, line);
    }
    Ok(tools.into_values().collect::<Vec<_>>().join("\n"))
}

// The Lua SDK is documentation, not a provider validation schema. Omit root
// generator metadata without traversing data properties or changing the frozen declaration.
fn sdk_schema(schema: &serde_json::Value) -> String {
    let mut schema = schema.clone();
    if let Some(object) = schema.as_object_mut() {
        object.remove("$schema");
        object.remove("title");
    }
    schema.to_string()
}

/// Pure declaration projection over the frozen visible set (including newly discovered tools).
pub fn project_catalog(declarations: &[pl_core::model::ModelToolDeclaration]) -> OpaquePayload {
    let sdk = sdk(declarations
        .iter()
        .map(|tool| (tool.tool_id.clone(), tool.declaration.clone())))
    .expect("host prepared valid tool specifications");
    let definition = pl_tool_lua::definition(&sdk);
    let spec = pl_model::completion::tool_definition_to_spec(
        &definition,
        pl_model::completion::ToolCallPolicy::DirectOnly,
    );
    pl_model::runtime::thread_tool_declaration(&spec).expect("host Lua declaration encodes")
}

#[cfg(test)]
mod tests {
    #[test]
    fn sdk_omits_root_metadata_but_keeps_named_properties_and_references() {
        let schema = serde_json::json!({
            "$schema":"https://json-schema.org/draft/2020-12/schema",
            "title":"GeneratedInput", "type":"object",
            "$defs":{"Item":{"type":"string","title":"ReferencedItem"}},
            "properties":{
                "title":{"type":"string","description":"User supplied title"},
                "$schema":{"$ref":"#/$defs/Item"}
            },
            "required":["title"], "additionalProperties":false
        });
        let original = schema.to_string();
        let projected: serde_json::Value =
            serde_json::from_str(&super::sdk_schema(&schema)).unwrap();
        assert!(projected.get("title").is_none());
        assert!(projected.get("$schema").is_none());
        for key in [
            "type",
            "$defs",
            "properties",
            "required",
            "additionalProperties",
        ] {
            assert_eq!(projected[key], schema[key]);
        }
        assert_eq!(schema.to_string(), original);
    }

    #[test]
    fn mcp_structured_result_matches_its_output_schema_without_the_protocol_wrapper() {
        use pl_core::{context::OpaquePayload, tool::ToolOutput};
        let protocol = serde_json::json!({"content":[{"type":"text","text":"not selected"}],"structuredContent":{"count":3},"isError":false});
        let output = ToolOutput::new(
            OpaquePayload::new("pl.tool.mcp-result", 1, protocol.to_string()).unwrap(),
            vec![],
        );
        assert_eq!(
            super::decode_output(&output).unwrap(),
            serde_json::json!({"count":3})
        );
        let protocol =
            serde_json::json!({"content":[{"type":"text","text":"plain result"}],"isError":false});
        let output = ToolOutput::new(
            OpaquePayload::new("pl.tool.mcp-result", 1, protocol.to_string()).unwrap(),
            vec![],
        );
        assert_eq!(super::decode_output(&output).unwrap(), protocol);
    }

    #[test]
    fn selected_output_including_diagnostics_respects_utf8_byte_budget() {
        for maximum in [1, 8, 64, 8192] {
            for error in [None, Some("错误".repeat(4096))] {
                let result = pl_tool_lua::ExecOutput {
                    output: "中间".repeat(8192),
                    model_output_bytes: maximum,
                    error,
                };
                let text = super::selected_text(&result, "task:budget-test");
                assert!(!text.is_empty());
                assert!(text.len() <= maximum);
                assert_eq!(result.output.len(), 49152);
            }
        }
    }
}
