//! 跨产品共享的 Agent runtime 标识。

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

macro_rules! generated_id {
    ($name:ident, $label:literal, $prefix:literal) => {
        #[doc = concat!($label, " 的非空透明字符串标识。")]
        #[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
        pub struct $name(String);

        impl $name {
            /// 校验并创建标识。
            pub fn new(value: impl Into<String>) -> crate::Result<Self> {
                let value = value.into();
                if value.trim().is_empty() {
                    return Err(crate::PureError::ConfigError(
                        concat!($label, " cannot be empty").into(),
                    ));
                }
                Ok(Self(value))
            }

            /// 生成进程内唯一、便于诊断的标识。
            pub fn generate() -> Self {
                static SEQUENCE: AtomicU64 = AtomicU64::new(0);
                let millis = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis();
                let sequence = SEQUENCE.fetch_add(1, Ordering::Relaxed);
                Self(format!("{}_{millis:x}_{sequence:x}", $prefix))
            }

            /// 返回标识文本。
            pub fn as_str(&self) -> &str {
                &self.0
            }

            /// 消费标识并返回字符串。
            pub fn into_string(self) -> String {
                self.0
            }
        }

        impl std::fmt::Display for $name {
            fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str(&self.0)
            }
        }

        impl std::str::FromStr for $name {
            type Err = crate::PureError;

            fn from_str(value: &str) -> crate::Result<Self> {
                Self::new(value)
            }
        }

        impl serde::Serialize for $name {
            fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
            where
                S: serde::Serializer,
            {
                serializer.serialize_str(&self.0)
            }
        }

        impl<'de> serde::Deserialize<'de> for $name {
            fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                let value = <String as serde::Deserialize>::deserialize(deserializer)?;
                Self::new(value).map_err(serde::de::Error::custom)
            }
        }
    };
}

macro_rules! string_id {
    ($name:ident, $label:literal) => {
        #[doc = concat!($label, " 的非空透明字符串标识。")]
        #[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
        pub struct $name(String);

        impl $name {
            /// 校验并创建标识。
            pub fn new(value: impl Into<String>) -> crate::Result<Self> {
                let value = value.into();
                if value.trim().is_empty() {
                    return Err(crate::PureError::ConfigError(
                        concat!($label, " cannot be empty").into(),
                    ));
                }
                Ok(Self(value))
            }

            /// 返回标识文本。
            pub fn as_str(&self) -> &str {
                &self.0
            }

            /// 消费标识并返回字符串。
            pub fn into_string(self) -> String {
                self.0
            }
        }

        impl std::fmt::Display for $name {
            fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str(&self.0)
            }
        }

        impl std::str::FromStr for $name {
            type Err = crate::PureError;

            fn from_str(value: &str) -> crate::Result<Self> {
                Self::new(value)
            }
        }

        impl TryFrom<String> for $name {
            type Error = crate::PureError;

            fn try_from(value: String) -> crate::Result<Self> {
                Self::new(value)
            }
        }

        impl serde::Serialize for $name {
            fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
            where
                S: serde::Serializer,
            {
                serializer.serialize_str(&self.0)
            }
        }

        impl<'de> serde::Deserialize<'de> for $name {
            fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                let value = <String as serde::Deserialize>::deserialize(deserializer)?;
                Self::new(value).map_err(serde::de::Error::custom)
            }
        }
    };
}

generated_id!(ThreadId, "thread id", "thread");
generated_id!(TurnId, "turn id", "turn");
string_id!(AgentRoleId, "agent role id");

pub(crate) use string_id;
