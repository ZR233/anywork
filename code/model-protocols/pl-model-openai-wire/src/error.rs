//! Shared Chat Completions and Responses error envelope, without vendor code tables.

use pl_model_wire::protocol::WireApi;
use pl_model_wire::provider_error::{
    ClassifiedProviderError, ErrorDecodeError, ProviderErrorEntry, ProviderErrorInput,
    ProviderFailureKind as Kind, RetryHint,
};
use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub enum StringOrNumber {
    Text(String),
    Number(serde_json::Number),
}

impl From<StringOrNumber> for String {
    fn from(value: StringOrNumber) -> Self {
        match value {
            StringOrNumber::Text(text) => text,
            StringOrNumber::Number(number) => number.to_string(),
        }
    }
}

#[derive(Default, Deserialize)]
struct ErrorFields {
    code: Option<StringOrNumber>,
    #[serde(rename = "type")]
    error_type: Option<String>,
    message: Option<String>,
    param: Option<StringOrNumber>,
    status: Option<Value>,
    status_code: Option<Value>,
    retry_after_ms: Option<StringOrNumber>,
}

impl ErrorFields {
    fn status(&self) -> Option<u16> {
        self.status
            .as_ref()
            .and_then(status_number)
            .or_else(|| self.status_code.as_ref().and_then(status_number))
    }
}

/// The extracted shape shared by the OpenAI-family adapters.
#[derive(Default)]
pub struct OpenAiError {
    pub code: Option<String>,
    pub error_type: Option<String>,
    pub message: Option<String>,
    pub param: Option<String>,
    pub http_status: Option<u16>,
    pub retry_hint: RetryHint,
    pub terminal_kind: Option<Kind>,
}

impl OpenAiError {
    pub fn classify(self, kind: Kind, retryable: bool) -> ClassifiedProviderError {
        let mut result = ClassifiedProviderError::new(
            kind,
            retryable,
            self.message
                .unwrap_or_else(|| "provider reported a failure".to_owned()),
        );
        result.code = self.code;
        result.error_type = self.error_type;
        result.http_status = self.http_status;
        result.retry_hint = self.retry_hint;
        result
    }
}

pub fn decode_openai_error(
    input: &ProviderErrorInput<'_>,
) -> Result<Option<OpenAiError>, ErrorDecodeError> {
    let Some(value) = input.payload else {
        return Ok(None);
    };
    let event = if input.entry != ProviderErrorEntry::HttpResponse {
        input
            .event_name
            .filter(|name| {
                matches!(
                    *name,
                    "error" | "response.completed" | "response.failed" | "response.incomplete"
                )
            })
            .or_else(|| value.get("type").and_then(Value::as_str))
    } else {
        None
    };
    let explicit_failure = matches!(event, Some("response.failed" | "response.incomplete"));
    let response_event = explicit_failure || event == Some("response.completed");
    let outer = if response_event {
        match value.get("response") {
            Some(response) if response.is_object() => response,
            _ => return Err(ErrorDecodeError::Structure("missing or invalid response")),
        }
    } else {
        value
    };
    let body_error = outer.get("error").filter(|error| !error.is_null());
    let terminal = terminal_reason(input, event, outer)?;
    if body_error.is_none() && !explicit_failure && event != Some("error") && terminal.is_none() {
        return Ok(None);
    }
    let (_, terminal_kind) = terminal.unwrap_or(("", Kind::Unknown));
    let terminal_code = terminal.map(|(code, _)| code.to_owned());
    let mut inner: ErrorFields = match body_error {
        Some(error) if error.is_object() => serde_json::from_value(error.clone())?,
        Some(_) => return Err(ErrorDecodeError::Structure("error must be an object")),
        None => ErrorFields::default(),
    };
    // The outer type is an event discriminator when present, rather than an error type.
    let mut fields: ErrorFields = serde_json::from_value(outer.clone())?;
    if event.is_some() && !response_event {
        fields.error_type = None;
    }
    let wait = |value: Option<StringOrNumber>| match value {
        Some(StringOrNumber::Text(value)) => RetryHint::from_millis(&value),
        Some(StringOrNumber::Number(value)) => RetryHint::from_number_millis(&value),
        None => RetryHint::Absent,
    };
    let http_status = inner.status().or(fields.status()).or_else(|| {
        response_event
            .then(|| {
                value
                    .get("status")
                    .and_then(status_number)
                    .or_else(|| value.get("status_code").and_then(status_number))
            })
            .flatten()
    });
    let message = inner.message.take().or(fields.message).or_else(|| {
        terminal_code
            .as_ref()
            .map(|code| format!("provider stopped generation: {code}"))
    });
    Ok(Some(OpenAiError {
        code: inner
            .code
            .or(fields.code)
            .map(String::from)
            .or(terminal_code),
        error_type: inner.error_type.or(fields.error_type),
        message,
        param: inner.param.or(fields.param).map(String::from),
        http_status,
        retry_hint: wait(inner.retry_after_ms).combine(wait(fields.retry_after_ms)),
        terminal_kind: (terminal_kind != Kind::Unknown).then_some(terminal_kind),
    }))
}

fn terminal_reason<'a>(
    input: &ProviderErrorInput<'a>,
    event: Option<&str>,
    outer: &'a Value,
) -> Result<Option<(&'a str, Kind)>, ErrorDecodeError> {
    if event == Some("response.incomplete")
        || (event == Some("response.completed")
            && outer.get("status").and_then(Value::as_str) == Some("incomplete"))
    {
        let reason = match outer.get("incomplete_details") {
            Some(details) if !details.is_null() => details
                .get("reason")
                .and_then(Value::as_str)
                .ok_or(ErrorDecodeError::Structure(
                    "incomplete_details has no reason",
                ))?,
            _ => "incomplete",
        };
        let kind = match reason {
            "max_output_tokens" => Kind::OutputLimit,
            "content_filter" => Kind::ContentBlocked,
            _ => Kind::Unknown,
        };
        return Ok(Some((reason, kind)));
    }
    if input.entry == ProviderErrorEntry::HttpResponse {
        return Ok(None);
    }
    if event == Some("response.completed")
        && outer
            .get("output")
            .and_then(Value::as_array)
            .is_some_and(|items| {
                items.iter().any(|item| {
                    item.get("content")
                        .and_then(Value::as_array)
                        .is_some_and(|parts| {
                            parts.iter().any(|part| {
                                part.get("type").and_then(Value::as_str) == Some("refusal")
                                    && part
                                        .get("refusal")
                                        .and_then(Value::as_str)
                                        .is_some_and(|text| !text.is_empty())
                            })
                        })
                })
            })
    {
        return Ok(Some(("refusal", Kind::ContentBlocked)));
    }
    if input.wire_api == Some(WireApi::ChatCompletions)
        && let Some(choice) = outer
            .get("choices")
            .and_then(Value::as_array)
            .and_then(|choices| choices.first())
    {
        if choice
            .get("delta")
            .and_then(|delta| delta.get("refusal"))
            .and_then(Value::as_str)
            .is_some_and(|refusal| !refusal.is_empty())
        {
            return Ok(Some(("refusal", Kind::ContentBlocked)));
        }
        let reason = choice.get("finish_reason").and_then(Value::as_str);
        let terminal = match reason {
            Some("length") => Some(("length", Kind::OutputLimit)),
            Some("content_filter") => Some(("content_filter", Kind::ContentBlocked)),
            Some("" | "stop" | "tool_calls" | "function_call") | None => None,
            Some(reason) => Some((reason, Kind::Unknown)),
        };
        return Ok(terminal);
    }
    Ok(None)
}

fn status_number(value: &Value) -> Option<u16> {
    let status = value
        .as_u64()
        .and_then(|status| u16::try_from(status).ok())
        .or_else(|| value.as_str()?.parse().ok())?;
    (100..=599).contains(&status).then_some(status)
}
