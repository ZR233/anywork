use std::fmt;

use serde::{Deserialize, Deserializer, Serialize};

/// 不含 revision、时间戳等易变元数据的模型可见工作上下文段。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelContextSectionSnapshot {
    pub id: ContextSectionId,
    pub title: String,
    pub content: String,
    pub content_hash: String,
}

/// 独立于可压缩时间线的上下文段标识。
///
/// 标识会作为持久化协议的一部分，必须稳定且非空。产品层应使用带命名空间的
/// 值，例如 `pl.current_todo` 或 `pl.workflow`。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(transparent)]
pub struct ContextSectionId(String);

impl ContextSectionId {
    pub fn new(value: impl Into<String>) -> Result<Self, ContextSectionIdError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(ContextSectionIdError);
        }
        Ok(Self(value))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for ContextSectionId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl<'de> Deserialize<'de> for ContextSectionId {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::new(value).map_err(serde::de::Error::custom)
    }
}

/// 空上下文段标识错误。
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("context section id must not be empty")]
pub struct ContextSectionIdError;
