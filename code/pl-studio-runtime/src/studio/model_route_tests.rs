use super::*;

/// 恢复 child 只消费冻结 Profile：缺失时明确失败，不读当前 catalog，也不改已有事实。
#[test]
fn missing_frozen_child_profile_fails_without_writing_anything() -> Result<()> {
    let mut state = ThreadSnapshot::default();
    state.extensions.insert(
        "studio.workspace".into(),
        ExtensionRecord {
            revision: 2,
            payload: OpaquePayload::new("pl.studio.workspace", 1, "\"receipt\"")?,
        },
    );
    let before = serde_json::to_vec(&state)?;
    assert!(
        saved_profile(&state)?.is_none(),
        "该 checkpoint 没有冻结 Profile"
    );
    let error =
        required_saved_profile(&state, "child-missing").expect_err("缺冻结 Profile 必须失败");
    assert!(
        error.to_string().contains("has no frozen Agent Profile"),
        "{error}"
    );
    assert_eq!(serde_json::to_vec(&state)?, before);
    assert!(!state.extensions.contains_key(AGENT_PROFILE_EXTENSION));
    Ok(())
}
