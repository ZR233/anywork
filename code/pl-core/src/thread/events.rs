//! Single CoreEvent exit and live model/tool/compaction stream diffing.
use super::*;
use crate::model::{
    AggregateChannel, ContentBaseline, ContentIncrement, ModelProgress, ModelRecoveryStatus,
    ObservedPart, ObservedPartIdentity, ObservedPartKind,
};
use std::{collections::BTreeMap, fmt, sync::Arc};
use tokio::sync::broadcast;

/// Immutable durable commit emitted by the serial Thread owner.
#[derive(Debug, Clone)]
pub struct CoreCommitEvent {
    pub thread_id: String,
    pub sequence: u64,
    pub export: Arc<HistoryExport>,
}

/// Ephemeral realtime event emitted by the serial Thread owner (never persisted verbatim).
#[derive(Debug, Clone)]
pub enum CoreLiveEvent {
    TextStreamStarted {
        attempt_id: String,
        item_id: String,
        generation: u32,
    },
    TextStreamDelta {
        attempt_id: String,
        item_id: String,
        generation: u32,
        text: String,
        replace: bool,
    },
    TextStreamEnded {
        attempt_id: String,
        item_id: String,
        generation: u32,
    },
    ReasoningDelta {
        attempt_id: String,
        item_id: String,
        generation: u32,
        text: String,
        replace: bool,
        is_summary: bool,
    },
    ToolProgress {
        task_id: String,
        call_id: String,
        tool_id: String,
        progress: crate::model::ToolProgress,
    },
    CompactionStarted {
        turn_id: Option<String>,
        revision: u64,
        manual: bool,
    },
    ModelRecovery {
        attempt_id: String,
        status: ModelRecoveryStatus,
    },
    ModelRecoveryCleared {
        attempt_id: String,
    },
    RunActivity {
        execution: Option<ActiveExecution>,
    },
}

/// Unified Core output event: durable commits plus ephemeral streaming signals.
#[derive(Debug, Clone)]
pub enum CoreEvent {
    Durable(Arc<CoreCommitEvent>),
    Live(CoreLiveEvent),
}

/// Optional host sink attached to receive every `CoreEvent` without snapshot polling.
pub trait CoreEventSink: Send + Sync + fmt::Debug + 'static {
    fn emit(&self, event: CoreEvent);
}

#[derive(Debug)]
pub(super) struct EventBus {
    broadcast: broadcast::Sender<CoreEvent>,
    sink: Option<Arc<dyn CoreEventSink>>,
}

impl EventBus {
    pub(super) fn new() -> (Self, broadcast::Sender<CoreEvent>) {
        let (broadcast, _) = broadcast::channel(512);
        let sender = broadcast.clone();
        (
            Self {
                broadcast,
                sink: None,
            },
            sender,
        )
    }

    pub(super) fn attach_sink(&mut self, sink: Arc<dyn CoreEventSink>) {
        self.sink = Some(sink);
    }

    pub(super) fn emit(&self, event: CoreEvent) {
        if let Some(sink) = &self.sink {
            sink.emit(event.clone());
        }
        let _ = self.broadcast.send(event);
    }
}

/// Tracks live `ModelProgress` snapshots per attempt using prefix-chain baselines.
#[derive(Debug, Default)]
pub(super) struct ModelProgressTracker {
    attempt_id: Option<String>,
    generation: u32,
    active_text: BTreeMap<String, ContentBaseline>,
    active_reasoning: BTreeMap<String, ContentBaseline>,
    last_recovery: Option<ModelRecoveryStatus>,
}

impl ModelProgressTracker {
    pub(super) fn finish_attempt(&mut self, attempt_id: &str, bus: &EventBus) {
        if self.attempt_id.as_deref() != Some(attempt_id) {
            return;
        }
        self.emit_end_all(bus);
    }

    pub(super) fn clear(&mut self, bus: &EventBus) {
        if self.attempt_id.is_some() {
            self.emit_end_all(bus);
        }
    }

    fn emit_end_all(&mut self, bus: &EventBus) {
        let Some(attempt_id) = self.attempt_id.take() else {
            return;
        };
        let generation = self.generation;
        for item_id in std::mem::take(&mut self.active_text).into_keys() {
            bus.emit(CoreEvent::Live(CoreLiveEvent::TextStreamEnded {
                attempt_id: attempt_id.clone(),
                item_id,
                generation,
            }));
        }
        self.active_reasoning.clear();
        if self.last_recovery.take().is_some() {
            bus.emit(CoreEvent::Live(CoreLiveEvent::ModelRecoveryCleared {
                attempt_id,
            }));
        }
        self.generation = 0;
    }

    pub(super) fn observe(&mut self, attempt_id: &str, progress: &ModelProgress, bus: &EventBus) {
        if self.attempt_id.as_deref() != Some(attempt_id) {
            self.emit_end_all(bus);
            self.attempt_id = Some(attempt_id.to_owned());
        }
        let generation = progress.observation().generation;
        if generation != self.generation && !self.active_text.is_empty() {
            let old_gen = self.generation;
            for item_id in std::mem::take(&mut self.active_text).into_keys() {
                bus.emit(CoreEvent::Live(CoreLiveEvent::TextStreamEnded {
                    attempt_id: attempt_id.to_owned(),
                    item_id,
                    generation: old_gen,
                }));
            }
            self.active_reasoning.clear();
        }
        self.generation = generation;

        let next_recovery = progress.observation().recovery;
        match (self.last_recovery, next_recovery) {
            (prev, Some(status)) if prev != Some(status) => {
                self.last_recovery = Some(status);
                bus.emit(CoreEvent::Live(CoreLiveEvent::ModelRecovery {
                    attempt_id: attempt_id.to_owned(),
                    status,
                }));
            }
            (Some(_), None) => {
                self.last_recovery = None;
                bus.emit(CoreEvent::Live(CoreLiveEvent::ModelRecoveryCleared {
                    attempt_id: attempt_id.to_owned(),
                }));
            }
            _ => {}
        }

        let mut seen_text = BTreeMap::new();
        for part in progress.parts().iter() {
            match part.identity() {
                ObservedPartIdentity::Aggregate {
                    channel: AggregateChannel::Text,
                } => {
                    seen_text.insert("aggregate:text".to_owned(), part);
                }
                ObservedPartIdentity::Aggregate {
                    channel: AggregateChannel::Reasoning,
                } => {
                    self.emit_reasoning_part(
                        attempt_id,
                        generation,
                        "aggregate:reasoning",
                        "aggregate:reasoning",
                        false,
                        part,
                        bus,
                    );
                }
                ObservedPartIdentity::Provider(identity) => match identity.part {
                    ObservedPartKind::OutputText => {
                        let key = format!("{}:{}", identity.item_id, identity.content_index);
                        seen_text.insert(key, part);
                    }
                    ObservedPartKind::ReasoningText | ObservedPartKind::SummaryText => {
                        let item_id = format!("{}:{}", identity.item_id, identity.content_index);
                        let (baseline_key, is_summary) = match identity.part {
                            ObservedPartKind::SummaryText => (format!("summary:{item_id}"), true),
                            ObservedPartKind::ReasoningText => (format!("raw:{item_id}"), false),
                            ObservedPartKind::OutputText => unreachable!(),
                        };
                        self.emit_reasoning_part(
                            attempt_id,
                            generation,
                            &baseline_key,
                            &item_id,
                            is_summary,
                            part,
                            bus,
                        );
                    }
                },
            }
        }

        let ended_keys: Vec<String> = self
            .active_text
            .keys()
            .filter(|key| !seen_text.contains_key(*key))
            .cloned()
            .collect();
        for item_id in ended_keys {
            self.active_text.remove(&item_id);
            bus.emit(CoreEvent::Live(CoreLiveEvent::TextStreamEnded {
                attempt_id: attempt_id.to_owned(),
                item_id,
                generation,
            }));
        }

        for (item_id, part) in seen_text {
            match self.active_text.get(&item_id) {
                None => {
                    bus.emit(CoreEvent::Live(CoreLiveEvent::TextStreamStarted {
                        attempt_id: attempt_id.to_owned(),
                        item_id: item_id.clone(),
                        generation,
                    }));
                    if !part.is_empty() {
                        bus.emit(CoreEvent::Live(CoreLiveEvent::TextStreamDelta {
                            attempt_id: attempt_id.to_owned(),
                            item_id: item_id.clone(),
                            generation,
                            text: part.text(),
                            replace: false,
                        }));
                    }
                    self.active_text.insert(item_id, part.baseline());
                }
                Some(prev) => match part.increment_since(prev) {
                    ContentIncrement::Current => {}
                    ContentIncrement::Append(text) => {
                        if !text.is_empty() {
                            bus.emit(CoreEvent::Live(CoreLiveEvent::TextStreamDelta {
                                attempt_id: attempt_id.to_owned(),
                                item_id: item_id.clone(),
                                generation,
                                text,
                                replace: false,
                            }));
                        }
                        self.active_text.insert(item_id, part.baseline());
                    }
                    ContentIncrement::Replace(text) => {
                        bus.emit(CoreEvent::Live(CoreLiveEvent::TextStreamDelta {
                            attempt_id: attempt_id.to_owned(),
                            item_id: item_id.clone(),
                            generation,
                            text,
                            replace: true,
                        }));
                        self.active_text.insert(item_id, part.baseline());
                    }
                },
            }
        }
    }

    fn emit_reasoning_part(
        &mut self,
        attempt_id: &str,
        generation: u32,
        baseline_key: &str,
        item_id: &str,
        is_summary: bool,
        part: &ObservedPart,
        bus: &EventBus,
    ) {
        match self.active_reasoning.get(baseline_key) {
            None => {
                if !part.is_empty() {
                    bus.emit(CoreEvent::Live(CoreLiveEvent::ReasoningDelta {
                        attempt_id: attempt_id.to_owned(),
                        item_id: item_id.to_owned(),
                        generation,
                        text: part.text(),
                        replace: false,
                        is_summary,
                    }));
                }
                self.active_reasoning
                    .insert(baseline_key.to_owned(), part.baseline());
            }
            Some(prev) => match part.increment_since(prev) {
                ContentIncrement::Current => {}
                ContentIncrement::Append(text) => {
                    if !text.is_empty() {
                        bus.emit(CoreEvent::Live(CoreLiveEvent::ReasoningDelta {
                            attempt_id: attempt_id.to_owned(),
                            item_id: item_id.to_owned(),
                            generation,
                            text,
                            replace: false,
                            is_summary,
                        }));
                    }
                    self.active_reasoning
                        .insert(baseline_key.to_owned(), part.baseline());
                }
                ContentIncrement::Replace(text) => {
                    bus.emit(CoreEvent::Live(CoreLiveEvent::ReasoningDelta {
                        attempt_id: attempt_id.to_owned(),
                        item_id: item_id.to_owned(),
                        generation,
                        text,
                        replace: true,
                        is_summary,
                    }));
                    self.active_reasoning
                        .insert(baseline_key.to_owned(), part.baseline());
                }
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{ObservedItemKind, ProviderPartIdentity};

    #[test]
    fn summary_and_raw_reasoning_at_same_item_and_index_do_not_collide() {
        let (bus, _rx) = EventBus::new();
        let emitted = Arc::new(std::sync::Mutex::new(Vec::<CoreLiveEvent>::new()));

        #[derive(Debug)]
        struct Collector(Arc<std::sync::Mutex<Vec<CoreLiveEvent>>>);
        impl CoreEventSink for Collector {
            fn emit(&self, event: CoreEvent) {
                if let CoreEvent::Live(live) = event {
                    self.0.lock().unwrap().push(live);
                }
            }
        }

        let mut bus = bus;
        bus.attach_sink(Arc::new(Collector(emitted.clone())));
        let mut tracker = ModelProgressTracker::default();

        let summary_1 = ObservedPart::new(ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: Arc::from("rs_1"),
            output_index: Some(0),
            item_kind: ObservedItemKind::Reasoning,
            part: ObservedPartKind::SummaryText,
            content_index: 0,
        }))
        .appended("**Plan**");

        let raw_1 = ObservedPart::new(ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: Arc::from("rs_1"),
            output_index: Some(0),
            item_kind: ObservedItemKind::Reasoning,
            part: ObservedPartKind::ReasoningText,
            content_index: 0,
        }))
        .appended("Step 1");

        tracker.observe("att-1", &ModelProgress::new(1, vec![summary_1.clone(), raw_1.clone()]), &bus);

        let summary_2 = summary_1.appended("\n**Execute**");
        let raw_2 = raw_1.appended(" -> Step 2");

        tracker.observe("att-1", &ModelProgress::new(2, vec![summary_2, raw_2]), &bus);

        let events = emitted.lock().unwrap();
        assert_eq!(events.len(), 4);
        assert!(matches!(
            &events[0],
            CoreLiveEvent::ReasoningDelta {
                item_id,
                text,
                replace: false,
                is_summary: true,
                ..
            } if item_id == "rs_1:0" && text == "**Plan**"
        ));
        assert!(matches!(
            &events[1],
            CoreLiveEvent::ReasoningDelta {
                item_id,
                text,
                replace: false,
                is_summary: false,
                ..
            } if item_id == "rs_1:0" && text == "Step 1"
        ));
        assert!(matches!(
            &events[2],
            CoreLiveEvent::ReasoningDelta {
                item_id,
                text,
                replace: false,
                is_summary: true,
                ..
            } if item_id == "rs_1:0" && text == "\n**Execute**"
        ));
        assert!(matches!(
            &events[3],
            CoreLiveEvent::ReasoningDelta {
                item_id,
                text,
                replace: false,
                is_summary: false,
                ..
            } if item_id == "rs_1:0" && text == " -> Step 2"
        ));
    }
}
