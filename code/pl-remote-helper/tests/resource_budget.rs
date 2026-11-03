use pl_remote_helper::budget::{FRAME_BYTES, ResourceBudget, ResourcePolicy};
use tokio_util::sync::CancellationToken;

#[tokio::test]
async fn admission_progresses_and_cancelled_intents_release_bytes() {
    let allocation = ResourcePolicy {
        available_memory_divisor: 16,
        resident_ceiling: Some(FRAME_BYTES * 64),
    }
    .allocation()
    .expect("allocation");
    let budget = ResourceBudget::new(allocation).expect("budget");
    let stop = CancellationToken::new();
    let occupied = budget
        .try_reserve(allocation.resident_bytes / 2)
        .expect("initial reservation");
    let large = budget.reserve(allocation.resident_bytes * 3 / 4, &stop);
    tokio::pin!(large);
    assert!(futures::poll!(&mut large).is_pending());
    let small = tokio::time::timeout(
        std::time::Duration::from_secs(5),
        budget.reserve(FRAME_BYTES, &stop),
    )
    .await
    .expect("small reserve timeout")
    .expect("small reserve");
    drop(occupied);
    let admitted = tokio::time::timeout(std::time::Duration::from_secs(5), large)
        .await
        .expect("large reserve timeout")
        .expect("large reserve");
    drop(admitted);
    drop(small);
    assert_eq!(budget.usage().0, 0);
    let controls = ResourceBudget::new(allocation).expect("control budget");
    let occupied_controls = controls
        .try_reserve(allocation.resident_bytes)
        .expect("full control pool");
    let waiting_control = controls.reserve_with_intent(FRAME_BYTES, &stop, &budget);
    tokio::pin!(waiting_control);
    assert!(futures::poll!(&mut waiting_control).is_pending());
    assert!(budget.usage().0 > 0);
    assert_eq!(controls.usage().0, allocation.resident_bytes);
    drop(occupied_controls);
    drop(
        tokio::time::timeout(std::time::Duration::from_secs(5), waiting_control)
            .await
            .expect("control reserve timeout")
            .expect("control reserve"),
    );
    assert_eq!(budget.usage().0, 0);
    assert_eq!(controls.usage().0, 0);
    let occupied = budget
        .try_reserve(allocation.resident_bytes / 2)
        .expect("shrink reservation");
    let waiting = budget.reserve(allocation.resident_bytes * 3 / 4, &stop);
    tokio::pin!(waiting);
    assert!(futures::poll!(&mut waiting).is_pending());
    let mut reduced = allocation;
    reduced.resident_bytes /= 2;
    budget.resize(reduced).expect("resize down");
    assert!(
        waiting.await.is_err(),
        "oversized intent survived an incompatible resource shrink"
    );
    drop(occupied);
    budget.resize(allocation).expect("resize restore");
    stop.cancel();
    assert!(budget.reserve(FRAME_BYTES, &stop).await.is_err());
    assert_eq!(budget.usage().0, 0, "cancelled intents retained bytes");
}
