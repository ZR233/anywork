use crate::exec::ExecInput;
pub fn exec_definition() -> pl_agent_tool::ToolDefinition {
    let stream = serde_json::json!({"type":"object","properties":{
        "content":{"type":"string"},"wasTruncated":{"type":"boolean"}
    },"required":["content"],"additionalProperties":true});
    pl_agent_tool::ToolDefinition::json("exec_command",
        "Run a shell command. Read exitCode (0=success), stdout.content and stderr.content. rg/grep exit 1 means no matches; inspect it without reruns, echo or || true. Options precede --, then pattern and quoted paths: rg -n -F -g '!vendor/**' -- 'literal' 'path'. Read truncated stdoutFile/stderrFile relative to the workspace root, with cwd omitted or '.'. On failure inspect processStarted, diagnostic, captureStatus and archiveStatus; preserve completed effects.",
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
