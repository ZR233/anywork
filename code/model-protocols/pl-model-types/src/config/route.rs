use serde::{Deserialize, Serialize};
/// 模型推理强度的产品无关字符串值。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(transparent)]
pub struct ReasoningEffort(String);

impl ReasoningEffort {
    /// 创建推理强度值；最终有效性由具体模型参数目录校验。
    pub fn new(effort: impl Into<String>) -> Self {
        Self(effort.into())
    }

    /// 返回配置文本。
    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }

    /// 是否明确禁用推理。
    pub fn is_none(&self) -> bool {
        self.as_str() == "none"
    }
}
