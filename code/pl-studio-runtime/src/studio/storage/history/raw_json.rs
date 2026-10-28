//! Surgical JSON field edits at the legacy import boundary. Unchanged slices stay byte-identical.

use anyhow::{Context, Result, ensure};
use serde::de::{MapAccess, Visitor};
use serde_json::value::RawValue;
use std::collections::BTreeMap;

struct Object<'a>(BTreeMap<String, &'a RawValue>);
impl<'de> serde::Deserialize<'de> for Object<'de> {
    fn deserialize<D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> std::result::Result<Self, D::Error> {
        struct ObjectVisitor;
        impl<'de> Visitor<'de> for ObjectVisitor {
            type Value = Object<'de>;
            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("an object with unique field names")
            }
            fn visit_map<M: MapAccess<'de>>(
                self,
                mut map: M,
            ) -> std::result::Result<Self::Value, M::Error> {
                let mut fields = BTreeMap::new();
                while let Some((key, value)) = map.next_entry::<String, &'de RawValue>()? {
                    if fields.insert(key, value).is_some() {
                        return Err(serde::de::Error::custom("duplicate legacy JSON field"));
                    }
                }
                Ok(Object(fields))
            }
        }
        deserializer.deserialize_map(ObjectVisitor)
    }
}

pub(super) fn replace(raw: &str, path: &[&str], value: &serde_json::Value) -> Result<String> {
    replace_encoded(raw, path, &serde_json::to_string(value)?)
}

pub(super) fn replace_encoded(raw: &str, path: &[&str], replacement: &str) -> Result<String> {
    let Some((key, tail)) = path.split_first() else {
        serde_json::from_str::<&RawValue>(replacement)?;
        return Ok(replacement.to_owned());
    };
    let object: Object<'_> =
        serde_json::from_str(raw).context("legacy JSON path is not a supported object")?;
    if let Some(field) = object.0.get(*key) {
        let value = if tail.is_empty() {
            replacement.to_owned()
        } else {
            replace_encoded(field.get(), tail, replacement)?
        };
        let offset = field.get().as_ptr() as usize - raw.as_ptr() as usize;
        let mut result = raw.to_owned();
        result.replace_range(offset..offset + field.get().len(), &value);
        return Ok(result);
    }
    ensure!(tail.is_empty(), "legacy JSON path parent is absent");
    let end = raw.rfind('}').context("legacy JSON object is not closed")?;
    let separator = if object.0.is_empty() { "" } else { "," };
    let inserted = format!("{separator}{}:{replacement}", serde_json::to_string(key)?);
    let mut result = raw.to_owned();
    result.insert_str(end, &inserted);
    Ok(result)
}

pub(super) fn remove(raw: &str, key: &str) -> Result<String> {
    let mut object: Object<'_> = serde_json::from_str(raw)?;
    object.0.remove(key);
    Ok(serde_json::to_string(&object.0)?)
}

/// A read projection for a closed domain DTO. The caller retains the original stored envelope;
/// unrecognized members never enter this view and must not be overwritten with its serialization.
pub(super) fn select(raw: &str, fields: &[&str]) -> Result<String> {
    let object: Object<'_> = serde_json::from_str(raw)?;
    let known = object
        .0
        .into_iter()
        .filter(|(key, _)| fields.contains(&key.as_str()))
        .collect::<BTreeMap<_, _>>();
    Ok(serde_json::to_string(&known)?)
}

pub(super) fn at<'a>(raw: &'a str, path: &[&str]) -> Result<&'a str> {
    let Some((key, tail)) = path.split_first() else {
        return Ok(raw);
    };
    let object: Object<'a> = serde_json::from_str(raw)?;
    let value: &'a RawValue = *object.0.get(*key).context("legacy JSON field is absent")?;
    at(value.get(), tail)
}

/// Reconciles a known representation while retaining every unrecognized object member. Arrays
/// retain unknown members per element when their identity/order is unchanged; length changes must
/// be authorized by the frozen envelope converter, not by this helper.
pub(super) fn overlay(raw: &str, known: &serde_json::Value) -> Result<String> {
    match known {
        serde_json::Value::Object(fields) => {
            let original: Object<'_> = serde_json::from_str(raw)?;
            let mut result = raw.to_owned();
            for (key, value) in fields {
                let encoded = match original.0.get(key) {
                    Some(prior) => overlay(prior.get(), value)?,
                    None => serde_json::to_string(value)?,
                };
                result = replace_encoded(&result, &[key.as_str()], &encoded)?;
            }
            Ok(result)
        }
        serde_json::Value::Array(values) => {
            let old: Vec<&RawValue> = serde_json::from_str(raw)?;
            ensure!(
                old.len() == values.len(),
                "legacy JSON array changed shape without a supported conversion"
            );
            let mut result = raw.to_owned();
            for (prior, value) in old.into_iter().zip(values).rev() {
                let replacement = overlay(prior.get(), value)?;
                let offset = prior.get().as_ptr() as usize - raw.as_ptr() as usize;
                result.replace_range(offset..offset + prior.get().len(), &replacement);
            }
            Ok(result)
        }
        _ => {
            let previous: serde_json::Value = serde_json::from_str(raw)?;
            if previous == *known {
                Ok(raw.to_owned())
            } else {
                Ok(serde_json::to_string(known)?)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn edits_only_the_requested_field_including_unknown_raw_slices() -> Result<()> {
        let raw =
            r#"{ "unknown": {"x":1e+00}, "state" : { "turnId" : "old", "vendor": [ 1, 2 ] }}"#;
        let patched = replace(raw, &["state", "turnId"], &serde_json::json!("new"))?;
        assert_eq!(patched, raw.replace("\"old\"", "\"new\""));
        Ok(())
    }
}
