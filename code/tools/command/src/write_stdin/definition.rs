use crate::write_stdin::WriteStdinInput;
pub fn write_stdin_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json("write_stdin",
                "Write chars to an exec_command taskId started with interactive=true. closeStdin=true sends EOF after text; empty chars is valid only for EOF. For a live target Lua returns taskId, targetTaskId and inputReceipt with acceptedBytes, closeState, outcome and detail. Accepted bytes do not prove the target consumed them; never resend accepted input after cancellation. Input cancellation leaves the target command alive. Wait for the input program before dependent actions.", pl_agent_tool::typed::input_schema_for::<WriteStdinInput>()).expect("static tool definition")
}
