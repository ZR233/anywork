use crate::completion::stable_tool_schemas;
use std::collections::BTreeMap;

use pl_protocol::{
    Message, PromptPrefixChangedReason, PureError, ThreadPromptMetadata, ThreadPromptSnapshot,
};

use crate::completion::ReasoningConfig;
use crate::protocol::{EffectivePromptCachePolicy, ProtocolEndpoint};
use pl_protocol::ToolSpec;
use sha2::{Digest, Sha256};

/// 计算 prompt generation 所需的固定请求属性。
#[derive(Debug)]
pub struct PromptCacheInput<'a> {
    pub scope: &'a str,
    /// 稳定账号身份；诊断身份必须来自它，不能来自 endpoint 显示名。
    pub account_id: &'a str,
    pub account: &'a ProtocolEndpoint,
    pub model: &'a str,
    pub instructions: &'a str,
    pub prelude_messages: &'a [Message],
    pub context_hash: &'a str,
    pub fixed_prefix_section_hashes: BTreeMap<String, String>,
    /// 实际发送的 eager 工具 schema（`WirePrefixFingerprint` 语义）。
    pub tools: &'a [ToolSpec],
    pub tool_choice: &'a str,
    pub parallel_tool_calls: bool,
    pub reasoning: Option<&'a ReasoningConfig>,
    pub output_schema: Option<&'a serde_json::Value>,
    pub service_tier: Option<&'a str>,
    pub compacted: bool,
    pub prompt_cache_policy: EffectivePromptCachePolicy,
    pub updated_at: i64,
}

struct PromptHashes<'a> {
    context: &'a str,
    account: &'a str,
    fixed_prefix: &'a str,
    request_properties: &'a str,
    tool_schema: &'a str,
}

/// Computes a diagnostic update from frozen model input without modifying caller state.
///
/// # Errors
/// Returns an encoding failure before producing any replacement metadata.
pub fn prompt_diagnostics(
    previous_metadata: &ThreadPromptMetadata,
    input: PromptCacheInput<'_>,
) -> Result<Option<ThreadPromptSnapshot>, PureError> {
    let context_hash = input.context_hash.to_owned();
    let stable_tools = stable_tool_schemas(input.tools.to_vec());
    let tool_schema_hash = canonical_json_hash(&serde_json::to_value(&stable_tools)?);
    let account_hash = account_hash(input.account_id, input.account)?;
    let request_properties_hash = request_properties_hash(&input, &account_hash)?;
    let fixed_prefix_hash = fixed_prefix_hash(&input, &account_hash)?;
    let previous_prompt = previous_metadata.slots.get(input.scope);
    let previous_active_scope = (!previous_metadata.active_scope.is_empty())
        .then_some(previous_metadata.active_scope.as_str());
    let previous_generation = previous_metadata
        .slots
        .values()
        .map(|snapshot| snapshot.generation)
        .max()
        .unwrap_or_default();

    let reason = changed_reason(
        previous_prompt,
        previous_active_scope,
        PromptHashes {
            context: &context_hash,
            account: &account_hash,
            fixed_prefix: &fixed_prefix_hash,
            request_properties: &request_properties_hash,
            tool_schema: &tool_schema_hash,
        },
        &input,
    );
    let Some(reason) = reason else {
        return Ok(None);
    };
    let generation = if matches!(
        reason,
        PromptPrefixChangedReason::ContextAppended | PromptPrefixChangedReason::ContextRecovered
    ) {
        previous_prompt.map_or(previous_generation.max(1), |previous| previous.generation)
    } else {
        previous_generation.saturating_add(1).max(1)
    };
    let prompt = ThreadPromptSnapshot {
        scope: input.scope.to_string(),
        generation,
        account_id: input.account_id.to_string(),
        account_hash,
        model_id: input.model.to_string(),
        fixed_prefix_hash,
        fixed_prefix_section_hashes: input.fixed_prefix_section_hashes.clone(),
        request_properties_hash,
        tool_schema_hash,
        context_hash,
        prompt_cache_policy: input.prompt_cache_policy.label().to_string(),
        prefix_changed_reason: reason,
        updated_at: input.updated_at,
    };
    Ok(Some(prompt))
}

/// Classifies observed changes for diagnostics; this does not choose a provider cache key.
fn changed_reason(
    previous: Option<&ThreadPromptSnapshot>,
    previous_active_scope: Option<&str>,
    hashes: PromptHashes<'_>,
    input: &PromptCacheInput<'_>,
) -> Option<PromptPrefixChangedReason> {
    if previous_active_scope.is_none() {
        return Some(PromptPrefixChangedReason::Initial);
    }
    if input.compacted {
        return Some(PromptPrefixChangedReason::ContextCompacted);
    }
    if previous_active_scope != Some(input.scope) {
        return Some(PromptPrefixChangedReason::PromptScopeChanged);
    }
    let Some(previous) = previous else {
        return Some(PromptPrefixChangedReason::Initial);
    };
    if previous.prefix_changed_reason == PromptPrefixChangedReason::ContextRecovered {
        return Some(PromptPrefixChangedReason::ContextRecovered);
    }
    // A legacy snapshot that recorded no stable account ID cannot prove the same identity;
    // its old display name is not an identity and is never used to match.
    if previous.account_id.is_empty() || input.account_id.trim().is_empty() {
        return Some(PromptPrefixChangedReason::AccountChanged);
    }
    if previous.account_hash != hashes.account {
        return Some(PromptPrefixChangedReason::AccountChanged);
    }
    if previous.model_id != input.model {
        return Some(PromptPrefixChangedReason::ModelChanged);
    }
    if previous.tool_schema_hash != hashes.tool_schema {
        return Some(PromptPrefixChangedReason::ToolSchemaChanged);
    }
    if previous.fixed_prefix_section_hashes != input.fixed_prefix_section_hashes {
        return Some(PromptPrefixChangedReason::FixedPrefixChanged);
    }
    if previous.request_properties_hash != hashes.request_properties {
        return Some(PromptPrefixChangedReason::RequestPropertiesChanged);
    }
    if previous.fixed_prefix_hash != hashes.fixed_prefix {
        return Some(PromptPrefixChangedReason::FixedPrefixChanged);
    }
    (previous.context_hash != hashes.context).then_some(PromptPrefixChangedReason::ContextAppended)
}

/// 稳定账号 ID 参与指纹；endpoint 显示名不是身份，也不进入 hash。
fn account_hash(account_id: &str, account: &ProtocolEndpoint) -> Result<String, PureError> {
    let value = serde_json::json!({
        "accountId": account_id,
        "protocol": account.protocol,
        "baseUrl": account.base_url,
        "toolWirePolicy": account.tool_wire_policy,
        "applyPatchToolType": account.apply_patch_tool_type,
        "serviceCapabilities": account.service_capabilities,
    });
    Ok(canonical_json_hash(&value))
}

fn fixed_prefix_hash(
    input: &PromptCacheInput<'_>,
    account_hash: &str,
) -> Result<String, PureError> {
    let value = serde_json::json!({
        "accountHash": account_hash,
        "model": input.model,
        "instructions": input.instructions,
        "preludeMessages": input.prelude_messages,
        "toolChoice": input.tool_choice,
        "parallelToolCalls": input.parallel_tool_calls,
        "reasoning": input.reasoning,
        "outputSchema": input.output_schema,
        "serviceTier": input.service_tier,
        "store": false,
    });
    Ok(canonical_json_hash(&value))
}

fn request_properties_hash(
    input: &PromptCacheInput<'_>,
    account_hash: &str,
) -> Result<String, PureError> {
    let value = serde_json::json!({
        "accountHash": account_hash,
        "model": input.model,
        "toolChoice": input.tool_choice,
        "parallelToolCalls": input.parallel_tool_calls,
        "reasoning": input.reasoning,
        "outputSchema": input.output_schema,
        "serviceTier": input.service_tier,
        "store": false,
        "promptCachePolicy": input.prompt_cache_policy,
    });
    Ok(canonical_json_hash(&value))
}
fn canonical_json_hash(value: &serde_json::Value) -> String {
    let mut value = value.clone();
    crate::completion::canonicalize_json(&mut value);
    let digest = Sha256::digest(value.to_string().as_bytes());
    format!("sha256:{}", hex::encode(digest))
}
