//! Fixture encoding for checkpoint formats predating named accounting groups.
pub fn flatten(checkpoint: &mut serde_json::Value) {
    let current = &checkpoint["state"]["usageSummary"];
    let mut flat = current["totals"].as_object().unwrap().clone();
    flat.insert("appliedSequence".into(), current["appliedSequence"].clone());
    if let Some(binding) = current["binding"].as_object() {
        for key in [
            "model",
            "contextWindow",
            "maxContextWindow",
            "autoCompactLimit",
        ] {
            flat.insert(key.into(), binding[key].clone());
        }
    }
    for (old, group, key) in [
        ("cacheInputTokens", "cache", "inputTokens"),
        ("cacheReadTokens", "cache", "readTokens"),
        ("cacheIncomplete", "cache", "incomplete"),
        ("latestContextTokens", "context", "tokens"),
        ("turnId", "throughput", "turnId"),
        ("turnCompletionTokens", "throughput", "completionTokens"),
        ("turnResponseMillis", "throughput", "responseMillis"),
        ("hasUnpricedUsage", "pricing", "incomplete"),
        ("estimatedCosts", "pricing", "estimatedCosts"),
        ("estimatedCacheSavings", "pricing", "estimatedCacheSavings"),
    ] {
        flat.insert(old.into(), current[group][key].clone());
    }
    flat.insert(
        "hasIncompleteUsage".into(),
        serde_json::json!(current["diagnostics"]["incompleteCalls"].as_u64().unwrap() > 0),
    );
    checkpoint["state"]["usageSummary"] = serde_json::Value::Object(flat);
}
