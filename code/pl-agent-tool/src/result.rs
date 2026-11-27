use serde::{Deserialize, Serialize};
use serde_json::Value;

/// A program-visible value explicitly supplied by the tool author.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ToolData {
    #[default]
    Absent,
    Value(Value),
}

impl ToolData {
    pub fn is_absent(&self) -> bool {
        matches!(self, Self::Absent)
    }

    pub fn as_value(&self) -> Option<&Value> {
        match self {
            Self::Absent => None,
            Self::Value(value) => Some(value),
        }
    }
}

/// The author's program value, model content, and optional supporting material.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolResult<C> {
    #[serde(default, skip_serializing_if = "ToolData::is_absent")]
    data: ToolData,
    content: Vec<C>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "deserialize_details"
    )]
    details: Option<Value>,
}

fn deserialize_details<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<Value>, D::Error> {
    Value::deserialize(deserializer).map(Some)
}

impl<C> ToolResult<C> {
    pub fn new(data: ToolData, content: Vec<C>) -> Self {
        Self {
            data,
            content,
            details: None,
        }
    }

    pub fn from_data(value: Value, content: Vec<C>) -> Self {
        Self::new(ToolData::Value(value), content)
    }

    pub fn data(&self) -> Option<&Value> {
        self.data.as_value()
    }

    pub fn tool_data(&self) -> &ToolData {
        &self.data
    }

    pub fn content(&self) -> &[C] {
        &self.content
    }

    pub fn details(&self) -> Option<&Value> {
        self.details.as_ref()
    }

    pub fn with_details(mut self, details: Value) -> Self {
        self.details = Some(details);
        self
    }

    /// Appends a boundary diagnostic without copying or reinterpreting the author's result.
    pub fn with_appended_content(mut self, content: C) -> Self {
        self.content.push(content);
        self
    }

    pub fn map_content<D>(self, map: impl FnMut(C) -> D) -> ToolResult<D> {
        ToolResult {
            data: self.data,
            content: self.content.into_iter().map(map).collect(),
            details: self.details,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn program_values_and_details_round_trip_without_changing_shape() {
        let absent = ToolResult::<String>::new(ToolData::Absent, vec![]);
        assert_eq!(
            serde_json::to_value(&absent).unwrap(),
            json!({"content": []})
        );
        let decoded: ToolResult<String> = serde_json::from_value(json!({"content": []})).unwrap();
        assert_eq!(decoded, absent);
        assert_eq!(decoded.data(), None);

        for data in [
            Value::Null,
            json!([]),
            json!({}),
            json!(""),
            json!("  {\"a\":1}\n"),
        ] {
            let result = ToolResult::from_data(data.clone(), vec!["model text"])
                .with_details(Value::Null)
                .map_content(str::to_owned);
            let wire = json!({"data": {"value": data}, "content": ["model text"], "details": null});
            assert_eq!(serde_json::to_value(&result).unwrap(), wire);
            let decoded: ToolResult<String> = serde_json::from_value(wire).unwrap();
            assert_eq!(decoded.data(), Some(&data));
            assert_eq!(decoded.content(), &["model text"]);
            assert_eq!(decoded.details(), Some(&Value::Null));
        }
    }
}
