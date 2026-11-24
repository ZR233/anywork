pub(crate) fn canonical_json_hash(value: &serde_json::Value) -> String {
    let mut value = value.clone();
    value.sort_all_objects();
    pl_core::context::content_hash(value.to_string().as_bytes())
}
