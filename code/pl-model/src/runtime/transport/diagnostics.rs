//! Request-local diagnostic redaction. Never retain this outside the send/stream lifecycle.
use super::{HeaderMap, PureError, SseStreamEvent};

#[derive(Clone)]
pub(super) struct RequestDiagnostics {
    secrets: Vec<String>,
}

impl RequestDiagnostics {
    pub(super) fn from_headers(headers: &HeaderMap) -> Self {
        let mut secrets = Vec::new();
        for value in headers.values().filter(|value| value.is_sensitive()) {
            if let Ok(value) = value.to_str() {
                if !value.is_empty() {
                    secrets.push(value.to_owned());
                }
                // Retain the credential independently of the Authorization scheme: a provider
                // may reflect only the bearer itself, not the complete sensitive header.
                if let Some((_, credential)) = value.split_once(' ')
                    && !credential.is_empty()
                {
                    secrets.push(credential.to_owned());
                }
            }
        }
        secrets.sort_by_key(|value| std::cmp::Reverse(value.len()));
        secrets.dedup();
        Self { secrets }
    }

    fn text(&self, text: &mut String) {
        for secret in &self.secrets {
            *text = text.replace(secret, "[REDACTED_CREDENTIAL]");
        }
        *text = super::super::provider_error::redact_secret_like_values(text);
    }

    pub(super) fn redact_error(&self, error: &mut PureError) {
        if let PureError::Provider(failure) = error {
            self.text(&mut failure.message);
            for value in [&mut failure.code, &mut failure.context.request_id]
                .into_iter()
                .flatten()
            {
                self.text(value);
            }
        }
    }

    fn value(&self, value: &mut serde_json::Value) {
        match value {
            serde_json::Value::String(text) => self.text(text),
            serde_json::Value::Array(values) => {
                values.iter_mut().for_each(|value| self.value(value))
            }
            serde_json::Value::Object(values) => {
                values.values_mut().for_each(|value| self.value(value))
            }
            _ => {}
        }
    }

    pub(super) fn redact_event(&self, event: &mut SseStreamEvent) {
        if let Some(error) = &mut event.error {
            self.value(error);
        }
        if let Some(error) = event
            .response
            .as_mut()
            .and_then(|response| response.get_mut("error"))
        {
            self.value(error);
        }
        if let Some(response) = event.response.as_mut() {
            // Match the terminal diagnostic fallbacks consumed by the production decoder.
            // Do not traverse response/output: normal content and opaque replay are not errors.
            match event.kind.as_str() {
                "response.failed" => {
                    for field in ["message", "code"] {
                        if let Some(serde_json::Value::String(text)) = response.get_mut(field) {
                            self.text(text);
                        }
                    }
                }
                "response.incomplete" => {
                    if let Some(serde_json::Value::String(reason)) = response
                        .get_mut("incomplete_details")
                        .and_then(|details| details.get_mut("reason"))
                    {
                        self.text(reason);
                    }
                }
                _ => {}
            }
        }
        if event.kind == "error" {
            for value in [&mut event.message, &mut event.code].into_iter().flatten() {
                self.text(value);
            }
        }
    }
}
