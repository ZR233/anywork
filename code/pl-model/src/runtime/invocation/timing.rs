use crate::completion::InferenceTiming;
use std::sync::{Arc, Mutex};
use std::time::Duration;

#[derive(Debug, Clone)]
pub(super) struct InferenceTimer {
    started_at: tokio::time::Instant,
    observation: Arc<Mutex<TimingObservation>>,
}

#[derive(Debug, Default)]
struct TimingObservation {
    first_output: Option<(u64, pl_protocol::FirstOutputSource)>,
    terminal_millis: Option<u64>,
}

impl InferenceTimer {
    pub(super) fn start() -> Self {
        Self {
            started_at: tokio::time::Instant::now(),
            observation: Arc::new(Mutex::new(TimingObservation::default())),
        }
    }

    pub(super) fn observe(&self, event: &crate::completion::stream::event::ModelStreamEvent) {
        // Time and provenance publish as one observation, including across cloned stream owners.
        let mut observation = self
            .observation
            .lock()
            .expect("timing observation poisoned");
        if observation.terminal_millis.is_some() {
            return;
        }
        if matches!(
            event,
            crate::completion::stream::event::ModelStreamEvent::Completed { .. }
                | crate::completion::stream::event::ModelStreamEvent::Failed { .. }
        ) {
            observation.terminal_millis = Some(duration_millis(self.started_at.elapsed()));
            return;
        }
        if observation.first_output.is_none()
            && let Some(source) = event.first_output_source()
        {
            observation.first_output = Some((duration_millis(self.started_at.elapsed()), source));
        }
    }

    /// 本 attempt 起点到当前时刻（已到终态则到终态）的单调总响应耗时。
    pub(super) fn response_millis(&self) -> u64 {
        self.observation
            .lock()
            .expect("timing observation poisoned")
            .terminal_millis
            .unwrap_or_else(|| duration_millis(self.started_at.elapsed()))
    }

    /// Freeze non-event termination before failure projection, tracing or retry backoff.
    pub(super) fn mark_terminal(&self) {
        self.observation
            .lock()
            .expect("timing observation poisoned")
            .terminal_millis
            .get_or_insert_with(|| duration_millis(self.started_at.elapsed()));
    }

    /// 归一化终态到达后的耗时事实；未观察到首内容只让首字相关字段保持未知。
    ///
    /// 总响应耗时始终是消费方确认的终态边界，因此它不依赖首字；仅当首字晚于已记录的终态值
    /// 这类不一致边界出现时，才把首字整组视为未知，而不是伪造负的首字后耗时。
    pub(super) fn finish(&self) -> Option<InferenceTiming> {
        let observation = self
            .observation
            .lock()
            .expect("timing observation poisoned");
        let response_millis = observation.terminal_millis?;
        let (ttft_millis, decode_millis, first_output_source) = match observation.first_output {
            Some((first, source)) if first <= response_millis => {
                (Some(first), Some(response_millis - first), source)
            }
            _ => (None, None, pl_protocol::FirstOutputSource::Unobserved),
        };
        Some(InferenceTiming {
            first_output_source,
            ttft_millis,
            decode_millis,
            response_millis,
        })
    }
}

fn duration_millis(duration: Duration) -> u64 {
    u64::try_from(duration.as_millis()).unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests;
