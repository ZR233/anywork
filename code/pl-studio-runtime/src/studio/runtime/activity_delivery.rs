//! One subscriber's bounded encoding cursor over shared canonical current-activity content.

use std::sync::Arc;

use anyhow::{Result, ensure};
use pl_core::model::ContentBlock;
use pl_protocol::{
    ACTIVITY_FRAME_BYTES, ACTIVITY_TEXT_FRAME_BYTES, ActivityContentFrame, ActivityTextOperation,
    ActivityTextRegion,
};

use crate::studio::thread_projection::ActivitySnapshot;

/// Independent transport/staging ceiling. It does not release or reduce reliable writer budgets.
pub(super) const ACTIVITY_CONTENT_BUDGET_BYTES: u64 = 64 * 1024 * 1024;

/// This cursor retains shared source blocks, never another materialized current-state mirror.
/// A failed send retires the observation; a new observation starts with a snapshot.
pub(super) struct ActivityDelivery {
    generation: String,
    revision: u64,
    previous: Option<Arc<ActivitySnapshot>>,
}

impl Default for ActivityDelivery {
    fn default() -> Self {
        Self {
            generation: crate::studio::ids::new_id("activity-content"),
            revision: 0,
            previous: None,
        }
    }
}

impl ActivityDelivery {
    /// Preparing the next change is serialized with delivery of the preceding Commit. The caller's
    /// reliable activity budget is also the admission limit for the SDK's declared staging.
    pub(super) fn encode(
        &mut self,
        snapshot: Arc<ActivitySnapshot>,
        content_budget: u64,
    ) -> Result<Vec<ActivityContentFrame>> {
        let total_bytes = snapshot
            .text
            .values()
            .try_fold(0u64, |total, block| total.checked_add(block.len() as u64));
        let total_bytes = total_bytes.ok_or_else(|| anyhow::anyhow!("activity length overflow"))?;
        ensure!(
            total_bytes <= content_budget,
            "activity content budget exceeded"
        );
        let revision = self
            .revision
            .checked_add(1)
            .ok_or_else(|| anyhow::anyhow!("activity delivery revision overflow"))?;
        let begin = ActivityContentFrame::Begin {
            generation: self.generation.clone(),
            base_revision: self.previous.as_ref().map(|_| self.revision),
            revision,
            activity: snapshot.activity.clone().map(Box::new),
            reasoning: snapshot.reasoning.clone(),
            response: snapshot.response.clone(),
            tools: snapshot.tools.clone(),
            total_bytes,
        };
        ensure!(
            serde_json::to_vec(&begin)?.len() <= ACTIVITY_FRAME_BYTES,
            "activity metadata frame budget exceeded"
        );
        let mut frames = vec![begin];
        if let Some(previous) = &self.previous {
            for region in previous.text.keys() {
                if !snapshot.text.contains_key(region) {
                    self.push_operation(
                        &mut frames,
                        revision,
                        ActivityTextOperation::Remove {
                            region: region.clone(),
                        },
                    )?;
                }
            }
        }
        for (region, block) in &snapshot.text {
            let old = self
                .previous
                .as_ref()
                .and_then(|value| value.text.get(region));
            let append = old.and_then(|old| ContentBlock::appended_since(block, old));
            match append {
                Some(text) => self.push_text(&mut frames, revision, region, &text, false)?,
                None if old.is_some_and(|old| ContentBlock::text_eq(block, old)) => {}
                None => {
                    // Snapshot/replacement is emitted one UTF-8 range at a time; no full-body copy.
                    let mut offset = 0;
                    loop {
                        let (text, next) = block
                            .range(offset, ACTIVITY_TEXT_FRAME_BYTES)
                            .ok_or_else(|| anyhow::anyhow!("invalid activity text boundary"))?;
                        self.push_text(&mut frames, revision, region, &text, offset == 0)?;
                        if next == block.len() {
                            break;
                        }
                        ensure!(next > offset, "activity text failed to advance");
                        offset = next;
                    }
                }
            }
        }
        frames.push(ActivityContentFrame::Commit {
            generation: self.generation.clone(),
            revision,
        });
        self.revision = revision;
        self.previous = Some(snapshot);
        Ok(frames)
    }

    fn push_text(
        &self,
        frames: &mut Vec<ActivityContentFrame>,
        revision: u64,
        region: &ActivityTextRegion,
        text: &str,
        replace: bool,
    ) -> Result<()> {
        if text.is_empty() && !replace {
            return Ok(());
        }
        let mut offset = 0;
        loop {
            let mut end = text.len().min(offset + ACTIVITY_TEXT_FRAME_BYTES);
            let operation = loop {
                while !text.is_char_boundary(end) {
                    end -= 1;
                }
                let chunk = text[offset..end].to_owned();
                let operation = if replace && offset == 0 {
                    ActivityTextOperation::Replace {
                        region: region.clone(),
                        text: chunk,
                    }
                } else {
                    ActivityTextOperation::Append {
                        region: region.clone(),
                        text: chunk,
                    }
                };
                let encoded = ActivityContentFrame::Text {
                    generation: self.generation.clone(),
                    revision,
                    operations: vec![operation.clone()],
                };
                if serde_json::to_vec(&encoded)?.len() <= ACTIVITY_FRAME_BYTES {
                    break operation;
                }
                ensure!(end > offset, "activity text identity exceeds frame budget");
                end = offset + (end - offset) / 2;
            };
            self.push_operation(frames, revision, operation)?;
            if end == text.len() {
                return Ok(());
            }
            ensure!(end > offset, "activity text failed to advance");
            offset = end;
        }
    }

    fn push_operation(
        &self,
        frames: &mut Vec<ActivityContentFrame>,
        revision: u64,
        operation: ActivityTextOperation,
    ) -> Result<()> {
        let frame = ActivityContentFrame::Text {
            generation: self.generation.clone(),
            revision,
            operations: vec![operation],
        };
        ensure!(
            serde_json::to_vec(&frame)?.len() <= ACTIVITY_FRAME_BYTES,
            "activity text frame budget exceeded"
        );
        frames.push(frame);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot(block: Arc<ContentBlock>) -> Arc<ActivitySnapshot> {
        let mut snapshot = ActivitySnapshot::default();
        snapshot.text.insert(
            ActivityTextRegion::Response {
                item_id: "answer".into(),
            },
            block,
        );
        Arc::new(snapshot)
    }

    fn text_operations(frames: &[ActivityContentFrame]) -> Vec<&ActivityTextOperation> {
        frames
            .iter()
            .flat_map(|frame| match frame {
                ActivityContentFrame::Text { operations, .. } => operations.as_slice(),
                _ => &[],
            })
            .collect()
    }

    #[test]
    fn shared_prefix_delivers_only_new_bytes_and_replacement_is_explicit() -> Result<()> {
        let mut delivery = ActivityDelivery::default();
        let first = ContentBlock::from_text("已经接收");
        delivery.encode(snapshot(first.clone()), 1024)?;
        let next = ContentBlock::append(&first, "新的内容");
        let frames = delivery.encode(snapshot(next), 1024)?;
        assert!(matches!(
            text_operations(&frames).as_slice(),
            [ActivityTextOperation::Append { text, .. }] if text == "新的内容"
        ));
        assert!(matches!(
            &frames[0],
            ActivityContentFrame::Begin {
                base_revision: Some(1),
                revision: 2,
                ..
            }
        ));
        let frames = delivery.encode(snapshot(ContentBlock::from_text("替换")), 1024)?;
        assert!(matches!(
            text_operations(&frames).as_slice(),
            [ActivityTextOperation::Replace { text, .. }] if text == "替换"
        ));
        Ok(())
    }

    #[test]
    fn snapshot_over_two_frames_is_utf8_bounded_and_has_one_commit() -> Result<()> {
        let mut delivery = ActivityDelivery::default();
        let text = "带引号\"的中文\n\0".repeat(ACTIVITY_TEXT_FRAME_BYTES);
        let frames =
            delivery.encode(snapshot(ContentBlock::from_text(&text)), text.len() as u64)?;
        assert!(frames.len() > 2);
        for frame in &frames {
            assert!(serde_json::to_vec(frame)?.len() <= ACTIVITY_FRAME_BYTES);
        }
        assert!(matches!(
            &frames[0],
            ActivityContentFrame::Begin {
                base_revision: None,
                ..
            }
        ));
        let mut reconstructed = String::new();
        for operation in text_operations(&frames) {
            match operation {
                ActivityTextOperation::Append { text, .. }
                | ActivityTextOperation::Replace { text, .. } => {
                    assert!(text.len() <= ACTIVITY_TEXT_FRAME_BYTES);
                    reconstructed.push_str(text);
                }
                ActivityTextOperation::Remove { .. } => panic!("snapshot cannot remove text"),
            }
        }
        assert_eq!(reconstructed, text);
        assert!(matches!(
            frames.last(),
            Some(ActivityContentFrame::Commit { .. })
        ));
        assert_eq!(
            frames
                .iter()
                .filter(|f| matches!(f, ActivityContentFrame::Commit { .. }))
                .count(),
            1
        );
        Ok(())
    }

    #[test]
    fn rejected_budget_does_not_advance_delivery_baseline() -> Result<()> {
        let mut delivery = ActivityDelivery::default();
        let content = snapshot(ContentBlock::from_text("内容"));
        assert!(delivery.encode(content.clone(), 1).is_err());
        assert_eq!(delivery.revision, 0);
        let frames = delivery.encode(content, 32)?;
        assert!(matches!(
            &frames[0],
            ActivityContentFrame::Begin {
                base_revision: None,
                revision: 1,
                ..
            }
        ));
        Ok(())
    }
}
