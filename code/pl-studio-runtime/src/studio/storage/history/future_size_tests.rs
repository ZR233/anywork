//! Cold recovery must remain composable on the normal native/test thread stack.
use std::future::Future;
use std::mem::size_of;

use super::{HistoryStore, schema};
use crate::studio::storage::state::StateStore;
use crate::studio::thread_factory::recovery::load_checkpoint_for_recovery;
use crate::studio::{StudioRuntime, StudioStore};
use sea_orm::DatabaseConnection;

// Inspect the returned type without constructing/polling it or inventing a receiver.
fn future_size<Input, F: Future + Send>(_: impl FnOnce(Input) -> F) -> usize {
    size_of::<F>()
}

#[test]
fn cold_recovery_futures_remain_bounded() {
    let sizes = [
        (
            "schema preparation",
            future_size(|db: &'static DatabaseConnection| {
                schema::prepare(db, "size", schema::Preparation::Schema, None)
            }),
        ),
        (
            "writer initialization",
            future_size(|history: &'static HistoryStore| {
                history.open_writer(crate::studio::paths::SqliteFileMode::ReadWrite)
            }),
        ),
        (
            "history preparation",
            future_size(|history: &'static HistoryStore| history.prepare_history_access()),
        ),
        (
            "checkpoint read",
            future_size(|history: &'static HistoryStore| history.checkpoint()),
        ),
        (
            "model preparation",
            future_size(|history: &'static HistoryStore| history.prepare_model_access()),
        ),
        (
            "execution identity preparation",
            future_size(|history: &'static HistoryStore| {
                history.prepare_execution_identity(|_| Ok(()))
            }),
        ),
        (
            "state recovery",
            future_size(
                |(state, history): (&'static StateStore, &'static HistoryStore)| {
                    state.prepare_recovery(history)
                },
            ),
        ),
        (
            "checkpoint recovery",
            future_size(
                |(store, thread): (&'static StudioStore, &'static pl_protocol::Thread)| {
                    load_checkpoint_for_recovery(store, thread)
                },
            ),
        ),
        (
            "owner activation",
            future_size(|runtime: &'static StudioRuntime| runtime.ensure_thread_owner("size")),
        ),
        (
            "thread subscription",
            future_size(|runtime: &'static StudioRuntime| {
                runtime.subscribe_thread(pl_protocol::ThreadSubscriptionRequest {
                    thread_id: "size".into(),
                })
            }),
        ),
        (
            "child interactions",
            future_size(|runtime: &'static StudioRuntime| runtime.read_child_interactions("size")),
        ),
        (
            "timeline page",
            future_size(
                |(runtime, query): (
                    &'static StudioRuntime,
                    &'static pl_protocol::TimelinePageQuery,
                )| { runtime.timeline_page("size", query) },
            ),
        ),
    ];
    for (name, bytes) in &sizes {
        eprintln!("{name}: {bytes} bytes");
    }
    // Bound individual inline states rather than raising the thread's stack limit. This is
    // deliberately a ceiling, not an exact compiler/target-specific layout snapshot.
    assert!(
        sizes.iter().all(|(_, bytes)| *bytes <= 16 * 1024),
        "cold recovery futures grew beyond the inline-state budget: {sizes:?}"
    );
}
