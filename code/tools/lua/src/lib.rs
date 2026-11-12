//! Bounded Lua orchestration. Hosts retain all tool admission and side-effect ownership.
use futures::{StreamExt, stream};
use mlua::{Function, HookTriggers, Lua, LuaSerdeExt, StdLib, Value, VmState};
use serde::{Deserialize, Serialize};
use std::{
    future::Future,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio_util::sync::CancellationToken;

pub const MAX_CAPTURE_BYTES: usize = 16 * 1024 * 1024;
pub const MAX_MODEL_BYTES: usize = 64 * 1024;

#[pl_agent_tool::tool_args]
#[derive(Clone)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExecInput {
    /// Lua source. Call tools.name(args); only print and return enter the conversation.
    pub code: String,
    /// Total elapsed budget, including tool waits. Default 120000, maximum 600000.
    #[serde(default)]
    pub timeout_ms: Option<u64>,
    /// UTF-8 model output budget. Default 8192, maximum 65536. Full output is retained separately.
    #[serde(default)]
    pub max_output_bytes: Option<usize>,
}

#[derive(Debug, Clone)]
pub struct Binding {
    pub name: String,
    pub parallel: bool,
}

/// A failed tool can carry its already-observed result without becoming successful.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CallFailure {
    pub message: String,
    pub output: Option<serde_json::Value>,
}
impl From<String> for CallFailure {
    fn from(message: String) -> Self {
        Self {
            message,
            output: None,
        }
    }
}
impl From<&str> for CallFailure {
    fn from(message: &str) -> Self {
        message.to_owned().into()
    }
}

/// A capability scoped to a single program. The host authorizes and retains every call.
pub trait ToolHost: Send + Sync + 'static {
    fn bindings(&self) -> Vec<Binding>;
    fn call(
        &self,
        name: String,
        arguments: serde_json::Value,
    ) -> impl Future<Output = Result<serde_json::Value, CallFailure>> + Send;
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecOutput {
    pub output: String,
    pub model_output_bytes: usize,
    pub error: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum ExecError {
    #[error("{0}")]
    InvalidInput(String),
    #[error("Lua worker failed: {0}")]
    Worker(String),
}

pub fn definition(sdk: &str) -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json("exec", format!(
        "Execute Lua 5.4 to orchestrate tools. Call tools.name(args) with Lua tables; asynchronous tools suspend this program automatically. Only print(...) and the returned value enter model context; tables are rendered as JSON. Example: local r = tools.exec_command({{command='rg --files'}}); print(r.stdout.content). Filter intermediate results before printing. Each call has fresh state. Use parallel({{function() ... end, ...}}) for independent work; the host serializes mutations. Failed calls raise Lua errors (pcall returns an error table with message and optional output); completed side effects are never replayed. json.null and json.array preserve JSON null and empty arrays. OS/file/network operations are available only through tools.\nProgram-only tools (these names are not directly callable):\n{sdk}"
    ), pl_agent_tool::typed::input_schema_for::<ExecInput>()).expect("static Lua declaration")
}

pub async fn execute<H: ToolHost>(
    input: ExecInput,
    host: H,
    cancellation: CancellationToken,
) -> Result<ExecOutput, ExecError> {
    let timeout = input.timeout_ms.unwrap_or(120_000);
    let maximum = input.max_output_bytes.unwrap_or(8192);
    if input.code.trim().is_empty()
        || !(1..=600_000).contains(&timeout)
        || !(1..=MAX_MODEL_BYTES).contains(&maximum)
    {
        return Err(ExecError::InvalidInput(
            "code must be nonblank; timeoutMs must be 1..600000 and maxOutputBytes 1..65536".into(),
        ));
    }
    let deadline = Instant::now() + Duration::from_millis(timeout);
    let guard = cancellation.clone().drop_guard();
    let output = tokio::task::spawn_blocking(move || {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| ExecError::Worker(e.to_string()))?;
        runtime.block_on(run(input.code, Arc::new(host), cancellation, deadline))
    })
    .await
    .map_err(|e| ExecError::Worker(e.to_string()))?;
    guard.disarm();
    output.map(|mut output| {
        output.model_output_bytes = maximum;
        output
    })
}

async fn run<H: ToolHost>(
    code: String,
    host: Arc<H>,
    cancellation: CancellationToken,
    deadline: Instant,
) -> Result<ExecOutput, ExecError> {
    let logs = Arc::new(Mutex::new(Capture::default()));
    let lua = Lua::new_with(
        StdLib::TABLE | StdLib::STRING | StdLib::MATH | StdLib::UTF8,
        Default::default(),
    )
    .map_err(|e| ExecError::Worker(e.to_string()))?;
    lua.set_memory_limit(64 * 1024 * 1024)
        .map_err(|e| ExecError::Worker(e.to_string()))?;
    // Yield rather than throwing a catchable hook error: the Rust cancellation boundary owns stop.
    lua.set_global_hook(HookTriggers::new().every_nth_instruction(10_000), |_, _| {
        Ok(VmState::Yield)
    })
    .map_err(|e| ExecError::Worker(e.to_string()))?;
    let result: mlua::Result<()> = async {
        let globals = lua.globals();
        for name in ["dofile", "loadfile", "load", "collectgarbage"] { globals.set(name, Value::Nil)?; }
        let tools = lua.create_table()?;
        let gate = Arc::new(tokio::sync::RwLock::new(()));
        for binding in host.bindings() {
            let host = host.clone();
            let gate = gate.clone();
            let name = binding.name.clone();
            let callback = lua.create_async_function(move |lua, value: Value| {
                let host = host.clone(); let gate = gate.clone(); let name = name.clone();
                async move {
                    let arguments = lua.from_value(value)?;
                    let result = if binding.parallel {
                        let _guard = gate.read().await;
                        host.call(name, arguments).await
                    } else {
                        let _guard = gate.write().await;
                        host.call(name, arguments).await
                    };
                    match result {
                        Ok(value) => Ok((true, lua.to_value(&value)?)),
                        Err(error) => {
                            let value = lua.to_value(&error)?;
                            if let Value::Table(table) = &value {
                                let meta = lua.create_table()?;
                                meta.set("__tostring", lua.create_function(|lua, table: mlua::Table| {
                                    let message: String = table.get("message")?;
                                    let output: Value = table.get("output")?;
                                    if output.is_nil() { return Ok(message); }
                                    let output: serde_json::Value = lua.from_value(output)?;
                                    Ok(format!("{message}\nObserved output: {output}"))
                                })?)?;
                                table.set_metatable(Some(meta))?;
                            }
                            Ok((false, value))
                        }
                    }
                }
            })?;
            let wrap: Function = lua.load("return function(call) return function(args) local ok,value=call(args); if not ok then error(value,0) end; return value end end").eval()?;
            tools.set(binding.name, wrap.call::<Function>(callback)?)?;
        }
        globals.set("tools", tools)?;
        let json = lua.create_table()?;
        json.set("null", lua.null())?;
        json.set("array", lua.create_function(|lua, table: mlua::Table| { table.set_metatable(Some(lua.array_metatable()))?; Ok(table) })?)?;
        globals.set("json", json)?;
        globals.set("parallel", lua.create_async_function(|lua, functions: Vec<Function>| async move {
            let results = stream::iter(functions.into_iter().map(|f| async move { f.call_async::<Value>(()).await })).buffered(4).collect::<Vec<_>>().await;
            let table = lua.create_table()?;
            table.set_metatable(Some(lua.array_metatable()))?;
            for (i, result) in results.into_iter().enumerate() { table.set(i + 1, result?)?; }
            Ok(table)
        })?)?;
        let print_logs = logs.clone();
        globals.set("print", lua.create_function(move |lua, values: mlua::MultiValue| {
            let tostring: Function = lua.globals().get("tostring")?;
            let mut line = String::new();
            for value in values {
                if !line.is_empty() { line.push('\t'); }
                if matches!(value, Value::Table(_)) {
                    let value: serde_json::Value = lua.from_value(value)?;
                    line.push_str(&serde_json::to_string(&value).map_err(mlua::Error::external)?);
                } else { line.push_str(&tostring.call::<String>(value)?); }
            }
            line.push('\n');
            append(&print_logs, &line)
        })?)?;
        let evaluation = lua.load(&code).set_name("exec").set_mode(mlua::chunk::ChunkMode::Text).eval_async::<Value>();
        tokio::pin!(evaluation);
        let value = tokio::select! {
            biased;
            _ = cancellation.cancelled() => return Err(mlua::Error::external("Lua execution cancelled")),
            _ = tokio::time::sleep_until(tokio::time::Instant::from_std(deadline)) => return Err(mlua::Error::external("Lua execution timed out")),
            value = &mut evaluation => value?,
        };
        if !value.is_nil() {
            let value: serde_json::Value = lua.from_value(value)?;
            let text = match value { serde_json::Value::String(text) => text, value => serde_json::to_string(&value).map_err(mlua::Error::external)? };
            append(&logs, &text)?;
        }
        Ok(())
    }.await;
    Ok(ExecOutput {
        output: logs
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .text
            .clone(),
        model_output_bytes: 8192,
        error: result.err().map(|e| {
            let message = e.to_string();
            let mut end = message.len().min(4096);
            while !message.is_char_boundary(end) {
                end -= 1;
            }
            message[..end].to_owned()
        }),
    })
}

#[derive(Default)]
struct Capture {
    text: String,
    encoded_bytes: usize,
}

fn append(logs: &Mutex<Capture>, text: &str) -> mlua::Result<()> {
    let mut logs = logs
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    // Count both the result JSON string and its opaque-payload escaping. Reserve room for
    // the bounded model view, diagnostics and framework envelope before accepting bytes.
    let cost = text
        .bytes()
        .map(|byte| match byte {
            b'"' | b'\\' => 4,
            b'\n' | b'\r' | b'\t' | 8 | 12 => 3,
            0..=31 => 7,
            _ => 1,
        })
        .sum::<usize>();
    let limit = MAX_CAPTURE_BYTES - MAX_MODEL_BYTES * 8 - 16 * 1024;
    if logs.encoded_bytes.saturating_add(cost) > limit {
        return Err(mlua::Error::external("Lua output capture limit exceeded"));
    }
    logs.encoded_bytes += cost;
    logs.text.push_str(text);
    Ok(())
}

/// Invocation-scoped capabilities; the independent author does not retain host resources.
pub struct ExecContext<H> {
    pub host: H,
    pub cancellation: CancellationToken,
}
/// Independent consumer-side Lua tool, also usable without Anywork.
pub struct ExecTool<H> {
    definition: pl_agent_tool::ToolDefinition,
    host: std::marker::PhantomData<fn() -> H>,
}
impl<H> ExecTool<H> {
    pub fn new(definition: pl_agent_tool::ToolDefinition) -> Self {
        Self {
            definition,
            host: std::marker::PhantomData,
        }
    }
}
impl<H: ToolHost> pl_agent_tool::Tool for ExecTool<H> {
    type Input = String;
    type Context = ExecContext<H>;
    type Output = ExecOutput;
    type Error = ExecError;
    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }
    async fn execute(
        &self,
        input: String,
        context: ExecContext<H>,
    ) -> Result<ExecOutput, ExecError> {
        let input = pl_agent_tool::typed::decode_json(&input)
            .map_err(|error| ExecError::InvalidInput(error.to_string()))?;
        execute(input, context.host, context.cancellation).await
    }
}
