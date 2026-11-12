use crate::exec::ExecInput;
pub fn exec_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json("exec_command",
                "Execute one independent shell (cwd defaults to workspace root). timeoutSeconds is the total admission-to-exit budget and remains active after a task receipt. maxOutputChars caps combined stdout+stderr text at 65536 UTF-8 bytes; metadata, JSON escaping and protocol wrappers are additional. Results distinguish execution, capture and archive facts. stdoutFile/stderrFile are exact workspace-root-relative paths: read them with cwd omitted or set to '.', even when the original command used another cwd. Never reconstruct paths or repeat side effects to recover output; query the original receipt.", pl_agent_tool::typed::input_schema_for::<ExecInput>()).expect("static tool definition")
}
