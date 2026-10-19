use std::fmt;
use std::str::FromStr;

use pl_protocol::{PureError, Result};
use serde::{Deserialize, Deserializer, Serialize, Serializer, de};

macro_rules! string_id {
    ($name:ident, $label:literal) => {
        #[doc = concat!($label, " 的非空透明字符串标识。")]
        #[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
        pub struct $name(String);

        impl $name {
            /// 校验并创建标识。
            pub fn new(value: impl Into<String>) -> Result<Self> {
                let value = value.into();
                if value.trim().is_empty() {
                    return Err(PureError::ConfigError(
                        concat!($label, " cannot be empty").into(),
                    ));
                }
                Ok(Self(value))
            }

            /// 返回未改变的标识文本。
            pub fn as_str(&self) -> &str {
                &self.0
            }

            /// 消费标识并返回字符串。
            pub fn into_string(self) -> String {
                self.0
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str(&self.0)
            }
        }

        impl FromStr for $name {
            type Err = PureError;

            fn from_str(value: &str) -> Result<Self> {
                Self::new(value)
            }
        }

        impl TryFrom<String> for $name {
            type Error = PureError;

            fn try_from(value: String) -> Result<Self> {
                Self::new(value)
            }
        }

        impl Serialize for $name {
            fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
            where
                S: Serializer,
            {
                serializer.serialize_str(&self.0)
            }
        }

        impl<'de> Deserialize<'de> for $name {
            fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
            where
                D: Deserializer<'de>,
            {
                let value = String::deserialize(deserializer)?;
                Self::new(value).map_err(de::Error::custom)
            }
        }
    };
}

string_id!(AccountId, "account id");
string_id!(ModelCatalogId, "model catalog id");
string_id!(AccountTemplateId, "account template id");

/// 一次性目录成员的稳定复合身份 `(account_id, model_id)`。
///
/// 目录、路由冻结与统计共用这个身份；`model_id` 只是目录成员的标识，不是发送别名或
/// 账号报告名。字段为产品 wire 的 camelCase 字符串，调用方可以从已解析路由或路由配置
/// 构造键，不需要再保存一份重复字段。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountModelKey {
    pub account_id: String,
    pub model_id: String,
}

impl AccountModelKey {
    /// 从账号 ID 与目录 `model_id` 构造复合身份；两者都必须非空。
    pub fn new(account_id: impl Into<String>, model_id: impl Into<String>) -> Result<Self> {
        let account_id = account_id.into();
        let model_id = model_id.into();
        if account_id.trim().is_empty() {
            return Err(PureError::ConfigError("account id cannot be empty".into()));
        }
        if model_id.trim().is_empty() {
            return Err(PureError::ConfigError("model id cannot be empty".into()));
        }
        Ok(Self {
            account_id,
            model_id,
        })
    }
}

impl fmt::Display for AccountModelKey {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}/{}", self.account_id, self.model_id)
    }
}

pub use pl_protocol::AgentRoleId;
