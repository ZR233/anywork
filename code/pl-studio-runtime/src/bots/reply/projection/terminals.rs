use super::ReplyProjection;
use crate::TurnState;

#[test]
fn typed_turn_terminal_requires_immutable_receipt_and_history_barrier() -> anyhow::Result<()> {
    use super::super::content::{ReplyItem, ReplyItemKind};
    let mut projection = ReplyProjection::new();
    projection.mark_covered();
    let terminal = TurnState::Completed(crate::CompletedTurnState::new(
        Some(1),
        3,
        crate::TurnCompletion::Normal,
    ));
    assert!(
        projection.terminal().is_none(),
        "coverage alone authorized final delivery"
    );
    projection.set_activity(false, Vec::new())?;
    assert!(
        projection.terminal().is_none(),
        "empty activity authorized final delivery"
    );
    projection.replace(vec![ReplyItem {
        member_id: "receipt".into(),
        id: "receipt".into(),
        kind: ReplyItemKind::Terminal(terminal.clone()),
    }])?;
    assert!(
        projection.terminal().is_none(),
        "receipt skipped the history barrier"
    );
    projection.mark_history_terminal();
    assert_eq!(projection.terminal(), Some(terminal));
    assert!(
        projection.completed().is_err(),
        "uncovered content authorized delivery"
    );
    projection.mark_covered();
    assert_eq!(projection.completed()?.len(), 1);
    Ok(())
}
