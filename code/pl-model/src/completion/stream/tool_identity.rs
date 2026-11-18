//! Shared tool correlation rules for lifecycle validation and argument accumulation.
use std::collections::HashMap;

#[derive(Clone, Copy)]
pub(super) struct ToolIdentity<'a> {
    pub item_id: &'a str,
    pub call_id: Option<&'a str>,
    pub stable_item: bool,
}

impl ToolIdentity<'_> {
    pub fn matches(self, call_id: Option<&String>, item_id: &str) -> bool {
        call_id
            .filter(|id| !id.is_empty())
            .zip(self.call_id)
            .is_some_and(|(incoming, stored)| incoming == stored)
            || (!item_id.is_empty() && self.item_id == item_id)
    }

    pub fn uses_item_fallback(self) -> bool {
        self.stable_item && !self.item_id.is_empty() && self.call_id == Some(self.item_id)
    }

    pub fn accepts_call_id(self) -> bool {
        self.call_id.is_none_or(str::is_empty) || self.call_id == Some(self.item_id)
    }
}

pub(super) fn tool_key(
    stream_id: Option<&String>,
    call_id: Option<&String>,
    item_id: &str,
) -> String {
    stream_id
        .filter(|id| !id.is_empty())
        .or_else(|| call_id.filter(|id| !id.is_empty()))
        .map_or_else(|| item_id.to_owned(), Clone::clone)
}

pub(super) fn resolve_key<'a, T>(
    entries: &'a HashMap<String, T>,
    identity: impl Fn(&'a T) -> ToolIdentity<'a>,
    stream_id: Option<&String>,
    call_id: Option<&String>,
    item_id: &str,
) -> String {
    let key = tool_key(stream_id, call_id, item_id);
    if entries.contains_key(&key) {
        return key;
    }
    if let Some(found) = entries.iter().find_map(|(key, value)| {
        identity(value)
            .matches(call_id, item_id)
            .then(|| key.clone())
    }) {
        return found;
    }
    // Late call-only metadata may upgrade an item fallback only when it is unambiguous.
    if stream_id.is_none_or(String::is_empty)
        && call_id.is_some_and(|id| !id.is_empty() && id == item_id)
    {
        let mut candidates = entries
            .iter()
            .filter(|(_, value)| identity(value).uses_item_fallback());
        if let Some((candidate, _)) = candidates.next()
            && candidates.next().is_none()
        {
            return candidate.clone();
        }
    }
    key
}
