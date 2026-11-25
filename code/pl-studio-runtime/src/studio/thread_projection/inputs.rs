//! Accepted input items retain stable product identity across queueing, steering and retries.
use super::{ContentError, InputView, ProjectionError, input_view};
use crate::{ExecutionItem, ExecutionShape};
use crate::{MessagePresentation, ThreadContentLifecycle, ThreadTextChannel, ThreadTextItem};
use pl_core::thread::input::InputState;

pub(super) fn project_input(
    thread_id: &str,
    input: &pl_core::thread::input::InputRecord,
    ordinal: u64,
    created_at: i64,
    revision: u64,
    updated_at: i64,
) -> Result<Option<ExecutionItem>, ProjectionError> {
    let turn_id = match &input.state {
        InputState::Consumed { turn_id, .. } => turn_id.clone(),
        // Preparation may fail without consuming the input. Only consumption establishes its
        // permanent Turn binding; a later attempt can still consume the same queued input.
        InputState::Pending | InputState::Discarded => String::new(),
    };
    let lifecycle = match input.state {
        InputState::Pending | InputState::Consumed { .. } => {
            ThreadContentLifecycle::completed(created_at)
        }
        InputState::Discarded => ThreadContentLifecycle::cancelled(
            updated_at,
            "Input discarded before model admission.".into(),
        ),
    };
    let Some(state) =
        project_input_shape(input, lifecycle, updated_at, InputProjection::Placement)?
    else {
        return Ok(None);
    };
    Ok(Some(ExecutionItem::new(
        input.input.id.clone(),
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Owned(thread_id.into()),
            turn_id: std::borrow::Cow::Owned(turn_id),
            ordinal,
            revision,
            created_at,
            updated_at,
        },
        state,
    )))
}

/// Admission freezes the original public input. Placement also carries runtime notices and
/// preserves invalid resident payloads for diagnostics.
pub(in crate::studio) enum InputProjection {
    Admission,
    Placement,
}

pub(in crate::studio) fn project_input_shape(
    input: &pl_core::thread::input::InputRecord,
    lifecycle: ThreadContentLifecycle,
    timestamp: i64,
    projection: InputProjection,
) -> Result<Option<ExecutionShape>, ProjectionError> {
    let shape = match input_view(input) {
        Ok(InputView::Content(content)) if content.presentation == MessagePresentation::Hidden => {
            return Ok(None);
        }
        Ok(InputView::Content(content)) => ExecutionShape::Text(ThreadTextItem::new(
            ThreadTextChannel::User,
            content.text,
            content.attachments,
            lifecycle,
        )),
        Ok(InputView::ControlNotice { notice }) => match projection {
            InputProjection::Admission => return Ok(None),
            InputProjection::Placement => {
                ExecutionShape::Raw(crate::ThreadRawItem::runtime_control(notice, timestamp))
            }
        },
        Err(error) => {
            if matches!(projection, InputProjection::Admission)
                && !matches!(error, ContentError::Unsupported { .. })
            {
                return Err(ProjectionError::UserInput(error.to_string()));
            }
            ExecutionShape::Raw(crate::ThreadRawItem::stored(
                vec![super::raw_payload(&input.input.payload)],
                error.to_string(),
                timestamp,
            ))
        }
    };
    Ok(Some(shape))
}
