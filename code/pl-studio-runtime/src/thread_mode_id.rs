use schemars::JsonSchema;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::fmt;

pub(crate) const MODE_EXTENSION: &str = "studio.mode";

pub(crate) fn valid_ascii_id(id: &str, max_bytes: usize) -> bool {
    !id.is_empty()
        && id.len() <= max_bytes
        && id.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'-' | b'_')
        })
}

/// Stable identity used by both mode registration and workflow execution.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ThreadModeId(String);

impl ThreadModeId {
    pub const AUTO: &'static str = "mode.auto";
    const PREFIX: &'static str = "mode.";
    const MAX_BYTES: usize = 64;

    /// Validates the canonical `mode.<name>` representation.
    pub fn new(value: impl Into<String>) -> Result<Self, crate::UnknownLabelError> {
        let value = value.into();
        if !value
            .strip_prefix(Self::PREFIX)
            .is_some_and(|name| valid_ascii_id(name, Self::MAX_BYTES - Self::PREFIX.len()))
        {
            return Err(crate::UnknownLabelError::new("ThreadModeId", value));
        }
        Ok(Self(value))
    }

    pub fn auto() -> Self {
        Self(Self::AUTO.to_string())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub(crate) fn legacy_builtin_replacement(&self) -> Option<Self> {
        matches!(self.as_str(), "mode.simple" | "mode.task").then(Self::auto)
    }
}

impl Default for ThreadModeId {
    fn default() -> Self {
        Self::auto()
    }
}

impl fmt::Display for ThreadModeId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl Serialize for ThreadModeId {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(self.as_str())
    }
}

impl<'de> Deserialize<'de> for ThreadModeId {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        Self::new(String::deserialize(deserializer)?).map_err(serde::de::Error::custom)
    }
}

impl JsonSchema for ThreadModeId {
    fn schema_name() -> std::borrow::Cow<'static, str> {
        "ThreadModeId".into()
    }

    fn json_schema(_: &mut schemars::SchemaGenerator) -> schemars::Schema {
        schemars::json_schema!({"type": "string", "pattern": "^mode\\.[a-z0-9_-]+$", "maxLength": Self::MAX_BYTES})
    }
}
