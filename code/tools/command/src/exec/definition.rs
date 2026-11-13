use crate::exec::ExecInput;
pub fn exec_definition() -> pl_agent_tool::ToolDefinition {
    let stream = serde_json::json!({"type":"object","properties":{
        "content":{"type":"string"},"wasTruncated":{"type":"boolean"}
    },"required":["content"],"additionalProperties":true});
    pl_agent_tool::ToolDefinition::json("exec_command",
        "Run a shell command. Return exitCode, stdout.content and stderr.content. Nonzero exit preserves both streams; shell pipelines and later commands determine the final exit status. Truncated streams retain their original stdoutFile/stderrFile: read these paths from the workspace root (cwd omitted or '.'). Execution failures retain observed output (including signal), diagnostic and captureStatus; completed effects are not replayed.",
        pl_agent_tool::typed::input_schema_for::<ExecInput>())
        .expect("static tool definition")
        .with_output_schema(serde_json::json!({"type":"object","properties":{
            "taskId":{"type":["string","null"]},
            "processStarted":{"type":["boolean","null"]},
            "exitCode":{"type":["integer","null"]},
            "signal":{"type":["integer","null"]},
            "stdout":stream,"stderr":stream,
            "stdoutFile":{"type":"string"},"stderrFile":{"type":"string"},
            "captureStatus":{"type":"string"},"archiveStatus":{"type":"string"},
            "diagnostic":{"type":["object","null"]}
        },"additionalProperties":true}))
        .expect("static output schema")
}
