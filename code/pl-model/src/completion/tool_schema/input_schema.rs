//! Minimal model-facing input declarations. Frozen author schemas remain unchanged.
use serde_json::{Map, Value, json};
use std::collections::BTreeSet;

const TABLES: &[&str] = &[
    "properties",
    "$defs",
    "definitions",
    "patternProperties",
    "dependentSchemas",
    "dependencies",
];
const LISTS: &[&str] = &["oneOf", "anyOf", "allOf", "prefixItems"];
const CHILDREN: &[&str] = &[
    "items",
    "additionalItems",
    "unevaluatedItems",
    "contentSchema",
    "additionalProperties",
    "unevaluatedProperties",
    "contains",
    "propertyNames",
    "not",
    "if",
    "then",
    "else",
];

pub(super) fn project(schema: &mut Value) {
    node(schema);
    prune_definitions(schema);
}

fn node(schema: &mut Value) {
    if let Value::Bool(allowed) = schema {
        *schema = if *allowed {
            json!({})
        } else {
            json!({"not":{}})
        };
        return;
    }
    let Some(object) = schema.as_object_mut() else {
        return;
    };
    // Keep argument shape and useful constraints, never generator/application annotations.
    object.retain(|key, _| {
        matches!(
            key.as_str(),
            "type"
                | "description"
                | "enum"
                | "const"
                | "$ref"
                | "$defs"
                | "definitions"
                | "properties"
                | "required"
                | "additionalProperties"
                | "patternProperties"
                | "items"
                | "prefixItems"
                | "minItems"
                | "maxItems"
                | "uniqueItems"
                | "minLength"
                | "maxLength"
                | "pattern"
                | "format"
                | "minimum"
                | "maximum"
                | "exclusiveMinimum"
                | "exclusiveMaximum"
                | "multipleOf"
                | "minProperties"
                | "maxProperties"
                | "dependentRequired"
                | "dependentSchemas"
                | "oneOf"
                | "anyOf"
                | "allOf"
                | "not"
                | "if"
                | "then"
                | "else"
                | "contains"
                | "minContains"
                | "maxContains"
                | "propertyNames"
                | "unevaluatedProperties"
                | "$id"
                | "$anchor"
                | "$dynamicRef"
                | "$dynamicAnchor"
                | "$recursiveRef"
                | "$recursiveAnchor"
                | "dependencies"
                | "additionalItems"
                | "unevaluatedItems"
                | "contentSchema"
                | "contentEncoding"
                | "contentMediaType"
                | "encrypted"
        )
    });
    factor_object_branches(object);
    let closed = object.get("additionalProperties") == Some(&Value::Bool(false));
    if closed
        && !object.contains_key("patternProperties")
        && let Some(properties) = object.get_mut("properties").and_then(Value::as_object_mut)
    {
        // A forbidden parameter is not an available argument. Object closure still forbids it.
        properties.retain(|_, schema| schema != &Value::Bool(false));
    }
    for key in TABLES {
        if let Some(children) = object.get_mut(*key).and_then(Value::as_object_mut) {
            for child in children.values_mut() {
                node(child);
            }
        }
    }
    for key in LISTS {
        if let Some(children) = object.get_mut(*key).and_then(Value::as_array_mut) {
            for child in children {
                node(child);
            }
        }
    }
    for key in CHILDREN {
        if let Some(child) = object.get_mut(*key) {
            // additionalProperties is a protocol-supported boolean flag; schema-valued
            // positions such as items/not still need object-form true/false schemas.
            if *key == "items" && child.is_array() {
                for item in child.as_array_mut().expect("tuple items") {
                    node(item);
                }
            } else if *key != "additionalProperties" || !child.is_boolean() {
                node(child);
            }
        }
    }
}

/// A closed object already supplies common property definitions. Closed union branches need
/// only their allowed names and differing restrictions, not copies of every argument schema.
fn factor_object_branches(object: &mut Map<String, Value>) {
    if object.get("type").and_then(Value::as_str) != Some("object")
        || object.get("additionalProperties") != Some(&Value::Bool(false))
        || object.contains_key("patternProperties")
    {
        return;
    }
    let Some(properties) = object.get("properties").and_then(Value::as_object).cloned() else {
        return;
    };
    let common_required = object
        .get("required")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    for key in ["oneOf", "anyOf"] {
        if !object.contains_key("description") {
            let common = object
                .get(key)
                .and_then(Value::as_array)
                .and_then(|branches| {
                    let description = branches.first()?.get("description")?.as_str()?;
                    branches
                        .iter()
                        .all(|branch| {
                            branch.get("description").and_then(Value::as_str) == Some(description)
                        })
                        .then(|| Value::String(description.into()))
                });
            if let Some(description) = common {
                object.insert("description".into(), description);
            }
        }
        let description = object.get("description").cloned();
        let Some(branches) = object.get_mut(key).and_then(Value::as_array_mut) else {
            continue;
        };
        for branch in branches {
            let Some(branch) = branch.as_object_mut() else {
                continue;
            };
            if branch.contains_key("additionalProperties")
                || branch.contains_key("patternProperties")
            {
                continue;
            }
            let Some(fields) = branch.get_mut("properties").and_then(Value::as_object_mut) else {
                continue;
            };
            if fields.len() != properties.len()
                || !properties.keys().all(|key| fields.contains_key(key))
            {
                continue;
            }
            fields.retain(|_, schema| schema != &Value::Bool(false));
            for (key, schema) in fields.iter_mut() {
                if properties.get(key) == Some(schema) {
                    *schema = json!({});
                }
            }
            branch.insert("additionalProperties".into(), false.into());
            if branch.get("type").and_then(Value::as_str) == Some("object") {
                branch.remove("type");
            }
            // These branches inherit the surrounding parameter descriptions and required fields.
            if description.is_some() && branch.get("description") == description.as_ref() {
                branch.remove("description");
            }
            if let Some(required) = branch.get_mut("required").and_then(Value::as_array_mut) {
                required.retain(|field| !common_required.contains(field));
                if required.is_empty() {
                    branch.remove("required");
                }
            }
        }
    }
}

// False means a nested identifier changes reference resolution; retain definitions conservatively.
fn references(schema: &Value, output: &mut Vec<String>) -> bool {
    let Some(object) = schema.as_object() else {
        return true;
    };
    if object.contains_key("$id") {
        return false;
    }
    for key in ["$ref", "$dynamicRef", "$recursiveRef"] {
        if let Some(reference) = object.get(key).and_then(Value::as_str) {
            output.push(reference.into());
        }
    }
    for key in TABLES
        .iter()
        .filter(|key| !matches!(**key, "$defs" | "definitions"))
    {
        if let Some(children) = object.get(*key).and_then(Value::as_object) {
            for child in children.values() {
                if !references(child, output) {
                    return false;
                }
            }
        }
    }
    for key in LISTS {
        if let Some(children) = object.get(*key).and_then(Value::as_array) {
            for child in children {
                if !references(child, output) {
                    return false;
                }
            }
        }
    }
    for key in CHILDREN {
        if let Some(child) = object.get(*key) {
            if *key == "items" && child.is_array() {
                for item in child.as_array().expect("tuple items") {
                    if !references(item, output) {
                        return false;
                    }
                }
            } else if !references(child, output) {
                return false;
            }
        }
    }
    true
}

fn prune_definitions(schema: &mut Value) {
    let mut pending = Vec::new();
    if !references(schema, &mut pending) {
        return;
    }
    let mut visited = BTreeSet::new();
    let mut reachable = BTreeSet::new();
    while let Some(reference) = pending.pop() {
        if !visited.insert(reference.clone()) {
            continue;
        }
        let Some(pointer) = reference.strip_prefix('#') else {
            return;
        };
        let mut parts = pointer.split('/');
        if parts.next() != Some("") {
            return;
        }
        let Some(table @ ("$defs" | "definitions")) = parts.next() else {
            return;
        };
        let Some(name) = parts.next() else {
            return;
        };
        let name = name.replace("~1", "/").replace("~0", "~");
        reachable.insert((table.to_owned(), name.clone()));
        if let Some(target) = schema.get(table).and_then(|table| table.get(&name))
            && !references(target, &mut pending)
        {
            return;
        }
    }
    for table in ["$defs", "definitions"] {
        if let Some(definitions) = schema.get_mut(table).and_then(Value::as_object_mut) {
            definitions.retain(|name, _| reachable.contains(&(table.to_owned(), name.clone())));
            if definitions.is_empty() {
                schema
                    .as_object_mut()
                    .expect("definition owner")
                    .remove(table);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn closed_profile_branches_reuse_parent_arguments_and_forbid_excluded_fields() {
        let message =
            json!({"type":"string","description":"Task","title":"Rust String","default":"unused"});
        let mut schema = json!({"type":"object","additionalProperties":false,
        "properties":{"message":message,"choice":{"type":"string","enum":["a","b"]},"paths":{"type":"array","items":{"type":"string"}}},
        "required":["message","choice"],
        "oneOf":[
            {"type":"object","description":"Use for a only","properties":{"message":message,"choice":{"const":"a"},"paths":false},"required":["message","choice"]},
            {"type":"object","properties":{"message":message,"choice":{"const":"b"},"paths":{"type":"array","items":{"type":"string"}}},"required":["message","choice","paths"]}
        ]});
        let original = schema.clone();
        project(&mut schema);
        assert!(schema["properties"]["message"].get("title").is_none());
        assert!(schema["properties"]["message"].get("default").is_none());
        assert_eq!(schema["properties"]["message"]["description"], "Task");
        let a = &schema["oneOf"][0];
        assert!(a["properties"].get("paths").is_none());
        assert_eq!(a["additionalProperties"], false);
        assert_eq!(a["description"], "Use for a only");
        assert_eq!(a["properties"]["message"], json!({}));
        assert_eq!(a["properties"]["choice"], json!({"const":"a"}));
        assert!(a.get("required").is_none());
        assert_eq!(schema["oneOf"][1]["required"], json!(["paths"]));
        assert!(
            serde_json::to_vec(&schema).unwrap().len()
                < serde_json::to_vec(&original).unwrap().len()
        );
        let once = schema.clone();
        project(&mut schema);
        assert_eq!(schema, once);
    }

    #[test]
    fn older_tuple_dependencies_and_scoped_references_keep_their_constraints() {
        let mut schema = json!({"type":"object",
            "properties":{"tuple":{"type":"array","items":[{"$ref":"#/$defs/value"}],"additionalItems":false}},
            "dependencies":{"tuple":["other"],"other":{"properties":{"value":{"$ref":"#/$defs/value"}}}},
            "$defs":{"value":{"type":"string"},"unused":{"type":"number"}}});
        project(&mut schema);
        assert_eq!(schema["dependencies"]["tuple"], json!(["other"]));
        assert_eq!(
            schema["properties"]["tuple"]["additionalItems"],
            json!({"not":{}})
        );
        assert_eq!(
            schema["properties"]["tuple"]["items"][0]["$ref"],
            "#/$defs/value"
        );
        assert!(schema["$defs"].get("value").is_some());
        assert!(schema["$defs"].get("unused").is_none());
        let mut scoped = json!({"properties":{"local":{"$id":"nested","$ref":"#/$defs/value"}},
            "$defs":{"value":{"type":"string"},"keep":{"type":"number"}}});
        let definitions = scoped["$defs"].clone();
        project(&mut scoped);
        assert_eq!(scoped["$defs"], definitions);
    }

    #[test]
    fn schema_positions_preserve_literal_values_and_transitive_recursive_references() {
        let literal = json!({"title":"literal","default":false,"properties":{"x":false}});
        let mut schema = json!({"type":"object","$schema":"unused","x-internal":"never sent",
            "properties":{"value":{"$ref":"#/$defs/a~1b"},"literal":{"enum":[literal]},
                "empty":{"type":"array","items":false},"free":true},
            "$defs":{"a/b":{"type":"object","properties":{"next":{"$ref":"#/$defs/recursive"}}},
                "recursive":{"anyOf":[{"type":"null"},{"$ref":"#/$defs/recursive"}]},
                "unused":{"title":"Not referenced","type":"string"}}});
        project(&mut schema);
        assert!(schema.get("$schema").is_none() && schema.get("x-internal").is_none());
        assert!(schema["$defs"].get("unused").is_none());
        assert!(schema["$defs"].get("a/b").is_some() && schema["$defs"].get("recursive").is_some());
        assert_eq!(schema["properties"]["literal"]["enum"], json!([literal]));
        assert_eq!(schema["properties"]["empty"]["items"], json!({"not":{}}));
        assert_eq!(schema["properties"]["free"], json!({}));
    }
}
