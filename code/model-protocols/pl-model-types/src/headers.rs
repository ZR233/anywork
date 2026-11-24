use pl_protocol::{PureError, Result};
use reqwest::header::{AUTHORIZATION, HeaderMap, HeaderName, HeaderValue};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// How an endpoint transmits its API key or bearer credential on HTTP requests.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ApiKeyHeaderScheme {
    #[default]
    AuthorizationBearer,
    XGoogApiKey,
}

pub fn headers(
    token: Option<&str>,
    provider: Option<&HashMap<String, String>>,
    model: &HashMap<String, String>,
) -> Result<HeaderMap> {
    headers_with_scheme(
        ApiKeyHeaderScheme::AuthorizationBearer,
        token,
        provider,
        model,
    )
}

pub fn headers_with_scheme(
    scheme: ApiKeyHeaderScheme,
    token: Option<&str>,
    provider: Option<&HashMap<String, String>>,
    model: &HashMap<String, String>,
) -> Result<HeaderMap> {
    let mut headers = HeaderMap::new();
    if let Some(token) = token {
        match scheme {
            ApiKeyHeaderScheme::AuthorizationBearer => {
                let mut value = HeaderValue::from_str(&format!("Bearer {token}"))
                    .map_err(|_| PureError::ConfigError("invalid authorization header".into()))?;
                value.set_sensitive(true);
                headers.insert(AUTHORIZATION, value);
            }
            ApiKeyHeaderScheme::XGoogApiKey => {
                let mut value = HeaderValue::from_str(token)
                    .map_err(|_| PureError::ConfigError("invalid x-goog-api-key header".into()))?;
                value.set_sensitive(true);
                headers.insert(HeaderName::from_static("x-goog-api-key"), value);
            }
        }
    }
    for layer in provider.into_iter().chain(std::iter::once(model)) {
        let mut names = std::collections::HashSet::new();
        for (key, value) in layer {
            let name = HeaderName::from_bytes(key.as_bytes())
                .map_err(|_| PureError::ConfigError("invalid provider header name".into()))?;
            if !names.insert(name.clone()) {
                return Err(PureError::ConfigError(
                    "duplicate provider header name".into(),
                ));
            }
            let mut value = HeaderValue::from_str(value)
                .map_err(|_| PureError::ConfigError("invalid provider header value".into()))?;
            value.set_sensitive(true);
            headers.insert(name, value);
        }
    }
    Ok(headers)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn x_goog_api_key_omits_authorization_and_marks_header_sensitive() {
        let map = headers_with_scheme(
            ApiKeyHeaderScheme::XGoogApiKey,
            Some("secret-key"),
            None,
            &HashMap::new(),
        )
        .unwrap();
        assert!(map.get(AUTHORIZATION).is_none());
        let header = map.get("x-goog-api-key").expect("x-goog-api-key header");
        assert_eq!(header.to_str().unwrap(), "secret-key");
        assert!(header.is_sensitive());
    }
}
