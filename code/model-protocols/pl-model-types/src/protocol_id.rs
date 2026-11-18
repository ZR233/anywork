use std::{borrow::Cow, fmt, str::FromStr};

use serde::{Deserialize, Deserializer, Serialize};

/// Stable identity of a protocol supplied by the application.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(transparent)]
pub struct ProtocolId(Cow<'static, str>);

impl ProtocolId {
    pub const fn from_static(id: &'static str) -> Self {
        assert!(!id.is_empty(), "empty protocol ID");
        Self(Cow::Borrowed(id))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl FromStr for ProtocolId {
    type Err = InvalidProtocolId;

    fn from_str(id: &str) -> Result<Self, Self::Err> {
        if id.is_empty() || id.chars().any(char::is_whitespace) {
            return Err(InvalidProtocolId);
        }
        Ok(Self(Cow::Owned(id.to_owned())))
    }
}

impl<'de> Deserialize<'de> for ProtocolId {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        String::deserialize(deserializer)?
            .parse()
            .map_err(serde::de::Error::custom)
    }
}

impl fmt::Display for ProtocolId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

#[derive(Debug, Clone, Copy, thiserror::Error)]
#[error("protocol ID must be nonempty and contain no whitespace")]
pub struct InvalidProtocolId;
