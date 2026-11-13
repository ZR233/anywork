/// Stable identity of actual UTF-8 or binary content, without interpreting its format.
pub fn content_hash(content: &[u8]) -> String {
    use sha2::Digest;
    format!("sha256:{}", hex::encode(sha2::Sha256::digest(content)))
}

/// Hashes JSON after recursively sorting object keys; array order remains significant.
pub fn canonical_json_hash(value: &serde_json::Value) -> String {
    let mut value = value.clone();
    value.sort_all_objects();
    content_hash(value.to_string().as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_identity_sorts_nested_objects_and_preserves_array_order() {
        let first: serde_json::Value =
            serde_json::from_str(r#"{"b":[{"z":2,"a":1},3],"a":0}"#).unwrap();
        let reordered: serde_json::Value =
            serde_json::from_str(r#"{"a":0,"b":[{"a":1,"z":2},3]}"#).unwrap();
        assert_eq!(canonical_json_hash(&first), canonical_json_hash(&reordered));
        assert_eq!(
            canonical_json_hash(&first),
            content_hash(br#"{"a":0,"b":[{"a":1,"z":2},3]}"#)
        );
        let changed = serde_json::json!({"a":0,"b":[3,{"a":1,"z":2}]});
        assert_ne!(canonical_json_hash(&first), canonical_json_hash(&changed));
    }
}
