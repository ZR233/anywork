use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::runtime::{bridge_skill_search_result, bridge_skills_state};
use crate::api::studio::types::{BridgeError, BridgeSkillSearchResult, BridgeSkillsStateSnapshot};
pub async fn read_skills_state(
    workspace_id: String,
) -> Result<BridgeSkillsStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(owned_skills_state(
        bridge.studio.read_skills_state(&workspace_id).await,
    ))
}

fn owned_skills_state(
    state: pl_studio_runtime::StudioSkillsStateSnapshot,
) -> BridgeSkillsStateSnapshot {
    bridge_skills_state(state)
}

pub async fn discover_skills(workspace_id: String) -> Result<BridgeSkillsStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(skills_state(
        bridge.studio.discover_skills(&workspace_id).await?,
    ))
}

pub async fn search_skills(
    workspace_id: String,
    query: String,
    limit: u32,
) -> Result<BridgeSkillSearchResult, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_skill_search_result(
        bridge
            .studio
            .search_skills(&workspace_id, &query, limit as usize)
            .await?,
    ))
}

fn skills_state(state: pl_studio_runtime::SkillsStateSnapshot) -> BridgeSkillsStateSnapshot {
    bridge_skills_state(state.into())
}
