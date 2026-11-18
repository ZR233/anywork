use crate::completion::stream::replay::ReplayUpdate;
use serde_json::Value;
pub fn replay_update(event: &super::SseStreamEvent) -> Option<ReplayUpdate> {
    if let Some(choices) = &event.choices {
        return Some(ReplayUpdate::TextDelta(
            choices
                .first()
                .and_then(|choice| choice.delta.content.clone())
                .unwrap_or_default(),
        ));
    }
    match event.kind.as_str() {
        "response.output_item.added" => event.item.clone().map(|item| ReplayUpdate::PendingItem {
            index: event.output_index,
            item,
        }),
        "response.output_item.done" => event.item.clone().map(|item| ReplayUpdate::Item {
            index: event.output_index,
            item,
        }),
        "response.completed" => Some(ReplayUpdate::Output {
            items: event
                .response
                .as_ref()
                .and_then(|response| response.get("output"))
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default(),
        }),
        _ => None,
    }
}
