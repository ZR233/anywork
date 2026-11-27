//! Lua's narrow binding to the original Thread owner; no direct executor access.
use pl_agent_tool::{Tool, ToolDefinition};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::{TaskAccess, ToolOutcome},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError, ToolFailureKind},
    },
};
use pl_model::completion::ToolSpec;
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};
use tokio_util::sync::CancellationToken;

pub use pl_tool_lua::ExecInput;

/// Reads owner-assigned child identities from the details of a committed Lua result.
pub fn saved_nested_call_ids(
    details: Option<&serde_json::Value>,
) -> Result<Option<Vec<String>>, ToolError> {
    details
        .and_then(|details| details.get("nestedCallIds"))
        .map(|ids| serde_json::from_value(ids.clone()).map_err(ToolError::new))
        .transpose()
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
    fn retain_resources(&self, output: &ToolOutput) {
        let mut saved = self
            .resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for part in output.content() {
            if matches!(
                part,
                ContextContent::Resource { .. } | ContextContent::Media { .. }
            ) && !saved.contains(part)
            {
                saved.push(part.clone());
            }
        }
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
    ) -> Result<Option<serde_json::Value>, pl_tool_lua::CallFailure> {
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
        let completion = self
            .tasks
            .call_nested(binding.id.clone(), arguments, self.cancellation.clone())
            .await
            .map_err(|error| error.to_string())?;
        let observed = completion.output();
        let output = observed.and_then(ToolOutput::data).cloned();
        let message = match completion.outcome() {
            ToolOutcome::Succeeded => None,
            ToolOutcome::Failed(error) if error.kind() == ToolFailureKind::Operation => None,
            ToolOutcome::Failed(error) => Some(error.to_string()),
            outcome @ (ToolOutcome::Cancelled | ToolOutcome::Interrupted) => {
                let mut message = if matches!(outcome, ToolOutcome::Cancelled) {
                    String::from("tool execution cancelled")
                } else {
                    String::from("tool execution interrupted")
                };
                if let Some(cause) = completion.error() {
                    message.push_str(&format!(": {cause}"));
                }
                Some(message)
            }
        };
        let Some(mut message) = message else {
            if let Some(observed) = observed {
                self.retain_resources(observed);
            }
            return Ok(output);
        };
        if let Some(observed) = observed {
            append_invocation_diagnostic(&mut message, observed);
        }
        Err(pl_tool_lua::CallFailure { message, output })
    }
}

/// Authors can select explicit text blocks for failed invocations, without exposing unselected content.
fn append_invocation_diagnostic(message: &mut String, output: &ToolOutput) {
    let Some(selection) = output
        .details()
        .and_then(|details| details.get("invocationDiagnosticContent"))
        .and_then(serde_json::Value::as_array)
    else {
        return;
    };
    for index in selection {
        if let Some(index) = index.as_u64().and_then(|index| usize::try_from(index).ok())
            && let Some(ContextContent::Text { text }) = output.content().get(index)
        {
            message.push('\n');
            message.push_str(text);
        }
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
    // The original cannot be recovered if its identity or paging arguments are cut off.
    // A budget smaller than this control receipt leaves no room for a content preview.
    let mut selected = notice;
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
        let text = selected_text(&result, tasks.current_task_id());
        let selected_resources: Vec<_> = resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .filter(|part| match part {
                ContextContent::Resource { reference } => {
                    result.output.contains(reference.id()) && text.contains(reference.id())
                }
                ContextContent::Media { .. } => true,
                _ => false,
            })
            .cloned()
            .collect();
        let mut content = vec![ContextContent::Text { text: text.into() }];
        content.extend(selected_resources);
        let output = ToolOutput::from_data(
            serde_json::json!({"output": result.output, "error": result.error}),
            content,
        )
        .with_details(serde_json::json!({
            "nestedCallIds": tasks.nested_call_ids(),
            "modelOutputBytes": result.model_output_bytes,
        }));
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

// Embedded SDK declarations are model input too. Reuse the model's schema-position-aware
// projection; never recursively filter arbitrary JSON data or mutate authored declarations.
fn sdk_schema(schema: &serde_json::Value) -> String {
    let mut schema = schema.clone();
    pl_model::completion::tool_schema::project_schema_for_model(&mut schema);
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
    fn sdk_omits_nested_generator_metadata_but_keeps_named_properties_and_references() {
        let schema = serde_json::json!({
            "$schema":"https://json-schema.org/draft/2020-12/schema",
            "title":"GeneratedInput", "type":"object",
            "$defs":{"Item":{"type":"string","title":"ReferencedItem"},"Unused":{"type":"number"}},
            "properties":{
                "title":{"type":"string","description":"User supplied title"},
                "$schema":{"$ref":"#/$defs/Item"},
                "literal":{"const":{"title":"literal value","default":7}},
                "count":{"type":"integer","minimum":1,"default":3,"examples":[4]}
            },
            "required":["title"], "additionalProperties":false
        });
        let original = schema.to_string();
        let projected: serde_json::Value =
            serde_json::from_str(&super::sdk_schema(&schema)).unwrap();
        assert!(projected.get("title").is_none());
        assert!(projected.get("$schema").is_none());
        for key in ["type", "required", "additionalProperties"] {
            assert_eq!(projected[key], schema[key]);
        }
        assert_eq!(
            projected["properties"]["title"],
            schema["properties"]["title"]
        );
        assert_eq!(
            projected["properties"]["$schema"],
            schema["properties"]["$schema"]
        );
        assert_eq!(
            projected["properties"]["literal"],
            schema["properties"]["literal"]
        );
        assert_eq!(
            projected["properties"]["count"],
            serde_json::json!({"type":"integer","minimum":1})
        );
        assert_eq!(
            projected["$defs"],
            serde_json::json!({"Item":{"type":"string"}})
        );
        assert_eq!(schema.to_string(), original);
    }

    #[test]
    fn selected_output_including_diagnostics_respects_utf8_byte_budget() {
        for maximum in [256, 8192] {
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

    #[test]
    fn truncated_output_keeps_complete_recovery_receipt_with_a_tiny_budget() {
        let task_id = format!(
            "task:model-call:36:{}:37:call_{}",
            "a".repeat(36),
            "b".repeat(32)
        );
        for (maximum, error) in [1, 8, 64, 128].into_iter().flat_map(|maximum| {
            [None, Some("EXPECTED_FAILURE".into())].map(|error| (maximum, error))
        }) {
            let result = pl_tool_lua::ExecOutput {
                output: "中文🧭".repeat(4096),
                model_output_bytes: maximum,
                error,
            };
            let text = super::selected_text(&result, &task_id);
            assert!(
                text.contains(&format!("taskId=\"{task_id}\",resultCursor=0}})]\n")),
                "incomplete recovery receipt: {text}"
            );
            assert!(
                !text.contains("中文🧭"),
                "a tiny budget must not include an output preview"
            );
        }
    }
}
