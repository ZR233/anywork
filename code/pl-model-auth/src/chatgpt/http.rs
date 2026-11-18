use super::ChatGptAuthError;
use futures::StreamExt;
use std::time::Duration;

/// The oauth2/openidconnect adapter contract accepts an async closure over HTTP values.
/// No second HTTP/TLS stack, redirects, retries, body diagnostics or detached tasks.
pub(super) async fn request(
    input: oauth2::HttpRequest,
) -> Result<oauth2::HttpResponse, ChatGptAuthError> {
    tokio::time::timeout(Duration::from_secs(30), async {
        let uri = input.uri();
        if uri.scheme_str() != Some("https") || uri.host() != Some("auth.openai.com") {
            return Err(ChatGptAuthError::InvalidIdentity);
        }
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .timeout(Duration::from_secs(30))
            .build()
            .map_err(|_| ChatGptAuthError::Network)?;
        let (parts, body) = input.into_parts();
        let response = client
            .request(parts.method, parts.uri.to_string())
            .headers(parts.headers)
            .body(body)
            .send()
            .await
            .map_err(|_| ChatGptAuthError::Network)?;
        if response
            .content_length()
            .is_some_and(|size| size > 1_048_576)
        {
            return Err(ChatGptAuthError::Network);
        }
        let mut output = oauth2::http::Response::builder().status(response.status());
        *output.headers_mut().ok_or(ChatGptAuthError::Network)? = response.headers().clone();
        let mut bytes = Vec::new();
        let mut stream = response.bytes_stream();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|_| ChatGptAuthError::Network)?;
            if bytes.len() + chunk.len() > 1_048_576 {
                return Err(ChatGptAuthError::Network);
            }
            bytes.extend_from_slice(&chunk);
        }
        output.body(bytes).map_err(|_| ChatGptAuthError::Network)
    })
    .await
    .map_err(|_| ChatGptAuthError::Network)?
}
