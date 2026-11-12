//! Stable account cache hints, independent of execution and diagnostic identities.
use crate::{
    model::ModelInfo,
    protocol::{ProtocolEndpoint, WireApi},
};
use sha2::{Digest, Sha256};

/// Host-owned cache affinity, independent of transport, trace IDs and prefix diagnostics.
///
/// Each agent supplies its own stable Thread ID. Auxiliary work remains bound to that Thread,
/// but uses a separate purpose so title/review traffic does not compete with its conversation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PromptCacheScope {
    thread_id: String,
    purpose: Option<String>,
}

impl PromptCacheScope {
    /// Conversation and compaction for the same Thread share this scope.
    pub fn thread(thread_id: impl Into<String>) -> Self {
        Self {
            thread_id: thread_id.into(),
            purpose: None,
        }
    }

    /// A stable auxiliary purpose within the owning Thread, such as `title` or `tool-review`.
    pub fn auxiliary(thread_id: impl Into<String>, purpose: impl Into<String>) -> Self {
        Self {
            thread_id: thread_id.into(),
            purpose: Some(purpose.into()),
        }
    }

    pub(super) fn resolve(
        &self,
        account_id: &str,
        endpoint: &ProtocolEndpoint,
        model: &ModelInfo,
    ) -> pl_protocol::Result<Option<String>> {
        if self.thread_id.trim().is_empty()
            || self.purpose.as_ref().is_some_and(|p| p.trim().is_empty())
        {
            return Err(pl_protocol::PureError::ConfigError(
                "prompt cache scope requires a nonempty Thread ID and auxiliary purpose".into(),
            ));
        }
        if !endpoint
            .effective_prompt_cache_policy(model)
            .uses_prompt_cache_key()
        {
            return Ok(None);
        }
        let isolation = binding_cache_namespace(account_id, endpoint);
        let key = match &self.purpose {
            None => cache_digest(
                &isolation,
                &self.thread_id,
                &model.model_id,
                model.binding.transport.protocol,
            ),
            Some(purpose) => {
                let mut hash = Sha256::new();
                for part in [
                    "pl-model/auxiliary-cache-key/v1",
                    &isolation,
                    &self.thread_id,
                    purpose,
                    &model.model_id,
                    match model.binding.transport.protocol {
                        WireApi::Responses => "responses",
                        WireApi::ChatCompletions => "chatCompletions",
                    },
                ] {
                    hash.update((part.len() as u64).to_le_bytes());
                    hash.update(part.as_bytes());
                }
                hex::encode(hash.finalize())
            }
        };
        Ok(Some(key))
    }
}

/// Derives a deterministic cache hint from stable model input identity and host isolation.
/// The isolation value must represent an account/deployment boundary and contain no credentials.
/// Appended dynamic context, timestamps, scope labels and diagnostic generations do not rotate it.
pub fn derive_prompt_cache_key(
    isolation: &str,
    thread_id: &str,
    model: &str,
    protocol: WireApi,
) -> String {
    // This representation is also persisted as route provenance. Keep it unchanged when
    // shortening the actual provider hint to a 64-character digest.
    format!("pl:{}", cache_digest(isolation, thread_id, model, protocol))
}

fn cache_digest(isolation: &str, thread_id: &str, model: &str, protocol: WireApi) -> String {
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
    hex::encode(hash.finalize())
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
    if let Some(session) = &endpoint.chatgpt_session {
        field(session.registration_id().as_bytes());
    }
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
