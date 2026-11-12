//! Passive one-shot reads share the same public baseline as long-lived observers.
use super::Boundary;
use anyhow::{Context, Result};
use pl_protocol::{ThreadSnapshot, ThreadSubscriptionUpdate, studio::StudioErrorReason};
use pl_studio_runtime::{ConversationStateFeed, StudioRuntime};

pub fn resync_error(error: &anyhow::Error) -> Option<&pl_protocol::studio::StudioError> {
    error
        .downcast_ref::<pl_protocol::studio::StudioError>()
        .filter(|error| {
            error.reason() == Some(StudioErrorReason::ConversationResyncRequired.label())
        })
}

// Opening State is passive: cancelling it drops only read/subscription preparation, not an owner
// command. Every successfully returned feed is owned by the caller and released there.
pub async fn open(
    runtime: &StudioRuntime,
    id: &str,
    budget: &Boundary,
) -> Result<ConversationStateFeed> {
    budget.check()?;
    let opened = tokio::select! {
        biased;
        _ = budget.stopped() => {
            budget.check()?;
            anyhow::bail!("State open boundary stopped without a reason");
        }
        opened = runtime.open_conversation_state_feed(id) => opened,
    };
    if let Err(stopped) = budget.check() {
        return Err(match opened {
            Ok(mut feed) => match feed.close().await {
                Ok(()) => stopped,
                Err(error) => stopped.context(format!("State close also failed: {error:#}")),
            },
            Err(error) => stopped.context(format!("State open also failed: {error:#}")),
        });
    }
    opened
}

pub async fn snapshot(
    runtime: &StudioRuntime,
    id: &str,
    budget: &Boundary,
) -> Result<ThreadSnapshot> {
    loop {
        let result = async {
            let mut feed = open(runtime, id, budget).await?;
            let first = budget.read(feed.recv()).await;
            // State close is synchronous release in the public API; retain the original read
            // failure if both operations fail.
            let closed = feed.close().await;
            let first = match (first, closed) {
                (Err(error), Err(closed)) => {
                    return Err(
                        error.context(format!("State baseline close also failed: {closed:#}"))
                    );
                }
                (Err(error), _) | (_, Err(error)) => return Err(error),
                (Ok(first), Ok(())) => first,
            };
            match first.context("State feed ended before its baseline")? {
                ThreadSubscriptionUpdate::Snapshot {
                    completed_history_version,
                    snapshot,
                } => {
                    anyhow::ensure!(
                        completed_history_version == pl_protocol::COMPLETED_HISTORY_VERSION,
                        "unsupported completed-history protocol version"
                    );
                    Ok(*snapshot)
                }
                _ => anyhow::bail!("State notification before baseline"),
            }
        }
        .await;
        match result {
            Err(error) if resync_error(&error).is_some() => continue,
            result => return result,
        }
    }
}
