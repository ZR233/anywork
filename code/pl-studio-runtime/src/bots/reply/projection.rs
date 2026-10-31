//! Bounded target-only projection of immutable completions and committed activity.

use super::content::{FinalError, MAX_TURN_BODY_BYTES, MAX_TURN_CONTENT_ITEMS};
use pl_protocol::{
    ActivityContentFrame, ActivityPartMetadata, ActivityTextOperation, ActivityTextRegion,
    ActivityToolMetadata, ThreadActivity, ThreadContentField, ThreadTextChannel,
    TimelineDescriptor, TimelineItem, TimelineTurnOutcome,
};
use std::collections::BTreeMap;

const ACTIVITY_BUDGET: usize = 64 * 1024 * 1024;

#[derive(Clone)]
struct ActivityState {
    generation: String,
    revision: u64,
    activity: Option<Box<ThreadActivity>>,
    response: Vec<ActivityPartMetadata>,
    reasoning: Vec<ActivityPartMetadata>,
    tools: Vec<ActivityToolMetadata>,
    text: BTreeMap<ActivityTextRegion, String>,
    total_bytes: u64,
}

pub(super) struct ReplyProjection {
    thread_id: String,
    turn_id: String,
    items: BTreeMap<u64, TimelineItem>,
    covered: bool,
    current: Option<ActivityState>,
    staging: Option<ActivityState>,
}

impl ReplyProjection {
    pub(super) fn new(thread_id: &str, turn_id: &str) -> Self {
        Self {
            thread_id: thread_id.into(),
            turn_id: turn_id.into(),
            items: BTreeMap::new(),
            covered: false,
            current: None,
            staging: None,
        }
    }

    pub(super) fn add_page(&mut self, items: Vec<TimelineItem>) -> Result<(), FinalError> {
        let mut staged = self.items.clone();
        for mut item in items {
            if item.header.thread_id != self.thread_id
                || item.header.id.is_empty()
                || item.header.append_seq == 0
            {
                return Err(gap("reply completion identity conflict"));
            }
            if item.header.turn_id.as_deref() != Some(&self.turn_id) {
                continue;
            }
            if !matches!(&item.descriptor, TimelineDescriptor::Turn(_))
                && !matches!(&item.descriptor, TimelineDescriptor::Text(text) if text.channel == ThreadTextChannel::Final)
            {
                continue;
            }
            item.fields
                .retain(|field| field.field == ThreadContentField::Text);
            if item.fields.len() > 1
                || item
                    .fields
                    .iter()
                    .any(|field| field.text.len() as u64 > field.total_bytes)
            {
                return Err(gap("invalid reply text preview"));
            }
            if let Some(old) = staged.get(&item.header.append_seq) {
                if old != &item {
                    return Err(gap("reply completion changed immutable item"));
                }
                continue;
            }
            if staged.values().any(|old| old.header.id == item.header.id) {
                return Err(gap("duplicate reply completion identity"));
            }
            staged.insert(item.header.append_seq, item);
        }
        let bytes = staged
            .values()
            .flat_map(|item| &item.fields)
            .try_fold(0usize, |n, field| n.checked_add(field.text.len()))
            .ok_or_else(|| gap("reply body size overflow"))?;
        if staged.len() > MAX_TURN_CONTENT_ITEMS || bytes > MAX_TURN_BODY_BYTES {
            return Err(FinalError::Attention(
                "reply projection exceeded its item or UTF-8 budget".into(),
            ));
        }
        self.items = staged;
        Ok(())
    }

    pub(super) fn mark_covered(&mut self) {
        self.covered = true;
    }

    pub(super) fn reset_activity(&mut self) {
        self.current = None;
        self.staging = None;
    }

    pub(super) fn validate_commit(&self, frame: &ActivityContentFrame) -> Result<(), FinalError> {
        let ActivityContentFrame::Commit {
            generation,
            revision,
        } = frame
        else {
            return Err(gap("activity frame is not commit"));
        };
        let stage = self
            .staging
            .as_ref()
            .ok_or_else(|| gap("activity commit without begin"))?;
        if stage.generation != *generation
            || stage.revision != *revision
            || stage
                .text
                .values()
                .map(|text| text.len() as u64)
                .sum::<u64>()
                != stage.total_bytes
            || stage.response.iter().any(|part| {
                stage
                    .text
                    .get(&ActivityTextRegion::Response {
                        item_id: part.item_id.clone(),
                    })
                    .map_or(0, String::len) as u64
                    != part.total_bytes
            })
        {
            return Err(gap("activity commit identity or length conflict"));
        }
        Ok(())
    }

    pub(super) fn terminal(&self, durable_seq: u64) -> Option<TimelineTurnOutcome> {
        self.items
            .values()
            .rev()
            .find_map(|item| match &item.descriptor {
                TimelineDescriptor::Turn(turn) if item.header.append_seq <= durable_seq => {
                    Some(turn.outcome.clone())
                }
                _ => None,
            })
    }

    pub(super) fn preview(&self) -> Option<String> {
        if !self.covered {
            return None;
        }
        let mut text = String::new();
        for item in self.items.values() {
            if !matches!(&item.descriptor, TimelineDescriptor::Text(value) if value.channel == ThreadTextChannel::Final)
            {
                continue;
            }
            if let Some(field) = item
                .fields
                .iter()
                .find(|field| field.field == ThreadContentField::Text)
            {
                text.push_str(&field.text);
                if field.text.len() as u64 != field.total_bytes {
                    return (!text.trim().is_empty()).then_some(text);
                }
            }
        }
        if let Some(current) = &self.current
            && current.activity.as_ref().is_some_and(|a| {
                a.thread_id == self.thread_id && a.turn_id.as_deref() == Some(self.turn_id.as_str())
            })
        {
            let mut progress = String::new();
            for part in &current.reasoning {
                if let Some(value) = current.text.get(&ActivityTextRegion::Reasoning {
                    item_id: part.item_id.clone(),
                }) && !value.trim().is_empty()
                {
                    progress.push_str("思考中：");
                    progress.extend(value.chars().take(2048));
                    progress.push('\n');
                }
            }
            for tool in &current.tools {
                progress.push_str("工具：");
                progress.extend(tool.name.chars().take(128));
                progress.push_str(&format!(" ({:?})\n", tool.state));
            }
            if !progress.is_empty() {
                text.push_str(&progress);
                text.push('\n');
            }
            for part in &current.response {
                if self
                    .items
                    .values()
                    .any(|item| item.header.id == part.item_id)
                {
                    continue;
                }
                if let Some(value) = current.text.get(&ActivityTextRegion::Response {
                    item_id: part.item_id.clone(),
                }) {
                    text.push_str(value);
                }
            }
        }
        (!text.trim().is_empty()).then_some(text)
    }

    /// Prepare a change without exposing any intermediate frame.
    pub(super) fn activity(&mut self, frame: ActivityContentFrame) -> Result<(), FinalError> {
        if matches!(frame, ActivityContentFrame::Commit { .. }) {
            self.validate_commit(&frame)?;
        }
        match frame {
            ActivityContentFrame::Begin {
                generation,
                base_revision,
                revision,
                activity,
                reasoning,
                response,
                tools,
                total_bytes,
            } => {
                if self.staging.is_some()
                    || generation.is_empty()
                    || total_bytes > ACTIVITY_BUDGET as u64
                    || reasoning.len() + response.len() + tools.len() > MAX_TURN_CONTENT_ITEMS
                    || activity
                        .as_ref()
                        .is_some_and(|a| a.thread_id != self.thread_id)
                {
                    return Err(gap("invalid activity begin"));
                }
                let text = match (base_revision, &self.current) {
                    (None, _) => BTreeMap::new(),
                    (Some(base), Some(current))
                        if current.generation == generation
                            && current.revision == base
                            && revision > base =>
                    {
                        current.text.clone()
                    }
                    _ => return Err(gap("activity revision gap")),
                };
                self.staging = Some(ActivityState {
                    generation,
                    revision,
                    activity,
                    reasoning,
                    response,
                    tools,
                    text,
                    total_bytes,
                });
            }
            ActivityContentFrame::Text {
                generation,
                revision,
                operations,
            } => {
                let stage = self
                    .staging
                    .as_mut()
                    .ok_or_else(|| gap("activity text without begin"))?;
                if stage.generation != generation || stage.revision != revision {
                    return Err(gap("activity text identity conflict"));
                }
                for operation in operations {
                    match operation {
                        ActivityTextOperation::Append { region, text } => {
                            stage.text.entry(region).or_default().push_str(&text)
                        }
                        ActivityTextOperation::Replace { region, text } => {
                            stage.text.insert(region, text);
                        }
                        ActivityTextOperation::Remove { region } => {
                            stage.text.remove(&region);
                        }
                    }
                    let bytes = stage
                        .text
                        .values()
                        .try_fold(0usize, |n, text| n.checked_add(text.len()))
                        .ok_or_else(|| gap("activity size overflow"))?;
                    if bytes > ACTIVITY_BUDGET {
                        return Err(gap("activity content budget exceeded"));
                    }
                }
            }
            ActivityContentFrame::Commit { .. } => {
                let stage = self
                    .staging
                    .take()
                    .ok_or_else(|| gap("activity commit without begin"))?;
                self.current = Some(stage);
            }
        }
        Ok(())
    }
}

pub(super) fn gap(message: &str) -> FinalError {
    FinalError::Retryable(message.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::{ThreadActivityKind, ThreadActivityTools};

    fn begin(revision: u64, base_revision: Option<u64>, size: u64) -> ActivityContentFrame {
        ActivityContentFrame::Begin {
            generation: "generation".into(),
            base_revision,
            revision,
            activity: Some(Box::new(ThreadActivity {
                thread_id: "thread".into(),
                identity: "activity".into(),
                revision,
                turn_id: Some("turn".into()),
                execution_id: None,
                input_id: None,
                attempt_id: None,
                kind: ThreadActivityKind::Responding,
                summary: String::new(),
                summary_truncated: false,
                thinking_summary: None,
                thinking_seconds: None,
                tools: ThreadActivityTools::default(),
            })),
            reasoning: vec![],
            response: vec![ActivityPartMetadata {
                item_id: "response".into(),
                complete: false,
                total_bytes: size,
            }],
            tools: vec![],
            total_bytes: size,
        }
    }

    fn text(revision: u64, value: &str, append: bool) -> ActivityContentFrame {
        let region = ActivityTextRegion::Response {
            item_id: "response".into(),
        };
        let operation = if append {
            ActivityTextOperation::Append {
                region,
                text: value.into(),
            }
        } else {
            ActivityTextOperation::Replace {
                region,
                text: value.into(),
            }
        };
        ActivityContentFrame::Text {
            generation: "generation".into(),
            revision,
            operations: vec![operation],
        }
    }

    fn commit(revision: u64) -> ActivityContentFrame {
        ActivityContentFrame::Commit {
            generation: "generation".into(),
            revision,
        }
    }

    #[test]
    fn activity_is_published_only_after_valid_commit() {
        let mut projection = ReplyProjection::new("thread", "turn");
        projection.mark_covered();
        assert!(projection.activity(begin(1, None, 3)).is_ok());
        assert!(projection.activity(text(1, "abc", false)).is_ok());
        assert_eq!(projection.preview(), None);
        assert!(projection.activity(commit(1)).is_ok());
        assert_eq!(projection.preview().as_deref(), Some("abc"));
        assert!(projection.activity(begin(2, Some(1), 4)).is_ok());
        assert!(projection.activity(text(2, "d", true)).is_ok());
        assert_eq!(projection.preview().as_deref(), Some("abc"));
        assert!(projection.activity(commit(2)).is_ok());
        assert_eq!(projection.preview().as_deref(), Some("abcd"));
        assert!(projection.activity(begin(3, Some(1), 4)).is_err());
        assert_eq!(projection.preview().as_deref(), Some("abcd"));
    }

    #[test]
    fn bad_commit_never_publishes_partial_text() {
        let mut projection = ReplyProjection::new("thread", "turn");
        projection.mark_covered();
        assert!(projection.activity(begin(1, None, 4)).is_ok());
        assert!(projection.activity(text(1, "abc", false)).is_ok());
        assert!(projection.activity(commit(1)).is_err());
        assert_eq!(projection.preview(), None);
    }

    #[test]
    fn terminal_requires_durable_completion_and_exact_turn() {
        use pl_protocol::{
            CompletedTurnState, TimelineItemHeader, TimelineItemSource, TimelineTurnDescriptor,
            TurnCompletion,
        };
        let mut projection = ReplyProjection::new("thread", "turn");
        let item = TimelineItem {
            header: TimelineItemHeader {
                id: "turn-item".into(),
                thread_id: "thread".into(),
                turn_id: Some("turn".into()),
                append_seq: 7,
                source_effect_seq: None,
                sealed_at: None,
            },
            descriptor: TimelineDescriptor::Turn(TimelineTurnDescriptor {
                input_id: None,
                outcome: TimelineTurnOutcome::Completed(CompletedTurnState::new(
                    None,
                    1,
                    TurnCompletion::Normal,
                )),
            }),
            source: TimelineItemSource::Content,
            fields: vec![],
        };
        let mut unbound = item.clone();
        unbound.header.turn_id = None;
        assert!(projection.add_page(vec![unbound]).is_ok());
        assert!(projection.terminal(7).is_none());
        assert!(projection.add_page(vec![item]).is_ok());
        assert!(projection.terminal(6).is_none());
        assert!(matches!(
            projection.terminal(7),
            Some(TimelineTurnOutcome::Completed(_))
        ));
    }
}
