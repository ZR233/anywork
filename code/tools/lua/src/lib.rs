//! Bounded Lua orchestration. Hosts retain all tool admission and side-effect ownership.
use futures::{StreamExt, stream::FuturesUnordered};
use mlua::{Function, HookTriggers, Lua, LuaSerdeExt, StdLib, Value, VmState};
use serde::{Deserialize, Serialize};
use std::{
    future::Future,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::{Duration, Instant},
};
use tokio_util::sync::CancellationToken;

pub const MAX_CAPTURE_BYTES: usize = 16 * 1024 * 1024;
const COMMAND_EXAMPLE: &str = "local r = tools.exec_command({command=[=[pwd]=]}); print({exitCode=r.exitCode, stdout=r.stdout.content, stderr=r.stderr.content})";

struct AdmissionPause(Arc<AtomicUsize>);
impl AdmissionPause {
    fn new(admission: &Arc<AtomicUsize>) -> Self {
        admission.fetch_add(1, Ordering::AcqRel);
        Self(admission.clone())
    }
}
impl Drop for AdmissionPause {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::Release);
    }
}

async fn invoke_function(index: usize, function: Function) -> (usize, mlua::Result<Value>) {
    (index, function.call_async::<Value>(()).await)
}

#[pl_agent_tool::tool_args]
#[derive(Clone)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExecInput {
    /// Lua 5.4 program. Complete shell example: local r = tools.exec_command({command=[=[pwd]=]}); print({exitCode=r.exitCode, stdout=r.stdout.content, stderr=r.stderr.content})
    /// Use Lua tables with key=value. Put shell text inside command; only print/return enter context.
    pub code: String,
    /// Positive total execution deadline in milliseconds, including child waits (default 120000).
    /// Expiry cancels the program and its children. Background delivery is automatic;
    /// this is not a foreground wait or yield setting.
    #[serde(default)]
    pub timeout_ms: Option<u64>,
    /// Positive UTF-8 model output budget. Default 8192. Full output is retained separately.
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
        "Run a Lua 5.4 program in code. Complete shell-call example (replace the command string):\n{COMMAND_EXAMPLE}\n\nLua calls use parentheses and tables with key=value; close the table before the call: tools.name({{key=value}}). Long strings [=[...]=] preserve quotes and newlines: local text = [=[content]=]; return tools.name(text). A string assignment has no closing call parenthesis. tools.exec_command returns a terminal record: exitCode 0 means command success; nonzero exits are returned as data with stdout.content and stderr.content. Include stderr and exitCode when printing command output so command errors stay visible. Check exitCode before dependent actions; use assert(r.exitCode == 0) to stop the program on a failed command.\nOnly print(...) and return enter context; print tables as JSON and select the fields you need. Selected output defaults to 8192 UTF-8 bytes: filter before printing, or set a larger maxOutputBytes for a complete relevant excerpt. Truncated results identify the original task for get_tool_task paging; do not rerun commands to recover output. timeoutMs is the total execution deadline, not a yield delay: expiry cancels children. Background delivery is automatic; leave this deadline long enough for commands and any later stdin input. maxOutputBytes controls selected output only. Child calls suspend automatically until terminal. If the outer exec returns a running taskId, the program and its child remain owned by Thread: call top-level wait on that taskId for completion. A message can wake wait early; check the selected task status before dependent actions. Start commands requiring stdin with interactive=true. To feed one, use another exec to list_tool_tasks, select the running exec_command taskId, and call tools.write_stdin; then wait for the original program. No busy polling is needed. Each invocation has fresh state; keep dependent reads, calculations and writes in one program. Use parallel({{function() ... end, ...}}) for independent calls; the host serializes mutations within that program. Keep dependent actions in one program or wait for the previous program before starting another. Tool failures raise errors: pcall catches an error with message and optional output for inspection; completed side effects are retained and never replayed automatically. Lua syntax errors start no tools. MCP calls return structuredContent when provided, otherwise their full content record. json.decode(text) parses JSON, json.encode(value) serializes it; arrays use 1-based Lua indexing and ipairs. json.null and json.array preserve JSON null and empty arrays. json.null is truthy in Lua: compare optional cursors with nil or json.null. OS/file/network operations go through tools.\n\nFrozen Lua SDK (only these names exist inside code; discover_tools, Plan, wait, interaction and turn-ending tools are separate top-level calls, without tools. or exec; newly discovered bindings appear in the next exec):\n{sdk}"
    ), pl_agent_tool::typed::input_schema_for::<ExecInput>()).expect("static Lua declaration")
}

pub async fn execute<H: ToolHost>(
    input: ExecInput,
    host: H,
    cancellation: CancellationToken,
) -> Result<ExecOutput, ExecError> {
    let timeout = input.timeout_ms.unwrap_or(120_000);
    let maximum = input.max_output_bytes.unwrap_or(8192);
    if input.code.trim().is_empty() || timeout == 0 || maximum == 0 {
        return Err(ExecError::InvalidInput(
            "code must be nonblank; timeoutMs and maxOutputBytes must be positive".into(),
        ));
    }
    let deadline = Instant::now()
        .checked_add(Duration::from_millis(timeout))
        .ok_or_else(|| {
            ExecError::InvalidInput("timeoutMs exceeds the system clock range".into())
        })?;
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
        for name in ["dofile", "loadfile", "load"] { globals.set(name, Value::Nil)?; }
        let tools = lua.create_table()?;
        let gate = Arc::new(tokio::sync::RwLock::new(()));
        let permits = Arc::new(tokio::sync::Semaphore::new(4));
        let admission = Arc::new(AtomicUsize::new(0));
        for binding in host.bindings() {
            let host = host.clone();
            let gate = gate.clone();
            let permits = permits.clone();
            let admission = admission.clone();
            let name = binding.name.clone();
            let callback = lua.create_async_function(move |lua, value: Value| {
                let host = host.clone(); let gate = gate.clone(); let name = name.clone();
                let permits = permits.clone(); let admission = admission.clone();
                async move {
                    let _permit = permits.acquire().await.map_err(mlua::Error::external)?;
                    let arguments = lua.from_value(value)?;
                    let result = if binding.parallel {
                        let _guard = gate.read().await;
                        if admission.load(Ordering::Acquire) != 0 { Err("parallel batch stopped after an unhandled error".into()) }
                        else { host.call(name, arguments).await }
                    } else {
                        let _guard = gate.write().await;
                        if admission.load(Ordering::Acquire) != 0 { Err("parallel batch stopped after an unhandled error".into()) }
                        else { host.call(name, arguments).await }
                    };
                    match result {
                        Ok(value) => Ok((true, lua.to_value(&value)?)),
                        Err(error) => {
                            let value = lua.to_value(&error)?;
                            if let Value::Table(table) = &value {
                                let meta = lua.create_table()?;
                                meta.set("__tostring", lua.create_function(|_, table: mlua::Table| {
                                    table.get::<String>("message")
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
        let tools_meta = lua.create_table()?;
        tools_meta.set("__index", lua.create_function(|_, (_, name): (mlua::Table, String)| -> mlua::Result<Value> {
            Err(mlua::Error::RuntimeError(format!("tools[{name:?}] is absent from this program's frozen SDK. Use an exact declared name; discover_tools is a separate top-level call, and discovered bindings become available in the next exec.")))
        })?)?;
        tools.set_metatable(Some(tools_meta))?;
        globals.set("tools", tools)?;
        let json = lua.create_table()?;
        json.set("decode", lua.create_function(|lua, text: String| {
            let value: serde_json::Value = serde_json::from_str(&text).map_err(mlua::Error::external)?;
            lua.to_value(&value)
        })?)?;
        json.set("encode", lua.create_function(|lua, value: Value| {
            let value: serde_json::Value = lua.from_value(value)?;
            serde_json::to_string(&value).map_err(mlua::Error::external)
        })?)?;
        json.set("null", lua.null())?;
        json.set("array", lua.create_function(|lua, table: mlua::Table| { table.set_metatable(Some(lua.array_metatable()))?; Ok(table) })?)?;
        globals.set("json", json)?;
        globals.set("parallel", lua.create_async_function(move |lua, functions: Vec<Function>| {
            let admission = admission.clone();
            async move {
            let mut values = vec![None; functions.len()];
            let mut queued = functions.into_iter().enumerate();
            let mut running = FuturesUnordered::new();
            for (index, function) in queued.by_ref().take(4) { running.push(invoke_function(index, function)); }
            let mut failure = None;
            let mut pause = None;
            while let Some((index, result)) = running.next().await {
                match result {
                    Ok(value) => values[index] = Some(value),
                    Err(error) if failure.is_none() => {
                        pause = Some(AdmissionPause::new(&admission));
                        failure = Some(error);
                    }
                    Err(_) => {},
                }
                if failure.is_none() && let Some((index, function)) = queued.next() { running.push(invoke_function(index, function)); }
            }
            drop(pause);
            if let Some(error) = failure { return Err(error); }
            let table = lua.create_table()?;
            table.set_metatable(Some(lua.array_metatable()))?;
            for (i, value) in values.into_iter().enumerate() { table.set(i + 1, value.expect("all functions completed without failure"))?; }
            Ok(table)
        }})?)?;
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
        error: result.err().map(|error| {
            if matches!(&error, mlua::Error::SyntaxError { .. }) {
                format!("{error}\nLua parsing failed before any tool started. Complete shell-call example:\n{COMMAND_EXAMPLE}")
            } else { error.to_string() }
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
    // Account JSON escaping in the retained receipt. The owner independently accounts
    // the complete delivery against its existing reliable-output quota.
    let cost = text
        .bytes()
        .map(|byte| match byte {
            b'"' | b'\\' => 4,
            b'\n' | b'\r' | b'\t' | 8 | 12 => 3,
            0..=31 => 7,
            _ => 1,
        })
        .sum::<usize>();
    let limit = MAX_CAPTURE_BYTES;
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
