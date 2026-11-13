use std::future::Future;
use std::panic::AssertUnwindSafe;
use std::time::Duration;

use futures::FutureExt;
use tokio::time::{MissedTickBehavior, interval};

use pl_studio_update::StudioUpdateCancellation;

pub(super) const CHECK_INTERVAL: Duration = Duration::from_secs(20 * 60);

/// The callback owns and joins its current round, including after cancellation.
/// Only the process stop signal ends scheduling; failures cannot escape a tick.
pub(super) async fn schedule<F, Fut>(stop: &StudioUpdateCancellation, mut round: F)
where
    F: FnMut() -> Fut,
    Fut: Future<Output = ()>,
{
    let mut ticks = interval(CHECK_INTERVAL);
    ticks.set_missed_tick_behavior(MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            biased;
            _ = stop.cancelled() => return,
            _ = ticks.tick() => {}
        }
        // Include callback construction in the unwind boundary as well as polling.
        if AssertUnwindSafe(async { round().await })
            .catch_unwind()
            .await
            .is_err()
        {
            tracing::error!("Studio update scheduling round panicked; continuing next interval");
        }
    }
}
