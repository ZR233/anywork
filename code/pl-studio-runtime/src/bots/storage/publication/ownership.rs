//! 原输入/规范续接链的单一归属判定。cut 由 O 在 Frontend 判定后另核真实 Turn-start。

use super::super::{BotStateStore, statement};
use super::*;
use sea_orm::ConnectionTrait;

/// 调用者必须从 canonical input/interaction 事实取得完整祖先链；事件或文本不是证明。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) enum DeliveryInputChain {
    Proven {
        input_id: String,
        continuation_ancestors: Vec<String>,
    },
    Unavailable,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryTurnIdentity {
    pub thread_id: String,
    pub turn_id: String,
    pub input_chain: DeliveryInputChain,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) enum DeliveryTurnOwner {
    LegacyFinal {
        scope: DeliveryScopeKey,
    },
    /// 可证不是旧链；这不是已经越过 Saved cut 的许可。
    Frontend,
    Unproven,
}

impl BotStateStore {
    pub(in crate::bots) async fn delivery_turn_owner(
        &self,
        identity: &DeliveryTurnIdentity,
    ) -> Result<DeliveryTurnOwner, FeishuError> {
        turn_owner(self.audience_db()?, identity).await
    }
}

pub(super) async fn turn_owner<C: ConnectionTrait>(
    db: &C,
    identity: &DeliveryTurnIdentity,
) -> Result<DeliveryTurnOwner, FeishuError> {
    if identity.thread_id.is_empty() || identity.turn_id.is_empty() {
        return Err(rejected("canonical Turn identity is required"));
    }
    let chain = match &identity.input_chain {
        DeliveryInputChain::Unavailable => None,
        DeliveryInputChain::Proven {
            input_id,
            continuation_ancestors,
        } => {
            if input_id.is_empty() || continuation_ancestors.iter().any(String::is_empty) {
                return Err(rejected("canonical input chain is incomplete"));
            }
            Some((input_id, continuation_ancestors))
        }
    };
    let mut after = String::new();
    let mut owner = None;
    loop {
        let rows = db.query_all_raw(statement("SELECT * FROM bot_delivery_scopes WHERE (thread_id=? OR thread_id='') AND kind='legacyFinal' AND scope_key>? ORDER BY scope_key LIMIT 64", vec![identity.thread_id.clone().into(), after.clone().into()])).await.map_err(super::store::storage)?;
        if rows.is_empty() {
            break;
        }
        for row in &rows {
            let scope = super::records::decode_scope_row(row)?;
            after = scope.key.storage_key()?;
            let DeliveryScopeOrigin::LegacyFinal { legacy } = &scope.origin else {
                return Err(unreadable());
            };
            let matches_turn = !scope.thread_id.is_empty()
                && legacy.original_turn_id.as_deref() == Some(identity.turn_id.as_str());
            let matches_input = chain.is_some_and(|(input, ancestors)| {
                [
                    legacy.original_input_id.as_str(),
                    legacy.watch_input.as_str(),
                ]
                .iter()
                .filter(|id| !id.is_empty())
                .any(|id| *id == input || ancestors.iter().any(|ancestor| ancestor == id))
            });
            if scope.thread_id.is_empty() && matches_input {
                return Ok(DeliveryTurnOwner::Unproven);
            }
            if matches_turn || matches_input {
                if owner.as_ref().is_some_and(|key| *key != scope.key) {
                    return Ok(DeliveryTurnOwner::Unproven);
                }
                owner = Some(scope.key);
            }
        }
    }
    Ok(match owner {
        Some(scope) => DeliveryTurnOwner::LegacyFinal { scope },
        None if chain.is_some() => DeliveryTurnOwner::Frontend,
        None => DeliveryTurnOwner::Unproven,
    })
}
