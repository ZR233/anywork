//! Stable account cache hints, independent of execution and diagnostic identities.
use crate::protocol::WireApi;
use sha2::{Digest, Sha256};

/// Derives a deterministic cache hint from stable model input identity and host isolation.
/// The isolation value must represent an account/deployment boundary and contain no credentials.
/// Appended dynamic context, timestamps, scope labels and diagnostic generations do not rotate it.
pub fn derive_prompt_cache_key(
    isolation: &str,
    thread_id: &str,
    model: &str,
    protocol: WireApi,
) -> String {
    let mut hash = Sha256::new();
    for part in [
        "pl-model/cache-key/v2",
        isolation,
        thread_id,
        model,
        match protocol {
            WireApi::Responses => "responses",
            WireApi::ChatCompletions => "chatCompletions",
        },
    ] {
        hash.update((part.len() as u64).to_le_bytes());
        hash.update(part.as_bytes());
    }
    format!("pl:{}", hex::encode(hash.finalize()))
}

/// Creates an account/deployment isolation namespace without exposing endpoint credentials.
/// Only configured connection material participates; execution IDs and generated transport headers do not.
/// The stable account ID is part of the namespace, so renaming the surrounding API cannot turn the
/// same account into a different physical binding.
pub fn binding_cache_namespace(
    account_id: &str,
    endpoint: &crate::protocol::ProtocolEndpoint,
) -> String {
    let mut hash = Sha256::new();
    let mut field = |value: &[u8]| {
        hash.update((value.len() as u64).to_le_bytes());
        hash.update(value);
    };
    field(b"pl-model/cache-isolation/v1");
    field(account_id.as_bytes());
    field(endpoint.base_url.as_bytes());
    field(
        endpoint
            .bearer_token
            .as_deref()
            .unwrap_or_default()
            .as_bytes(),
    );
    let mut headers = endpoint
        .http_headers
        .iter()
        .flat_map(|headers| headers.iter())
        .map(|(name, value)| (name.to_ascii_lowercase(), value.as_str()))
        .collect::<Vec<_>>();
    headers.sort();
    for (name, value) in headers {
        field(name.as_bytes());
        field(value.as_bytes());
    }
    format!("binding:{}", hex::encode(hash.finalize()))
}
