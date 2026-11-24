use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::ContentOwner;
use pl_core::chat::{ChatError, ChatKey};

static ID_COUNTER: AtomicU64 = AtomicU64::new(0);

pub fn new_id(prefix: &str) -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_micros();
    let seq = ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{prefix}-{now:x}-{seq:x}")
}

pub fn unix_seconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

/// One encoding for product content ownership at the Core/storage boundary.
pub(crate) fn content_owner_key(owner: &ContentOwner) -> Result<ChatKey, ChatError> {
    match owner {
        ContentOwner::Item { item_id } => ChatKey::new("item", item_id),
        ContentOwner::DisplayObservation {
            block_id,
            member_key,
        } => {
            if block_id.is_empty() || member_key.is_empty() {
                return Err(ChatError::InvalidArgument(
                    "display observation requires block and member identity".into(),
                ));
            }
            let value = serde_json::to_string(&(block_id, member_key))
                .map_err(|error| ChatError::InvalidArgument(error.to_string()))?;
            ChatKey::new("display-observation", &value)
        }
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
