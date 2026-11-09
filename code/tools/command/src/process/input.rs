//! Strict command-input diagnostics, independent of host error and history types.
use serde::{Serialize, de::DeserializeOwned};

/// Parameter failure before any business process or permission request.
#[derive(Debug, thiserror::Error)]
#[error("{code}: {detail}")]
pub struct ExecInputError {
    pub code: &'static str,
    pub field: Option<String>,
    pub detail: String,
    #[source]
    pub source: Option<serde_json::Error>,
}

impl ExecInputError {
    pub fn range(field: &str, detail: &str) -> Self {
        Self {
            code: "exec.argument_out_of_range",
            field: Some(field.into()),
            detail: detail.into(),
            source: None,
        }
    }

    /// Preserves both the typed source and a bounded model-readable validation receipt.
    pub fn diagnostic_json(&self) -> Result<String, serde_json::Error> {
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
        serde_json::to_string(&receipt)
    }
}

pub fn parse<T: DeserializeOwned>(raw: &str) -> Result<T, ExecInputError> {
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
