//! Stable identity and presentation classification of Core model observations.
use crate::studio::runtime::chat_item::BodyKey;
use crate::{
    ExecutionShape, ThreadContentLifecycle, ThreadTextChannel, ThreadTextItem, ThreadThinkingItem,
};
use pl_core::{
    chat::PresentationPart,
    model::{
        AggregateChannel, ModelTextChannel, ObservedItemKind, ObservedPart, ObservedPartIdentity,
        ObservedPartKind,
    },
};

/// The supported combinations of model item and observed part.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum ObservedKind {
    Text(ThreadTextChannel),
    Reasoning,
    Summary,
}

pub(super) fn classify(identity: &ObservedPartIdentity) -> Option<ObservedKind> {
    match identity {
        ObservedPartIdentity::Aggregate { channel } => Some(match channel {
            AggregateChannel::Text => ObservedKind::Text(ThreadTextChannel::Commentary),
            AggregateChannel::Reasoning => ObservedKind::Reasoning,
        }),
        ObservedPartIdentity::Provider(identity) => match (identity.item_kind, identity.part) {
            (ObservedItemKind::Text(channel), ObservedPartKind::OutputText) => {
                Some(ObservedKind::Text(text_channel(channel)))
            }
            (ObservedItemKind::Reasoning, ObservedPartKind::ReasoningText) => {
                Some(ObservedKind::Reasoning)
            }
            (ObservedItemKind::Reasoning, ObservedPartKind::SummaryText) => {
                Some(ObservedKind::Summary)
            }
            _ => None,
        },
    }
}

impl ObservedKind {
    pub(super) fn shape(
        self,
        body: String,
        lifecycle: &ThreadContentLifecycle,
    ) -> (BodyKey, ExecutionShape) {
        let lifecycle = lifecycle.clone();
        match self {
            Self::Text(channel) => (
                BodyKey::Body,
                ExecutionShape::Text(ThreadTextItem::new(channel, body, Vec::new(), lifecycle)),
            ),
            Self::Reasoning => (
                BodyKey::Part(PresentationPart::ReasoningText(0)),
                ExecutionShape::Thinking(ThreadThinkingItem::new(
                    Vec::new(),
                    vec![body],
                    lifecycle,
                )),
            ),
            Self::Summary => (
                BodyKey::Part(PresentationPart::SummaryText(0)),
                ExecutionShape::Thinking(ThreadThinkingItem::new(
                    vec![body],
                    Vec::new(),
                    lifecycle,
                )),
            ),
        }
    }
}

pub(super) fn failed_preview(
    attempt_id: &str,
    generation: u32,
    part: &ObservedPart,
    lifecycle: &ThreadContentLifecycle,
) -> Result<(String, ExecutionShape), super::ProjectionError> {
    let identity = part.identity();
    let kind = classify(identity).ok_or_else(|| {
        super::ProjectionError::UnsupportedOutput(
            "failed observation has invalid part identity".into(),
        )
    })?;
    Ok((
        stable_id(attempt_id, generation, identity),
        kind.shape(part.text(), lifecycle).1,
    ))
}

/// The canonical identity of one aggregate streaming channel of an attempt.
/// It is the same in-memory identity the committed effect later finalizes for the whole channel, so a
/// preview and the terminal item it precedes never disagree on the id.
pub(super) fn aggregate_id(attempt_id: &str, generation: u32, channel: AggregateChannel) -> String {
    match channel {
        AggregateChannel::Text => super::order::observation_id(attempt_id, generation, "text"),
        AggregateChannel::Reasoning => {
            super::order::observation_id(attempt_id, generation, "reasoning")
        }
    }
}

/// Projects one live observation into its stable item identity, content field and static structure.
///
/// The identity comes from the observation's own stable fact — a request-level aggregate channel, or a
/// provider item id plus part discriminator — never from the provider payload or a late output index.
/// The returned `ExecutionShape` carries **no body**: it is the Runtime's static execution shape,
/// while the body is handed out by the caller straight from the observation's
/// shared `Arc<ContentBlock>`, so the hot path never calls `part.text()`.
///
/// The field index is fixed at `0`: one presentation id owns exactly one part, and the commit side
/// `project_presentation_items` puts that part into a chunk vector of length 1, so the streaming and
/// terminal field identities agree and a streaming `SummaryText(n)` never misaligns with a terminal
/// reasoning chunk. `None` reports a part that cannot belong to its item kind instead of inventing a
/// row.
pub(super) fn observation_preview(
    attempt_id: &str,
    generation: u32,
    part: &ObservedPart,
    lifecycle: &ThreadContentLifecycle,
) -> Option<(String, BodyKey, ExecutionShape)> {
    observation_start(attempt_id, generation, part.identity(), lifecycle)
}

pub(super) fn observation_start(
    attempt_id: &str,
    generation: u32,
    identity: &ObservedPartIdentity,
    lifecycle: &ThreadContentLifecycle,
) -> Option<(String, BodyKey, ExecutionShape)> {
    let (field, shape) = classify(identity)?.shape(String::new(), lifecycle);
    Some((stable_id(attempt_id, generation, identity), field, shape))
}

pub(super) fn stable_id(
    attempt_id: &str,
    generation: u32,
    identity: &ObservedPartIdentity,
) -> String {
    match identity {
        ObservedPartIdentity::Aggregate { channel } => {
            aggregate_id(attempt_id, generation, *channel)
        }
        ObservedPartIdentity::Provider(identity) => super::order::presentation_id(
            attempt_id,
            generation,
            identity.item_id.as_ref(),
            Some(identity.presentation_part()),
        ),
    }
}

/// Maps the core observation channel vocabulary onto the protocol text channel.
pub(super) fn text_channel(channel: ModelTextChannel) -> ThreadTextChannel {
    match channel {
        ModelTextChannel::User => ThreadTextChannel::User,
        ModelTextChannel::Commentary => ThreadTextChannel::Commentary,
        ModelTextChannel::Final => ThreadTextChannel::Final,
    }
}
