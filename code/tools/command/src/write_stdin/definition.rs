use crate::write_stdin::WriteStdinInput;
pub fn write_stdin_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json("write_stdin",
                "Write text to the original exec receipt taskId. closeStdin=true sends EOF after text; empty chars is valid only for EOF. A blocked write returns its own task receipt: cancel that input task to stop writing without stopping exec, then query its result. Accepted bytes and remote ACKs are distinct: never resend accepted input after cancellation. Wait for the input task before actions that require completed delivery.", pl_agent_tool::typed::input_schema_for::<WriteStdinInput>()).expect("static tool definition")
}
