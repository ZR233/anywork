//! Adapters for the new persistent view; old production checkpoint fields remain supported there.

use super::*;
use serde::{Deserializer, Serializer};

pub(super) mod inputs {
    use super::*;

    pub fn serialize<S: Serializer>(
        inputs: &Arc<[input::InputRecord]>,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        let mut value = serde_json::to_value(inputs).map_err(serde::ser::Error::custom)?;
        for input in value.as_array_mut().expect("inputs").iter_mut() {
            input
                .as_object_mut()
                .expect("input record")
                .remove("acceptedSequence");
        }
        value.serialize(serializer)
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<Arc<[input::InputRecord]>, D::Error> {
        let mut value = serde_json::Value::deserialize(deserializer)?;
        let inputs = value
            .as_array_mut()
            .ok_or_else(|| serde::de::Error::custom("inputs must be an array"))?;
        for input in inputs {
            let input = input
                .as_object_mut()
                .ok_or_else(|| serde::de::Error::custom("input record must be an object"))?;
            if input.contains_key("acceptedSequence") {
                return Err(serde::de::Error::custom(
                    "history admission fence is not current data",
                ));
            }
            input.insert("acceptedSequence".into(), 0.into());
        }
        serde_json::from_value(value).map_err(serde::de::Error::custom)
    }
}

pub(super) mod tasks {
    use super::*;

    pub fn serialize<S: Serializer>(
        tasks: &BTreeMap<String, task::TaskRecord>,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        let mut value = serde_json::to_value(tasks).map_err(serde::ser::Error::custom)?;
        for task in value.as_object_mut().expect("map").values_mut() {
            let task = task.as_object_mut().expect("record");
            if let Some(order) = task.remove("startedSequence") {
                task.insert("startedOrder".into(), order);
            }
        }
        value.serialize(serializer)
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<BTreeMap<String, task::TaskRecord>, D::Error> {
        let mut value = serde_json::Value::deserialize(deserializer)?;
        let tasks = value
            .as_object_mut()
            .ok_or_else(|| serde::de::Error::custom("tasks must be a map"))?;
        for task in tasks.values_mut() {
            let task = task
                .as_object_mut()
                .ok_or_else(|| serde::de::Error::custom("task must be an object"))?;
            if task.contains_key("startedSequence") {
                return Err(serde::de::Error::custom(
                    "history task start sequence is not current data",
                ));
            }
            if let Some(order) = task.remove("startedOrder") {
                task.insert("startedSequence".into(), order);
            }
        }
        serde_json::from_value(value).map_err(serde::de::Error::custom)
    }
}

pub(super) mod usage {
    use super::*;

    pub fn serialize<S: Serializer>(
        summary: &UsageSummary,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        let mut value = serde_json::to_value(summary).map_err(serde::ser::Error::custom)?;
        value
            .as_object_mut()
            .expect("summary")
            .remove("appliedSequence");
        value.serialize(serializer)
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<UsageSummary, D::Error> {
        let value = serde_json::Value::deserialize(deserializer)?;
        if value.get("appliedSequence").is_some() {
            return Err(serde::de::Error::custom(
                "history usage fence is not current data",
            ));
        }
        serde_json::from_value(value).map_err(serde::de::Error::custom)
    }
}

pub(super) mod continuation {
    use super::*;

    pub fn serialize<S: Serializer>(
        point: &Option<ContinuationPoint>,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        let mut value = serde_json::to_value(point).map_err(serde::ser::Error::custom)?;
        if let Some(point) = value.as_object_mut() {
            point.remove("claim");
        }
        value.serialize(serializer)
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<Option<ContinuationPoint>, D::Error> {
        let value = serde_json::Value::deserialize(deserializer)?;
        if value.get("claim").is_some() {
            return Err(serde::de::Error::custom(
                "old continuation authority is not current data",
            ));
        }
        serde_json::from_value(value).map_err(serde::de::Error::custom)
    }
}
