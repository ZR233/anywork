use std::time::{Duration, Instant};

const PROGRESS_INTERVAL: Duration = Duration::from_millis(250);

/// Coalesce progress until the next interval or a known total is reached.
#[derive(Default)]
pub(super) struct ProgressThrottle(Option<Instant>);

impl ProgressThrottle {
    pub(super) fn should_emit(&mut self, completed: u64, total: Option<u64>) -> bool {
        if self
            .0
            .is_none_or(|last| last.elapsed() >= PROGRESS_INTERVAL)
            || total.is_some_and(|total| completed >= total)
        {
            self.0 = Some(Instant::now());
            true
        } else {
            false
        }
    }
}
