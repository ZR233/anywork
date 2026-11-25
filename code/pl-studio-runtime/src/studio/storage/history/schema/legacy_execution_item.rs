//! 已发布旧执行条目的冻结解码器，仅用于正式数据升级。
use crate::{ExecutionItem, ExecutionShape};
use serde::{Deserialize, Serialize};
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyExecutionItem {
    id: String,
    thread_id: String,
    turn_id: String,
    ordinal: u64,
    revision: u64,
    created_at: i64,
    updated_at: i64,
    state: ExecutionShape,
}
pub(in crate::studio::storage::history) fn decode(
    bytes: &[u8],
) -> serde_json::Result<ExecutionItem> {
    let old: LegacyExecutionItem = serde_json::from_slice(bytes)?;
    Ok(ExecutionItem::new(
        old.id,
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Owned(old.thread_id),
            turn_id: std::borrow::Cow::Owned(old.turn_id),
            ordinal: old.ordinal,
            revision: old.revision,
            created_at: old.created_at,
            updated_at: old.updated_at,
        },
        old.state,
    ))
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LegacyTurn {
    pub turn: crate::Turn,
    pub last_item_id: String,
    pub context_disposition: crate::ThreadContextDisposition,
}
