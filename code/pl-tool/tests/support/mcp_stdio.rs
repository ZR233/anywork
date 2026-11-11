use pl_tool::mcp::config::{
    EffectiveMcpServerConfig, McpExecutionContext, McpServerConfig, McpServerMutationPolicy,
    McpServerSourceKind, McpServerStatusKind, McpServerTransport,
};
use std::collections::BTreeMap;

pub fn write_python_mcp_server(
    dir: &std::path::Path,
    name: &str,
    body: &str,
) -> std::path::PathBuf {
    let path = dir.join(name);
    std::fs::write(&path, body).expect("write python mcp server");
    path
}

pub const STDIO_MCP_SCRIPT: &str = r##"import json, os, signal, sys, time

pid_file = os.environ.get("MCP_PID_FILE")
if pid_file:
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

exit_marker = os.environ.get("MCP_EXIT_MARKER")
ignore_term_ms = int(os.environ.get("MCP_IGNORE_TERM_MS", "0"))
term_started_marker = os.environ.get("MCP_TERM_STARTED_MARKER")
term_release_marker = os.environ.get("MCP_TERM_RELEASE_MARKER")
hang_initialize = os.environ.get("MCP_HANG_INITIALIZE") == "1"
hang_call_ms = int(os.environ.get("MCP_HANG_CALL_MS", "0"))

def on_term(signum, frame):
    if term_release_marker:
        with open(term_started_marker, "w") as f:
            f.write("terminating")
        deadline = time.monotonic() + 5
        while not os.path.exists(term_release_marker):
            if time.monotonic() >= deadline:
                sys.exit("timed out waiting for SIGTERM handler release")
            time.sleep(0.025)
    if ignore_term_ms > 0:
        time.sleep(ignore_term_ms / 1000.0)
    if exit_marker:
        with open(exit_marker, "w") as f:
            f.write("terminated")
    sys.exit(0)

signal.signal(signal.SIGTERM, on_term)

for raw in sys.stdin:
    line = raw.strip()
    if not line:
        continue
    msg = json.loads(line)
    method = msg.get("method")
    msg_id = msg.get("id")
    if os.environ.get("MCP_REQUEST_LOG"):
        with open(os.environ["MCP_REQUEST_LOG"], "a") as log:
            log.write(json.dumps({"method": method, "params": msg.get("params"), "tag": os.environ.get("MCP_SCHEMA_TAG"), "pid": os.getpid()}) + "\n")
    if method == "server/discover":
        resp = {
            "jsonrpc": "2.0",
            "id": msg_id,
            "error": {"code": -32601, "message": "method not found"}
        }
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()
    elif method == "initialize":
        if hang_initialize:
            time.sleep(60)
        resources_enabled = os.environ.get("MCP_NO_RESOURCES") != "1"
        resources_flag = os.environ.get("MCP_RESOURCES_FLAG")
        if resources_flag and os.path.exists(resources_flag):
            with open(resources_flag) as flag:
                resources_enabled = flag.read().strip() != "0"
        resp = {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "protocolVersion": "2025-11-25",
                "capabilities": {"tools": {}, **({"resources": {}} if resources_enabled else {})},
                "serverInfo": {"name": "test-stdio", "version": "1.0.0"}
            }
        }
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()
    elif method == "notifications/initialized":
        continue
    elif method == "tools/list":
        schema = {"type": "object", "properties": {}}
        if os.environ.get("MCP_BINDING_RESULTS") == "1":
            schema = {
                "$schema": "https://json-schema.org/draft/2020-12/schema",
                "description": os.environ["MCP_SCHEMA_TAG"],
                "$defs": {"Mode": {"type": "string", "enum": ["success", "error", "unarchived"]}},
                "allOf": [{"type": "object", "properties": {"mode": {"$ref": "#/$defs/Mode"}}, "required": ["mode"]}],
                "unevaluatedProperties": False
            }
        resp = {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "tools": [{
                    "name": "inspect_env",
                    "description": "Returns argv, cwd, and env",
                    "inputSchema": schema,
                    "annotations": {"readOnlyHint": True},
                    **({"outputSchema": {"type": "object", "additionalProperties": True}}
                       if os.environ.get("MCP_BINDING_RESULTS") == "1" else {})
                }]
            }
        }
        if os.environ.get("MCP_RESOURCES_ONLY") == "1":
            resp["result"]["tools"] = []
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()
    elif method == "tools/call":
        if hang_call_ms > 0:
            time.sleep(hang_call_ms / 1000.0)
        payload = {
            "argv": sys.argv[1:],
            "cwd": os.getcwd(),
            "special_env": os.environ.get("SPECIAL_ENV"),
            "bash_env": os.environ.get("BASH_ENV"),
        }
        resp = {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "content": [{"type": "text", "text": json.dumps(payload)}]
            }
        }
        if os.environ.get("MCP_BINDING_RESULTS") == "1":
            mode = msg.get("params", {}).get("arguments", {}).get("mode", "success")
            if mode == "unarchived":
                content = [{"type": "resource", "resource": {
                    "uri": "fixture://received", "mimeType": "application/octet-stream", "blob": "Ynl0ZXM="
                }}]
            else:
                content = [{"type": "text", "text": os.environ["MCP_SCHEMA_TAG"] + ":" + mode}]
            resp["result"] = {"content": content, "isError": mode == "error"}
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()
    elif method in ("resources/list", "resources/templates/list"):
        key = "resources" if method == "resources/list" else "resourceTemplates"
        resp = {"jsonrpc": "2.0", "id": msg_id, "result": {key: []}}
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()
    elif method == "resources/read":
        if hang_call_ms > 0:
            time.sleep(hang_call_ms / 1000.0)
        resp = {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "contents": [
                    {"uri": "test://doc", "mimeType": "application/octet-stream", "blob": "Ynl0ZXM="}
                    if msg.get("params", {}).get("uri") == "test://blob"
                    else {"uri": "test://doc", "text": "hello"}
                ]
            }
        }
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()

if term_release_marker:
    # T09 must stay alive after transport EOF until the real SIGTERM handler runs.
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        time.sleep(0.025)
    sys.exit("stdin closed without SIGTERM")
"##;

pub fn stdio_effective_config(
    id: &str,
    script: &std::path::Path,
    extra_args: Vec<String>,
    env: BTreeMap<String, String>,
    cwd: Option<String>,
    execution_context: McpExecutionContext,
) -> EffectiveMcpServerConfig {
    let mut args = vec![script.to_string_lossy().into_owned()];
    args.extend(extra_args);
    EffectiveMcpServerConfig {
        id: id.to_owned(),
        source_kind: McpServerSourceKind::User,
        source_label: "user".to_owned(),
        source_detail: None,
        status_kind: McpServerStatusKind::Enabled,
        status_message: None,
        mutation_policy: McpServerMutationPolicy::UserEditable,
        bearer_token: None,
        tool_effect: None,
        execution_context,
        config: McpServerConfig {
            required: false,
            transport: McpServerTransport::Stdio,
            command: Some("python3".to_owned()),
            args,
            env,
            cwd,
            url: None,
            bearer_token_env_var: None,
            headers: BTreeMap::new(),
            enabled: true,
            startup_timeout_secs: Some(10),
            tool_timeout_secs: Some(10),
            enabled_tools: None,
            disabled_tools: Vec::new(),
        },
    }
}
