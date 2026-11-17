use serde::{Deserialize, Serialize};

/// 客户端首次内容观测，不代表供应商生成首 token 的时间。
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum FirstOutputSource {
    #[default]
    Unobserved,
    Incremental,
    CompletedToolInput,
    LegacyUnknown,
}
