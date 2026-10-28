//! One input contract shared by authorization and direct tool execution.
use super::{ExecInput, WriteStdinInput};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{ToolOutput, opaque::ToolError},
};
use serde::{Serialize, de::DeserializeOwned};
use std::{path::Path, sync::Arc};

/// Validated exec arguments. Only this module can construct a validated value.
#[derive(Debug)]
pub struct ValidatedExecInput(ExecInput);

impl ValidatedExecInput {
    pub fn cwd(&self) -> Option<&Path> {
        self.0.cwd.as_deref()
    }
    pub fn into_input(self) -> ExecInput {
        self.0
    }
}

/// Parameter failure before any business process or permission request.
#[derive(Debug, thiserror::Error)]
#[error("{code}: {detail}")]
pub struct ExecInputError {
    pub code: &'static str,
    pub field: Option<String>,
    pub detail: String,
    #[source]
    source: Option<serde_json::Error>,
}

impl ExecInputError {
    fn range(field: &str, detail: &str) -> Self {
        Self {
            code: "exec.argument_out_of_range",
            field: Some(field.into()),
            detail: detail.into(),
            source: None,
        }
    }

    /// Preserves both the typed source and a bounded model-readable validation receipt.
    pub fn into_tool_error(self) -> ToolError {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Diagnostic<'a> {
            code: &'a str,
            stage: &'static str,
            field: Option<&'a str>,
            detail: &'a str,
            line: Option<usize>,
            column: Option<usize>,
            next_action: &'static str,
        }
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Receipt<'a> {
            diagnostic: Diagnostic<'a>,
            process_started: bool,
        }
        let mut detail = self.detail.as_str();
        let mut end = detail.len().min(4096);
        while !detail.is_char_boundary(end) {
            end -= 1;
        }
        detail = &detail[..end];
        let receipt = Receipt {
            diagnostic: Diagnostic {
                code: self.code,
                stage: "validate",
                field: self.field.as_deref().filter(|field| field.len() <= 4096),
                detail,
                line: self.source.as_ref().map(serde_json::Error::line),
                column: self.source.as_ref().map(serde_json::Error::column),
                next_action: "correct_arguments",
            },
            process_started: false,
        };
        let output = serde_json::to_string(&receipt)
            .map_err(ToolError::new)
            .and_then(|text| {
                let payload =
                    OpaquePayload::new("pl.tool.exec", 2, text.clone()).map_err(ToolError::new)?;
                Ok(ToolOutput::new(
                    payload,
                    vec![ContextContent::Text {
                        text: Arc::from(text),
                    }],
                ))
            });
        match output {
            Ok(output) => ToolError::new(self).with_output(output),
            Err(error) => error,
        }
    }
}

fn parse<T: DeserializeOwned>(raw: &str) -> Result<T, ExecInputError> {
    let mut deserializer = serde_json::Deserializer::from_str(raw);
    let value = serde_path_to_error::deserialize(&mut deserializer).map_err(|error| {
        let path = error.path().to_string();
        let source = error.into_inner();
        json_error(source, (!path.is_empty() && path != ".").then_some(path))
    })?;
    deserializer
        .end()
        .map_err(|source| json_error(source, None))?;
    Ok(value)
}

fn json_error(source: serde_json::Error, field: Option<String>) -> ExecInputError {
    ExecInputError {
        code: if source.is_data() {
            "exec.invalid_arguments"
        } else {
            "exec.invalid_json"
        },
        field,
        detail: source.to_string(),
        source: Some(source),
    }
}

/// Strict, side-effect-free parsing; does not normalize the actual shell command.
pub fn parse_and_validate_exec_input(raw: &str) -> Result<ValidatedExecInput, ExecInputError> {
    let input: ExecInput = parse(raw)?;
    if input.command.trim().is_empty() {
        return Err(ExecInputError {
            code: "exec.empty_command",
            field: Some("command".into()),
            detail: "Expected a nonblank shell command.".into(),
            source: None,
        });
    }
    if input.timeout_seconds == Some(0) {
        return Err(ExecInputError::range(
            "timeoutSeconds",
            "Expected a positive integer in seconds.",
        ));
    }
    if input.max_output_chars == Some(0) {
        return Err(ExecInputError::range(
            "maxOutputChars",
            "Expected a positive UTF-8 byte budget.",
        ));
    }
    Ok(ValidatedExecInput(input))
}

/// Strict stdin input validation shared with the authorization boundary.
pub fn parse_and_validate_stdin_input(raw: &str) -> Result<WriteStdinInput, ExecInputError> {
    let input: WriteStdinInput = parse(raw)?;
    if input.task_id.trim().is_empty() {
        return Err(ExecInputError::range(
            "taskId",
            "Expected an exec receipt taskId from this Thread.",
        ));
    }
    if input.chars.is_empty() && !input.close_stdin {
        return Err(ExecInputError::range(
            "chars",
            "Expected nonempty text or closeStdin=true for EOF; use wait to observe completion.",
        ));
    }
    if input.max_output_chars == Some(0) {
        return Err(ExecInputError::range(
            "maxOutputChars",
            "Expected a positive UTF-8 byte budget.",
        ));
    }
    Ok(input)
}
