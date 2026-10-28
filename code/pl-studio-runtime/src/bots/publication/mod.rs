//! One managed delivery owner for public frontend items and migrated finite Final obligations.
//! Session is the only content source; storage/publication owns all durable delivery fences.

mod cards;
mod eligibility;
mod legacy;
mod operation;
mod projection;
mod scan;
mod tasks;
mod worker;

pub(in crate::bots) use tasks::PublicationTasks;

use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};

fn unavailable(message: &'static str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Unavailable, message, true, None)
}

fn attention(message: &'static str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Unavailable, message, false, None)
}

/// A concurrent revision/coverage race is not corrupt history or a removal. Preserve the typed
/// error as a source, retry the canonical read, and never manufacture an empty/truncated item.
fn content_error(context: &'static str, error: anyhow::Error) -> FeishuError {
    use pl_core::chat::ChatError;
    if let Some(chat) = error.downcast_ref::<ChatError>() {
        match chat {
            ChatError::StaleRevision { .. }
            | ChatError::NotFound(_)
            | ChatError::ReadInvalidated => {
                return unavailable(
                    "canonical publication source changed or is temporarily missing",
                );
            }
            ChatError::Cancelled => return FeishuError::cancelled(),
            ChatError::Overloaded(_) => {
                return attention(
                    "canonical publication reader budget exhausted; local recovery required",
                );
            }
            _ => {}
        }
    }
    FeishuError::history_read(context, error)
}
