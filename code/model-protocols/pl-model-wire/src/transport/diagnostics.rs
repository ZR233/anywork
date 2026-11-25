//! Request-local diagnostic redaction. Never retain this outside the send/stream lifecycle.
use super::{HeaderMap, PureError};

#[derive(Clone)]
pub struct RequestDiagnostics {
    secrets: Vec<String>,
}

impl RequestDiagnostics {
    pub fn from_headers(headers: &HeaderMap) -> Self {
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

    pub fn redact_text(&self, input: &str) -> String {
        let mut text = input.to_owned();
        self.text(&mut text);
        text
    }

    pub fn text(&self, text: &mut String) {
        for secret in &self.secrets {
            *text = text.replace(secret, "[REDACTED_CREDENTIAL]");
        }
        *text = super::super::provider_error::redact_secret_like_values(text);
    }

    pub fn redact_error(&self, error: &mut PureError) {
        if let PureError::Provider(failure) = error {
            self.text(&mut failure.message);
            for value in [
                &mut failure.code,
                &mut failure.error_type,
                &mut failure.context.request_id,
            ]
            .into_iter()
            .flatten()
            {
                self.text(value);
            }
            if let Some(details) = &mut failure.details {
                self.redact_value(details);
            }
        }
    }

    pub fn redact_value(&self, value: &mut serde_json::Value) {
        match value {
            serde_json::Value::String(text) => self.text(text),
            serde_json::Value::Array(values) => {
                values.iter_mut().for_each(|value| self.redact_value(value))
            }
            serde_json::Value::Object(values) => values
                .values_mut()
                .for_each(|value| self.redact_value(value)),
            _ => {}
        }
    }
}
