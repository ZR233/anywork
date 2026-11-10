//! Runtime-owned pagination identity; only its opaque string crosses the wire.

use pl_protocol::DelegationModelFilter;
use serde::{Deserialize, Serialize};

/// 分页游标版本；查询身份或排序语义变化时递增。
const DELEGATION_MODEL_CURSOR_VERSION: u32 = 1;
const DELEGATION_MODEL_CURSOR_PREFIX: &str = "dmc1.";

/// 稳定目录身份；分页按该顺序推进。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct DelegationModelKey {
    pub(super) account_id: String,
    pub(super) model_id: String,
}

/// 绑定查询条件与目录水位的分页游标。
///
/// 只表达身份边界：查询条件、目录水位或锚点不成立时必须重新查询，而不是把游标当成
/// 「附近某条」的猜测位置。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct DelegationModelCursor {
    version: u32,
    pub(super) filter: DelegationModelFilter,
    /// 产生该位置的目录水位。
    pub(super) catalog_watermark: u64,
    /// 本页最后一条的稳定身份。
    pub(super) after: DelegationModelKey,
}

impl DelegationModelCursor {
    /// 构造当前版本游标。
    pub(super) fn new(
        filter: DelegationModelFilter,
        catalog_watermark: u64,
        after: DelegationModelKey,
    ) -> Self {
        Self {
            version: DELEGATION_MODEL_CURSOR_VERSION,
            filter,
            catalog_watermark,
            after,
        }
    }

    /// 编码为可跨 wire 传输的 opaque token。
    ///
    /// # Panics
    /// 仅在内部 JSON 编码失败时 panic；字段均为可序列化的原始类型。
    pub(super) fn encode(&self) -> String {
        let payload = serde_json::to_string(self).expect("delegation cursor is serializable");
        format!("{DELEGATION_MODEL_CURSOR_PREFIX}{payload}")
    }

    /// 解析 opaque token；非游标输入或版本不符返回 `None`。
    pub(super) fn decode(token: &str) -> Option<Self> {
        let payload = token.strip_prefix(DELEGATION_MODEL_CURSOR_PREFIX)?;
        let cursor: Self = serde_json::from_str(payload).ok()?;
        (cursor.version == DELEGATION_MODEL_CURSOR_VERSION).then_some(cursor)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::{AgentTaskCategory, BillingKind, DelegationModelCapability};

    #[test]
    fn cursor_preserves_query_identity_and_wire_format() {
        let filter = DelegationModelFilter {
            capabilities: vec![DelegationModelCapability::ToolCalling],
            task_category: Some(AgentTaskCategory::General),
            account_id: Some("account-a".into()),
            billing_kind: Some(BillingKind::Subscription),
            min_context_window: Some(32_000),
        };
        let after = DelegationModelKey {
            account_id: "account-a".into(),
            model_id: "model-b".into(),
        };
        let cursor = DelegationModelCursor::new(filter.clone(), 17, after.clone());
        let token = r#"dmc1.{"version":1,"filter":{"capabilities":["toolCalling"],"taskCategory":"general","accountId":"account-a","billingKind":"subscription","minContextWindow":32000},"catalogWatermark":17,"after":{"accountId":"account-a","modelId":"model-b"}}"#;
        assert_eq!(cursor.encode(), token);
        let decoded = DelegationModelCursor::decode(token).expect("current cursor");
        assert_eq!(decoded.filter, filter);
        assert_eq!(decoded.catalog_watermark, 17);
        assert_eq!(decoded.after, after);
    }

    #[test]
    fn cursor_rejects_wrong_version_prefix_and_unknown_fields() {
        let token = r#"dmc1.{"version":1,"filter":{},"catalogWatermark":17,"after":{"accountId":"account-a","modelId":"model-b"}}"#;
        assert!(DelegationModelCursor::decode(token).is_some());
        for invalid in [
            token.replacen("dmc1.", "dmc2.", 1),
            token.replace("\"version\":1", "\"version\":2"),
            token.replace("\"version\":1", "\"version\":0"),
            token.replace("\"version\":1", "\"unexpected\":true,\"version\":1"),
            "dmc1.not-json".into(),
        ] {
            assert!(
                DelegationModelCursor::decode(&invalid).is_none(),
                "accepted invalid cursor: {invalid}"
            );
        }
    }
}
