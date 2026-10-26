//! Full existing durable Turn history, not the execution facet's active/recent summary.
use crate::api::studio::bridge_runtime::installed_bridge;
use crate::api::studio::convert::thread_stream::{bridge_chat_thread_item, bridge_turn};
use crate::api::studio::types::{BridgeError, BridgeThreadItem, BridgeTurn};

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeTurnHistoryPage {
    pub turns: Vec<BridgeTurnHistory>,
    pub next_cursor: Option<String>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeTurnHistory {
    pub turn: BridgeTurn,
    pub items: Vec<BridgeThreadItem>,
    pub context_disposition: BridgeTurnContextDisposition,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTurnContextDisposition {
    Active,
    RolledBack,
}

pub async fn list_thread_turns(
    thread_id: String,
    cursor: Option<String>,
    limit: u32,
) -> Result<BridgeTurnHistoryPage, BridgeError> {
    let bridge = installed_bridge()?;
    let page = bridge
        .studio
        .list_thread_turns(&thread_id, cursor.as_deref(), limit as usize)
        .await?;
    let mut turns = Vec::with_capacity(page.turns.len());
    for value in page.turns {
        let items = value
            .items
            .into_iter()
            .map(bridge_chat_thread_item)
            .collect::<anyhow::Result<Vec<_>>>()?;
        turns.push(BridgeTurnHistory {
            turn: bridge_turn(value.turn),
            items,
            context_disposition: match value.context_disposition {
                pl_protocol::ThreadContextDisposition::Active => {
                    BridgeTurnContextDisposition::Active
                }
                pl_protocol::ThreadContextDisposition::RolledBack => {
                    BridgeTurnContextDisposition::RolledBack
                }
            },
        });
    }
    Ok(BridgeTurnHistoryPage {
        turns,
        next_cursor: page.next_cursor,
    })
}
