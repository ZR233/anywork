use pl_protocol::{PureError, Result};
use reqwest::header::{AUTHORIZATION, HeaderMap, HeaderName, HeaderValue};
use std::collections::HashMap;
pub fn headers(
    token: Option<&str>,
    provider: Option<&HashMap<String, String>>,
    model: &HashMap<String, String>,
) -> Result<HeaderMap> {
    let mut headers = HeaderMap::new();
    if let Some(token) = token {
        let mut value = HeaderValue::from_str(&format!("Bearer {token}"))
            .map_err(|_| PureError::ConfigError("invalid authorization header".into()))?;
        value.set_sensitive(true);
        headers.insert(AUTHORIZATION, value);
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
