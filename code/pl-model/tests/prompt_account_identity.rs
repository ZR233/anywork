//! 账号诊断身份来自稳定 account ID；endpoint 显示名不是身份。
use std::collections::BTreeMap;

use pl_model::protocol::{EffectivePromptCachePolicy, ProtocolEndpoint};
use pl_model::runtime::{PromptCacheInput, ThreadPromptMetadata, prompt_diagnostics};
use pl_protocol::PromptPrefixChangedReason;

fn input<'a>(
    account_id: &'a str,
    account: &'a ProtocolEndpoint,
    model: &'a str,
) -> PromptCacheInput<'a> {
    PromptCacheInput {
        scope: "turn",
        account_id,
        account,
        model,
        instructions: "instructions",
        prelude_messages: &[],
        context_hash: "context",
        fixed_prefix_section_hashes: BTreeMap::new(),
        tools: &[],
        tool_choice: "auto",
        parallel_tool_calls: false,
        reasoning: None,
        output_schema: None,
        service_tier: None,
        compacted: false,
        prompt_cache_policy: EffectivePromptCachePolicy::None,
        updated_at: 1,
    }
}

fn recorded(
    account_id: &str,
    account: &ProtocolEndpoint,
    model: &str,
) -> (ThreadPromptMetadata, pl_protocol::ThreadPromptSnapshot) {
    let snapshot = prompt_diagnostics(
        &ThreadPromptMetadata::default(),
        input(account_id, account, model),
    )
    .expect("diagnostics encode")
    .expect("first diagnostics record");
    let metadata = ThreadPromptMetadata {
        active_scope: "turn".into(),
        slots: BTreeMap::from([("turn".to_string(), snapshot.clone())]),
    };
    (metadata, snapshot)
}

#[test]
fn stable_account_id_drives_snapshot_and_hash_not_display_name() {
    let endpoint = ProtocolEndpoint::compatible("Display A", "http://127.0.0.1:1");
    let (metadata, first) = recorded("acc-a", &endpoint, "model");
    assert_eq!(
        first.account_id, "acc-a",
        "the snapshot records the stable ID, not the display name"
    );
    assert!(!first.account_hash.is_empty());

    // 同一账号改显示名：诊断身份和 hash 不变，不产生新 generation。
    let renamed = ProtocolEndpoint::compatible("Display B", "http://127.0.0.1:1");
    assert!(
        prompt_diagnostics(&metadata, input("acc-a", &renamed, "model"))
            .expect("diagnostics encode")
            .is_none()
    );

    // 同 endpoint、同 model、不同稳定 ID：account hash 与诊断身份都隔离。
    let (_, other) = recorded("acc-b", &endpoint, "model");
    assert_eq!(other.account_id, "acc-b");
    assert_ne!(first.account_hash, other.account_hash);
    let changed = prompt_diagnostics(&metadata, input("acc-b", &endpoint, "model"))
        .expect("diagnostics encode")
        .expect("a different account rotates the prompt identity");
    assert_eq!(
        changed.prefix_changed_reason,
        PromptPrefixChangedReason::AccountChanged
    );
    assert!(changed.generation > first.generation);
}

#[test]
fn a_legacy_snapshot_without_a_stable_id_is_never_matched_by_its_old_display_name() {
    let endpoint = ProtocolEndpoint::compatible("Display A", "http://127.0.0.1:1");
    let (mut metadata, mut legacy) = recorded("acc-a", &endpoint, "model");
    // 旧快照只记录了 endpoint 显示名，没有真实账号 ID。
    legacy.account_id.clear();
    metadata.slots.insert("turn".to_string(), legacy.clone());

    let next = prompt_diagnostics(&metadata, input("acc-a", &endpoint, "model"))
        .expect("diagnostics encode")
        .expect("missing frozen identity rotates instead of guessing from the name");
    assert_eq!(next.account_id, "acc-a");
    assert_eq!(
        next.prefix_changed_reason,
        PromptPrefixChangedReason::AccountChanged
    );
    assert!(next.generation > legacy.generation);

    // 新建快照记录真实 ID 后，同一账号的后续诊断恢复稳定。
    let metadata = ThreadPromptMetadata {
        active_scope: "turn".into(),
        slots: BTreeMap::from([("turn".to_string(), next)]),
    };
    assert!(
        prompt_diagnostics(&metadata, input("acc-a", &endpoint, "model"))
            .expect("diagnostics encode")
            .is_none()
    );
}
