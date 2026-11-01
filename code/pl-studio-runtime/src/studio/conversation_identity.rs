//! One encoding for product content ownership at the Core/storage boundary.

use pl_core::chat::{ChatError, ChatKey};
use pl_protocol::ContentOwner;

pub(in crate::studio) fn content_owner_key(owner: &ContentOwner) -> Result<ChatKey, ChatError> {
    match owner {
        ContentOwner::Item { item_id } => ChatKey::new("item", item_id),
        ContentOwner::Current {
            domain,
            id,
            revision,
        } => {
            if domain.is_empty() || id.is_empty() {
                return Err(ChatError::InvalidArgument(
                    "current content owner requires a domain and identity".into(),
                ));
            }
            let value = serde_json::to_string(&(domain, id, revision))
                .map_err(|error| ChatError::InvalidArgument(error.to_string()))?;
            ChatKey::new("current", &value)
        }
    }
}
