use crate::exec::ExecInput;
pub fn exec_definition() -> pl_agent_tool::ToolDefinition {
    let stream = serde_json::json!({"type":"object","properties":{
        "content":{"type":"string"},"wasTruncated":{"type":"boolean"}
    },"required":["content"],"additionalProperties":true});
    pl_agent_tool::ToolDefinition::json("exec_command",
        "Run one independent shell. Returns a process record: inspect exitCode (0 is success), stdout.content and stderr.content. Nonzero exits retain their observed output. cwd defaults to the workspace root. timeoutSeconds includes startup and execution; defaults normally suffice. maxOutputChars budgets combined stdout+stderr UTF-8 text (default and maximum 65536), with metadata additional. stdoutFile/stderrFile are exact workspace-root-relative capture paths: read with cwd omitted or '.', even if the original command used another cwd. Inspect processStarted, diagnostic, captureStatus and archiveStatus on a tool failure; preserve completed effects and use the original receipt to recover output.",
        pl_agent_tool::typed::input_schema_for::<ExecInput>())
        .expect("static tool definition")
        .with_output_schema(serde_json::json!({"type":"object","properties":{
            "taskId":{"type":["string","null"]},
            "processStarted":{"type":["boolean","null"]},
            "exitCode":{"type":["integer","null"]},
            "stdout":stream,"stderr":stream,
            "stdoutFile":{"type":"string"},"stderrFile":{"type":"string"},
            "captureStatus":{"type":"string"},"archiveStatus":{"type":"string"},
            "diagnostic":{"type":["object","null"]}
        },"additionalProperties":true}))
        .expect("static output schema")
}
