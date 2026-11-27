use crate::{exec::ExecInput, process::input::input_rejection_schema};
use serde_json::json;

pub fn exec_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json("exec_command",
        "Run a shell command. Process results return taskId, exitCode, stdout and stderr. Shell pipelines and later commands determine the final exit status. Check stdoutWasTruncated/stderrWasTruncated and read the corresponding stdoutFile/stderrFile from the workspace root (cwd omitted or '.'). Failures before capture preserve processStarted and diagnostic. Other execution failures preserve observed output, signal, diagnostic and captureStatus where available; completed effects are not replayed.",
        pl_agent_tool::typed::input_schema_for::<ExecInput>())
        .expect("static tool definition")
        .with_output_schema(json!({"oneOf":[{"type":"object","properties":{
            "taskId":{"type":["string","null"]},
            "exitCode":{"type":["integer","null"]},
            "signal":{"type":"integer"},
            "stdout":{"type":"string"},"stderr":{"type":"string"},
            "stdoutWasTruncated":{"type":"boolean"},"stderrWasTruncated":{"type":"boolean"},
            "stdoutOmittedBytes":{"type":["integer","null"]},"stderrOmittedBytes":{"type":["integer","null"]},
            "stdoutTextLossy":{"type":"boolean"},"stderrTextLossy":{"type":"boolean"},
            "stdoutFile":{"type":"string"},"stderrFile":{"type":"string"},
            "captureStatus":{"type":"string"},"archiveStatus":{"type":"string"},
            "diagnostic":{"type":"object","properties":{
                "code":{"type":"string"},"detail":{"type":"string"},"nextAction":{"type":"string"}
            },"required":["code","detail","nextAction"],"additionalProperties":false}
        },"required":["taskId","exitCode","stdout","stderr"],"additionalProperties":false},
        {"type":"object","properties":{
            "taskId":{"type":["string","null"]},"processStarted":{"type":["boolean","null"]},
            "diagnostic":{"type":"object","properties":{
                "code":{"type":"string"},"detail":{"type":"string"},"nextAction":{"type":"string"}
            },"required":["code","detail","nextAction"],"additionalProperties":false}
        },"required":["taskId","processStarted","diagnostic"],"additionalProperties":false},
        {"type":"object","properties":{
            "processStarted":{"const":false},"diagnostic":{"type":"object","properties":{
                "code":{"const":"exec.permission_denied"},"stage":{"const":"authorize"},"detail":{"type":"string"}
            },"required":["code","stage","detail"],"additionalProperties":false}
        },"required":["processStarted","diagnostic"],"additionalProperties":false},
        input_rejection_schema()]}))
        .expect("static output schema")
}
