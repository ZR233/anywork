use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::runtime::{
    bridge_account_usage_state, bridge_skill_search_result, bridge_skills_state,
};
use crate::api::studio::types::{
    BridgeAccountUsageStateSnapshot, BridgeError, BridgeSkillSearchResult,
    BridgeSkillsStateSnapshot,
};
// ── Account usage ──

pub async fn read_account_usage_state() -> Result<BridgeAccountUsageStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(account_usage_state(
        bridge.studio.read_account_usage_state().await,
    ))
}

pub async fn check_account_usage(
    account_id: String,
) -> Result<BridgeAccountUsageStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(account_usage_state(
        bridge.studio.check_account_usage(&account_id).await?,
    ))
}

pub async fn read_skills_state(
    project_id: String,
) -> Result<BridgeSkillsStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(owned_skills_state(
        bridge.studio.read_skills_state(&project_id).await,
    ))
}

fn owned_skills_state(
    state: pl_studio_runtime::StudioSkillsStateSnapshot,
) -> BridgeSkillsStateSnapshot {
    bridge_skills_state(state)
}

pub async fn discover_skills(project_id: String) -> Result<BridgeSkillsStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(skills_state(
        bridge.studio.discover_skills(&project_id).await?,
    ))
}

pub async fn search_skills(
    project_id: String,
    query: String,
    limit: u32,
) -> Result<BridgeSkillSearchResult, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_skill_search_result(
        bridge
            .studio
            .search_skills(&project_id, &query, limit as usize)
            .await?,
    ))
}

fn account_usage_state(
    state: pl_studio_runtime::AccountUsageStateSnapshot,
) -> BridgeAccountUsageStateSnapshot {
    bridge_account_usage_state(state.state)
}

fn skills_state(state: pl_studio_runtime::SkillsStateSnapshot) -> BridgeSkillsStateSnapshot {
    bridge_skills_state(state.into())
}
