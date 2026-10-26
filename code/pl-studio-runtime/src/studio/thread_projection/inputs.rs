//! Accepted input items retain stable product identity across queueing, steering and retries.
use super::{
    ProjectionError,
    content::{InputView, input_view},
};
use pl_core::thread::input::InputState;
use pl_protocol::{
    MessagePresentation, ThreadContentLifecycle, ThreadItem, ThreadItemState, ThreadTextChannel,
    ThreadTextItem,
};

pub(super) fn project_input(
    thread_id: &str,
    input: &pl_core::thread::input::InputRecord,
    ordinal: u64,
    created_at: i64,
    revision: u64,
    updated_at: i64,
) -> Result<Option<ThreadItem>, ProjectionError> {
    let view = input_view(input);
    if matches!(
        &view,
        Ok(InputView::Content(content)) if content.presentation == MessagePresentation::Hidden
    ) {
        return Ok(None);
    }
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
    let state = match view {
        Ok(InputView::Content(content)) => ThreadItemState::Text(ThreadTextItem::new(
            ThreadTextChannel::User,
            content.text,
            content.attachments,
            lifecycle,
        )),
        // A continuation's control input is framework control, not saved user content: it projects as
        // one runtime notice with no payload to expand, so the framework encoding never reaches the
        // transcript and no user question is repeated.
        Ok(InputView::ControlNotice { notice }) => ThreadItemState::Raw(
            pl_protocol::ThreadRawItem::runtime_control(notice, updated_at),
        ),
        Err(error) => ThreadItemState::Raw(pl_protocol::ThreadRawItem::stored(
            vec![super::raw_payload(&input.input.payload)],
            error.to_string(),
            updated_at,
        )),
    };
    Ok(Some(ThreadItem::new(
        input.input.id.clone(),
        thread_id.into(),
        turn_id,
        ordinal,
        revision,
        created_at,
        updated_at,
        state,
    )))
}
