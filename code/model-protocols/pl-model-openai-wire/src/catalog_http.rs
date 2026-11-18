use futures::StreamExt;
use pl_model_types::discovery::ModelCatalogQueryError;
use reqwest::{
    Url,
    header::{ETAG, HeaderMap, IF_NONE_MATCH},
};
use std::time::Duration;

use crate::query_transport_error;

const BODY_LIMIT: usize = 4 * 1024 * 1024;

pub enum CatalogResponse {
    Updated {
        bytes: Vec<u8>,
        etag: Option<String>,
    },
    NotModified {
        etag: Option<String>,
    },
}

/// Executes a bounded catalog request using the supplied endpoint and conditional cache token.
pub async fn fetch(
    url: Url,
    headers: HeaderMap,
    previous_etag: Option<&str>,
) -> Result<CatalogResponse, ModelCatalogQueryError> {
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .retry(reqwest::retry::never())
        .pool_max_idle_per_host(0)
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(query_transport_error)?;
    let mut request = client.get(url).headers(headers);
    if let Some(etag) = previous_etag {
        let mut value = reqwest::header::HeaderValue::from_str(etag)
            .map_err(|_| ModelCatalogQueryError::Configuration)?;
        value.set_sensitive(true);
        request = request.header(IF_NONE_MATCH, value);
    }
    let response = request.send().await.map_err(query_transport_error)?;
    let status = response.status().as_u16();
    let etag = response
        .headers()
        .get(ETAG)
        .and_then(|value| value.to_str().ok())
        .filter(|value| value.len() <= 1024)
        .map(str::to_owned);
    if status == 304 {
        return Ok(CatalogResponse::NotModified { etag });
    }
    if !(200..300).contains(&status) {
        return Err(ModelCatalogQueryError::Http { status });
    }
    if response
        .content_length()
        .is_some_and(|len| len > BODY_LIMIT as u64)
    {
        return Err(ModelCatalogQueryError::TooLarge);
    }
    let mut bytes = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(query_transport_error)?;
        if chunk.len() > BODY_LIMIT - bytes.len() {
            return Err(ModelCatalogQueryError::TooLarge);
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(CatalogResponse::Updated { bytes, etag })
}
