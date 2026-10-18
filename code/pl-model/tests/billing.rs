//! 计费记录的公开边界：只有已终态的 attempt 事实才产生 billing 记录。

use pl_core::thread::{AttemptOutcome, journal::AttemptUpdate};
use pl_model::runtime::model_attempt_billing;

#[test]
fn running_attempts_do_not_look_like_completed_billing() {
    let attempt = AttemptUpdate {
        request_metadata: None,
        usage_binding: None,
        tool_projection: None,
        turn_id: "turn".into(),
        attempt_id: "attempt".into(),
        retry_of: None,
        input_revision: 1,
        tools: Default::default(),
        outcome: AttemptOutcome::Running,
        input_estimate: None,
    };
    assert_eq!(
        model_attempt_billing(&attempt, 42).expect("running is valid"),
        None
    );
}
