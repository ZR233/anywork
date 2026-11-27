use crate::{process::input::input_rejection_schema, write_stdin::WriteStdinInput};
pub fn write_stdin_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json("write_stdin",
                "Write chars to an exec_command taskId started with interactive=true. closeStdin=true sends EOF after text; empty chars is valid only for EOF. Returns taskId, targetTaskId and inputReceipt with acceptedBytes, closeState, outcome and detail. Accepted bytes do not prove the target consumed them; never resend accepted input after cancellation. Input cancellation leaves the target command alive. Wait for the input program before dependent actions.", pl_agent_tool::typed::input_schema_for::<WriteStdinInput>()).expect("static tool definition")
        .with_output_schema(serde_json::json!({"oneOf":[{"type":"object","properties":{
            "taskId":{"type":["string","null"]},"targetTaskId":{"type":"string"},
            "status":{"type":"string"},
            "diagnostic":{"type":"object","properties":{
                "code":{"enum":["exec.stdin_closed","exec.invalid_arguments"]},
                "nextAction":{"const":"inspect_original_exec_do_not_restart"}
            },"required":["code","nextAction"],"additionalProperties":false},
            "inputReceipt":{
                "type":["object","null"],"properties":{
                    "acceptedBytes":{"type":"integer","minimum":0},"closeState":{"enum":["open","closing","closed"]},
                    "outcome":{"enum":["complete","cancelled","partial","failed","notSent"]},"detail":{"type":["string","null"]}
                },"required":["acceptedBytes","outcome"],"additionalProperties":false}
        },"required":["taskId","targetTaskId","inputReceipt"],"additionalProperties":false},input_rejection_schema()]}))
        .expect("static output schema")
}
