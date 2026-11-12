//! Script authors express native calls as JSON; emit the actual Lua model protocol.
use serde_json::{Value, json};

/// Read the native binding names from the SDK carried by the real frozen declaration.
pub(crate) fn catalogue(body: &Value) -> Vec<String> {
    let mut names = Vec::new();
    for tool in body["tools"].as_array().into_iter().flatten() {
        let tool = tool.get("function").unwrap_or(tool);
        if let Some(name) = tool["name"].as_str() {
            names.push(name.into());
        }
        if tool["name"] == "exec" {
            for line in tool["description"].as_str().unwrap_or_default().lines() {
                if let Some(name) = line
                    .strip_prefix("tools[")
                    .and_then(|line| {
                        line.split_once("](args)")
                            .or_else(|| line.split_once("](text)"))
                    })
                    .map(|(name, _)| name)
                    && let Ok(name) = serde_json::from_str::<String>(name)
                {
                    names.push(name);
                }
            }
        }
    }
    names
}

pub(crate) fn invocation(body: &Value, name: &str, input: &Value) -> (String, String) {
    let direct = body["tools"]
        .as_array()
        .into_iter()
        .flatten()
        .any(|tool| tool.get("function").unwrap_or(tool)["name"] == name);
    if direct || !catalogue(body).iter().any(|binding| binding == name) {
        (name.into(), input.to_string())
    } else {
        ("exec".into(), arguments(name, input).to_string())
    }
}

pub(crate) fn arguments(name: &str, arguments: &Value) -> Value {
    json!({"code":format!("return tools[{}]({})", value(&Value::String(name.into())), value(arguments)),"timeoutMs":600000,"maxOutputBytes":65536})
}

fn value(input: &Value) -> String {
    match input {
        Value::Null => "json.null".into(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::String(value) => {
            let mut quoted = String::from("\"");
            for character in value.chars() {
                match character {
                    '\\' => quoted.push_str("\\\\"),
                    '"' => quoted.push_str("\\\""),
                    character if character.is_control() && (character as u32) < 128 => {
                        quoted.push_str(&format!("\\{:03}", character as u32));
                    }
                    character => quoted.push(character),
                }
            }
            quoted.push('"');
            quoted
        }
        Value::Array(values) => format!(
            "json.array({{{}}})",
            values.iter().map(value).collect::<Vec<_>>().join(",")
        ),
        Value::Object(values) => format!(
            "{{{}}}",
            values
                .iter()
                .map(|(key, item)| format!(
                    "[{}]={}",
                    value(&Value::String(key.clone())),
                    value(item)
                ))
                .collect::<Vec<_>>()
                .join(",")
        ),
    }
}
