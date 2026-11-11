use super::*;
use serde_json::{Number, Value};

pub(super) fn json(value: Value) -> R<BridgeAcpJsonValue> {
    Ok(match value {
        Value::Null => BridgeAcpJsonValue::Null,
        Value::Bool(value) => BridgeAcpJsonValue::Bool { value },
        Value::String(value) => BridgeAcpJsonValue::String { value },
        Value::Array(values) => BridgeAcpJsonValue::Array {
            values: many(values, json)?,
        },
        Value::Object(values) => BridgeAcpJsonValue::Object {
            fields: meta(values)?,
        },
        Value::Number(n) => BridgeAcpJsonValue::Number {
            value: match (n.as_i64(), n.as_u64(), n.as_f64()) {
                (Some(value), _, _) => BridgeAcpJsonNumber::Signed { value },
                (_, Some(value), _) => BridgeAcpJsonNumber::Unsigned { value },
                (_, _, Some(value)) => BridgeAcpJsonNumber::Float { value },
                _ => return Err(unsupported("JSON number")),
            },
        },
    })
}
pub(crate) fn protocol_json(value: BridgeAcpJsonValue) -> R<Value> {
    Ok(match value {
        BridgeAcpJsonValue::Null => Value::Null,
        BridgeAcpJsonValue::Bool { value } => Value::Bool(value),
        BridgeAcpJsonValue::String { value } => Value::String(value),
        BridgeAcpJsonValue::Array { values } => Value::Array(many(values, protocol_json)?),
        BridgeAcpJsonValue::Object { fields } => Value::Object(protocol_meta(fields)?),
        BridgeAcpJsonValue::Number { value } => Value::Number(match value {
            BridgeAcpJsonNumber::Signed { value } => Number::from(value),
            BridgeAcpJsonNumber::Unsigned { value } => Number::from(value),
            BridgeAcpJsonNumber::Float { value } => Number::from_f64(value).ok_or_else(|| {
                BridgeAcpBusinessError::Runtime(BridgeError::invalid_argument(
                    "ACP JSON numbers must be finite",
                ))
            })?,
        }),
    })
}
pub(super) fn meta(value: s::Meta) -> R<BridgeAcpMeta> {
    value
        .into_iter()
        .map(|(key, value)| Ok((key, json(value)?)))
        .collect()
}
pub(super) fn protocol_meta(value: BridgeAcpMeta) -> R<s::Meta> {
    value
        .into_iter()
        .map(|(key, value)| Ok((key, protocol_json(value)?)))
        .collect()
}
pub(super) fn opt_meta(value: Option<s::Meta>) -> R<Option<BridgeAcpMeta>> {
    value.map(meta).transpose()
}
pub(super) fn opt_protocol_meta(value: Option<BridgeAcpMeta>) -> R<Option<s::Meta>> {
    value.map(protocol_meta).transpose()
}
