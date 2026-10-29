//! Single managed task owns both native receive and the sole StreamSink (no secondary sink task).
use std::sync::Arc;

use pl_protocol::studio::StudioErrorCode;
use pl_studio_runtime::ConversationEvent;

use super::owner::{ConversationOwner, error};
use crate::api::studio::convert::{thread_stream::bridge_thread_update, timeline_content};
use crate::api::studio::types::{BridgeConversationEvent, BridgeConversationFrame, BridgeError};
use crate::frb_generated::StreamSink;

pub(super) async fn run(
    owner: Arc<ConversationOwner>,
    sink: StreamSink<BridgeConversationFrame>,
) -> Result<(), BridgeError> {
    let terminal = pump(&owner, &sink).await;
    owner.request_close();
    // Exactly one terminal attempt, without acquiring credit or waiting for ACK. A disconnected sink
    // gets no second failure attempt. FRB 2.13 exposes disconnection through add() only; adapter stream
    // cancellation must also call request_close so an idle/credit-blocked producer is woken.
    if let Some(event) = terminal {
        let sequence = owner.state.lock().unwrap_or_else(|e| e.into_inner()).sent;
        let _ = sink.add(frame(&owner, sequence, event));
    }
    drop(sink);
    owner.close_native().await
}

async fn pump(
    owner: &ConversationOwner,
    sink: &StreamSink<BridgeConversationFrame>,
) -> Option<BridgeConversationEvent> {
    // This async guard serializes the unique native receiver and close; queries never touch it. The
    // guard is released before run calls close_native, including every conversion/error/cancel path.
    let mut native = owner.native().await;
    let Some(feed) = native.as_mut() else {
        return Some(BridgeConversationEvent::Closed);
    };
    loop {
        if !owner.wait_credit().await {
            return Some(BridgeConversationEvent::Closed);
        }
        let result = tokio::select! {
            biased;
            () = owner.cancel.cancelled() => return Some(BridgeConversationEvent::Closed),
            result = feed.recv() => result,
        };
        let event = match result {
            Ok(Some(event)) => event,
            Ok(None) => return Some(BridgeConversationEvent::Closed),
            Err(error) => {
                return Some(BridgeConversationEvent::Failure {
                    error: error.into(),
                });
            }
        };
        if owner.cancel.is_cancelled() {
            return Some(BridgeConversationEvent::Closed);
        }
        let event = match convert(event) {
            Ok(event) => event,
            Err(error) => return Some(BridgeConversationEvent::Failure { error }),
        };
        match publish(owner, sink, event) {
            Publication::Sent => {}
            Publication::Closing => return Some(BridgeConversationEvent::Closed),
            Publication::Disconnected => return None,
            Publication::Failed(error) => return Some(BridgeConversationEvent::Failure { error }),
        }
    }
}

fn convert(event: ConversationEvent) -> Result<BridgeConversationEvent, BridgeError> {
    Ok(match event {
        ConversationEvent::ActivityContent { frame, completed } => {
            BridgeConversationEvent::ActivityContent {
                frame: crate::api::studio::convert::thread_stream::bridge_activity_content(frame),
                completed: completed.map(|value| Box::new(timeline_content::update(*value))),
            }
        }
        ConversationEvent::State { update } => BridgeConversationEvent::State {
            update: Box::new(bridge_thread_update(*update)?),
        },
        ConversationEvent::ContentBaseline { baseline } => {
            BridgeConversationEvent::ContentBaseline {
                baseline: timeline_content::baseline(baseline),
            }
        }
        ConversationEvent::ContentUpdate { update } => BridgeConversationEvent::ContentUpdate {
            update: timeline_content::update(update),
        },
    })
}

enum Publication {
    Sent,
    Closing,
    Disconnected,
    Failed(BridgeError),
}

fn publish(
    owner: &ConversationOwner,
    sink: &StreamSink<BridgeConversationFrame>,
    event: BridgeConversationEvent,
) -> Publication {
    // FRB add() synchronously encodes/posts a bounded DTO; it never calls Dart synchronously or awaits.
    // Post and sent-prefix publication share the ACK mutex: Dart's immediate ACK cannot race ahead of
    // sent, and a failed post never becomes an acknowledgeable prefix. No other producer exists.
    let mut state = owner.state.lock().unwrap_or_else(|e| e.into_inner());
    if state.closing || owner.cancel.is_cancelled() {
        return Publication::Closing;
    }
    let Some(sequence) = state.sent.checked_add(1) else {
        return Publication::Failed(error(
            StudioErrorCode::Overloaded,
            "conversation delivery sequence exhausted",
        ));
    };
    if sink.add(frame(owner, sequence, event)).is_err() {
        return Publication::Disconnected;
    }
    state.sent = sequence;
    Publication::Sent
}

fn frame(
    owner: &ConversationOwner,
    sequence: u64,
    event: BridgeConversationEvent,
) -> BridgeConversationFrame {
    BridgeConversationFrame {
        thread_id: owner.thread_id.clone(),
        subscription_id: owner.subscription_id.clone(),
        delivery_sequence: sequence,
        event,
    }
}
