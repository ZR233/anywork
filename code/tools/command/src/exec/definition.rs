use crate::exec::ExecInput;
pub fn exec_definition() -> pl_agent_tool::ToolDefinition {
    let stream = serde_json::json!({"type":"object","properties":{
        "content":{"type":"string"},"wasTruncated":{"type":"boolean"}
    },"required":["content"],"additionalProperties":true});
    pl_agent_tool::ToolDefinition::json("exec_command",
        "Run a shell command. Return exitCode, stdout.content and stderr.content: pipelines and later commands can mask failures. If rg is unavailable, use grep -R for directories or find. rg/grep exit 1 means no matches; refine the query without masking status. Put options, including --glob/--exclude-dir, BEFORE --; pattern and quoted paths follow. Read truncated stdoutFile/stderrFile from the workspace root (cwd omitted or '.'). Preserve completed effects on failure; inspect diagnostic and captureStatus.",
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
