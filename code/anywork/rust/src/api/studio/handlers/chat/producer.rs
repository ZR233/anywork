//! Single managed task owns both native receive and the sole StreamSink (no secondary sink task).
use std::sync::Arc;

use pl_protocol::studio::StudioErrorCode;
use pl_studio_runtime::ConversationEvent;

use super::owner::{ConversationOwner, error};
use crate::api::studio::convert::{chat, thread_stream::bridge_thread_update};
use crate::api::studio::types::{BridgeConversationEvent, BridgeConversationFrame, BridgeError};
use crate::frb_generated::{SseEncode, StreamSink};

// Includes the generated SSE encoding, envelope identities, collection overhead and action byte.
const MAX_FRAME_BYTES: usize = pl_protocol::CHAT_BATCH_MAX_BYTES as usize;
const MAX_TERMINAL_BYTES: usize = 16 * 1024;

pub(super) async fn run(
    owner: Arc<ConversationOwner>,
    sink: StreamSink<BridgeConversationFrame>,
) -> Result<(), BridgeError> {
    run_into(owner, move |frame| sink.add(frame).is_ok()).await
}

pub(super) async fn run_into(
    owner: Arc<ConversationOwner>,
    post: impl Fn(BridgeConversationFrame) -> bool,
) -> Result<(), BridgeError> {
    let terminal = pump(&owner, &post).await;
    owner.producer_cancel.cancel();
    // Exactly one terminal attempt, without acquiring credit or waiting for ACK. A disconnected sink
    // gets no second failure attempt. FRB 2.13 exposes disconnection through add() only; adapter stream
    // cancellation must also call request_close so an idle/credit-blocked producer is woken.
    if let Some(event) = terminal {
        let sequence = owner.state.lock().unwrap_or_else(|e| e.into_inner()).sent;
        match bounded_terminal(frame(&owner, sequence, event)) {
            Ok(frame) => {
                post(frame);
            }
            Err(error) => owner.remember_failure("terminal", error),
        }
    }
    drop(post);
    owner.close_native().await
}

async fn pump(
    owner: &ConversationOwner,
    post: &impl Fn(BridgeConversationFrame) -> bool,
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
            () = owner.producer_cancel.cancelled() => return Some(BridgeConversationEvent::Closed),
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
        if owner.producer_cancel.is_cancelled() {
            return Some(BridgeConversationEvent::Closed);
        }
        let event = match convert(event) {
            Ok(event) => event,
            Err(error) => return Some(BridgeConversationEvent::Failure { error }),
        };
        match publish(owner, post, event) {
            Publication::Sent => {}
            Publication::Closing => return Some(BridgeConversationEvent::Closed),
            Publication::Disconnected => return None,
            Publication::Failed(error) => return Some(BridgeConversationEvent::Failure { error }),
        }
    }
}

fn convert(event: ConversationEvent) -> Result<BridgeConversationEvent, BridgeError> {
    Ok(match event {
        ConversationEvent::State { update } => BridgeConversationEvent::State {
            update: Box::new(bridge_thread_update(*update)?),
        },
        ConversationEvent::Chat { batch } => BridgeConversationEvent::Chat {
            batch: Box::new(chat::batch(*batch)),
        },
        ConversationEvent::Activity { snapshot } => BridgeConversationEvent::Activity {
            snapshot: Box::new(chat::activity((*snapshot).clone())),
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
    post: &impl Fn(BridgeConversationFrame) -> bool,
    event: BridgeConversationEvent,
) -> Publication {
    // FRB add() synchronously encodes/posts a bounded DTO; it never calls Dart synchronously or awaits.
    // Post and sent-prefix publication share the ACK mutex: Dart's immediate ACK cannot race ahead of
    // sent, and a failed post never becomes an acknowledgeable prefix. No other producer exists.
    let mut state = owner.state.lock().unwrap_or_else(|e| e.into_inner());
    if state.closing || owner.producer_cancel.is_cancelled() {
        return Publication::Closing;
    }
    let Some(sequence) = state.sent.checked_add(1) else {
        return Publication::Failed(error(
            StudioErrorCode::Overloaded,
            "conversation delivery sequence exhausted",
        ));
    };
    // There is no pending FRB payload while credit is occupied. Even an accidental second
    // publication must not bypass the single-unacknowledged-batch invariant.
    if state.inflight_bytes != 0 {
        return Publication::Failed(error(
            StudioErrorCode::Internal,
            "conversation publication has no credit",
        ));
    }
    let frame = frame(owner, sequence, event);
    let bytes = match data_bytes(&frame) {
        Ok(bytes) => bytes,
        Err(error) => return Publication::Failed(error),
    };
    if !post(frame) {
        return Publication::Disconnected;
    }
    tracing::debug!(
        target: "conversation_work",
        thread_id = %owner.thread_id,
        trace_id = %owner.subscription_id,
        delivery_sequence = sequence,
        frb_encoded_bytes = bytes,
        "FRB frame posted"
    );
    state.sent = sequence;
    state.inflight_bytes = bytes;
    Publication::Sent
}

fn data_bytes(frame: &BridgeConversationFrame) -> Result<usize, BridgeError> {
    let bytes = encoded_bytes(frame);
    if bytes > MAX_FRAME_BYTES {
        return Err(error(
            StudioErrorCode::Overloaded,
            "conversation frame exceeds the encoded transport budget",
        ));
    }
    Ok(bytes)
}

fn encoded_bytes(frame: &BridgeConversationFrame) -> usize {
    // Use the pinned FRB encoder, not a payload-length estimate or an independent wire schema.
    // The temporary encoding is dropped before sink.add encodes/posts the one admitted frame.
    let mut serializer = flutter_rust_bridge::for_generated::SseSerializer::new();
    frame.clone().sse_encode(&mut serializer);
    serializer.cursor.get_ref().len() + 1
}

fn bounded_terminal(
    mut frame: BridgeConversationFrame,
) -> Result<BridgeConversationFrame, BridgeError> {
    if encoded_bytes(&frame) <= MAX_TERMINAL_BYTES {
        return Ok(frame);
    }
    // Preserve the original diagnostic outside the bounded port envelope, and report the actual
    // transport limit explicitly instead of truncating typed domain error details into invalid JSON.
    tracing::error!(terminal = ?frame.event, "conversation terminal exceeds transport budget");
    frame.event = BridgeConversationEvent::Failure {
        error: error(
            StudioErrorCode::Overloaded,
            "conversation terminal exceeds the encoded transport budget",
        ),
    };
    if encoded_bytes(&frame) > MAX_TERMINAL_BYTES {
        return Err(error(
            StudioErrorCode::Overloaded,
            "conversation identity exceeds terminal transport budget",
        ));
    }
    Ok(frame)
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::studio::types::{
        BridgeChatAtom, BridgeChatAtomKind, BridgeChatAtomLifecycle, BridgeChatBatch,
        BridgeChatDeliveryKind, BridgeChatPlacement, BridgeChatSourceId, BridgeChatTerminalOutcome,
        BridgeCompletedEntry, BridgeCompletionRunPosition, BridgeErrorCode, BridgeMainPresentation,
        BridgePayloadData,
    };

    fn data(payload_bytes: usize) -> BridgeConversationFrame {
        BridgeConversationFrame {
            thread_id: "线程".into(),
            subscription_id: "subscription".into(),
            delivery_sequence: 7,
            event: BridgeConversationEvent::Chat {
                batch: Box::new(BridgeChatBatch {
                    placement: BridgeChatPlacement::Append,
                    entries: vec![BridgeCompletedEntry {
                        record_id: "frozen-completion".into(),
                        completion_seq: 3,
                        run: Some(BridgeCompletionRunPosition {
                            start_seq: 3,
                            ordinal: 1,
                        }),
                        main_presentation: BridgeMainPresentation::Single,
                        atom: BridgeChatAtom {
                            id: "member".into(),
                            completion_item_id: Some("frozen-completion".into()),
                            completion_seq: Some(3),
                            source: BridgeChatSourceId::ForegroundTurn {
                                turn_id: "turn".into(),
                            },
                            source_state: None,
                            source_order: Some(2),
                            kind: BridgeChatAtomKind::Text,
                            delivery: BridgeChatDeliveryKind::Foreground,
                            lifecycle: BridgeChatAtomLifecycle::Terminal {
                                started: None,
                                ended: None,
                                outcome: BridgeChatTerminalOutcome::Completed,
                            },
                            turn_id: None,
                            attempt_id: None,
                            tool: None,
                            wait: None,
                            text_channel: None,
                            content_present: None,
                            started_at: None,
                            finished_at: None,
                            contents: Vec::new(),
                            payload: Some(BridgePayloadData::Inline {
                                bytes: vec![b'x'; payload_bytes],
                            }),
                        },
                    }],
                    before: None,
                    from_seq: Some(2),
                    through_seq: 3,
                }),
            },
        }
    }

    #[test]
    fn data_admission_counts_the_real_frame_and_rejects_one_byte_over_budget() {
        let overhead = data_bytes(&data(0)).unwrap();
        assert!(overhead > "线程subscriptionmessage".len());
        let exact = data(MAX_FRAME_BYTES - overhead);
        assert_eq!(data_bytes(&exact).unwrap(), MAX_FRAME_BYTES);
        let too_big = data(MAX_FRAME_BYTES - overhead + 1);
        assert_eq!(
            data_bytes(&too_big).unwrap_err().code,
            BridgeErrorCode::Overloaded
        );
    }

    #[test]
    fn failure_and_closed_keep_the_last_sequence_even_zero_and_have_a_fixed_budget() {
        for sequence in [0, 7] {
            let mut terminal = data(0);
            terminal.delivery_sequence = sequence;
            terminal.event = BridgeConversationEvent::Closed;
            let terminal = bounded_terminal(terminal).unwrap();
            assert_eq!(terminal.delivery_sequence, sequence);
            assert!(encoded_bytes(&terminal) <= MAX_TERMINAL_BYTES);
            let mut failure = terminal;
            failure.event = BridgeConversationEvent::Failure {
                error: error(
                    StudioErrorCode::Internal,
                    &"诊断".repeat(MAX_TERMINAL_BYTES),
                ),
            };
            let failure = bounded_terminal(failure).unwrap();
            assert_eq!(failure.delivery_sequence, sequence);
            assert!(encoded_bytes(&failure) <= MAX_TERMINAL_BYTES);
            assert!(
                matches!(failure.event, BridgeConversationEvent::Failure { error } if error.code == BridgeErrorCode::Overloaded)
            );
        }
    }
}
